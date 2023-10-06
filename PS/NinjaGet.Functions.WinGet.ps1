# WhiteSpaceIsNull filter - returns null if the string is null or whitespace.
filter Assert-WhiteSpaceIsNull {
    if ([string]::IsNullOrWhiteSpace($_)) { $null } else { $_ }
}
# WinGet Source class - creates a WinGet source object or array of objects.
class WinGetSource {
    [string] $Name
    [string] $Argument
    [string] $Data
    [string] $Identifier
    [string] $Type
    # Empty constructor.
    WinGetSource () {}
    # Parameterised constructor.
    WinGetSource ([string]$name, [string]$argument, [string]$data, [string]$identifier, [string]$type) {
        $this.Name = $name.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Argument = $argument.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Data = $data.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Identifier = $identifier.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Type = $type.TrimEnd() | Assert-WhiteSpaceIsNull
    }
    # String array constructor.
    WinGetSource ([string[]]$source) {
        $this.name = $source[0].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Argument = $source[1].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Data = $source[2].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Identifier = $source[3].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Type = $source[4].TrimEnd() | Assert-WhiteSpaceIsNull
    }
    # Typed object constructor.
    WinGetSource ([WinGetSource]$source) {
        $this.Name = $source.Name.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Argument = $source.Argument.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Data = $source.Data.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Identifier = $source.Identifier.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Type = $source.Type.TrimEnd() | Assert-WhiteSpaceIsNull

    }
    # Typed object add method.
    [WinGetSource[]]Add ([WinGetSource]$source) {
        $FirstValue = [WinGetSource]::New($this)
        $SecondValue = [WinGetSource]::New($source)
        [WinGetSource[]]$Combined = @([WinGetSource]::New($FirstValue), [WinGetSource]::New($SecondValue))
        Return $Combined
    }
    # String array add method.
    [WinGetSource[]]Add ([String[]]$source) {
        $FirstValue = [WinGetSource]::New($this)
        $SecondValue = [WinGetSource]::New($source)
        [WinGetSource[]]$Combined = @([WinGetSource]::New($FirstValue), [WinGetSource]::New($SecondValue))
        Return $Combined
    }
}
# WinGet Package class - creates a WinGet package object or array of objects.
class WinGetPackage {
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$Available
    [string]$Source
    [string]$Match
    # Parameterised constructor.
    WinGetPackage ([string] $name, [string]$id, [string]$version, [string]$available, [string]$source) {
        $this.Name = $name.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Id = $id.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Version = $version.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Available = $available.TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Source = $source.TrimEnd() | Assert-WhiteSpaceIsNull
    }
    # Typed object constructor.
    WinGetPackage ([WinGetPackage] $package) {
        $this.Name = $package.Name | Assert-WhiteSpaceIsNull
        $this.Id = $package.Id | Assert-WhiteSpaceIsNull
        $this.Version = $package.Version | Assert-WhiteSpaceIsNull
        $this.Available = $package.Available | Assert-WhiteSpaceIsNull
        $this.Source = $package.Source | Assert-WhiteSpaceIsNull
    }
    # Generic object constructor.
    WinGetPackage ([psobject] $package) {
        $this.Name = $package.Name | Assert-WhiteSpaceIsNull
        $this.Id = $package.Id | Assert-WhiteSpaceIsNull
        $this.Version = $package.Version | Assert-WhiteSpaceIsNull
        $this.Available = $package.Available | Assert-WhiteSpaceIsNull
        $this.Source = $package.Source | Assert-WhiteSpaceIsNull
    }
    # String array constructor.
    WinGetPackage ([string[]]$package) {
        $this.name = $package[0].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Id = $package[1].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Version = $package[2].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Available = $package[3].TrimEnd() | Assert-WhiteSpaceIsNull
        $this.Source = $package[4].TrimEnd() | Assert-WhiteSpaceIsNull
    }
    # Typed object add method.
    [WinGetPackage[]]Add ([WinGetPackage] $package) {
        $FirstValue = [WinGetPackage]::New($this)
        $SecondValue = [WinGetPackage]::New($package)
        [WinGetPackage[]]$Combined = @([WinGetPackage]::New($FirstValue), [WinGetPackage]::New($SecondValue))
        Return $Combined
    }
    # String array add method.
    [WinGetPackage[]]Add ([String[]]$package) {
        $FirstValue = [WinGetPackage]::New($this)
        $SecondValue = [WinGetPackage]::New($package)
        [WinGetPackage[]]$Combined = @([WinGetPackage]::New($FirstValue), [WinGetPackage]::New($SecondValue))
        Return $Combined
    }
}
# Get WinGet command function - gets the path to the WinGet executable.
function Get-WinGetCommand {
    [CmdletBinding()]
    param()
    # Get the WinGet path (for use when running in SYSTEM context).
    $WinGetPathToResolve = Join-Path -Path $ENV:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe'
    $ResolveWinGetPath = Resolve-Path -Path $WinGetPathToResolve | Sort-Object {
        [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
    }
    if ($ResolveWinGetPath) {
        # If we have multiple versions - use the latest.
        $WinGetPath = $ResolveWinGetPath[-1].Path
    }
    # Get the WinGet exe location.
    $WinGetExePath = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($WinGetExePath) {
        # Running in user context.
        $Script:WinGet = $WinGetExePath.Path
    } elseif (Test-Path -Path (Join-Path $WinGetPath 'winget.exe')) {
        # Running in SYSTEM context.
        $Script:WinGet = Join-Path $WinGetPath 'winget.exe'
    } else {
        Write-NGLog -LogMsg 'WinGet not installed or could not be detected!' -LogColour 'Red'
        break
    }
    # Pre-accept the source agreements using the `list` command.
    $Null = & $Script:WinGet list --accept-source-agreements -s winget
    # Log the WinGet version and path.
    $WingetVer = & $Script:WinGet --version
    Write-NGLog "Winget Version: $WingetVer"
    Write-NGLog -LogMsg "Using WinGet path: $Script:WinGet"
}
# Start WinGet process function - starts the WinGet process and captures the output.
function Start-WinGetProcess {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - invoking a WinGet process.'
    )]
    [CmdletBinding()]
    param(
        # The arguments to pass to the WinGet process.
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        # Disable error handling.
        [switch]$NoErrorHandling
    )
    $ProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $ProcessInfo.FileName = $Script:WinGet
    $ProcessInfo.Arguments = $Arguments
    Write-Verbose ('Running WinGet process with the following arguments: {0}' -f $ProcessInfo.Arguments.ToString())
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $ProcessInfo
    $Process.Start() | Out-Null
    $Process.WaitForExit()
    [string[]]$WinGetProcessOutput = $Process.StandardOutput.ReadToEnd()
    Write-Debug "WinGet process output: $WinGetProcessOutput"
    Write-Debug "WinGet exit code: $($Process.ExitCode)"
    if ($Process.ExitCode -ne 0 -and !$NoErrorHandling) {
        switch ($Process.ExitCode) {
            -1978335230 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INVALID_CL_ARGUMENTS - Invalid command line arguments were provided.'
            }
            -1978335216 {
                $FullError = 'APPINSTALLER_CLI_ERROR_NO_APPLICABLE_INSTALLER - No installer package was found matching the configured settings.'
            }
            -1978335215 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALLER_HASH_MISMATCH - The installer package hash did not match the expected value.'
            }
            -1978335212 {
                $FullError = 'APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND - No applications were found matching the configured settings.'
            }
            -1978335211 {
                $FullError = 'APPINSTALLER_CLI_ERROR_NO_SOURCES_DEFINED - No sources were defined.'
            }
            -1978335210 {
                $FullError = 'APPINSTALLER_CLI_ERROR_MULTIPLE_APPLICATIONS_FOUND - Multiple applications were found matching the configured settings.'
            }
            -1978335209 {
                $FullError = 'APPINSTALLER_CLI_ERROR_NO_MANIFEST_FOUND - No manifest was found matching the configured settings.'
            }
            -1978335207 {
                $FullError = 'APPINSTALLER_CLI_COMMAND_REQUIRES_ADMIN - The command requires administrator privileges.'
            }
            -1978335206 {
                $FullError = 'APPINSTALLER_CLI_SOURCE_NOT_SECURE - The source is not secure.'
            }
            -1978335205 {
                $FullError = 'APPINSTALLER_CLI_MSSTORE_BLOCKED_BY_POLICY - The Microsoft Store client is blocked by policy.'
            }
            -1978335204 {
                $FullError = 'APPINSTALLER_CLI_MSSTORE_APP_BLOCKED_BY_POLICY - The Microsoft Store app is blocked by policy.'
            }
            -1978335202 {
                $FullError = 'APPINSTALLER_CLI_ERROR_MSSSTORE_INSTALL_FAILED - The Microsoft Store app failed to install.'
            }
            -1978335189 {
                $FullError = 'APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE - The update is not applicable.'
            }
            -1978335188 {
                $FullError = 'APPINSTALLER_CLI_ERROR_UPDATE_ALL_HAS_FAILURES - One or more updates failed.'
            }
            -1978335187 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALLER_SECURITY_CHECK_FAILED - The installer security check failed.'
            }
            -1978335186 {
                $FullError = 'APPINSTALLER_CLI_ERROR_DOWNLOAD_SIZE_MISMATCH - The downloaded file size did not match the expected value.'
            }
            -1978335185 {
                $FullError = 'APPINSTALLER_CLI_ERROR_NO_UNINSTALL_INFO_FOUND - No uninstall information was found.'
            }
            -1978335184 {
                $FullError = 'APPINSTALLER_CLI_ERROR_EXEC_UNINSTALL_COMMAND_FAILED - The uninstall command failed.'
            }
            -1978334975 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_PACKAGE_IN_USE - The application is currently running.'
            }
            -1978334974 {
                $FulLError = 'APPINSTALLER_CLI_ERROR_INSTALL_INSTALL_IN_PROGRESS - Another installation is already in progress.'
            }
            -1978334973 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_FILE_IN_USE - One or more files are in use.'
            }
            -1978334972 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_MISSING_DEPENDENCY - A dependency required to install the application is missing.'
            }
            -1978334971 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_DISK_FULL - The disk is full.'
            }
            -1978334970 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_INSUFFICIENT_MEMORY - There is insufficient memory to install the application.'
            }
            -1978334969 {
                $FullError = 'APPINSTALLER_CLI_ERROR_INSTALL_NO_NETWORK - There is no network connectivity.'
            }
            -1978334719 {
                $FullError = 'WINGET_INSTALLED_STATUS_ARP_ENTRY_NOT_FOUND - The application was not found in the add or remove programs list.'
            }
            -1978334718 {
                $FullError = 'WINGET_INSTALLED_STATUS_INSTALL_LOCATION_NOT_APPLICABLE - The application was installed from a location that is not applicable.'
            }
            -1978334716 {
                $FullError = 'WINGET_INSTALLED_STATUS_FILE_HASH_MISMATCH - The application file hash does not match the expected value.'
            }
            -1978334715 {
                $FullError = 'WINGET_INSTALLED_STATUS_FILE_NOT_FOUND - The application file was not found.'
            }
            -1978334714 {
                $FullError = 'WINGET_INSTALLED_STATUS_FILE_FOUND_WITHOUT_HASH_CHECK - The application file was found but the hash was not checked.'
            }
            -1978334713 {
                $FullError = 'WINGET_INSTALLED_STATUS_FILE_ACCESS_ERROR - There was an error accessing the application file.'
            }
        }
        if ($FullError) {
            Write-NGLog -LogMsg ('WinGet command invocation failed with the following error.{0}Error: {1}.' -f [System.Environment]::NewLine, $FullError) -LogColour 'Red'
        } else {
            Write-NGLog -LogMsg ('WinGet command invocation failed with the following exit code. Exit code: {0}' -f $Process.ExitCode) -LogColour 'Red'
        }
        $Output = [pscustomobject]@{
            ProcessOutput = $WinGetProcessOutput
            ExitCode = $Process.ExitCode
            IsSuccess = $Process.ExitCode -eq 0
        }
    } else {
        $Output = [pscustomobject]@{
            ProcessOutput = $WinGetProcessOutput
            ExitCode = $Process.ExitCode
            IsSuccess = $Process.ExitCode -eq 0
        }
    }
    Write-Debug "WinGet command output: $($Output | ConvertTo-Json -Depth 10)"
    return $Output
}
# Invoke WinGet command function - used to invoke the WinGet command and return the output as a PowerShell object or array of objects.
Function Invoke-WinGetCommand {
    [CmdletBinding()]
    param(
        # The arguments to pass to the winget command.
        [Parameter(Position = 0, Mandatory)]
        [string[]]$Arguments,
        # The properties to return from the winget command output.
        [Parameter(Position = 0, Mandatory)]
        [string[]]$Properties,
        # Expecting JSON output.
        [switch]$JSON
    )
    begin {
        Write-Debug -Message "Invoke-WinGetCommand arguments: $($Arguments -join ' ')"
        Write-Debug -Message "Invoke-WinGetCommand properties: $($Properties -join ' | ')"
        $Index = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Result = [System.Collections.Generic.List[PSCustomObject]]::new()
        $i = 0
        $PropertiesCount = $Properties.Count
        $Offset = 0
        $Found = $false
        ## Split the output into an array of lines and remove the ASCII characters Γ, Ç and ª.
        $WinGetSourceListRaw = (Start-WinGetProcess -Arguments $Arguments).ProcessOutput.Split([System.Environment]::NewLine) | ForEach-Object {
            $_ -replace ("$([char]915)|$([char]199)|$([char]170)", '')
        }
    }
    process {
        if ($JSON) {
            ## If expecting JSON content, return the object
            return $WinGetSourceListRaw | ConvertFrom-Json
        }
        Write-Debug -Message "Invoke-WinGetCommand raw output: $($WinGetSourceListRaw)"
        ## Gets the indexing of each title
        $regex = $Properties -join '|'
        for ($Offset = 0; $Offset -lt $WinGetSourceListRaw.Length; $Offset++) {
            if ($WinGetSourceListRaw[$Offset].Split(' ')[0].Trim() -match $regex) {
                $Found = $true
                break
            }
        }
        if (!$Found) {
            Write-NGLog 'No packages found for the specified arguments.' -LogColour 'Red'
            return
        }
        foreach ($Property in $Properties) {
            ## Creates an array of titles and their string location
            $IndexStart = $WinGetSourceListRaw[$Offset].IndexOf($Property)
            $IndexEnds = ''
            if ($IndexStart -ne '-1') {
                $Index.Add(
                    [pscustomobject]@{
                        Name = $Property
                        Start = $IndexStart
                        Ends  = $IndexEnds
                    }
                )
            }
        }
        ## Orders the Object based on Index value
        $Index = $Index | Sort-Object Start
        ## Sets the end of string value
        while ($i -lt $PropertiesCount) {
            $i ++
            ## Sets the End of string value (if not null)
            if ($Index[$i].Start) {
                $Index[$i - 1].Ends = ($Index[$i].Start - 1) - $Index[$i - 1].Start 
            }
        }
        ## Builds the WinGetSource Object with contents
        $i = $Offset + 2
        while ($i -lt $WinGetSourceListRaw.Length) {
            $row = $WinGetSourceListRaw[$i]
            try {
                [bool]$TestNotTitles = $WinGetSourceListRaw[0] -ne $row
                [bool]$TestNotHyphenLine = $WinGetSourceListRaw[1] -ne $row -and !$row.Contains('---')
                [bool]$TestNotNoResults = $row -ne 'No package found matching input criteria.'
                [bool]$TestNotUpgradesAvailable = $row -notlike '*upgrade* available.'
                
            } catch {
                Wait-Debugger
            }
            if (!$TestNotNoResults) {
                Write-NGLogEntry -LogEntry 'No package found matching input criteria.' -LogColour 'Red'
            }
            ## If this is the first pass containing titles or the table line, skip.
            if ($TestNotTitles -and $TestNotHyphenLine -and $TestNotNoResults -and $TestNotUpgradesAvailable) {
                $List = @{}
                foreach ($item in $Index) {
                    if ($item.Ends) {
                        Write-Debug -Message "Invoke-WinGetCommand row: $row"
                        $List[$Item.Name] = $row.SubString($item.Start, $item.Ends).Trim()
                    } else {
                        Write-Debug -Message "Invoke-WinGetCommand row: $row"
                        $List[$item.Name] = $row.SubString($item.Start, $row.Length - $Item.Start).Trim()
                    }
                }
                $result.Add([pscustomobject]$list)
            }
            $i++
        }
        Write-Debug -Message "Invoke-WinGetCommand result: $($Result | Out-String)"
    }
    end {
        return $Result
    }
}
# Find WinGet package function - finds a WinGet package from the WinGet repository.
function Find-WinGetPackage {
    [CmdletBinding()]
    param(
        # The package id to find.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to find the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('search')
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source)
        }
        if ($PSBoundParameters.ContainsKey('exact')) {
            $WGCommandArguments.Add('--exact')
        }
        if ($PSBoundParameters.ContainsKey('acceptSourceAgreements')) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        # Set the properties we're looking to retrieve from the output.
        [string[]]$Properties = @('Name', 'Id', 'Version', 'Available', 'Source')
    }
    process {
        $Packages = [System.Collections.Generic.List[WinGetPackage]]::new()
        # Run the WinGet command and get the output.
        $WinGetOutputObjects = Invoke-WinGetCommand -Arguments $WGCommandArguments -Properties $Properties
        # Cast the output to [WinGetPackage] objects.
        foreach ($Package in $WinGetOutputObjects) {
            $Packages.Add([WinGetPackage]::new($Package))
        }
    }
    end {
        return $Packages
    }
}
# Confirm WinGet package exists function - confirms a WinGet package exists in the WinGet repository.
function Confirm-WinGetPackageExists {
    [CmdletBinding()]
    param(
        # The package id to show.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to show the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the WinGet command arguments.
        $StartWGArguments = [System.Collections.Generic.List[string]]::new()
        $StartWGArguments.Add('show')
        if ($PSBoundParameters.ContainsKey('id')) {
            $StartWGArguments.Add('--id')
            $StartWGArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $StartWGArguments.Add('--source')
            $StartWGArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $StartWGArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $StartWGArguments.Add('--accept-source-agreements')
        }
    }
    process {
        # Run the WinGet command and get the output.
        $WinGetOutput = (Start-WinGetProcess -Arguments $StartWGArguments).ProcessOutput
        if ($WinGetOutput -match [regex]::Escape($id) -AND $WinGetOutput -notmatch [regex]::Escape('Installer Type:')) {
            Write-NGLog -LogMsg "Application '$id' exists in WinGet repository but no applicable installer scope or type was found." -LogColour 'Red'
            $Result = $false
        } elseif ($WinGetOutput -match [regex]::Escape($id)) {
            Write-NGLog -LogMsg "Application '$id' exists in WinGet repository." -LogColour 'Cyan'
            $Result = $true
        } else {
            Write-NGLog -LogMsg "Application '$id' does not exist in WinGet repository." -LogColour 'Red'
            $Result = $false
        }
    }
    end {
        # Return the result.
        return $Result
    }
}
# Confirm WinGet Package installed function - confirms a WinGet package is installed on the system.
function Confirm-WinGetPackageInstalled {
    [CmdletBinding()]
    param(
        # The package id to show.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to show the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the WinGet command arguments.
        $StartWGArguments = [System.Collections.Generic.List[string]]::new()
        $StartWGArguments.Add('list')
        if ($PSBoundParameters.ContainsKey('id')) {
            $StartWGArguments.Add('--id')
            $StartWGArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $StartWGArguments.Add('--source')
            $StartWGArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $StartWGArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $StartWGArguments.Add('--accept-source-agreements')
        }
    }
    process {
        # Run the WinGet command and get the output.
        $WinGetOutput = (Start-WinGetProcess -Arguments $StartWGArguments -NoErrorHandling).ProcessOutput
        if ($WinGetOutput -match [regex]::Escape('No installed package found matching input criteria.')) {
            Write-NGLog -LogMsg "Application '$id' is not installed." -LogColour 'Red'
            $Result = $false
        } elseif ($WinGetOutput -match [regex]::Escape($id)) {
            Write-NGLog -LogMsg "Application '$id' is installed." -LogColour 'Cyan'
            $Result = $true
        } else {
            Write-NGLog -LogMsg "Application '$id' does not exist in WinGet repository." -LogColour 'Red'
            $Result = $false
        }
    }
    end {
        # Return the result.
        return $Result
    }
}
# Confirm WinGet package version function - confirms a WinGet package is installed on the system and is the correct version.
function Confirm-WinGetPackageInstalledVersion {
    param(
        # The package id to check.
        [Parameter(Mandatory)]
        [string]$id,
        # The package version to check.
        [Parameter(Mandatory)]
        [string]$version,
        # The source to show the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the Get-WinGetInstalledPackages command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('exact')) {
            $WGCommandArguments.Add('--exact')
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('acceptSourceAgreements')) {
            $WGCommandArguments.Add('--acceptSourceAgreements')
        }
    }
    process {
        # Populate the tracking file with all installed apps.
        $InstalledApps = Get-WinGetInstalledPackages @WGCommandArguments
        if ($version) {
            # Check for the specific application and version.
            $Apps = $InstalledApps | Where-Object { $_.id -eq $id -and $_.version -like "$version*" }
        } else {
            # Check for the specific application.
            $Apps = $InstalledApps | Where-Object { $_.id -eq $id }
        }
        # Boolean return based on whether the application is installed.
        if ($Apps) {
            $Result = $true
        } else {
            $Result = $false
        }
    }
    end {
        # Return the result.
        return $Result
    }
}
# Get WinGet installed package function - gets packages installed on the system.
function Get-WinGetInstalledPackages {
    [CmdletBinding()]
    param(
        # The package id to get.
        [string]$id,
        # The source to get the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('list')
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $WGCommandArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        # Set the properties we're looking to retrieve from the output.
        [string[]]$Properties = @('Name', 'Id', 'Version', 'Available', 'Source')
    }
    process {
        $Packages = [System.Collections.Generic.List[WinGetPackage]]::new()
        # Run the WinGet command and get the output.
        $WinGetOutputObjects = Invoke-WinGetCommand -Arguments $WGCommandArguments -Properties $Properties
        # Cast the output to [WinGetPackage] objects.
        foreach ($Package in $WinGetOutputObjects) {
            $Packages.Add([WinGetPackage]::new($Package))
        }
    }
    end {
        # Return the packages.
        return $Packages
    }
}
# Get WinGet outdated package function - gets outdated packages installed on the system.
function Get-WinGetOutdatedPackages {
    [CmdletBinding()]
    param(
        # The source to get the packages from.
        [string]$source = 'winget',
        # Accept source agreements.
        [switch]$acceptSourceAgreements
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('upgrade')

        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($acceptSourceAgreements) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        # Set the properties we're looking to retrieve from the output.
        [string[]]$Properties = @('Name', 'Id', 'Version', 'Available', 'Source')
    }
    process {
        $Packages = [System.Collections.Generic.List[WinGetPackage]]::new()
        # Run the WinGet command and get the output.
        $WinGetOutputObjects = Invoke-WinGetCommand -Arguments $WGCommandArguments -Properties $Properties
        # Cast the output to [WinGetPackage] objects.
        foreach ($Package in $WinGetOutputObjects) {
            $Packages.Add([WinGetPackage]::new($Package))
        }
        if ($Script:IsSystem -eq $false) {
            $SystemApps = Get-Content -Path $Script:SystemAppsTrackingFile
            $Packages = $Packages | Where-Object { $SystemApps -notcontains $_.Id }
        }
    }
    end {
        # Return the packages.
        return $Packages
    }
}
# Get System Apps function - gets a list of system apps from WinGet.
function Get-WinGetSystemApps {
    # Populate the system apps tracking file with the current list of system apps.
    $WinGetCommandArguments = [System.Collections.Generic.List[string]]::new()
    $WinGetCommandArguments.Add('export')
    $WinGetCommandArguments.Add('--output')
    $WinGetCommandArguments.Add("`"$Script:SystemAppsTrackingFile`"")
    $WinGetCommandArguments.Add('--accept-source-agreements')
    $WinGetCommandArguments.Add('--source')
    $WinGetCommandArguments.Add('winget')
    $null = Start-WinGetProcess -Arguments $WinGetCommandArguments
    # Pull the content so we can reformat it to a list of app IDs.
    $SystemApps = Get-Content $Script:SystemAppsTrackingFile | ConvertFrom-Json | Sort-Object
    # Pull the app IDs from the list.
    return $SystemApps.Sources.Packages | ForEach-Object { $_.PackageIdentifier }
}
# Install WinGet package function - installs a WinGet package.
function Install-WinGetPackage {
    [CmdletBinding()]
    param(
        # The package id to install.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to install the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements,
        # Arguments to pass to the installer.
        [string]$arguments
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('install')
        $WGCommandArguments.Add('--silent')
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $WGCommandArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        if ($arguments) {
            $WGCommandArguments.Add('--custom')
            $WGCommandArguments.Add($arguments.Replace('...', ''))
        }
    }
    process {
        # Run the WinGet command.
        $null = Start-WinGetProcess -Arguments $WGCommandArguments
    }
}
# Update WinGet package function - updates a WinGet package.
function Update-WinGetPackage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Narrowly defined system state change - updating application.'
    )]
    [CmdletBinding()]
    param(
        # The package id to update.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to update the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements,
        # Arguments to pass to the installer.
        [string]$arguments
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('upgrade')
        $WGCommandArguments.Add('--silent')
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $WGCommandArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        if ($arguments) {
            $WGCommandArguments.Add('--custom')
            $WGCommandArguments.Add($arguments.Replace('...', ''))
        }
    }
    process {
        # Run the WinGet command.
        $null = Start-WinGetProcess -Arguments $WGCommandArguments
    }
}
# Uninstall WinGet package function - uninstalls a WinGet package.
function Uninstall-WinGetPackage {
    [CmdletBinding()]
    param(
        # The package id to install.
        [Parameter(Mandatory)]
        [string]$id,
        # The source to install the package from.
        [string]$source = 'winget',
        # Exact matches only.
        [switch]$exact,
        # Accept source agreements.
        [switch]$acceptSourceAgreements,
        # Arguments to pass to the installer.
        [string]$arguments
    )
    begin {
        # Build the WinGet command arguments.
        $WGCommandArguments = [System.Collections.Generic.List[string]]::new()
        $WGCommandArguments.Add('uninstall')
        $WGCommandArguments.Add('--silent')
        if ($PSBoundParameters.ContainsKey('id')) {
            $WGCommandArguments.Add('--id')
            $WGCommandArguments.Add($id.Replace('...', ''))
        }
        if ($PSBoundParameters.ContainsKey('source')) {
            $WGCommandArguments.Add('--source')
            $WGCommandArguments.Add($source.Replace('...', ''))
        }
        if ($exact) {
            $WGCommandArguments.Add('--exact')
        }
        if ($acceptSourceAgreements) {
            $WGCommandArguments.Add('--accept-source-agreements')
        }
        if ($arguments) {
            $WGCommandArguments.Add('--custom')
            $WGCommandArguments.Add($arguments.Replace('...', ''))
        }
    }
    process {
        # Run the WinGet command.
        $null = Start-WinGetProcess -Arguments $WGCommandArguments
    }
}