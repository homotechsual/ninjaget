# Outdated Apps function - gets a list of outdated apps from WinGet.
function Get-OutdatedApps {
    # Setup a class to store the app information.
    class App {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }
    # Run winget upgrade and store the output.
    $UpgradeResult = & $Script:WinGet upgrade --source winget | Out-String
    # Convert the output to an array - start by looking for the output '-----' which indicates that nothing was returned by the command.
    if (-not($UpgradeResult -match '-----')) {
        return ('No apps were found to upgrade or an error occured:`n{0}' -f $UpgradeResult)
    }
    # Split the output to an array of lines.
    $Lines = $UpgradeResult.Split([Environment]::NewLine) | Where-Object { $_ }

    # Search for lines that start with "------"
    $FindLine = 0
    while (-not $Lines[$FindLine].StartsWith('-----')) {
        $FindLine++
    }
    # Identify the header line
    $HeaderLine = $FindLine - 1
    # Get the header title by splitting the line on whitespace.
    $HeaderTitle = $Lines[$HeaderLine] -split '\s+'
    # Index into the header line to find the start of the ID, Version and Available columns.
    $AppIdStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[1])
    $AppVersionStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[2])
    $AppAvailableStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[3])
    # Create a list to store the apps.
    $UpgradeList = [System.Collections.Generic.List[App]]::new()
    # Loop through the lines and find the apps.
    For ($i = $HeaderLine + 2; $i -lt $Lines.Length; $i++) {
        $Line = $Lines[$i]
        if ($Line.StartsWith('-----')) {
            #Get header line
            $HeaderLine = $i - 1
            #Get header titles
            $HeaderTitle = $Lines[$HeaderLine] -split '\s+'
            # Index into the header line to find the start of the ID, Version and Available columns.
            $AppIdStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[1])
            $AppVersionStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[2])
            $AppAvailableStart = $Lines[$HeaderLine].IndexOf($HeaderTitle[3])
        }
        # Find a line that contains the pattern `character.character` which indicates that it is an app.
        if ($Line -match '\w\.\w') {
            $App = [App]::new()
            $App.Name = $Line.Substring(0, $AppIdStart).TrimEnd()
            $App.Id = $Line.Substring($AppIdStart, $AppVersionStart - $AppIdStart).TrimEnd()
            $App.Version = $Line.Substring($AppVersionStart, $AppAvailableStart - $AppVersionStart).TrimEnd()
            $App.AvailableVersion = $Line.Substring($AppAvailableStart).TrimEnd()
            # Add the App object to the list.
            $UpgradeList.Add($App)
        }
    }

    #If current user is not system, remove system apps from list
    if ($Script:IsSystem -eq $false) {
        $SystemApps = Get-Content -Path $Script:SystemAppsTrackingFile
        $UpgradeList = $UpgradeList | Where-Object { $SystemApps -notcontains $_.Id }
    }

    return $UpgradeList | Sort-Object { Get-Random }
}
# Get System Apps function - gets a list of system apps from WinGet.
function Get-WinGetSystemApps {
    # Populate the system apps tracking file with the current list of system apps.
    $null = & $Script:WinGet export -o $Script:SystemAppsTrackingFile --accept-source-agreements -s winget
    # Pull the content so we can reformat it to a list of app IDs.
    $SystemApps = Get-Content $Script:SystemAppsTrackingFile -Raw | ConvertFrom-Json | Sort-Object
    # Pull the app IDs from the list.
    Set-Content $SystemApps.Sources.Packages.PackageIdentifier -Path $Script:SystemAppsTrackingFile
}
# Install function - installs an application.
function Install-Application {
    param(
        # The application ID.
        [string]$ApplicationId,
        # The arguments to pass to the uninstall command.
        [string]$Arguments
    )
    # Check if the application is already installed.
    if (Confirm-AppInstalled $ApplicationId) {
        Write-NGLog -LogMsg "Application '$ApplicationId' already installed." -LogColour 'Cyan'
    } else {
        # Check if the application exists in the WinGet repository.
        if (Confirm-AppExists $ApplicationId) {
            # Install the application.
            Write-NGLog -LogMsg "Installing application '$ApplicationId'..." -LogColour 'Cyan'
            # Build and send the notification.
            $Title = "$($ApplicationId) will be installed."
            $Message = "The administrator has determined that $($ApplicationId) should be installed."
            $MessageType = 'information'
            $AppName = $ApplicationId
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
            & $Script:WinGet install --id $ApplicationId -e --accept-source-agreements $Arguments
            # Check if the application was installed successfully.
            if (Confirm-AppInstalled $ApplicationId) {
                Write-NGLog -LogMsg "Application '$ApplicationId' installed successfully." -LogColour 'Green'
                # Build and send the notification.
                $Title = "$($ApplicationId) has been installed."
                $Message = "$($ApplicationId) has been successfully installed."
                $MessageType = 'success'
                $AppName = $ApplicationId
                $Script:InstallOK += 1
                Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
                # Update the tracking file.
                Update-TrackingRecord $ApplicationId 'Install'
            } else {
                Write-NGLog -LogMsg "Application '$ApplicationId' failed to install." -LogColour 'Red'
                # Build and send the notification.
                $Title = "$($ApplicationId) was not installed."
                $Message = "$($ApplicationId) could not be installed."
                $MessageType = 'error'
                $AppName = $ApplicationId
                Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
            }
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
    # Check if the application is already installed.
    if (Confirm-AppInstalled $ApplicationId) {
        # Uninstall the application.
        Write-NGLog -LogMsg "Uninstalling application '$ApplicationId'..." -LogColour 'Cyan'
        # Build and send the notification.
        $Title = "$($ApplicationId) will be uninstalled."
        $Message = "The administrator has determined that $($ApplicationId) should be uninstalled."
        $MessageType = 'warning'
        $AppName = $ApplicationId
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        & $Script:WinGet uninstall --id $ApplicationId -e --accept-source-agreements $Arguments
        # Check if the application was uninstalled successfully.
        if (!Confirm-AppInstalled $ApplicationId) {
            Write-NGLog -LogMsg "Application '$ApplicationId' uninstalled successfully." -LogColour 'Green'
            # Build and send the notification.
            $Title = "$($ApplicationId) has been uninstalled."
            $Message = "$($ApplicationId) has been successfully uninstalled."
            $MessageType = 'success'
            $AppName = $ApplicationId
            $Script:UninstallOK += 1
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
            # Update the tracking file.
            Update-TrackingRecord $ApplicationId 'Uninstall'
        } else {
            Write-NGLog -LogMsg "Application '$ApplicationId' failed to uninstall." -LogColour 'Red'
            # Build and send the notification.
            $Title = "$($ApplicationId) was not uninstalled."
            $Message = "$($ApplicationId) could not be uninstalled."
            $MessageType = 'error'
            $AppName = $ApplicationId
            Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
        }
    } else {
        Write-NGLog -LogMsg "Application '$ApplicationId' not installed." -LogColour 'Cyan'
    }
}
# Update function - update an application.
function Update-Application {
    param(
        # The application object.
        [Object]$Application
    )
    # Get the release notes for the application.
    $ReleaseNotes = Get-AppReleaseNotes -ApplicationId $Application.id
    # Send a notification to the user.
    Write-Log -LogMsg "Updating $($Application.Name) from $($Application.Version) to $($Application.AvailableVersion)..." -LogColour 'Cyan'
    # Build and send the notification.
    $Title = "$($Application.Name) will be updated"
    $Message = "Version $($Application.AvailableVersion) is available for $($Application.Name), the current version is $($Application.Version)."
    $MessageType = 'information'
    $AppName = $Application.Name
    Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName -ButtonAction $ReleaseNotes -ButtonText 'Changelog'
    Write-NGLog "Invoking winget upgrade --id $($Application.Id) --accept-package-agreements --accept-source-agreements -h"
    & $Winget upgrade --id $($Application.Id) --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append
    $FailedToUpdate = $false
    $ConfirmInstall = Confirm-Installation -ApplicationId $($Application.Id) $($Application.AvailableVersion)
    if ($ConfirmInstall -eq $false) {
        $FailedToUpdate = $true
    }
    if (-not($FailedToUpdate)) {
        Write-NGLog "$($Application.Name) updated successfully to $($Application.AvailableVersion)" -LogColour 'Green'
        # Build and send the notification.
        $Title = "$($Application.Name) has updated."
        $Message = "$($Application.Name) has been updated to version $($Application.AvailableVersion)."
        $MessageType = 'success'
        $AppName = $Application.Name
        $Script:InstallOK += 1
        Invoke-NinjaGetNotification -Title $Title -Message $Message -MessageType $MessageType -AppName $AppName
    } else {
        Write-NGLog "$($Application.Name) failed to update to $($Application.AvailableVersion)" -LogColour 'Red'
        # Build and send the notification.
        $Title = "$($Application.Name) failed to update."
        $Message = "$($Application.Name) failed to update to version $($Application.AvailableVersion)."
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