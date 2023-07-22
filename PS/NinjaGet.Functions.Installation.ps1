# Test WinGet version function - tests the version of WinGet against the latest version on GitHub.
function Test-WinGetVersion {
    param(
        [version]$InstalledWinGetVersion
    )
    $LatestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Method Get
    $LatestWinGetVersion = $LatestRelease.tag_name
    [version]$LatestWinGetVersion = $LatestWinGetVersion.TrimStart('v')
    if ($InstalledWinGetVersion -lt $LatestWinGetVersion) {
        Write-NGLog 'WinGet is out of date.' -LogColour 'Yellow'
        $Script:WinGetURL = $LatestRelease.assets.browser_download_url | Where-Object { $_.EndsWith('.msixbundle') }
        return $false
    } else {
        Write-NGLog 'WinGet is up to date.' -LogColour 'Green'
        return $true
    }
}
# Install WinGet function - installs WinGet if it is not already installed or is out of date.
function Install-WinGet {
    Write-NGLog 'WinGet not installed or out of date. Installing/updating...' -LogColour 'Yellow' # No sense determining this dynamically - we have to update the version check above anyway.
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
        } catch {
            Write-NGLog -LogMsg 'Failed to install the required Microsoft Visual C++ redistributables!' -LogColour 'Red'
            exit 1
        }
    }
    $WinGet = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' } -ErrorAction SilentlyContinue
    
    if ($WinGet) {
        # WinGet is installed - let's test the version.
        if ([Version]$WinGet.Version -ge $Script:WinGetVersion) {
            Write-NGLog 'WinGet is installed and up to date.' -LogColour 'Green'
        } else {
            Install-WinGet
        }
    } else {
        Install-WinGet
    }
}
# Register NinjaGet in the registry.
function Register-NinjaGetProgramEntry {
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
    $HKCR = Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    If (!($HKCR)) {
        $null = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script
    }
    $BaseRegPath = 'HKCR:\AppUserModelId'
    $AppId = 'Windows.SystemToast.NinjaGet.Notification'
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
    $null = Remove-PSDrive -Name HKCR -Force
}
# Scheduled task function - creates a scheduled task to run NinjaGet updater.
function Register-NinjaGetUpdaterScheduledTask {
    param(
        # The time to update at.
        [string]$TimeToUpdate = '16:00',
        # The update interval.
        [string]$UpdateInterval = 'Daily',
        # Whether to update at logon.
        [switch]$UpdateAtLogon
    )
    $TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -File `"$InstallPath\PS\Invoke-NinjaGetUpdates.ps1`""
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
    )
    $taskAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$InstallPath\VBS\hideui.vbs`" `"powershell.exe -NoProfile -File `"$InstallPath\PS\Invoke-NinjaGetNotification.ps1`""
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
# Configure NinjaGet settings in the registry.
function Register-NinjaGetSettings {
    param(
        [ValidateSet('Full', 'SuccessOnly', 'None')]
        # Notification level setting.
        [string]$NotificationLevel = 'Full',
        # Auto update setting.
        [int]$AutoUpdate = 1,
        # Auto update blocklist.
        [string[]]$AutoUpdateBlocklist = @(),
        # Disable updates on metered connections.
        [int]$DisableOnMetered = 1
    )
    $RegistryPath = 'HKLM:\SOFTWARE\NinjaGet'
    $null = New-Item -Path $RegistryPath -Force
    $null = New-ItemProperty -Path $RegistryPath -Name 'NotificationLevel' -Value $NotificationLevel -Force
    $null = New-ItemProperty -Path $RegistryPath -Name 'AutoUpdate' -Value $AutoUpdate -PropertyType DWORD -Force
    $null = New-ItemProperty -Path $RegistryPath -Name 'AutoUpdateBlocklist' -Value $AutoUpdateBlocklist -PropertyType 'MultiString' -Force
    $null = New-ItemProperty -Path $RegistryPath -Name 'DisableOnMetered' -Value $DisableOnMetered -PropertyType DWORD -Force
}