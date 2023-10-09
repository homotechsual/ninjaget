[CmdletBinding()]
param(
    # Skip the blocklist check.
    [bool]$SkipBlocklist = $false,
    # Standalone Mode
    [bool]$Standalone = $false
)
$Script:Standalone = $Standalone
$WorkingDir = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet' -Name 'InstallLocation' -ErrorAction SilentlyContinue
if (-not($WorkingDir)) {
    throw 'The NinjaGet installation directory could not be found in the registry. NinjaGet may not be properly installed.'   
}
$Functions = Get-ChildItem -Path (Join-Path -Path $WorkingDir -ChildPath 'PS') -Filter '*.ps1' -Exclude @('Send-NinjaGetNotification.ps1', 'Invoke-NinjaGetUpdates.ps1') -Recurse
foreach ($Function in $Functions) {
    Write-Verbose ('Importing function file: {0}' -f $Function.FullName)
    . $Function.FullName
}
$AutoUpdateBlocklist = Get-NinjaGetSetting -Setting 'AutoUpdateBlocklist'
$UpdateFromInstallField = Get-NinjaGetSetting -Setting 'UpdateFromInstallField'
$InstallField = Get-NinjaGetSetting -Setting 'InstallField'
$AppsToInstall = Get-AppsToInstall -AppInstallField $Script:InstallField
$AppsToUpdate = (Get-WinGetOutdatedPackages -source $Script:Source -acceptSourceAgreements | Select-Object -ExpandProperty Id) -join ' '
$UpdateApps = [System.Collections.Generic.List[string]]::new()
$SkipUpdateApps = [System.Collections.Generic.List[string]]::new()
if ($UpdateFromInstallField) {
    foreach ($App in $AppsToUpdate) {
        if ($App -in $AppsToInstall) {
            $UpdateApps.Add($App)
        } else {
            $SkipUpdateApps.Add($App)
        }
    }
} elseif (-not($SkipBlocklist) -and $AutoUpdateBlocklist) {
    foreach ($App in $AppsToUpdate) {
        if ($App -in $AutoUpdateBlocklist) {
            $SkipUpdateApps.Add($App)
        } else {
            $UpdateApps.Add($App)
        }
    }
} else {
    $UpdateApps = $AppsToUpdate
}
if ($UpdateApps.Count -gt 0) {
    Write-Verbose ('Updating apps: {0}' -f ($UpdateApps -join ', '))
    foreach ($App in $UpdateApps) {
        Update-Application -Application $App
    }
}