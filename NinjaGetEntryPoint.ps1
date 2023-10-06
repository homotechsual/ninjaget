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
        Write-Verbose 'Install path provided, using that.'
        $Script:InstallPath = $InstallPath
    } elseif ($RegistryInstallPath) {
        Write-Verbose 'Install path found in registry, using that.'
        $Script:InstallPath = $RegistryInstallPath
    } else {
        Write-Verbose 'Install path not provided, using default.'
        $Script:InstallPath = (Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaGet')
    }
    # Set the NinjaGet version.
    $Script:Version = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'version.txt')
    # Get the NinjaGet log path setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLogPath = Get-NinjaGetSetting -Setting 'LogPath' -SkipLog
    if ($logpath) {
        Write-Verbose 'Log path provided, using that.'
        $Script:LogPath = $LogPath
    } elseif ($RegistryLogPath) {
        Write-Verbose 'Log path found in registry, using that.'
        $Script:LogPath = $RegistryLogPath
    } else {
        Write-Verbose 'Log path not provided, using default.'
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
        $Script:LogFile = Join-Path -Path $Script:LogPath -ChildPath ('NinjaGet_{0}.log' -f $Script:UserName)
    }
    # Create the log file if it doesn't exist.
    if (!(Test-Path $LogFile)) {
        $null = New-Item -ItemType File -Force -Path $LogFile
    }
    # Get the NinjaGet tracking path setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryTrackingPath = Get-NinjaGetSetting -Setting 'TrackingPath'
    if ($TrackingPath) {
        Write-Verbose 'Tracking path provided, using that.'
        $Script:TrackingPath = $TrackingPath
    } elseif ($RegistryTrackingPath) {
        Write-Verbose 'Tracking path found in registry, using that.'
        $Script:TrackingPath = $RegistryTrackingPath
    } else {
        Write-Verbose 'Tracking path not provided, using default.'
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
        Write-Verbose 'Notification level provided, using that.'
        $Script:NotificationLevel = $NotificationLevel
    } elseif ($RegistryNotificationLevel) {
        Write-Verbose 'Notification level found in registry, using that.'
        $Script:NotificationLevel = $RegistryNotificationLevel
    } else {
        Write-Verbose 'Notification level not provided, using default.'
        $Script:NotificationLevel = 'Full'
    }
    # Get the NinjaGet autoupdate setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryAutoUpdate = Get-NinjaGetSetting -Setting 'AutoUpdate'
    if ($AutoUpdate) {
        Write-Verbose 'Auto update setting provided, using that.'
        $Script:AutoUpdate = $AutoUpdate
    } elseif ($RegistryAutoUpdate) {
        Write-Verbose 'Auto update setting found in registry, using that.'
        $Script:AutoUpdate = [bool]$RegistryAutoUpdate
    } else {
        Write-Verbose 'Auto update setting not provided, using default.'
        $Script:AutoUpdate = $true
    }
    # Get the NinjaGet autoupdate blocklist setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryAutoUpdateBlocklist = Get-NinjaGetSetting -Setting 'AutoUpdateBlocklist'
    if ($AutoUpdateBlocklist) {
        Write-Verbose 'Auto update blocklist provided, using that.'
        $Script:AutoUpdateBlocklist = $AutoUpdateBlocklist
    } elseif ($RegistryAutoUpdateBlocklist) {
        Write-Verbose 'Auto update blocklist found in registry, using that.'
        $Script:AutoUpdateBlocklist = $RegistryAutoUpdateBlocklist
    } else {
        Write-Verbose 'Auto update blocklist not provided, using default.'
        $Script:AutoUpdateBlocklist = [System.Collections.Generic.List[string]]::new()
    }
    # Get the NinjaGet update from install field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateFromInstallField = Get-NinjaGetSetting -Setting 'UpdateFromInstallField'
    if ($UpdateFromInstallField) {
        Write-Verbose 'Update from install field setting provided, using that.'
        $Script:UpdateFromInstallField = $UpdateFromInstallField
    } elseif ($RegistryUpdateFromInstallField) {
        Write-Verbose 'Update from install field setting found in registry, using that.'
        $Script:UpdateFromInstallField = [bool]$RegistryUpdateFromInstallField
    } else {
        Write-Verbose 'Update from install field setting not provided, using default.'
        $Script:UpdateFromInstallField = $false
    }
    # Get the NinjaGet RMM Platform setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryRMMPlatform = Get-NinjaGetSetting -Setting 'RMMPlatform'
    if ($RMMPlatform) {
        Write-Verbose 'RMM platform setting provided, using that.'
        $Script:RMMPlatform = $RMMPlatform
    } elseif ($RegistryRMMPlatform) {
        Write-Verbose 'RMM platform setting found in registry, using that.'
        $Script:RMMPlatform = $RegistryRMMPlatform
    } else {
        Write-Verbose 'RMM platform setting not provided, using default.'
        $Script:RMMPlatform = 'NinjaOne'
    }
    # Get the NinjaGet last run field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLastRunField = Get-NinjaGetSetting -Setting 'LastRunField'
    if ($LastRunField) {
        Write-Verbose 'Last run field setting provided, using that.'
        $Script:LastRunField = $LastRunField
    } elseif ($RegistryLastRunField) {
        Write-Verbose 'Last run field setting found in registry, using that.'
        $Script:LastRunField = $RegistryLastRunField
    } else {
        Write-Verbose 'Last run field setting not provided, using default.'
        $Script:LastRunField = 'NGLastRun'
    }
    # Get the NinjaGet last run status field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryLastRunStatusField = Get-NinjaGetSetting -Setting 'LastRunStatusField'
    if ($LastRunStatusField) {
        Write-Verbose 'Last run status field setting provided, using that.'
        $Script:LastRunStatusField = $LastRunStatusField
    } elseif ($RegistryLastRunStatusField) {
        Write-Verbose 'Last run status field setting found in registry, using that.'
        $Script:LastRunStatusField = $RegistryLastRunStatusField
    } else {
        Write-Verbose 'Last run status field setting not provided, using default.'
        $Script:LastRunStatusField = 'NGLastRunStatus'
    }
    # Get the NinjaGet install field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryInstallField = Get-NinjaGetSetting -Setting 'InstallField'
    if ($InstallField) {
        Write-Verbose 'Install field setting provided, using that.'
        $Script:InstallField = $InstallField
    } elseif ($RegistryInstallField) {
        Write-Verbose 'Install field setting found in registry, using that.'
        $Script:InstallField = $RegistryInstallField
    } else {
        Write-Verbose 'Install field setting not provided, using default.'
        $Script:InstallField = 'NGInstall'
    }
    # Get the NinjaGet uninstall field setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUninstallField = Get-NinjaGetSetting -Setting 'UninstallField'
    if ($UninstallField) {
        Write-Verbose 'Uninstall field setting provided, using that.'
        $Script:UninstallField = $UninstallField
    } elseif ($RegistryUninstallField) {
        Write-Verbose 'Uninstall field setting found in registry, using that.'
        $Script:UninstallField = $RegistryUninstallField
    } else {
        Write-Verbose 'Uninstall field setting not provided, using default.'
        $Script:UninstallField = 'NGUninstall'
    }
    # Get the NinjaGet notification image URL setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryNotificationImageURL = Get-NinjaGetSetting -Setting 'NotificationImageURL'
    if ($NotificationImageURL) {
        Write-Verbose 'Notification image URL setting provided, using that.'
        $Script:NotificationImageURL = $NotificationImageURL
    } elseif ($RegistryNotificationImageURL) {
        Write-Verbose 'Notification image URL setting found in registry, using that.'
        $Script:NotificationImageURL = $RegistryNotificationImageURL
    } else {
        Write-Verbose 'Notification image URL setting not provided, using default.'
        $Script:NotificationImageURL = 'https://raw.githubusercontent.com/homotechsual/NinjaGet/main/resources/applications.png'
    }
    # Get the NinjaGet notification title setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryNotificationTitle = Get-NinjaGetSetting -Setting 'NotificationTitle'
    if ($NotificationTitle) {
        Write-Verbose 'Notification title setting provided, using that.'
        $Script:NotificationTitle = $NotificationTitle
    } elseif ($RegistryNotificationTitle) {
        Write-Verbose 'Notification title setting found in registry, using that.'
        $Script:NotificationTitle = $RegistryNotificationTitle
    } else {
        Write-Verbose 'Notification title setting not provided, using default.'
        $Script:NotificationTitle = 'NinjaGet'
    }
    # Get the NinjaGet update interval setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateInterval = Get-NinjaGetSetting -Setting 'UpdateInterval'
    if ($UpdateInterval) {
        Write-Verbose 'Update interval setting provided, using that.'
        $Script:UpdateInterval = $UpdateInterval
    } elseif ($RegistryUpdateInterval) {
        Write-Verbose 'Update interval setting found in registry, using that.'
        $Script:UpdateInterval = $RegistryUpdateInterval
    } else {
        Write-Verbose 'Update interval setting not provided, using default.'
        $Script:UpdateInterval = 'Daily'
    }
    # Get the NinjaGet update time setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateTime = Get-NinjaGetSetting -Setting 'UpdateTime'
    if ($UpdateTime) {
        Write-Verbose 'Update time setting provided, using that.'
        $Script:UpdateTime = $UpdateTime
    } elseif ($RegistryUpdateTime) {
        Write-Verbose 'Update time setting found in registry, using that.'
        $Script:UpdateTime = $RegistryUpdateTime
    } else {
        Write-Verbose 'Update time setting not provided, using default.'
        $Script:UpdateTime = '16:00'
    }
    # Get the NinjaGet update on login setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUpdateOnLogin = Get-NinjaGetSetting -Setting 'UpdateOnLogin'
    if ($UpdateOnLogin) {
        Write-Verbose 'Update on login setting provided, using that.'
        $Script:UpdateOnLogin = $UpdateOnLogin
    } elseif ($RegistryUpdateOnLogin) {
        Write-Verbose 'Update on login setting found in registry, using that.'
        $Script:UpdateOnLogin = [bool]$RegistryUpdateOnLogin
    } else {
        Write-Verbose 'Update on login setting not provided, using default.'
        $Script:UpdateOnLogin = $true
    }
    # Get the NinjaGet disable on metered connections setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryDisableOnMetered = Get-NinjaGetSetting -Setting 'DisableOnMetered'
    if ($DisableOnMetered) {
        Write-Verbose 'Disable on metered connections setting provided, using that.'
        $Script:DisableOnMetered = $DisableOnMetered
    } elseif ($RegistryDisableOnMetered) {
        Write-Verbose 'Disable on metered connections setting found in registry, using that.'
        $Script:DisableOnMetered = [bool]$RegistryDisableOnMetered
    } else {
        Write-Verbose 'Disable on metered connections setting not provided, using default.'
        $Script:DisableOnMetered = $true
    }
    # Get the NinjaGet machine scope only setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryMachineScopeOnly = Get-NinjaGetSetting -Setting 'MachineScopeOnly'
    if ($MachineScopeOnly) {
        Write-Verbose 'Machine scope only setting provided, using that.'
        $Script:MachineScopeOnly = $MachineScopeOnly
    } elseif ($RegistryMachineScopeOnly) {
        Write-Verbose 'Machine scope only setting found in registry, using that.'
        $Script:MachineScopeOnly = [bool]$RegistryMachineScopeOnly
    } else {
        Write-Verbose 'Machine scope only setting not provided, using default.'
        $Script:MachineScopeOnly = $false
    }
    # Get the NinjaGet use task scheduler setting, if it's not provided, fall back to the registry and if that fails, use the default.
    $RegistryUseTaskScheduler = Get-NinjaGetSetting -Setting 'UseTaskScheduler'
    if ($UseTaskScheduler) {
        Write-Verbose 'Use task scheduler setting provided, using that.'
        $Script:UseTaskScheduler = $UseTaskScheduler
    } elseif ($RegistryUseTaskScheduler) {
        Write-Verbose 'Use task scheduler setting found in registry, using that.'
        $Script:UseTaskScheduler = [bool]$RegistryUseTaskScheduler
    } else {
        Write-Verbose 'Use task scheduler setting not provided, using default.'
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
Initialize-NinjaGet
$Script:WorkingDir = $Script:InstallPath
Verbose "Working directory is $Script:WorkingDir"
$ExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($ExecutionPolicy -ne 'RemoteSigned') {
    Write-Warning 'Execution policy is not RemoteSigned. Setting to `RemoteSigned` for this process. Please run the following command to set it permanently:'
    Write-Warning 'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
}
$Functions = Get-ChildItem -Path (Join-Path -Path $Script:WorkingDir -ChildPath 'PS') -Filter '*.ps1' -Exclude @('Send-NinjaGetNotification.ps1', 'Invoke-NinjaGetUpdates.ps1') -Recurse
foreach ($Function in $Functions) {
    Write-Verbose ('Importing function file: {0}' -f $Function.FullName)
    . $Function.FullName
}
switch ($Script:Operation) {
    'Setup' {
        Write-NGLog -LogMsg 'Running setup operations.' -LogColour 'White'
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