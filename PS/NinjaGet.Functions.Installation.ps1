# Uninstall NinjaGet function - uninstalls NinjaGet and resets various changed settings.
function Uninstall-NinjaGet {
    # Confirm NinjaGet is installed.
    if (-not (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet')) {
        Write-NGLog -LogMsg 'NinjaGet is not installed.' -LogColour 'Cyan'
        return
    }
    # Get the NinjaGet installation path.
    $NinjaGetInstallPath = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet\' -Name 'InstallLocation'
    # Get the original setting for StoreAutoDownload.
    $NinjaGetSettingsRegistryPath = 'HKLM:\SOFTWARE\NinjaGet'
    if (Test-Path -Path $NinjaGetSettingsRegistryPath) {
        $OriginalStoreAutoDownload = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\NinjaGet\' -Name 'StoreUpdatesOriginalValue' -ErrorAction SilentlyContinue
    }
    # Remove the scheduled tasks.
    Write-NgLog 'Removing scheduled tasks...' -LogColour 'Yellow'
    Get-ScheduledTask -TaskName 'NinjaGet Notifier' | Unregister-ScheduledTask -Confirm:$false
    Get-ScheduledTask -TaskName 'NinjaGet Updater' | Unregister-ScheduledTask -Confirm:$false
    if ($Script:RemoveSettings) {
        # Remove the NinjaGet registry key.
        Write-NgLog 'Removing NinjaGet registry key...' -LogColour 'Yellow'
    }
    if ($Script:RemoveLogs) {
        # Remove the NinjaGet log files.
        Write-NgLog 'Removing NinjaGet log files...' -LogColour 'Yellow'
        Remove-Item -Path $Script:LogPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Empty the NinjaGet installation folder, except for the Logs folder.
    Write-NgLog 'Removing NinjaGet installation folder...' -LogColour 'Yellow'
    Get-ChildItem -Path $NinjaGetInstallPath -Exclude 'Logs' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    if ($OriginalStoreAutoDownload) {
        # Reset the StoreAutoDownload setting.
        Write-NgLog 'Resetting StoreAutoDownload setting...' -LogColour 'Yellow'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\NinjaGet\' -Name 'StoreAutoDownload' -Value $OriginalStoreAutoDownload
    }
}

# Get latest WinGet function - gets the latest WinGetversion and the download URL for the MSIXBundle from GitHub.
function Get-LatestWinGet {
    $LatestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Method Get 
    $LatestWinGetVersion = $LatestRelease.tag_name
    [version]$LatestWinGetVersion = $LatestWinGetVersion.TrimStart('v')
    $LatestVersion = @{
        Version = $LatestWinGetVersion
        DownloadURI = $LatestRelease.assets.browser_download_url | Where-Object { $_.EndsWith('.msixbundle') }
    }
    return $LatestVersion
}
# Test WinGet version function - tests the version of WinGet against the latest version on GitHub.
function Test-WinGetVersion {
    param(
        [version]$InstalledWinGetVersion
    )
    $LatestWinGet = Get-LatestWinGet
    if ($InstalledWinGetVersion -lt $LatestWinGet.Version) {
        Write-NGLog 'WinGet is out of date.' -LogColour 'Yellow'
        $Script:WinGetURL = $LatestWinGet.DownloadURI
        return $false
    } else {
        Write-NGLog 'WinGet is up to date.' -LogColour 'Green'
        return $true
    }
}
# Update WinGet function - updates WinGet, using the Microsoft Store, if it is out of date.
function Update-WinGetFromStore {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - updating WinGet.'
    )]
    param(
        # Stop WinGet processes before updating.
        [switch]$StopProcesses,
        # How long to wait for the update to complete. Value is in minutes.
        [int]$WaitTime = 10,
        # The target version of WinGet to wait for. If not specified, the latest version will be used.
        [version]$TargetVersion
    )
    Write-NGLog 'Attempting to update WinGet from the Microsoft Store...' -LogColour 'Yellow'
    # Stop WinGet processes if the switch is specified.
    if ($StopProcesses) {
        Write-NGLog 'Stopping WinGet processes...' -LogColour 'Yellow'
        Get-Process | Where-Object { $_.ProcessName -in @('winget', 'WindowsPackageManagerServer', 'AuthenticationManager', 'AppInstaller') } | Stop-Process -Force
    }
    # Send the update command to the Microsoft Store using the MDM bridge.
    Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' | Invoke-CimMethod -MethodName UpdateScanMethod
    # If no target version is specified, get the latest version from GitHub.
    if (!$TargetVersion) {
        $TargetVersion = (Get-LatestWinGet).Version
    }
    # Wait for the update to complete - wait in 30 second intervals until the WaitTime is reached.
    do {
        Write-NGLog 'Waiting for WinGet update to complete...' -LogColour 'Yellow'
        Start-Sleep -Seconds 30
        $WaitTime -= 0.5
    } until ($WaitTime -eq 0 -or (Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller').Version -eq $TargetVersion)
}
# Install Store App function - installs a store app using the MDM bridge.
## Inspired by and adapted from: https://oliverkieselbach.com/2020/04/22/how-to-completely-change-windows-10-language-with-intune/
function Install-MicrosoftStoreApp {
    param(
        # The app ID of the store app to install.
        [string]$AppId,
        # The SKUID to use for the install params.
        [int]$SKUID = 0016
    )
    # Get the package family name.
    $AppLockerDataResponse = Invoke-WebRequest -Uri "https://bspmts.mp.microsoft.com/v1/public/catalog/Retail/Products/$AppId/applockerdata" -UseBasicParsing
    $AppLockerData = $AppLockerDataResponse.Content | ConvertFrom-Json
    $PackageFamilyName = $AppLockerData.PackageFamilyName
    # Build the CIM session and instance.
    $CIMNamespace = 'root\cimv2\mdm\dmmap'
    $OMAURI = './Vendor/MSFT/EnterpriseModernAppManagement/AppInstallation'
    $CIMSession = New-CimSession
    $CIMInstance = [Microsoft.Management.Infrastructure.CimInstance]::New('MDM_EnterpriseModernAppManagement_AppInstallation01_01', $CIMNamespace)
    $CIMParentProperty = [Microsoft.Management.Infrastructure.CimProperty]::Create('ParentID', $OMAURI, 'String', 'Key')
    $CIMInstance.CimInstanceProperties.Add($CIMParentProperty)
    $CIMInstanceIdProperty = [Microsoft.Management.Infrastructure.CimProperty]::Create('InstanceID', $PackageFamilyName, 'String', 'Key')
    $CIMInstance.CimInstanceProperties.Add($CIMInstanceIdProperty)
    $Flags = 0
    $CIMParameterValue = [Security.SecurityElement]::Escape($('<Application id="{0}" flags="{1}" skuid="{2}" />' -f $AppId, $Flags, $SKUID))
    $CIMParametersCollection = [Microsoft.Management.Infrastructure.CimMethodParametersCollection]::New()
    $CIMParameter = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create('param', $CIMParameterValue, 'String', 'In')
    $CIMParametersCollection.Add($CIMParameter)
    $StoreInstallInstance = $CIMSession.CreateInstance($CIMNamespace, $CIMInstance)
    # Invoke the install method.
    $CIMSession.InvokeMethod($CIMNamespace, $StoreInstallInstance, 'StoreInstallMethod', $CIMParametersCollection)
}
# Install WinGet function (MSIX) - installs WinGet if it is not already installed or is out of date using the MSIX bundle from GitHub.
function Install-WinGetFromMSIX {
    Write-NGLog 'WinGet not installed or out of date. Installing/updating using MSIX...' -LogColour 'Yellow'
    $WinGetFileName = [Uri]$Script:WinGetURL | Select-Object -ExpandProperty Segments | Select-Object -Last 1
    $WebClient = New-Object System.Net.WebClient
    $PrerequisitesPath = Join-Path -Path $Script:InstallPath -ChildPath 'Prerequisites'
    $WinGetDownloadPath = Join-Path -Path $PrerequisitesPath -ChildPath $WinGetFileName
    $WebClient.DownloadFile($Script:WinGetURL, $WinGetDownloadPath)
    try {
        Write-NGLog 'Installing WinGet...' -LogColour 'Yellow'
        Add-AppxProvisionedPackage -Online -PackagePath $WinGetDownloadPath -SkipLicense -ErrorAction Stop | Out-Null
        Write-NGLog 'WinGet installed.' -LogColour 'Green'
    } catch {
        Write-NGLog -LogMsg 'Failed to install WinGet!' -LogColour 'Red'
    } finally {
        Remove-Item -Path $WinGetDownloadPath -Force -ErrorAction SilentlyContinue
    }
}
# Install WinGet function (Store) - installs WinGet if it is not already installed or is out of date using the MDM bridge.
function Install-WinGetFromStore {
    param(
        # How long to wait for the update to complete. Value is in minutes.
        [int]$WaitTime = 10
    )
    Write-NGLog 'WinGet not installed. Installing from store. This might take upto 10 minutes...' -LogColour 'Yellow'
    $WinGetAppId = '9NBLGGH4NNS1'
    Install-MicrosoftStoreApp -AppId $WinGetAppId
    do {
        Write-NGLog 'Waiting for WinGet update to complete...' -LogColour 'Yellow'
        Start-Sleep -Seconds 30
        $WaitTime -= 0.5
    } until (($WaitTime -eq 0) -or (Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' } -ErrorAction SilentlyContinue))
}
# Prerequisite test function - checks if the script can run.
function Test-NinjaGetPrerequisites {
    # Check if the script is running in a supported OS.
    if ([System.Environment]::OSVersion.Version.Build -lt 17763) {
        Write-NGLog -LogMsg 'This script requires Windows 10 1809 or later!' -LogColour 'Red'
        exit 1
    }
    # Check for the required Microsoft Visual C++ redistributables.
    $Visual2019 = 'Microsoft Visual C++ 2015-2019 Redistributable*'
    $Visual2022 = 'Microsoft Visual C++ 2015-2022 Redistributable*'
    $VCPPInstalled = Get-Item @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') | Where-Object {
        $_.GetValue('DisplayName') -like $Visual2019 -or $_.GetValue('DisplayName') -like $Visual2022
    }
    if (!($VCPPInstalled)) {
        Write-NGLog 'Installing the required Microsoft Visual C++ redistributables...' -LogColour 'Yellow'
        if ([System.Environment]::Is64BitOperatingSystem) {
            $OSArch = 'x64'
        } else {
            $OSArch = 'x86'
        }
        $VCPPRedistURL = ('https://aka.ms/vs/17/release/vc_redist.{0}.exe' -f $OSArch)
        $VCPPRedistFileName = [Uri]$VCPPRedistURL | Select-Object -ExpandProperty Segments | Select-Object -Last 1
        $WebClient = New-Object System.Net.WebClient
        $VCPPRedistDownloadPath = "$InstallPath\Prerequisites"
        if (!(Test-Path -Path $VCPPRedistDownloadPath)) {
            $null = New-Item -Path $VCPPRedistDownloadPath -ItemType Directory -Force
        }
        $VCPPRedistDownloadFile = "$VCPPRedistDownloadPath\$VCPPRedistFileName"
        $WebClient.DownloadFile($VCPPRedistURL, $VCPPRedistDownloadFile)
        try {
            Start-Process -FilePath $VCPPRedistDownloadFile -ArgumentList '/quiet', '/norestart' -Wait -ErrorAction Stop | Out-Null
            Write-NGLog 'Microsoft Visual C++ redistributables installed.' -LogColour 'Green'
        } catch {
            Write-NGLog -LogMsg 'Failed to install the required Microsoft Visual C++ redistributables!' -LogColour 'Red'
            exit 1
        }
    }
    $WinGet = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' } -ErrorAction SilentlyContinue
    if ($WinGet) {
        # WinGet is installed - let's test the version.
        if ([Version]$WinGet.Version -ge (Get-LatestWinGet).Version) {
            Write-NGLog 'WinGet is installed and up to date.' -LogColour 'Cyan'
        } else {
            Update-WinGetFromStore
        }
    } else {
        if (-not($Script:UseMSIX)) {
            Install-WinGetFromStore
        } else {
            Install-WinGetFromMSIX
        }
    }
    # Test that store app updates are enabled.
    $StorePoliciesRegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
    if (Test-Path -Path $StorePoliciesRegistryPath) {
        $StoreAppUpdatesEnabled = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -Name 'AutoDownload' -ErrorAction SilentlyContinue
    }
    if ($StoreAppUpdatesEnabled -eq '2') {
        Write-NGLog 'Store app updates are not enabled!' -LogColour 'Red'
        Set-StoreUpdates -OriginalValue $StoreAppUpdatesEnabled
    } elseif ($StoreAppUpdatesEnabled -eq '4') {
        Write-NGLog 'Store app updates are enabled!' -LogColour 'Cyan'
    }
}
# Enable store app updates function - enables store app updates.
function Set-StoreUpdates {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - setting store updates.'
    )]
    param(
        # The original value of the AutoDownload registry value.
        [int]$OriginalValue = $null
    )
    $WSPRegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
    $WSPropertyName = 'AutoDownload'
    if ($OriginalValue) {
        Write-NgLog -LogMsg ('Storing original value of AutoDownload registry value [{0}]...' -f $OriginalValue) -LogColour 'Yellow'
        Register-NinjaGetSettings -StoreUpdatesOriginalValue $OriginalValue
    }
    Write-NgLog 'Enabling store app updates...' -LogColour 'Yellow'
    New-ItemProperty -Path $WSPRegistryPath -Name $WSPropertyName -Value 4 -Force
}
# Register NinjaGet in the registry.
function Register-NinjaGetProgramEntry {
    param(
        # The display name of the program.
        [string]$DisplayName,
        # The publisher of the program.
        [string]$Publisher
    )
    $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet'
    $null = New-Item -Path $RegistryPath -Force
    $null = New-ItemProperty -Path $RegistryPath -Name 'DisplayName' -Value 'NinjaGet' -Force
    $null = New-ItemProperty $RegistryPath -Name DisplayIcon -Value '' -Force
    $null = New-ItemProperty $RegistryPath -Name DisplayVersion -Value $Script:Version -Force
    $null = New-ItemProperty $RegistryPath -Name InstallLocation -Value $Script:InstallPath -Force
    $null = New-ItemProperty $RegistryPath -Name UninstallString -Value "powershell.exe -NoProfile -File `"$Script:InstallPath\PS\Uninstall-NinjaGet.ps1`"" -Force
    $null = New-ItemProperty $RegistryPath -Name QuietUninstallString -Value "powershell.exe -NoProfile -File `"$Script:InstallPath\PS\Uninstall-NinjaGet.ps1`"" -Force
    $null = New-ItemProperty $RegistryPath -Name NoModify -Value 1 -Force
    $null = New-ItemProperty $RegistryPath -Name NoRepair -Value 1 -Force
    $null = New-ItemProperty $RegistryPath -Name Publisher -Value 'homotechsual' -Force
    $null = New-ItemProperty $RegistryPath -Name URLInfoAbout -Value 'https://docs.homotechsual.dev/tools/ninjaget' -Force
}
# Notification App Function - Creates an app user model ID and registers the app with Windows.
function Register-NotificationApp {
    param(
        [string]$DisplayName = 'Software Updater',
        [uri]$LogoUri
    )
    $BaseRegPath = 'Registry::HKEY_CLASSES_ROOT\AppUserModelId'
    $AppId = 'NinjaGet.Notifications'
    $AppRegPath = "$BaseRegPath\$AppId"
    If (!(Test-Path $AppRegPath)) {
        $null = New-Item -Path $BaseRegPath -Name $AppId -Force
    }
    if ($IconURI) {
        $IconFileName = $IconURI.Segments[-1]
        $IconPath = "$InstallPath\resources\$IconFileName"
        $IconFile = New-Object System.IO.FileInfo $IconFilePath
        If ($IconFile.Exists) {
            $IconFile.Delete()
        }
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($IconURI, $IconPath)
    } else {
        $IconPath = "$InstallPath\resources\applications.png"
    }
    $null = New-ItemProperty -Path $AppRegPath -Name DisplayName -Value $DisplayName -PropertyType String -Force
    $null = New-ItemProperty -Path $AppRegPath -Name IconUri -Value $IconPath -PropertyType String -Force
    $null = New-ItemProperty -Path $AppRegPath -Name ShowInSettings -Value 0 -PropertyType DWORD -Force
}
# Scheduled task function - creates a scheduled task to run NinjaGet updater.
function Register-NinjaGetUpdaterScheduledTask {
    param(
        # The time to update at.
        [string]$TimeToUpdate = '16:00',
        # The update interval.
        [string]$UpdateInterval = 'Daily',
        # Whether to update at logon.
        [int]$UpdateAtLogon,
        # Standalone Mode.
        [int]$Standalone = $false
    )
    $TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -File `"$InstallPath\PS\Invoke-NinjaGetUpdates.ps1 -Standalone $Standalone`""
    $TaskTriggers = [System.Collections.Generic.List[Object]]@()
    if ($UpdateAtLogon) {
        $LogonTrigger = New-ScheduledTaskTrigger -AtLogOn
        $TaskTriggers.Add($LogonTrigger)
    }
    if ($UpdateInterval -eq 'Daily') {
        $DailyTrigger = New-ScheduledTaskTrigger -Daily -At $TimeToUpdate
        $TaskTriggers.Add($DailyTrigger)
    }
    if ($UpdateInterval -eq 'Every2Days') {
        $DailyTrigger = New-ScheduledTaskTrigger -Daily -At $TimeToUpdate -DaysInterval 2
        $TaskTriggers.Add($DailyTrigger)
    }
    if ($UpdateInterval -eq 'Weekly') {
        $WeeklyTrigger = New-ScheduledTaskTrigger -Weekly -At $TimeToUpdate -DaysOfWeek 2
        $TaskTriggers.Add($WeeklyTrigger)
    }
    if ($UpdateInterval -eq 'Every2Weeks') {
        $WeeklyTrigger = New-ScheduledTaskTrigger -Weekly -At $TimeToUpdate -DaysOfWeek 2 -WeeksInterval 2
        $TaskTriggers.Add($WeeklyTrigger)
    }
    if ($UpdateInterval -eq 'Monthly') {
        $MonthlyTrigger = New-ScheduledTaskTrigger -Monthly -At $TimeToUpdate -DaysOfMonth 1
        $TaskTriggers.Add($MonthlyTrigger)
    }
    $TaskServicePrincipal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest
    $TaskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit '03:00:00'
    if ($TaskTriggers) {
        $ScheduledTask = New-ScheduledTask -Action $TaskAction -Principal $TaskServicePrincipal -Settings $TaskSettings -Trigger $TaskTriggers
    } else {
        $ScheduledTask = New-ScheduledTask -Action $TaskAction -Principal $TaskServicePrincipal -Settings $TaskSettings
    }
    $null = Register-ScheduledTask -TaskName 'NinjaGet Updater' -InputObject $ScheduledTask -Force
}
# Scheduled task function - creates a scheduled task for NinjaGet notifications.
function Register-NinjaGetNotificationsScheduledTask {
    param(
        # Disable use of Visual Basic Script to hide the console window when triggering the user notification.
        [bool]$DisableVBS = $true
    )
    $taskAction = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"powershell.exe -WindowStyle Hidden -NoProfile -File `"$InstallPath\PS\Send-NinjaGetNotification.ps1`""
    $TaskServicePrincipal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-11'
    $TaskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit '00:05:00'
    $ScheduledTask = New-ScheduledTask -Action $TaskAction -Principal $TaskServicePrincipal -Settings $TaskSettings
    $null = Register-ScheduledTask -TaskName 'NinjaGet Notifier' -InputObject $ScheduledTask -Force
    # Set the task to be runnable for all users.
    $Scheduler = New-Object -ComObject 'Schedule.Service'
    $Scheduler.Connect()
    $Task = $Scheduler.GetFolder('').GetTask('NinjaGet Notifier')
    $SecurityDescriptor = $Task.GetSecurityDescriptor(0xF)
    $SecurityDescriptor = $SecurityDescriptor + '(A;;GRGX;;;AU)'
    $Task.SetSecurityDescriptor($SecurityDescriptor, 0)
}
# Get NinjaGet settings function - gets the NinjaGet setting(s) from the registry.
function Get-NinjaGetSetting {
    [CmdletBinding()]
    param(
        # The setting to get.
        [ValidateSet(
            'LogPath',
            'Standalone',
            'StandaloneStatus',
            'StandaloneAppsToInstall',
            'StandaloneAppsToUninstall',
            'TrackingPath',
            'NotificationLevel',
            'AutoUpdate',
            'AutoUpdateBlocklist',
            'UpdateFromInstallField',
            'RMMPlatform',
            'LastRunField',
            'LastRunStatusField',
            'InstallField',
            'UninstallField',
            'NotificationImageURL',
            'NotificationTitle',
            'UpdateInterval',
            'UpdateTime',
            'UpdateOnLogin',
            'DisableOnMetered',
            'MachineScopeOnly',
            'UseTaskScheduler',
            'StoreUpdatesOriginalValue'
        )]
        [string]$Setting,
        # Sometimes we need to skip logging issues here because we're running this function before we have a log file.
        [switch]$SkipLog
    )
    begin {
        $RegistryPath = 'HKLM:\SOFTWARE\NinjaGet'
    }
    process {
        # Get the setting
        if (Test-Path -Path $RegistryPath) {
            if (Get-ItemProperty -Path $RegistryPath -Name $Setting -ErrorAction SilentlyContinue) {
                $SettingValue = Get-ItemPropertyValue -Path $RegistryPath -Name $Setting -ErrorAction SilentlyContinue
            }
        }
    }
    end {
        # If we have a value, return it.
        if ($SettingValue) {
            return $SettingValue
        } else {
            # If we don't have a value, log an error and return $null unless we're skipping logging.
            if (-not($SkipLog)) {
                Write-NGLog -LogMsg ('The setting [{0}] does not have a value set in the registry.' -f $Setting) -LogColour 'DarkYellow'
            }
            return $null
        }
    }
}
# Register NinjaGet settings function - registers the NinjaGet settings in the registry.
function Register-NinjaGetSettings {
    [CmdletBinding()]
    param(
        # The log file path setting.
        [string]$LogPath,
        # The standlone mode setting.
        [int]$Standalone,
        # The StandaloneStatus mode setting.
        [string]$StandaloneStatus,
        # The AppToinstallStandalone mode setting.
        [string]$StandaloneAppsToInstall,
        # The AppToUninstallStandalone mode setting.
        [string]$StandaloneAppsToUninstall,
        # The tracking file path setting.
        [string]$TrackingPath,
        # Notification level setting.
        [ValidateSet('Full', 'SuccessOnly', 'None')]
        [string]$NotificationLevel,
        # Auto update setting.
        [int]$AutoUpdate,
        # Auto update blocklist setting.
        [string[]]$AutoUpdateBlocklist,
        # Update from install field setting.
        [int]$UpdateFromInstallField,
        # RMM platform setting.
        [ValidateSet('NinjaOne')]
        [string]$RMMPlatform,
        # RMM platform last run field setting.
        [string]$LastRunField,
        # RMM platform last run status field setting.
        [string]$LastRunStatusField,
        # RMM platform install field setting.
        [string]$InstallField,
        # RMM platform uninstall field setting.
        [string]$UninstallField,
        # Notification image URL setting.
        [uri]$NotificationImageURL,
        # Notification title setting.
        [string]$NotificationTitle,
        # Update interval setting.
        [ValidateSet('Daily', 'Every2Days', 'Weekly', 'Every2Weeks', 'Monthly')]
        [string]$UpdateInterval,
        # Update time setting.
        [string]$UpdateTime,
        # Update on login setting.
        [int]$UpdateOnLogin,
        # Disable on metered setting.
        [int]$DisableOnMetered,
        # Machine scope only setting.
        [int]$MachineScopeOnly,
        # Use task scheduler setting.
        [int]$UseTaskScheduler,
        # Store Updates original setting.
        [int]$StoreUpdatesOriginalValue
    )
    $RegistryPath = 'HKLM:\SOFTWARE\NinjaGet'
    $null = New-Item -Path $RegistryPath -Force
    if ($LogPath) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'LogPath' -Value $LogPath -Force
    }
    if ($Standalone) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'Standalone' -Value $Standalone -PropertyType DWORD -Force
    }
    if ($StandaloneStatus) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'StandaloneStatus' -Value $StandaloneStatus -Force
    }
    if ($StandaloneAppsToInstall) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'StandaloneAppsToInstall' -Value $StandaloneAppsToInstall -PropertyType 'MultiString' -Force
    }
    if ($StandaloneAppsToUninstall) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'StandaloneAppsToUninstall' -Value $StandaloneAppsToUninstall -PropertyType 'MultiString' -Force
    }
    if ($TrackingPath) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'TrackingPath' -Value $TrackingPath -Force
    }
    if ($NotificationLevel) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'NotificationLevel' -Value $NotificationLevel -Force
    }
    if ($AutoUpdate) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'AutoUpdate' -Value $AutoUpdate -PropertyType DWORD -Force
    }
    if ($AutoUpdateBlocklist) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'AutoUpdateBlocklist' -Value $AutoUpdateBlocklist -PropertyType 'MultiString' -Force
    }
    if ($UpdateFromInstallField) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UpdateFromInstallField' -Value $UpdateFromInstallField -PropertyType DWORD -Force
    }
    if ($RMMPlatform) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'RMMPlatform' -Value $RMMPlatform -Force
    }
    if ($LastRunField) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'LastRunField' -Value $LastRunField -Force
    }
    if ($LastRunStatusField) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'LastRunStatusField' -Value $LastRunStatusField -Force
    }
    if ($InstallField) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'InstallField' -Value $InstallField -Force
    }
    if ($UninstallField) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UninstallField' -Value $UninstallField -Force
    }
    if ($NotificationImageURL) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'NotificationImageURL' -Value $NotificationImageURL -Force
    }
    if ($NotificationTitle) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'NotificationTitle' -Value $NotificationTitle -Force
    }
    if ($UpdateInterval) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UpdateInterval' -Value $UpdateInterval -Force
    }
    if ($UpdateTime) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UpdateTime' -Value $UpdateTime -Force
    }
    if ($UpdateOnLogin) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UpdateOnLogin' -Value $UpdateOnLogin -PropertyType DWORD -Force
    }
    if ($DisableOnMetered) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'DisableOnMetered' -Value $DisableOnMetered -PropertyType DWORD -Force
    }
    if ($MachineScopeOnly) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'MachineScopeOnly' -Value $MachineScopeOnly -PropertyType DWORD -Force
    }
    if ($UseTaskScheduler) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'UseTaskScheduler' -Value $UseTaskScheduler -PropertyType DWORD -Force
    }
    if ($StoreUpdatesOriginalValue) {
        $null = New-ItemProperty -Path $RegistryPath -Name 'StoreUpdatesOriginalValue' -Value $StoreUpdatesOriginalValue -PropertyType DWORD -Force
    }
}
# Set Scope Machine function - sets WinGet's default installation scope to machine.
function Set-ScopeMachine {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - altering WinGet configuration.'
    )]
    [CmdletBinding()]
    param (
        # Require only machine scoped packages.
        [bool]$MachineScopeOnly
    )
    # Get the WinGet settings path.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        # Running in SYSTEM context.
        $SettingsPath = "$ENV:WinDir\system32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\"
        $SettingsFile = Join-Path -Path $SettingsPath -ChildPath 'settings.json'
        Write-NGLog -LogMsg ('Configuring WinGet to use machine scope for SYSTEM context.') -LogColour 'Yellow'
        Write-Verbose ('Configuring WinGet to use machine scope for SYSTEM context using config path: {0}' -f $SettingsFile)
    } else {
        # Running in user context.
        $SettingsPath = "$ENV:LocalAppData\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\"
        $SettingsFile = Join-Path -Path $SettingsPath -ChildPath 'settings.json'
        Write-NGLog -LogMsg ('Configuring WinGet to use machine scope for user context.') -LogColour 'Yellow'
        Write-Verbose ('Configuring WinGet to use machine scope for user context using config path: {0}' -f $SettingsFile)
    }
    # Create the settings directory if it doesn't exist.
    if (!(Test-Path $SettingsPath)) {
        New-Item -Path $SettingsPath -ItemType Directory -Force
    }
    # Check if the settings file already exists.
    if (Test-Path $SettingsFile) {
        # Check if the settings file already has the correct scope.
        $WinGetConfig = Get-Content $SettingsFile -Raw | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    if (!$WinGetConfig) {
        # Initialise a blank WinGet config object.
        $WinGetConfig = @{
            '$schema' = 'https://aka.ms/winget-settings.schema.json'
        }
    }
    if (!$WinGetConfig.'$schema') {
        Add-Member -InputObject $WinGetConfig -MemberType NoteProperty -Name '$schema' -Value 'https://aka.ms/winget-settings.schema.json' -Force
    }
    if ($WinGetConfig.installBehavior.preferences) {
        Add-Member -InputObject $WinGetConfig.installBehavior.preferences -MemberType NoteProperty -Name 'scope' -Value 'machine' -Force
    } elseif ($WinGetConfig.InstallBehaviour) {
        $Scope = New-Object -TypeName PSObject -Property $(@{ scope = 'machine' })
        Add-Member -InputObject $WinGetConfig.installBehavior -Name 'preferences' -MemberType NoteProperty -Value $Scope
    } else {
        $Scope = New-Object -TypeName PSObject -Property $(@{ scope = 'machine' })
        $Preference = New-Object -TypeName PSObject -Property $(@{ preferences = $Scope })
        Add-Member -InputObject $WinGetConfig -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force
    }
    if ($MachineScopeOnly) {
        if ($WinGetConfig.installBehavior.requirements) {
            Add-Member -InputObject $WinGetConfig.installBehavior.requirements -MemberType NoteProperty -Name 'scope' -Value 'machine' -Force
        } elseif ($WinGetConfig.installBehavior) {
            $Scope = New-Object -TypeName PSObject -Property $(@{ scope = 'machine' })
            Add-Member -InputObject $WinGetConfig.installBehavior -MemberType NoteProperty -Name 'requirements' -Value $Scope
        } else {
            $Scope = New-Object -TypeName PSObject -Property $(@{ scope = 'machine' })
            $Requirement = Add-Member -InputObject $WinGetConfig -MemberType PSObject -Property $(@{ requirements = $Scope })
            Add-Member -InputObject $WinGetConfig -MemberType NoteProperty -Name 'installBehavior' -Value $Requirement -Force
        }
    }
    Write-Debug ('WinGet config: {0}' -f ($WinGetConfig | ConvertTo-Json -Depth 10))
    $WinGetConfigJSON = $WinGetConfig | ConvertTo-Json -Depth 10
    Set-Content -Path $SettingsFile -Value $WinGetConfigJSON -Force
}
# Notification priority function - sets the notification priority for NinjaGet.
function Set-NotificationPriority {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - altering priority for notifications.'
    )]
    [CmdletBinding()]
    param(
        # Set for all users.
        [switch]$AllUsers
    )
    $NotificationSettingsPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $AppNotificationSettingsPath = (Join-Path -Path $NotificationSettingsPath -ChildPath 'NinjaGet.Notifications')
    $AbsoluteRegistryPath = (Join-Path -Path 'HKLM:\' -ChildPath $AppNotificationSettingsPath)
    if (!$AllUsers) {
        # Set for current user only.
        New-Item -Path $AbsoluteRegistryPath
        New-ItemProperty -Path $AbsoluteRegistryPath -Name 'AllowUrgentNotifications' -PropertyType 'DWord' -Value 1
    } else {
        # Set for all users.
        $RegistryInstance = @{
            Name = 'AllowUrgentNotifications'
            Type = 'Dword'
            Value = 1
            Path = $AppNotificationSettingsPath
        }
        Set-RegistryValueForAllUsers -RegistryInstance $RegistryInstance
    }
}