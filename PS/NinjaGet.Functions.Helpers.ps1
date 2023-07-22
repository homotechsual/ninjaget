
# Get the path to the WinGet executable and prepare it for use.
function Get-WinGetCommand {
    # Get the WinGet path (for use when running in SYSTEM context).
    $WinGetPathToResolve = Join-Path -Path $ENV:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe'
    $ResolveWinGetPath = Resolve-Path -Path $WinGetPathToResolve | Sort-Object {
        [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
    }
    if ($ResolveWinGetPath) {
        # If we have multiple versions - use the latest.
        $WinGetPath = $ResolveWinGetPath[-1].Path
    }
    # Get the WinGet exe location.
    $WinGetExePath = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($WinGetExePath) {
        # Running in user context.
        $Script:WinGet = $WinGetExePath.Path
    } elseif (Test-Path -Path (Join-Path $WinGetPath 'winget.exe')) {
        # Running in SYSTEM context.
        $Script:WinGet = Join-Path $WinGetPath 'winget.exe'
    } else {
        Write-NGLog -LogMsg 'WinGet not installed or couldn''t be detected!' -LogColour 'Red'
        break
    }
    # Pre-accept the source agreements using the `list` command.
    $Null = & $Script:WinGet list --accept-source-agreements -s winget
    # Log the WinGet version and path.
    $WingetVer = & $Script:WinGet --version
    Write-NGLog "Winget Version: $WingetVer"
    Write-NGLog -LogMsg "Using WinGet path: $Script:WinGet"
}
# Set the default installation scope for WinGet to machine.
# Set Scope Machine function - sets WinGet's default installation scope to machine.
function Set-ScopeMachine {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param ()
    # Get the WinGet settings path.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        # Running in SYSTEM context.
        $SettingsPath = "$ENV:WinDir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\"
        $SettingsFile = Join-Path -Path $SettingsPath -ChildPath 'settings.json'
    } else {
        # Running in user context.
        $SettingsPath = "$ENV:LocalAppData\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\"
        $SettingsFile = Join-Path -Path $SettingsPath -ChildPath 'settings.json'
    }
    # Create the settings directory if it doesn't exist.
    if (!(Test-Path $SettingsPath)) {
        New-Item -Path $SettingsPath -ItemType Directory -Force
    }
    # Check if the settings file already exists.
    if (Test-Path $SettingsFile) {
        # Check if the settings file already has the correct scope.
        $WinGetConfig = Get-Content $SettingsFile | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    if (!$WinGetConfig) {
        # Initialise a blank WinGet config object.
        $WinGetConfig = @{}
    }
    if ($WinGetConfig.installBehavior.preferences) {
        Add-Member -InputObject $WinGetConfig.installBehavior.preferences -MemberType NoteProperty -Name 'scope' -Value 'Machine' -Force
    } else {
        $Scope = New-Object -TypeName PSObject -Property $(@{ scope = 'Machine' })
        $Preference = New-Object -TypeName PSObject -Property $(@{ preferences = $Scope })
        Add-Member -InputObject $WinGetConfig -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force
    }
    if ($PSCmdlet.ShouldProcess('WinGet is currently configured to install applications for the current user only. Do you want to change this to install applications for all users?', 'WinGet installation scope.', 'Changing WinGet installation scope to machine.')) {
        $WinGetConfig | ConvertTo-Json | Out-File -FilePath $SettingsFile -Encoding 'utf8' -Force
    }
}
# Confirm Install function - confirms the installation of an application.
function Confirm-AppInstalled {
    param(
        # The application ID.
        [string]$ApplicationId,
        # The application version.
        [string]$ApplicationVersion
    )
    # Populate the tracking file with all installed apps.
    $null = & $Script:WinGet export -s winget -o $Script:InstalledAppsTrackingFile --include-versions
    $JSON = Get-Content $Script:InstalledAppsTrackingFile -ErrorAction SilentlyContinue -Raw | ConvertFrom-Json
    $Packages = $JSON.Sources.Packages
    # Remove the tracking file.
    Remove-Item -Path $Script:InstalledAppsTrackingFile -Force
    # Check for the specific application and version.
    $Apps = $Packages | Where-Object { $_.PackageIdentifier -eq $ApplicationId -and $_.PackageVersion -like "$ApplicationVersion*" }
    # Boolean return based on whether the application is installed.
    if ($Apps) {
        return $true
    } else {
        return $false
    }
}
# Confirm Existence function - confirms the existence of an application.
function Confirm-AppExists ([string]$ApplicationId) {
    # Get the results of `winget show` for the application.
    $WinGetApp = & $Script:WinGet show --id $ApplicationId -e --accept-source-agreements -s winget | Out-String
    # Boolean return based on whether the application exists.
    if ($WinGetApp -match [regex]::Escape($ApplicationId)) {
        Write-NGLog -LogMsg "Application '$ApplicationId' exists in WinGet repository." -LogColour 'Cyan'
        return $true
    } else {
        Write-NGLog -LogMsg "Application '$ApplicationId' does not exist in WinGet repository." -LogColour 'Red'
        return $false
    }
}
# Tracking function - tracks the installation of applications.
function Write-Tracking ([string]$ApplicationId, [string]$Operation) {
    # Get the tracking file content and convert from JSON.
    $Tracking = Get-Content $Script:TrackingFile -ErrorAction SilentlyContinue -Raw | ConvertFrom-Json
    # Check that the tracking file has the expected structure.
    if (!$Tracking.Install) {
        $Tracking.Install = [System.Collections.Generic.List[string]]::new()
    } else {
        $Tracking.Install = [System.Collections.Generic.List[string]]@($Tracking.Install)
    }
    if (!$Tracking.Uninstall) {
        $Tracking.Uninstall = [System.Collections.Generic.List[string]]::new()
    } else {
        $Tracking.Uninstall = [System.Collections.Generic.List[string]]@($Tracking.Uninstall)
    }
    # Check if the application is already tracked to be installed.
    if ($Tracking.Install.Contains($ApplicationId)) {
        if ($Operation -eq 'Uninstall') {
            # Check if the application is still installed.
            if (!Confirm-AppInstalled $ApplicationId) {
                # Remove the application from the install tracking and add it to the uninstall tracking.
                $Tracking.Install.Remove($ApplicationId)
                $Tracking.Uninstall.Add($ApplicationId)
                $Tracking | Out-File -FilePath $Script:TrackingFile -Force
                Write-NGLog -LogMsg "Application '$ApplicationId' is no longer installed. Added to uninstall tracking." -LogColour 'Purple'
            }
        } elseif ($Operation -eq 'Install') {
            # Check if the application is already installed.
            if (Confirm-AppInstalled $ApplicationId) {
                Write-NGLog -LogMsg "Application '$ApplicationId' is already installed and is already tracked as installed." -LogColour 'Purple'
            }
        }
    } elseif ($Tracking.Uninstall.Contains($ApplicationId)) {
        if ($Operation -eq 'Install') {
            # Check if the application is still uninstalled.
            if (Confirm-AppInstalled $ApplicationId) {
                # Remove the application from the uninstall tracking and add it to the install tracking.
                $Tracking.Uninstall.Remove($ApplicationId)
                $Tracking.Install.Add($ApplicationId)
                $Tracking | Out-File -FilePath $Script:TrackingFile -Force
                Write-NGLog -LogMsg "Application '$ApplicationId' is no longer uninstalled. Added to install tracking." -LogColour 'Purple'
            }
        } elseif ($Operation -eq 'Install') {
            # Check if the application is already uninstalled.
            if (!Confirm-AppInstalled $ApplicationId) {
                Write-NGLog -LogMsg "Application '$ApplicationId' is already uninstalled and is already tracked as uninstalled." -LogColour 'Purple'
            }
        }
    } else {
        # Add the application to the tracking file.
        if ($Operation -eq 'Uninstall') {
            $Tracking.Uninstall.Add($ApplicationId)
        } elseif ($Operation -eq 'Install') {
            $Tracking.Install.Add($ApplicationId)
        }
        $Tracking | Out-File -FilePath $Script:TrackingFile -Force
        Write-NGLog -LogMsg "Application '$ApplicationId' added to tracking file." -LogColour 'Cyan'
    }
}