[CmdletBinding()]
$Script:WorkingDir = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet' -Name 'InstallLocation' -ErrorAction SilentlyContinue
if (-not($Script:WorkingDir)) {
    throw 'The NinjaGet installation directory could not be found in the registry. NinjaGet may not be properly installed.'   
}
$Functions = Get-ChildItem -Path (Join-Path -Path $WorkingDir -ChildPath 'PS') -Filter '*.ps1' -Exclude @('Send-NinjaGetNotification.ps1', 'Invoke-NinjaGetUpdate.ps1') -Recurse
foreach ($Function in $Functions) {
    Write-Verbose ('Importing function file: {0}' -f $Function.FullName)
    . $Function.FullName
}