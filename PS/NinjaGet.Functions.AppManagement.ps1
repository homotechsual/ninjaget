# Install function - installs an application.
function Install-Application {
    [CmdletBinding()]
    param(
        # The application ID.
        [string]$ApplicationId,
        # The arguments to pass to the application installer.
        [string]$Arguments
    )
    # Check if the application is already installed.
    # Confirm the package exists.
    if (-not(Confirm-WinGetPackageExists -id $ApplicationId -exact -acceptSourceAgreements)) {
        return
        # Confirm the package is not already installed.
    } elseif (Confirm-WinGetPackageInstalled -id $ApplicationId) {
        Write-NGLog -LogMsg ('Requested install of {0} but it is already installed.' -f $ApplicationId) -LogColour 'Yellow'
    } else {
        # Get the package information.
        $Package = Find-WinGetPackage -id $ApplicationId -exact -acceptSourceAgreements
        # Install the application.
        Write-NGLog -LogMsg "Installing application '$($Package.Name)'..." -LogColour 'Cyan'
        # Build and send the notification.
        $Title = "$($Package.Name) will be installed."
        $Message = "The administrator has determined that $($Package.Name) should be installed."
        $MessageType = 'information'
        $AppName = $($Package.Name)
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        Install-WinGetPackage -id $Package.id -exact -acceptSourceAgreements -arguments $Arguments
        # Check if the application was installed successfully.
        if (Confirm-WinGetPackageInstalled -id $Package.Id) {
            Write-NGLog -LogMsg "Application '$($Package.Name) installed successfully." -LogColour 'Green'
            # Build and send the notification.
            $Title = "$($Package.Name) has been installed."
            $Message = "$($Package.Name) has been successfully installed."
            $MessageType = 'success'
            $AppName = $($Package.Name)
            $Script:InstallOK += 1
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
            # Update the tracking file.
            Write-Tracking -ApplicationId $($Package.id) -Operation 'Install'
        } else {
            Write-NGLog -LogMsg "Application '$($Package.Name)' failed to install. Error: $LASTEXITCODE" -LogColour 'Red'
            # Build and send the notification.
            $Title = "$($Package.Name) was not installed."
            $Message = "$($Package.Name) could not be installed."
            $MessageType = 'error'
            $AppName = $($Package.Name)
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        }
    }
}
# Uninstall function - uninstalls an application.
function Uninstall-Application {
    param(
        # The application ID.
        [string]$ApplicationId,
        # The arguments to pass to the uninstall command.
        [string]$Arguments
    )
    # Confirm the package exists - needed so WinGet can remove it.
    $Package = Find-WinGetPackage -id $ApplicationId -exact -acceptSourceAgreements
    if (-not ($Package)) {
        return
        # Confirm the package is already installed.
    } elseif (-not(Confirm-WinGetPackageInstalled -id $ApplicationId -exact -acceptSourceAgreements)) {
        Write-NGLog -LogMsg ('Requested uninstall of {0} but it is not installed.' -f $Package.Name) -LogColour 'Cyan'
    } else {
        # Uninstall the application.
        Write-NGLog -LogMsg "Uninstalling application '$ApplicationId'..." -LogColour 'Cyan'
        # Build and send the notification.
        $Title = "$($Package.Name) will be uninstalled."
        $Message = "The administrator has determined that $($Package.Name) should be uninstalled."
        $MessageType = 'warning'
        $AppName = $Package.Name
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        Uninstall-WinGetPackage -id $Package.id -exact -acceptSourceAgreements -arguments $Arguments
        # Check if the application was uninstalled successfully.
        if (-not(Confirm-WinGetPackageInstalled -id $ApplicationId)) {
            Write-NGLog -LogMsg "Application '$($Package.Name)' uninstalled successfully." -LogColour 'Green'
            # Build and send the notification.
            $Title = "$($Package.Name) has been uninstalled."
            $Message = "$($Package.Name) has been successfully uninstalled."
            $MessageType = 'success'
            $AppName = $Package.Name
            $Script:UninstallOK += 1
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
            # Update the tracking file.
            Write-Tracking -ApplicationId $($Package.id) -Operation 'Uninstall'
        } else {
            Write-NGLog -LogMsg "Application '$($Package.Name)' failed to uninstall." -LogColour 'Red'
            # Build and send the notification.
            $Title = "$($Package.Name) was not uninstalled."
            $Message = "$($Package.Name) could not be uninstalled."
            $MessageType = 'error'
            $AppName = $Package.Name
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        }
    }
}
# Update function - update an application.
function Update-Application {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - updating application.'
    )]
    param(
        # The application object.
        [Object]$Application
    )
    # Get the release notes for the application.
    $ReleaseNotes = Get-AppReleaseNotes -ApplicationId $Application.id
    # Send a notification to the user.
    Write-NGLog -LogMsg "Updating $($Application.Name) from $($Application.Version) to $($Application.Available)..." -LogColour 'Cyan'
    # Build and send the notification.
    $Title = "$($Application.Name) will be updated"
    $Message = "Version $($Application.Available) is available for $($Application.Name), the current version is $($Application.Version)."
    $MessageType = 'information'
    $AppName = $Application.Name
    Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName -ButtonAction $ReleaseNotes -ButtonText 'Changelog'
    Write-NGLog "Invoking winget to update $($Application.Name) to $($Application.Available)..."
    Update-WingetPackage -id $Application.id -source $Script:Source -exact -acceptSourceAgreements
    $FailedToUpdate = $false
    $ConfirmUpdate = Confirm-WinGetPackageInstalledVersion -Id $($Application.Id) -Version $($Application.Available)
    if ($ConfirmUpdate -eq $false) {
        $FailedToUpdate = $true
    }
    if (-not($FailedToUpdate)) {
        Write-NGLog "$($Application.Name) updated successfully to $($Application.Available)" -LogColour 'Green'
        # Build and send the notification.
        $Title = "$($Application.Name) has updated."
        $Message = "$($Application.Name) has been updated to version $($Application.Available)."
        $MessageType = 'success'
        $AppName = $Application.Name
        $Script:InstallOK += 1
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
    } else {
        Write-NGLog "$($Application.Name) failed to update to $($Application.Available)" -LogColour 'Red'
        # Build and send the notification.
        $Title = "$($Application.Name) failed to update."
        $Message = "$($Application.Name) failed to update to version $($Application.Available)."
        $MessageType = 'error'
        $AppName = $Application.Name
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
    }
}
# Blocklist fetch function - gets the blocklist from registry.
function Get-AppBlocklist {
    $BlockList = Get-ItemProperty -Path 'HKLM:\SOFTWARE\NinjaGet' -Name 'BlockList' -ErrorAction SilentlyContinue
    if ($BlockList) {
        $BlockedApps = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\NinjaGet' -Name 'BlockList'
    }
    return $BlockedApps
}
# Blocklist lookup function - checks if an application is in the blocklist.
function Confirm-AppBlocked ([string]$ApplicationId) {
    $BlockList = Get-AppBlocklist
    if ($BlockList) {
        $Blocked = $BlockList -contains $ApplicationId
        return $Blocked
    }
}
# Release notes function - gets the release notes for an application.
function Get-AppReleaseNotes {
    param(
        # The application ID.
        [string]$ApplicationId
    )
    # Get the release notes for the application.
    $AppInfo = & $Script:WinGet show --id $ApplicationId --accept-source-agreements -s winget | Out-String
    # Get the release notes from the app info.
    $ReleaseNotes = [regex]::Match($AppInfo, '(?<=Release Notes Url: )(.*)(?=\n)').Groups[0].Value
    # Return the release notes.
    return $ReleaseNotes
}
# Tracking test function - checks if the tracking files exist.
