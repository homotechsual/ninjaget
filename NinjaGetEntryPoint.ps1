[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This script is not intended to be run interactively.')]
param (
    # The operation to perform. Valid values are Setup, Install, Uninstall, Process and Update.
    ## Setup - Creates the NinjaGet directories and files.
    ## Install - Installs the NinjaGet files.
    ## Uninstall - Uninstalls the NinjaGet files.
    ## Process - Processes the applications in the application install and uninstall fields.
    ## Update - Updates the NinjaGet files.
    [Parameter(Mandatory)]
    [ValidateSet('Setup', 'Info', 'Uninstall', 'Process', 'Update')]
    [string]$Operation,
    # Override the package source.
    [string]$PackageSource = 'winget',
    # The path to install the NinjaGet files to. Default is $ENV:ProgramData\NinjaGet.
    [System.IO.DirectoryInfo]$InstallPath,
    # The path to the NinjaGet log files. Default is $ENV:ProgramData\NinjaGet\Logs.
    [System.IO.DirectoryInfo]$LogPath,
    # The path to the NinjaGet tracking files. These files are used to track the installation status of applications. Default is $ENV:ProgramData\NinjaGet\Tracking.
    [System.IO.DirectoryInfo]$TrackingPath,
    # Allow the "install" application ids to be automatically update when NinjaGet runs autoupdate jobs.
    [bool]$AutoUpdate,
    # Auto update blocklist. Application ids in this list will not be automatically updated when NinjaGet runs autoupdate jobs.
    [string[]]$AutoUpdateBlocklist,
    # Update only apps in the install field. The default behaviour will update all eligible apps using `winget upgrade --all`.
    [bool]$UpdateFromInstallField,
    # The notification level - valid values are Full, SuccessOnly, ErrorOnly and None.
    [ValidateSet('Full', 'SuccessOnly', 'ErrorOnly', 'None')]
    [string]$NotificationLevel,
    # The name of the RMM platform. Currently only NinjaOne is implemented.
    [ValidateSet('NinjaOne')]
    [string]$RMMPlatform,
    # The name of the field in the RMM platform which will hold the last run date.
    [string]$LastRunField,
    # The name of the field in the RMM platform which will hold the last run status.
    [string]$LastRunStatusField,
    # The name of the field in tphe RMM platform which holds the applications to install. (Multi-line - one application id per line)
    [string]$InstallField,
    # The name of the field in the RMM platform which holds the applications to uninstall. (Multi-line - one application id per line)
    [string]$UninstallField,
    # The URL to the image to use for the user notifications.
    [string]$NotificationImageURL,
    # The title of the user notification application.
    [string]$NotificationTitle,
    # Set the program name to show in the add/remove programs list.
    [string]$ProgramName = 'NinjaGet',
    # Set the program publisher to show in the add/remove programs list.
    [string]$ProgramPublisher = 'homotechsual',
    # Set the update interval for the NinjaGet package update job.
    [ValidateSet('Daily', 'Every2Days', 'Weekly', 'Every2Weeks', 'Monthly')]
    [string]$UpdateInterval,
    # Set the time of day to run the NinjaGet package update job.
    [string]$UpdateTime,
    # Run package updates on login.
    [bool]$UpdateOnLogin,
    # Disable updates and installs on metered connections.
    [bool]$DisableOnMetered,
    # Require only machine-scoped packages to be installed.
    [bool]$MachineScopeOnly,
    # Use task scheduler to run NinjaGet update jobs.
    [bool]$UseTaskScheduler,
    # Remove the NinjaGet settings from the registry. Used with the Uninstall operation.
    [bool]$RemoveSettings,
    # Remove the NinjaGet logs. Used with the Uninstall operation.
    [bool]$RemoveLogs,
    # Ignore the auto update blocklist. Used with the Update operation.
    [bool]$IgnoreBlocklist
)
# Initialization function - sets up the environment for NinjaGet.
function Initialize-NinjaGet {
    # Store a variable for the current user's name (removing any characters not safe for filenames).
    $InvalidCharacters = [IO.Path]::GetInvalidFileNameChars() -join ''
    $RegEx = '[{0}]' -f [regex]::Escape($InvalidCharacters)
    $Script:UserName = ($ENV:UserName -replace $RegEx)
    # Set the NinjaGet install path setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryInstallPath = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet' -Name 'InstallLocation' -ErrorAction SilentlyContinue
    if ($InstallPath) {
        $Script:InstallPath = $InstallPath
    } elseif ($RegistryInstallPath) {
        $Script:InstallPath = $RegistryInstallPath
    } else {
        $Script:InstallPath = (Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaGet')
    }
    # Set the NinjaGet version.
    $Script:Version = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'version.txt')
    # Get the NinjaGet log path setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLogPath = Get-NinjaGetSetting -Setting 'LogPath'
    if ($logpath) {
        $Script:LogPath = $LogPath
    } elseif ($RegistryLogPath) {
        $Script:LogPath = $RegistryLogPath
    } else {
        $Script:LogPath = (Join-Path -Path $Script:InstallPath -ChildPath 'Logs')
    }
    # Create the NinjaGet log path if it doesn't exist.
    if (!(Test-Path $LogPath)) {
        $null = New-Item -ItemType Directory -Force -Path $LogPath
    }
    # Set the ACL on the log path.
    Set-NinjaGetACL -Path $LogPath
    # Setup differs depending on whether NinjaGet is running as SYSTEM or not.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:RunAsSystem = $true
        $Script:LogFile = Join-Path -Path $Script:LogPath -ChildPath 'NinjaGet.log'
    } else {
        $Script:RunAsSystem = $false
        $Script:LogFile = Join-Path -Path $Script:LogPath -ChildPath 'NinjaGet.log'
    }
    # Create the log file if it doesn't exist.
    if (!(Test-Path $LogFile)) {
        $null = New-Item -ItemType File -Force -Path $LogFile
    }
    # Get the NinjaGet tracking path setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryTrackingPath = Get-NinjaGetSetting -Setting 'TrackingPath'
    if ($TrackingPath) {
        $Script:TrackingPath = $TrackingPath
    } elseif ($RegistryTrackingPath) {
        $Script:TrackingPath = $RegistryTrackingPath
    } else {
        $Script:TrackingPath = (Join-Path -Path $Script:InstallPath -ChildPath 'Tracking')
    }
    # Create the NinjaGet tracking path if it doesn't exist.
    if (!(Test-Path $TrackingPath)) {
        $null = New-Item -ItemType Directory -Force -Path $TrackingPath
    }
    # Set the NinjaGet tracking file paths.
    $Script:InstalledAppsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.installedapps.tracking'
    $Script:SystemAppsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.systemapps.tracking'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:OperationsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.operations.tracking'
    } else {
        $Script:OperationsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath ('NinjaGet{0}.operations.tracking' -f $Script:UserName)
    }
    # Get the NinjaGet notification level setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryNotificationLevel = Get-NinjaGetSetting -Setting 'NotificationLevel'
    if ($NotificationLevel) {
        $Script:NotificationLevel = $NotificationLevel
    } elseif ($RegistryNotificationLevel) {
        $Script:NotificationLevel = $RegistryNotificationLevel
    } else {
        $Script:NotificationLevel = 'Full'
    }
    # Get the NinjaGet autoupdate setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryAutoUpdate = Get-NinjaGetSetting -Setting 'AutoUpdate'
    if ($AutoUpdate) {
        $Script:AutoUpdate = $AutoUpdate
    } elseif ($RegistryAutoUpdate) {
        $Script:AutoUpdate = [bool]$RegistryAutoUpdate
    } else {
        $Script:AutoUpdate = $true
    }
    # Get the NinjaGet autoupdate blocklist setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryAutoUpdateBlocklist = Get-NinjaGetSetting -Setting 'AutoUpdateBlocklist'
    if ($AutoUpdateBlocklist) {
        $Script:AutoUpdateBlocklist = $AutoUpdateBlocklist
    } elseif ($RegistryAutoUpdateBlocklist) {
        $Script:AutoUpdateBlocklist = $RegistryAutoUpdateBlocklist
    } else {
        $Script:AutoUpdateBlocklist = [System.Collections.Generic.List[string]]::new()
    }
    # Get the NinjaGet update from install field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateFromInstallField = Get-NinjaGetSetting -Setting 'UpdateFromInstallField'
    if ($UpdateFromInstallField) {
        $Script:UpdateFromInstallField = $UpdateFromInstallField
    } elseif ($RegistryUpdateFromInstallField) {
        $Script:UpdateFromInstallField = [bool]$RegistryUpdateFromInstallField
    } else {
        $Script:UpdateFromInstallField = $false
    }
    # Get the NinjaGet RMM Platform setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryRMMPlatform = Get-NinjaGetSetting -Setting 'RMMPlatform'
    if ($RMMPlatform) {
        $Script:RMMPlatform = $RMMPlatform
    } elseif ($RegistryRMMPlatform) {
        $Script:RMMPlatform = $RegistryRMMPlatform
    } else {
        $Script:RMMPlatform = 'NinjaOne'
    }
    # Get the NinjaGet last run field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLastRunField = Get-NinjaGetSetting -Setting 'LastRunField'
    if ($LastRunField) {
        $Script:LastRunField = $LastRunField
    } elseif ($RegistryLastRunField) {
        $Script:LastRunField = $RegistryLastRunField
    } else {
        $Script:LastRunField = 'NGLastRun'
    }
    # Get the NinjaGet last run status field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLastRunStatusField = Get-NinjaGetSetting -Setting 'LastRunStatusField'
    if ($LastRunStatusField) {
        $Script:LastRunStatusField = $LastRunStatusField
    } elseif ($RegistryLastRunStatusField) {
        $Script:LastRunStatusField = $RegistryLastRunStatusField
    } else {
        $Script:LastRunStatusField = 'NGLastRunStatus'
    }
    # Get the NinjaGet install field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryInstallField = Get-NinjaGetSetting -Setting 'InstallField'
    if ($InstallField) {
        $Script:InstallField = $InstallField
    } elseif ($RegistryInstallField) {
        $Script:InstallField = $RegistryInstallField
    } else {
        $Script:InstallField = 'NGInstall'
    }
    # Get the NinjaGet uninstall field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUninstallField = Get-NinjaGetSetting -Setting 'UninstallField'
    if ($UninstallField) {
        $Script:UninstallField = $UninstallField
    } elseif ($RegistryUninstallField) {
        $Script:UninstallField = $RegistryUninstallField
    } else {
        $Script:UninstallField = 'NGUninstall'
    }
    # Get the NinjaGet notification image URL setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryNotificationImageURL = Get-NinjaGetSetting -Setting 'NotificationImageURL'
    if ($NotificationImageURL) {
        $Script:NotificationImageURL = $NotificationImageURL
    } elseif ($RegistryNotificationImageURL) {
        $Script:NotificationImageURL = $RegistryNotificationImageURL
    } else {
        $Script:NotificationImageURL = 'https://raw.githubusercontent.com/homotechsual/NinjaGet/main/resources/applications.png'
    }
    # Get the NinjaGet notification title setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryNotificationTitle = Get-NinjaGetSetting -Setting 'NotificationTitle'
    if ($NotificationTitle) {
        $Script:NotificationTitle = $NotificationTitle
    } elseif ($RegistryNotificationTitle) {
        $Script:NotificationTitle = $RegistryNotificationTitle
    } else {
        $Script:NotificationTitle = 'NinjaGet'
    }
    # Get the NinjaGet update interval setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateInterval = Get-NinjaGetSetting -Setting 'UpdateInterval'
    if ($UpdateInterval) {
        $Script:UpdateInterval = $UpdateInterval
    } elseif ($RegistryUpdateInterval) {
        $Script:UpdateInterval = $RegistryUpdateInterval
    } else {
        $Script:UpdateInterval = 'Daily'
    }
    # Get the NinjaGet update time setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateTime = Get-NinjaGetSetting -Setting 'UpdateTime'
    if ($UpdateTime) {
        $Script:UpdateTime = $UpdateTime
    } elseif ($RegistryUpdateTime) {
        $Script:UpdateTime = $RegistryUpdateTime
    } else {
        $Script:UpdateTime = '16:00'
    }
    # Get the NinjaGet update on login setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateOnLogin = Get-NinjaGetSetting -Setting 'UpdateOnLogin'
    if ($UpdateOnLogin) {
        $Script:UpdateOnLogin = $UpdateOnLogin
    } elseif ($RegistryUpdateOnLogin) {
        $Script:UpdateOnLogin = [bool]$RegistryUpdateOnLogin
    } else {
        $Script:UpdateOnLogin = $true
    }
    # Get the NinjaGet disable on metered connections setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryDisableOnMetered = Get-NinjaGetSetting -Setting 'DisableOnMetered'
    if ($DisableOnMetered) {
        $Script:DisableOnMetered = $DisableOnMetered
    } elseif ($RegistryDisableOnMetered) {
        $Script:DisableOnMetered = [bool]$RegistryDisableOnMetered
    } else {
        $Script:DisableOnMetered = $true
    }
    # Get the NinjaGet machine scope only setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryMachineScopeOnly = Get-NinjaGetSetting -Setting 'MachineScopeOnly'
    if ($MachineScopeOnly) {
        $Script:MachineScopeOnly = $MachineScopeOnly
    } elseif ($RegistryMachineScopeOnly) {
        $Script:MachineScopeOnly = [bool]$RegistryMachineScopeOnly
    } else {
        $Script:MachineScopeOnly = $false
    }
    # Get the NinjaGet use task scheduler setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUseTaskScheduler = Get-NinjaGetSetting -Setting 'UseTaskScheduler'
    if ($UseTaskScheduler) {
        $Script:UseTaskScheduler = $UseTaskScheduler
    } elseif ($RegistryUseTaskScheduler) {
        $Script:UseTaskScheduler = [bool]$RegistryUseTaskScheduler
    } else {
        $Script:UseTaskScheduler = $true
    }
    # 
    # Set script variables for the current run / job.
    $Script:Operation = $Operation
    $Script:Source = $PackageSource
    $Script:IgnoreBlocklist = $IgnoreBlocklist
}
$OIP = $InformationPreference
$InformationPreference = 'Continue'
$Script:WorkingDir = $Script:InstallPath
Write-Debug "Working directory is $WorkingDir"
$Functions = Get-ChildItem -Path (Join-Path -Path $WorkingDir -ChildPath 'PS') -Filter '*.ps1' -Exclude @('Send-NinjaGetNotification.ps1', 'Invoke-NinjaGetUpdates.ps1') -Recurse
foreach ($Function in $Functions) {
    Write-Verbose ('Importing function file: {0}' -f $Function.FullName)
    . $Function.FullName
}
switch ($Script:Operation) {
    'Setup' {
        Write-NGLog -LogMsg 'Running setup operations.' -LogColour 'White'
        Initialize-NinjaGet
        if ($Script:DisableOnMetered -and (Test-MeteredConnection)) {
            Write-NGLog -LogMsg 'Metered connection detected, exiting.' -LogColour 'Red'
            exit 1
        }
        if ($Script:RunAsSystem) {
            Test-NinjaGetPrerequisites
            Register-NinjaGetProgramEntry -DisplayName $ProgramName -Publisher $ProgramPublisher
            Register-NotificationApp -DisplayName $NotificationTitle -ImageURL $NotificationImageURL
            Register-NinjaGetUpdaterScheduledTask -TimeToUpdate $UpdateTime -UpdateInterval $UpdateInterval -UpdateOnLogin $UpdateOnLogin
            Register-NinjaGetNotificationsScheduledTask
            $NinjaGetSettings = @{
                'LogPath' = $Script:LogPath
                'TrackingPath' = $Script:TrackingPath
                'NotificationLevel' = $Script:NotificationLevel
                'AutoUpdate' = $Script:AutoUpdate
                'AutoUpdateBlocklist' = $Script:AutoUpdateBlocklist
                'UpdateFromInstallField' = $Script:UpdateFromInstallField
                'RMMPlatform' = $Script:RMMPlatform
                'LastRunField' = $Script:LastRunField
                'LastRunStatusField' = $Script:LastRunStatusField
                'InstallField' = $Script:InstallField
                'UninstallField' = $Script:UninstallField
                'NotificationImageURL' = $Script:NotificationImageURL
                'NotificationTitle' = $Script:NotificationTitle
                'UpdateInterval' = $Script:UpdateInterval
                'UpdateTime' = $Script:UpdateTime
                'UpdateOnLogin' = $Script:UpdateOnLogin
                'DisableOnMetered' = $Script:DisableOnMetered
                'MachineScopeOnly' = $Script:MachineScopeOnly
                'UseTaskScheduler' = $Script:UseTaskScheduler
            }
            Register-NinjaGetSettings @NinjaGetSettings
            Set-ScopeMachine -MachineScopeOnly $MachineScopeOnly
        } else {
            if (-not(Test-NinjaGetInstalled)) {
                throw 'NinjaGet is not installed. Please run the setup operation as SYSTEM.'
            }
            Test-TrackingAvailable
        }
        Get-WinGetCommand
    }
    'Info' {
        Write-NGLog -LogMsg 'Running info operations.' -LogColour 'White'
        $InstalledApps = (Get-WinGetInstalledPackages -source $Script:Source -acceptSourceAgreements | Select-Object -ExpandProperty Id) -join ' '
        Write-NGLog -LogMsg "Installed applications:`r`n$InstalledApps" -LogColour 'White'
        $SystemApps = Get-WinGetSystemApps
        Write-NGLog -LogMsg "System applications:`r`n$SystemApps" -LogColour 'White'
        $AppsToInstall = Get-AppsToInstall -AppInstallField $Script:InstallField
        Write-NGLog -LogMsg "Applications to install:`r`n$AppsToInstall" -LogColour 'White'
        $AppsToUninstall = Get-AppsToUninstall -AppUninstallField $Script:UninstallField
        Write-NGLog -LogMsg "Applications to uninstall:`r`n$AppsToUninstall" -LogColour 'White'
        $OutdatedApps = (Get-WinGetOutdatedPackages -source $Script:Source -acceptSourceAgreements | Select-Object -ExpandProperty Id) -join ' '
        Write-NGLog -LogMsg "Outdated applications:`r`n$OutdatedApps" -LogColour 'White'
    }
    'Process' {
        $Script:InstallOK = 0
        $Script:UninstallOK = 0
        $AppsToInstall = Get-AppsToInstall -AppInstallField $Script:InstallField
        foreach ($App in $AppsToInstall) {
            Install-Application -ApplicationId $App
        }
        $OutdatedApps = Get-WinGetOutdatedPackages
        foreach ($App in $OutdatedApps) {
            if ($App -in $Script:AutoUpdateBlocklist -and (-not($Script:IgnoreBlocklist))) {
                Write-NGLog -LogMsg "Skipping $App as it is in the autoupdate blocklist." -LogColour 'Yellow'
                continue
            }
            Update-Application -Application $App
        }
        if ($Script:InstallOK -gt 0) {
            Write-NGLog -LogMsg "Installed or updated $InstallOK applications" -LogColour 'Green'
        }
        $AppsToUninstall = Get-AppsToUninstall -AppUninstallField $Script:UninstallField
        foreach ($App in $AppsToUninstall) {
            Uninstall-Application -Application $App
        }
        if ($Script:UninstallOK -gt 0) {
            Write-NGLog -LogMsg "Uninstalled $UninstallOK applications" -LogColour 'Green'
        }
    }
    'Update' {
        Write-NGLog -LogMsg 'Running update operations.' -LogColour 'White'
        if ($Script:DisableOnMetered -and (Test-MeteredConnection)) {
            Write-NGLog -LogMsg 'Metered connection detected, exiting.' -LogColour 'Red'
            exit 1
        }
        if (-not(Test-NinjaGetInstalled)) {
            throw 'NinjaGet is not installed. Please run the update operation as SYSTEM.'
        }
        if ($Script:UseTaskScheduler) {
            Get-ScheduledTask -TaskName 'NinjaGet Updater' | Start-ScheduledTask
        } else {
            .\(Join-Path -Path $Script:WorkingDir -ChildPath 'PS\Invoke-NinjaGetUpdates.ps1') -SkipBlockList $Script:IgnoreBlocklist
        }
    }
}
$InformationPreference = $OIP