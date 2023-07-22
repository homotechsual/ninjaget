[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'All', Justification = 'This script is not intended to be run interactively.')]
param (
    # The operation to perform. Valid values are Install, Uninstall and Check.
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Uninstall', 'Check')]
    [string]$Operation,
    # The application ids to install or uninstall.
    [Parameter(Mandatory)]
    [string[]]$ApplicationIds,
    # Allow the "install" application ids to be automatically update when RMMGet runs autoupdate jobs.
    [switch]$AutoUpdate,
    # The path to the RMMGet log files. Default is $ENV:ProgramData\RMMGet\Logs.
    [System.IO.DirectoryInfo]$LogPath = "$ENV:ProgramData\RMMGet\Logs",
    # The path to the RMMGet tracking files. These files are used to track the installation status of applications. Default is $ENV:ProgramData\RMMGet\Tracking.
    [System.IO.DirectoryInfo]$TrackingPath = "$ENV:ProgramData\RMMGet\Tracking",
    # The name of the field in the RMM platform which will hold the last run date.
    [string]$LastRunField = 'RGLastRun',
    # The name of the field in the RMM platform which will hold the last run status.
    [string]$LastRunStatusField = 'RGLastRunStatus',
    # The name of the field in the RMM platform which holds the applications to install. (Comma-separated list)
    [string]$InstallField = 'RGInstall',
    # The name of the field in the RMM platform which holds the applications to uninstall. (Comma-separated list)
    [string]$UninstallField = 'RGUninstall'
)

