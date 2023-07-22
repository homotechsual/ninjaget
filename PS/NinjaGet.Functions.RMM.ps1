# Last Run function - sets the last run time for the script in supported RMM platforms.
function Update-LastRun {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Does not change system state.')]
    [cmdletbinding()]
    param()
    # Get the current time.
    $CurrentTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
    if ($Script:RMMPlatform -eq 'NinjaOne') {
        # Set the last run time.
        Ninja-Property-Set -Name $LastRunField -Value $CurrentTime
    } elseif ($Script:RMMPlatform -eq 'Syncro') {
        # Set the last run time.
        # ToDo add syncro logic.
    } elseif ($Script:RMMPlatform -eq 'Datto') {
        # Set the last run time.
        # ToDo add datto logic.
    }
}
# Last Run Status function - sets the last run status for the script in supported RMM platforms.
function Update-LastRunStatus {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Does not change system state.')]
    [cmdletbinding()]
    param(
        # The status to set.
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failure')]
        [string]$Status
    )
    if ($Script:RMMPlatform -eq 'NinjaOne') {
        # Set the last run status.
        Ninja-Property-Set -Name $LastRunStatusField -Value $Status
    } elseif ($Script:RMMPlatform -eq 'Syncro') {
        # Set the last run status.
        # ToDo add syncro logic.
    } elseif ($Script:RMMPlatform -eq 'Datto') {
        # Set the last run status.
        # ToDo add datto logic.
    }
}
# Parse Application Install function - parses the application install field.
function Get-AppsToInstall {
    param(
        # The application install field.
        [Parameter(Mandatory)]
        [string]$AppInstallField
    )
    if ($Script:RMMPlatform -eq 'NinjaOne') {
        # Get the application install field.
        $AppsToInstall = Ninja-Property-Get -Name $AppInstallField
    } elseif ($Script:RMMPlatform -eq 'Syncro') {
        # Get the application install field.
        # ToDo add syncro logic.
    } elseif ($Script:RMMPlatform -eq 'Datto') {
        # Get the application install field.
        # ToDo add datto logic.
    }
    # Return the application install field.
    return $AppsToInstall
}
# Parse Application Uninstall function - parses the application uninstall field.
function Get-AppsToUninstall {
    param(
        # The application uninstall field.
        [Parameter(Mandatory)]
        [string]$AppUninstallField
    )
    if ($Script:RMMPlatform -eq 'NinjaOne') {
        # Get the application uninstall field.
        $AppsToUninstall = Ninja-Property-Get -Name $AppUninstallField
    } elseif ($Script:RMMPlatform -eq 'Syncro') {
        # Get the application uninstall field.
        # ToDo add syncro logic.
    } elseif ($Script:RMMPlatform -eq 'Datto') {
        # Get the application uninstall field.
        # ToDo add datto logic.
    }
    # Return the application uninstall field.
    return $AppsToUninstall
}