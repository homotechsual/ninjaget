# Test NinjaGet installed - make sure that the NinjaGet setup has run by testing the NinjaGet registry key exists.
function Test-NinjaGetInstalled {
    if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet') {
        return $true
    } else {
        return $false
    }
}
# Test internet connection - tests if the computer has an internet connection.
function Test-InternetConnection {
    $TimeOut = 0
    While ($TimeOut -lt 1800) {
        $TestURI = 'https://raw.githubusercontent.com/homotechsual/ninjaget/main/LICENSE.md'
        $TestContent = (Invoke-WebRequest -Uri $TestURI -UseBasicParsing).Content
        if ($TestContent -match 'MIT License') {
            Write-NGLog -LogMsg 'Internet connection is available.' -LogColour 'Green'
            return $true
        } else {
            Write-NGLog -LogMsg 'Internet connection is not available.' -LogColour 'Red'
            return $false
        }
    }
}
# Test metered connection - tests if the network connection is metered.
function Test-MeteredConnection {
    [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
    $InternetConnectionProfile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    $ConnectivityCost = $InternetConnectionProfile.GetConnectionCost()
    if ($ConnectivityCost.NetworkCostType -in @([Windows.Networking.Connectivity.NetworkCostType]::Fixed, [Windows.Networking.Connectivity.NetworkCostType]::Variable)) {
        Write-NGLog -LogMsg 'Network connection is metered.' -LogColour 'DarkMagenta'
        return $true
    } else {
        Write-NGLog -LogMsg 'Network connection is not metered.' -LogColour 'Green'
        return $false
    }
}
# Tracking function - tracks the installation of applications.
function Write-Tracking ([string]$ApplicationId, [string]$Operation) {
    # Get the tracking file content and convert from JSON.
    $ExistingTracking = Get-Content $Script:OperationsTrackingFile -ErrorAction SilentlyContinue -Raw | ConvertFrom-Json
    # If the tracking file is empty, create a new object.
    if (!$ExistingTracking) {
        $Tracking = [PSCustomObject]@{
            Install   = [System.Collections.Generic.List[object]]::new()
            Uninstall = [System.Collections.Generic.List[object]]::new()
        }
    } else {
        # Reconstruct the tracking file objects.
        $Tracking = [PSCustomObject]@{
            Install   = [System.Collections.Generic.List[object]]::new()
            Uninstall = [System.Collections.Generic.List[object]]::new()
        }
        $Tracking.Install.AddRange($ExistingTracking.Install)
        $Tracking.Uninstall.AddRange($ExistingTracking.Uninstall)
    }
    # Check that the tracking file has the expected structure.
    if (!$Tracking.Install) {
        $Tracking.Install = [System.Collections.Generic.List[object]]::new()
    } else {
        $Tracking.Install.AddRange($Tracking.Install)
    }
    if (!$Tracking.Uninstall) {
        $Tracking.Uninstall = [System.Collections.Generic.List[object]]::new()
    } else {
        $Tracking.Uninstall.AddRange($Tracking.Uninstall)
    }
    # Check if the application is already tracked to be installed.
    if ($Tracking.Install.Contains($ApplicationId)) {
        if ($Operation -eq 'Uninstall') {
            # Check if the application is still installed.
            if (-not(Confirm-WinGetPackageInstalled -id $ApplicationId)) {
                # Remove the application from the install tracking and add it to the uninstall tracking.
                if ($Tracking.Install.Contains($ApplicationId)) {
                    $Tracking.Install.Remove($ApplicationId)
                }
                if (-not($Tracking.Uninstall.Contains($ApplicationId))) {
                    $Tracking.Uninstall.Add($ApplicationId)
                }
                $Tracking | Out-File -FilePath $Script:OperationsTrackingFile -Force
                Write-NGLog -LogMsg "Application '$ApplicationId' is no longer installed. Added to uninstall tracking." -LogColour 'DarkMagenta'
            }
        } elseif ($Operation -eq 'Install') {
            # Check if the application is already installed.
            if (Confirm-WinGetPackageInstalled -id $ApplicationId) {
                Write-NGLog -LogMsg "Application '$ApplicationId' is already installed and is already tracked as installed." -LogColour 'DarkMagenta'
            }
        }
    } elseif ($Tracking.Uninstall.Contains($ApplicationId)) {
        if ($Operation -eq 'Install') {
            # Check if the application is still uninstalled.
            if (Confirm-WinGetPackageInstalled -id $ApplicationId) {
                # Remove the application from the uninstall tracking and add it to the install tracking.
                if ($Tracking.Uninstall.Contains($ApplicationId)) {
                    $Tracking.Uninstall.Remove($ApplicationId)
                }
                if (-not($Tracking.Install.Contains($ApplicationId))) {
                    $Tracking.Install.Add($ApplicationId)
                }
                $Tracking | Out-File -FilePath $Script:OperationsTrackingFile -Force
                Write-NGLog -LogMsg "Application '$ApplicationId' is no longer uninstalled. Added to install tracking." -LogColour 'DarkMagenta'
            }
        } elseif ($Operation -eq 'Install') {
            # Check if the application is already uninstalled.
            if (-not(Confirm-WinGetPackageInstalled -id $ApplicationId)) {
                Write-NGLog -LogMsg "Application '$ApplicationId' is already uninstalled and is already tracked as uninstalled." -LogColour 'DarkMagenta'
            }
        }
    } else {
        # Add the application to the tracking file.
        if ($Operation -eq 'Uninstall') {
            if (-not($Tracking.Uninstall.Contains($ApplicationId))) {
                $Tracking.Uninstall.Add($ApplicationId)
            }
        } elseif ($Operation -eq 'Install') {
            if (-not($Tracking.Install.Contains($ApplicationId))) {
                $Tracking.Install.Add($ApplicationId)
            }
        }
        $Tracking | ConvertTo-Json -Depth 5 | Out-File -FilePath $Script:OperationsTrackingFile -Force
        Write-NGLog -LogMsg "Application '$ApplicationId' added to tracking file." -LogColour 'DarkMagenta'
    }
}
# Set registry value for all users function - sets a registry value for all users using Active Setup.
function Set-RegistryValueForAllUsers {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - sets an Active Setup job to run a registry edit for all users.'
    )]
    <#
    .SYNOPSIS
        This function uses Active Setup to create a "seeder" key which creates or modifies a user-based registry value
        for all users on a computer. If the key path doesn't exist to the value, it will automatically create the key and add the value.
    .EXAMPLE
        PS> Set-RegistryValueForAllUsers -RegistryInstance @{'Name' = 'Setting'; 'Type' = 'String'; 'Value' = 'someval'; 'Path' = 'SOFTWARE\Microsoft\Windows\Something'}
    
        This example would modify the string registry value 'Type' in the path 'SOFTWARE\Microsoft\Windows\Something' to 'someval'
        for every user registry hive.
    .PARAMETER RegistryInstance
        A hash table containing key names of 'Name' designating the registry value name, 'Type' to designate the type
        of registry value which can be 'String,Binary,Dword,ExpandString or MultiString', 'Value' which is the value itself of the
        registry value and 'Path' designating the parent registry key the registry value is in.
    .LINK
        https://github.com/Adam-the-Automator/Scripts/blob/main/Set-RegistryValueForAllUsers.ps1
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable[]]$RegistryInstance
    )
    try {
        New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS | Out-Null
        # Change the registry values for the currently logged on user. Each logged on user SID is under HKEY_USERS
        $LoggedOnSIDs = (Get-ChildItem HKU: | Where-Object { $_.Name -match 'S-\d-\d+-(\d+-){1,14}\d+' }) | Select-Object -ExpandProperty PSChildName
        Write-Verbose "Found $($LoggedOnSIDs.Count) logged on user SIDs"
        foreach ($SID in $LoggedOnSIDs) {
            Write-Verbose -Message "Loading the user registry hive for the logged on SID $SID"
            foreach ($Instance in $RegistryInstance) {
                ## Create the key path if it doesn't exist
                New-Item -Path "HKU:\$SID\$($Instance.Path | Split-Path -Parent)" -Name ($Instance.Path | Split-Path -Leaf) -Force | Out-Null
                ## Create (or modify) the value specified in the param
                Set-ItemProperty -Path "HKU:\$SID\$($Instance.Path)" -Name $Instance.Name -Value $Instance.Value -Type $Instance.Type -Force
            }
        }
        ## Create the Active Setup registry key so that the reg add cmd will get ran for each user
        ## logging into the machine.
        ## http://www.itninja.com/blog/view/an-active-setup-primer
        Write-Verbose 'Setting Active Setup registry value to apply to all other users'
        foreach ($Instance in $RegistryInstance) {
            ## Generate a unique value (usually a GUID) to use for Active Setup
            $Guid = [guid]::NewGuid().Guid
            $ActiveSetupRegParentPath = 'HKLM:\Software\Microsoft\Active Setup\Installed Components'
            ## Create the GUID registry key under the Active Setup key
            New-Item -Path $ActiveSetupRegParentPath -Name $Guid -Force | Out-Null
            $ActiveSetupRegPath = "HKLM:\Software\Microsoft\Active Setup\Installed Components\$Guid"
            Write-Verbose "Using registry path '$ActiveSetupRegPath'"
            
            ## Convert the registry value type to one that reg.exe can understand.  This will be the
            ## type of value that's created for the value we want to set for all users
            switch ($instance.Type) {
                'String' {
                    $RegValueType = 'REG_SZ'
                }
                'Dword' {
                    $RegValueType = 'REG_DWORD'
                }
                'Binary' {
                    $RegValueType = 'REG_BINARY'
                }
                'ExpandString' {
                    $RegValueType = 'REG_EXPAND_SZ'
                }
                'MultiString' {
                    $RegValueType = 'REG_MULTI_SZ'
                }
                default {
                    throw "Registry type '$($instance.Type)' not recognized"
                }
            }
            
            ## Build the registry value to use for Active Setup which is the command to create the registry value in all user hives
            $ActiveSetupValue = 'reg add "{0}" /v {1} /t {2} /d {3} /f' -f "HKCU\$($instance.Path)", $instance.Name, $RegValueType, $instance.Value
            Write-Verbose -Message "Active setup value is '$ActiveSetupValue'"
            ## Create the necessary Active Setup registry values
            Set-ItemProperty -Path $ActiveSetupRegPath -Name '(Default)' -Value 'Active Setup Test' -Force
            Set-ItemProperty -Path $ActiveSetupRegPath -Name 'Version' -Value '1' -Force
            Set-ItemProperty -Path $ActiveSetupRegPath -Name 'StubPath' -Value $ActiveSetupValue -Force
        }
    } catch {
        Write-Warning -Message $_.Exception.Message
    }
}
# Remove file on reboot function - removes a file on reboot.
function Remove-FileOnReboot {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - removes a file on reboot.'
    )]
    [CmdletBinding()]
    param(
        # The path to the file to remove on reboot.
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $Mover = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Mover {
    public enum MoveFileFlags {
        MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004
    }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, MoveFileFlags dwFlags);
    public static bool MarkFileDelete (string sourcefile) {
        return MoveFileEx(sourcefile, null, MoveFileFlags.MOVEFILE_DELAY_UNTIL_REBOOT);         
    }
}
'@

    Add-Type -TypeDefinition $Mover -Language CSharp
    $RemoveResult = [Mover]::MarkFileDelete($FilePath)
    if ($RemoveResult) {
        Write-Verbose -Message ("Successfully marked file '{0}' for removal on reboot" -f $FilePath)
    } else {
        Write-Warning -Message ("Failed to mark file '{0}' for removal on reboot" -f $FilePath)
        throw [ComponentModel.Win32Exception]::new()
    }
}
# Set ACL function - sets the ACL for various NinjaGet files and folders to allow the 'Authenticated Users' group to modify them.
function Set-NinjaGetACL {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - altering ACLs for NinjaGet files and folders.'
    )]
    [CmdletBinding()]
    param(
        # The path to set the ACL for.
        [string]$Path
    )
    $Acl = Get-Acl $Path
    $Identity = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::AuthenticatedUserSid, $null)
    $FileSystemRights = @([System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.FileSystemRights]::Modify)
    $Inheritance = [System.Security.AccessControl.FileSystemRights]::ObjectInherit -bor [System.Security.AccessControl.FileSystemRights]::ContainerInherit
    $Propagation = [System.Security.AccessControl.PropagationFlags]::InheritOnly
    $AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    $AccessRule = [System.Security.AccessControl.FileSystemAccessRule]::new($Identity, $FileSystemRights, $Inheritance, $Propagation, $AccessControlType)
    $Acl.SetAccessRule($AccessRule)
    Set-Acl -Path $Path -AclObject $Acl
}