<# Function Definitions #>
# Initialization function - sets up the environment for RMMGet.
function Initialize-WinGet {
    # Get the WinGet AutoUpdate installation path, if it exists.
    $WAURegKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\'
    if (Test-Path $WAURegKey) {
        $Script:WAUInstallLocation = Get-ItemProperty $WAURegKey | Select-Object -ExpandProperty InstallLocation -ErrorAction SilentlyContinue
    }
    # Create the RMMGet log path if it doesn't exist.
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
    }
    # Set the RMMGet log file path.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:LogFile = "$LogPath\RMMGet.log"
    } else {
        $Script:LogFile = "$LogPath\RMMGet$ENV:UserName.log"
    }
    # Create the RMMGet tracking path if it doesn't exist.
    if (!(Test-Path $TrackingPath)) {
        New-Item -ItemType Directory -Force -Path $TrackingPath | Out-Null
    }
    # Set the RMMGet tracking file paths.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:TrackingFile = "$TrackingPath\RMMGet.tracking"
    } else {
        $Script:TrackingFile = "$TrackingPath\RMMGet$ENV:UserName.tracking"
    }
    # Add job header to the log file.
    if ($Uninstall) {
        Write-Log -LogMsg "###   $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL   ###" -LogColour 'Magenta'
    } else {
        Write-Log -LogMsg "###   $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) - NEW INSTALL   ###" -LogColour 'Magenta'
    }
}
# Log function - writes a message to the RMMGet log file.
function Write-Log ($LogMsg, [System.ConsoleColor]$LogColour = 'White') {
    # Create formatted log entry.
    $Log = "$(Get-Date -UFormat '%T') - $LogMsg"
    # Output log entry to the information stream.
    $MessageData = [System.Management.Automation.HostInformationMessage]@{
        Message = $Log
        ForegroundColor = $LogColour
    }
    Write-Information -MessageData $MessageData
    # Write log entry to the log file.
    $Log | Out-File -FilePath $LogFile -Append
}
# WinGet command function - gets the path to the WinGet executable.
function Get-WinGetCommand {
    # Get the WinGet path (for use when running in SYSTEM context).
    $ResolveWinGetPath = Resolve-Path "$ENV:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe" | Sort-Object { 
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
        Write-Log -LogMsg 'WinGet not installed or couldn''t be detected!' -LogColour 'Red'
        break
    }
    Write-Log -LogMsg "Using WinGet path: $WinGet`n"
}
# Set Scope Machine function - sets WinGet's default installation scope to machine.
function Set-ScopeMachine {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param ()
    # Get the WinGet settings path.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        # Running in SYSTEM context.
        $SettingsPath = "$ENV:WinDir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\settings.json"
    } else {
        # Running in user context.
        $SettingsPath = "$ENV:LocalAppData\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }
    # Check if the settings file already exists.
    if (Test-Path $SettingsPath) {
        # Check if the settings file already has the correct scope.
        $WinGetConfig = Get-Content $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
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
        $WinGetConfig | ConvertTo-Json | Out-File -FilePath $SettingsPath -Encoding [System.Text.UTF8Encoding] -Force
    }
}
# Confirm Install function - confirms the installation of an application.
function Confirm-AppInstalled ([string]$ApplicationId) {
    # Get the results of `winget list` for the application.
    $WinGetInstalledApp = & $Script:WinGet list --id $ApplicationId -e --accept-source-agreements | Out-String
    # Boolean return based on whether the application is installed.
    if ($WinGetInstalledApp -match [regex]::Escape($ApplicationId)) {
        return $true
    } else {
        return $false
    }
}
# Confirm Existence function - confirms the existence of an application.
function Confirm-AppExists ([string]$ApplicationId) {
    # Get the results of `winget show` for the application.
    $WinGetApp = & $Script:WinGet show --id $ApplicationId -e --accept-source-agreements | Out-String
    # Boolean return based on whether the application exists.
    if ($WinGetApp -match [regex]::Escape($ApplicationId)) {
        Write-Log -LogMsg "Application '$ApplicationId' exists in WinGet repository." -LogColour 'Cyan'
        return $true
    } else {
        Write-Log -LogMsg "Application '$ApplicationId' does not exist in WinGet repository." -LogColour 'Red'
        return $false
    }
}
# Tracking function - tracks the installation of applications.
function Write-Tracking ([string]$ApplicationId, [string]$Operation) {
    # Get the tracking file content and convert from JSON.
    $Tracking = Get-Content $Script:TrackingFile -ErrorAction SilentlyContinue | ConvertFrom-Json
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
    # Check if the application is already tracked.
    if ($Tracking.Install.Contains($ApplicationId)) {
        if ($Operation -eq 'Uninstall') {
            if (!Confirm-AppInstalled $ApplicationId) {
                $Tracking.Install.Remove($ApplicationId)
                $Tracking.Uninstall.Add($ApplicationId)
                $Tracking | Out-File -FilePath $Script:TrackingFile -Force
                Write-Log -LogMsg "Application '$ApplicationId' is no longer installed. Added to uninstall tracking." -LogColour 'Purple'
            }
        } elseif ($Operation -eq 'Install') {
            if (Confirm-AppInstalled $ApplicationId) {
                Write-Log -LogMsg "Application '$ApplicationId' is already installed and is already tracked as installed." -LogColour 'Purple'
            }
        }
    } elseif ($Tracking.Uninstall.Contains($ApplicationId)) {
        if ($Operation -eq 'Install') {
            if (Confirm-AppInstalled $ApplicationId) {
                $Tracking.Uninstall.Remove($ApplicationId)
                $Tracking.Install.Add($ApplicationId)
                $Tracking | Out-File -FilePath $Script:TrackingFile -Force
                Write-Log -LogMsg "Application '$ApplicationId' is no longer uninstalled. Added to install tracking." -LogColour 'Purple'
            }
        } elseif ($Operation -eq 'Install') {
            if (!Confirm-AppInstalled $ApplicationId) {
                Write-Log -LogMsg "Application '$ApplicationId' is already uninstalled and is already tracked as uninstalled." -LogColour 'Purple'
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
        Write-Log -LogMsg "Application '$ApplicationId' added to tracking file." -LogColour 'Cyan'
    }
}
# Install function - installs an application.
function Install-Application ([string]$ApplicationId, [string]$Arguments) {
    # Check if the application is already installed.
    if (Confirm-AppInstalled $ApplicationId) {
        Write-Log -LogMsg "Application '$ApplicationId' already installed." -LogColour 'Cyan'
    } else {
        # Check if the application exists in the WinGet repository.
        if (Confirm-AppExists $ApplicationId) {
            # Install the application.
            Write-Log -LogMsg "Installing application '$ApplicationId'..." -LogColour 'Cyan'
            & $Script:WinGet install --id $ApplicationId -e --accept-source-agreements $Arguments
            # Add to the AutoUpdate allowlist if appropriate.
            if ($AutoUpdate) {
                Add-WAUAllowlist -ApplicationId $ApplicationId
            }
            # Check if the application was installed successfully.
            if (Confirm-AppInstalled $ApplicationId) {
                Write-Log -LogMsg "Application '$ApplicationId' installed successfully." -LogColour 'Green'
                # Update the tracking file.
                Update-TrackingRecord $ApplicationId 'Install'
            } else {
                Write-Log -LogMsg "Application '$ApplicationId' failed to install." -LogColour 'Red'
            }
        }
    }
}
# Uninstall function - uninstalls an application.
function Uninstall-Application ([string]$ApplicationId, [string]$Arguments) {
    # Check if the application is already installed.
    if (Confirm-AppInstalled $ApplicationId) {
        # Uninstall the application.
        Write-Log -LogMsg "Uninstalling application '$ApplicationId'..." -LogColour 'Cyan'
        & $Script:WinGet uninstall --id $ApplicationId -e --accept-source-agreements $Arguments
        # Remove from the AutoUpdate allowlist if appropriate.
        if ($AutoUpdate) {
            Remove-WAUAllowlist -ApplicationId $ApplicationId
        }
        # Check if the application was uninstalled successfully.
        if (!Confirm-AppInstalled $ApplicationId) {
            Write-Log -LogMsg "Application '$ApplicationId' uninstalled successfully." -LogColour 'Green'
            # Update the tracking file.
            Update-TrackingRecord $ApplicationId 'Uninstall'
        } else {
            Write-Log -LogMsg "Application '$ApplicationId' failed to uninstall." -LogColour 'Red'
        }
    } else {
        Write-Log -LogMsg "Application '$ApplicationId' not installed." -LogColour 'Cyan'
    }
}
# AutoUpdate Allowlist Add function - adds an application to the AutoUpdate allowlist.
function Add-WAUAllowlist ([string]$ApplicationId) {
    $AllowlistPath = Join-Path -Path $Script:WAUInstallLocation -ChildPath 'included_apps.txt'
    if (Test-Path $AllowlistPath) {
        Write-Log -LogMsg "Adding application '$ApplicationId' to AutoUpdate allowlist..."
        # Add the application to the allowlist.
        Add-Content -Path $AllowlistPath -Value "`n$ApplicationId" -Force
        # Remove duplicate and blank lines.
        $AllowlistFile = Get-Content $AllowlistPath | Select-Object -Unique | Where-Object { $_.trim() -ne '' } | Sort-Object
        $AllowlistFile | Out-File -FilePath $AllowlistPath -Force
    }
}
# AutoUpdate Allowlist Remove function - removes an application from the AutoUpdate allowlist.
function Remove-WAUAllowlist {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId
    )
    $AllowlistPath = Join-Path -Path $Script:WAUInstallLocation -ChildPath 'included_apps.txt'
    if (Test-Path $AllowlistPath) {
        Write-Log -LogMsg "Removing application '$ApplicationId' from AutoUpdate allowlist..."
        # Remove the application from the allowlist.
        $AllowlistFile = Get-Content $AllowlistPath | Where-Object { $_ -notmatch [regex]::Escape($ApplicationId) }
        if ($PSCmdlet.ShouldProcess($ApplicationId, 'Remove from AutoUpdate allowlist')) {
            $AllowlistFile | Out-File -FilePath $AllowlistPath -Force
        }
    }
}
# Last Run function - sets the last run time for the script in supported RMM platforms.
function Update-LastRun {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Does not change system state.')]
    [cmdletbinding()]
    param()
    # Get the current time.
    $CurrentTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
    if ($RMMPlatform -eq 'NinjaOne') {
        # Set the last run time.
        Ninja-Property-Set -Name $LastRunField -Value $CurrentTime
    } elseif ($RMMPlatform -eq 'Syncro') {
        # Set the last run time.
        # ToDo add syncro logic.
    } elseif ($RMMPlatform -eq 'Datto') {
        # Set the last run time.
        # ToDo add datto logic.
    }
}