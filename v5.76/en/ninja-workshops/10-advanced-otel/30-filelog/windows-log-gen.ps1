# Define the log file
$LogFile = "quotes.log"

# Define quotes
$LOTRQuotes = @(
    "One does not simply walk into Mordor."
    "Even the smallest person can change the course of the future."
    "All we have to decide is what to do with the time that is given us."
    "There is some good in this world, and it's worth fighting for."
)

$StarWarsQuotes = @(
    "Do or do not, there is no try."
    "The Force will be with you. Always."
    "I find your lack of faith disturbing."
    "In my experience, there is no such thing as luck."
)

# Function to get a random quote
function Get-RandomQuote {
    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
        $LOTRQuotes | Get-Random
    } else {
        $StarWarsQuotes | Get-Random
    }
}

# Function to generate a log entry
function Generate-LogEntry {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLevel = Get-Random -InputObject "INFO", "WARN", "ERROR", "DEBUG"
    $Message = Get-RandomQuote
    return "$Timestamp [$LogLevel] - $Message"
}

# Main loop to write logs
Write-Host "Writing logs to $LogFile. Press Ctrl+C to stop."
while ($true) {
    $LogEntry = Generate-LogEntry
    Add-Content -Path $LogFile -Value $LogEntry
    Start-Sleep -Seconds 1 # Adjust this value for log frequency
}