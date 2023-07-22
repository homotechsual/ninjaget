[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'All', Justification = 'This script is not intended to be run interactively.')]
param (
    # The operation to perform. Valid values are Install, Uninstall and Check.
    [Parameter(Mandatory)]
    [ValidateSet('Setup', 'Install', 'Uninstall', 'Update', 'Check', 'RotateLogs')]
    [string]$Operation,
    # The application ids to install or uninstall.
    [string[]]$ApplicationIds,
    # Allow the "install" application ids to be automatically update when NinjaGet runs autoupdate jobs.
    [switch]$AutoUpdate,
    # Auto update blocklist. Application ids in this list will not be automatically updated when NinjaGet runs autoupdate jobs.
    [string[]]$AutoUpdateBlocklist = @(),
    # The path to install the NinjaGet files to. Default is $ENV:ProgramData\NinjaGet.
    [System.IO.DirectoryInfo]$InstallPath = (Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaGet'),
    # The path to the NinjaGet log files. Default is $ENV:ProgramData\NinjaGet\Logs.
    [System.IO.DirectoryInfo]$LogPath = (Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaGet\Logs'),
    # The path to the NinjaGet tracking files. These files are used to track the installation status of applications. Default is $ENV:ProgramData\NinjaGet\Tracking.
    [System.IO.DirectoryInfo]$TrackingPath = (Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaGet\Tracking'),
    # The name of the RMM platform. Currently only NinjaOne is implemented.
    [ValidateSet('NinjaOne')]
    [string]$RMMPlatform = 'NinjaOne',
    # The name of the field in the RMM platform which will hold the last run date.
    [string]$LastRunField = 'NGLastRun',
    # The name of the field in the RMM platform which will hold the last run status.
    [string]$LastRunStatusField = 'NGLastRunStatus',
    # The name of the field in tphe RMM platform which holds the applications to install. (Comma-separated list)
    [string]$InstallField = 'NGInstall',
    # The name of the field in the RMM platform which holds the applications to uninstall. (Comma-separated list)
    [string]$UninstallField = 'NGUninstall',
    # The URL to the image to use for the user notifications.
    [string]$NotificationImageURL = 'https://raw.githubusercontent.com/homotechsual/NinjaGet/main/resources/installing-updates.png',
    # The title of the user notification application.
    [string]$NotificationTitle = 'Software Updater',
    # Override the WinGet package version to test for. This is the latest version as at 2023-07-05. Microsoft use different versioning for the installed AppXPackage and the GitHub releases, so we can't determine this programmatically.
    [version]$WinGetVersion = '2023.417.2324.0',
    # Override the WinGet package download URL for the version to install if the constraint above is not met.
    [uri]$WinGetURL = 'https://github.com/microsoft/winget-cli/releases/download/v1.4.11071/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle',
    # Set the update interval for the NinjaGet package update job.
    [string]$UpdateInterval = 'Daily',
    # Set the time of day to run the NinjaGet package update job.
    [string]$UpdateTime = '16:00',
    # Run package updates on login.
    [switch]$UpdateOnLogin
)

# Initialization function - sets up the environment for NinjaGet.
function Initialize-NinjaGet {
    # Store a variable for the current user's name (removing any characters not safe for filenames).
    $InvalidCharacters = [IO.Path]::GetInvalidFileNameChars() -join ''
    $RegEx = '[{0}]' -f [regex]::Escape($InvalidCharacters)
    $Script:UserName = ($ENV:UserName -replace $RegEx)
    # Set the NinjaGet install path.
    $Script:InstallPath = $InstallPath
    # Set the NinjaGet version.
    $Script:Version = '0.0.1'
    # Create the NinjaGet log path if it doesn't exist.
    if (!(Test-Path $LogPath)) {
        $null = New-Item -ItemType Directory -Force -Path $LogPath
    }
    # Setup differs depending on whether NinjaGet is running as SYSTEM or not.
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:RunAsSystem = $true
        $Script:LogFile = Join-Path -Path $LogPath -ChildPath 'NinjaGet.log'
    } else {
        $Script:RunAsSystem = $false
        $Script:LogFile = Join-Path -Path $LogPath -ChildPath 'NinjaGet.log'
    }
    # Create the log file if it doesn't exist.
    if (!(Test-Path $LogFile)) {
        $null = New-Item -ItemType File -Force -Path $LogFile
    }
    # Set the ACL on the log file.
    $Acl = Get-Acl $LogFile
    $Identity = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::AuthenticatedUserSid, $null)
    $FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify
    $AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    $AccessRule = [System.Security.AccessControl.FileSystemAccessRule]::new($Identity, $FileSystemRights, $AccessControlType)
    $Acl.SetAccessRule($AccessRule)
    Set-Acl -Path $LogFile -AclObject $Acl
    # Create the NinjaGet tracking path if it doesn't exist.
    if (!(Test-Path $TrackingPath)) {
        $null = New-Item -ItemType Directory -Force -Path $TrackingPath
    }
    # Set the NinjaGet tracking file paths.
    $Script:TrackingPath = $TrackingPath
    $Script:InstalledAppsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.installedapps.tracking'
    $Script:SystemAppsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.systemapps.tracking'
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:OperationsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath 'NinjaGet.operations.tracking'
    } else {
        $Script:OperationsTrackingFile = Join-Path -Path $Script:TrackingPath -ChildPath ('NinjaGet{0}.operations.tracking' -f $Script:UserName)
    }
    # Set the operation and application ids if present.
    $Script:Operation = $Operation
    $Script:ApplicationIds = $ApplicationIds
    # Set the auto update and auto update blocklist variables.
    $Script:AutoUpdate = $AutoUpdate
    $Script:AutoUpdateBlocklist = $AutoUpdateBlocklist
    # Set the WinGet version and download URL.
    $Script:WinGetVersion = $WinGetVersion
    $Script:WinGetURL = $WinGetURL
    # Set the various RMM information used by NinjaGet.
    $Script:RMMPlatform = $RMMPlatform
    $Script:LastRunField = $LastRunField
    $Script:LastRunStatusField = $LastRunStatusField
    $Script:InstallField = $InstallField
    $Script:UninstallField = $UninstallField
}
$OIP = $InformationPreference
$InformationPreference = 'Continue'
$Script:WorkingDir = $Script:InstallPath
Write-Debug "Working directory is $WorkingDir"
$PowerShellFunctions = Get-ChildItem -Path (Join-Path -Path $WorkingDir -ChildPath 'PS') -Filter '*.ps1' -Recurse
foreach ($Function in $PowerShellFunctions) {
    Write-Verbose ('Importing function file: {0}' -f $Function.FullName)
    . $Function.FullName
}
Initialize-NinjaGet
if ($Script:RunAsSystem) {
    Write-NGLog -LogMsg 'Running as SYSTEM.' -LogColour 'White'
    Set-ScopeMachine
} else {
    Write-NGLog -LogMsg 'Running as user.' -LogColour 'White'
}
Test-NinjaGetPrerequisites
Register-NinjaGetProgramEntry
Register-NotificationApp
Register-NinjaGetUpdaterScheduledTask
Get-WinGetCommand
Set-ScopeMachine
if ($Script:Operation -eq 'Install') {
    $Script:InstallOK = 0
    $AppsToInstall = Get-AppsToInstall -AppInstallField $Script:InstallField
    foreach ($App in $AppsToInstall) {
        Install-Application -ApplicationId $App
    }
    $OutdatedApps = Get-OutdatedApps
    foreach ($App in $OutdatedApps) {
        Update-Application -Application $App
    }
    if ($Script:InstallOK -gt 0) {
        Write-NGLog "Installed or updated $InstallOK applications" 'Green'
    }
}
$InformationPreference = $OIP