# Log function - writes a message to the NinjaGet log file.
function Write-NGLog {
    param(
        # The message to write to the log file.
        [String]$LogMsg,
        # The colour of the log entry.
        [System.ConsoleColor]$LogColour = 'White'
    )
    # Create formatted log entry.
    $Log = "$(Get-Date -UFormat '%T') - $LogMsg"
    # Output log entry to the information stream.
    $MessageData = [System.Management.Automation.HostInformationMessage]@{
        Message = $Log
        ForegroundColor = $LogColour
    }
    Write-Information -MessageData $MessageData
    # Write log entry to the log file.
    $Log | Out-File -FilePath $Script:LogPath -Append
}