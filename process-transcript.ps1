# Processes the PowerShell transcript and updates context.json

param(
    [string]$TranscriptPath
)

# --- Configuration ---
$ContextPath = "D:\gemini_context\context.json"
$LogFile = "D:\gemini_context\process-transcript.log"

# --- Functions ---
function Write-Log($Message) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File -FilePath $LogFile -Append
}

# --- Main ---
Write-Log "--- Starting Transcript Processing ---"
Write-Host "[DEBUG] TranscriptPath: $TranscriptPath"

if (-not (Test-Path $TranscriptPath)) {
    Write-Log "Transcript file not found at '$TranscriptPath'. Exiting."
    Write-Host "[DEBUG] Error: Transcript file not found at $TranscriptPath."
    exit
}

# Read the entire transcript file
Write-Log "Reading entire transcript file: $TranscriptPath"
$lines = Get-Content $TranscriptPath

Write-Host "[INFO] Read entire file. Content length: $($lines.Length)"

# Extract timestamp from transcript header
$transcriptStartTime = ""
foreach ($line in $lines) {
    if ($line -match "Start time: (\d{14})") {
        $transcriptStartTime = $Matches[1]
        break
    }
}

if ([string]::IsNullOrEmpty($transcriptStartTime)) {
    Write-Log "WARNING: Could not find 'Start time:' in transcript header. Using current time for backup filename."
    $transcriptStartTime = (Get-Date -Format "yyyyMMddHHmmss") # Fallback to current time if not found
}

# Insert underscore into timestamp for filename format YYYYMMDD_HHmmss
$formattedTimestamp = $transcriptStartTime.Insert(8, '_')
$NewBackupFileName = "session_backup_$($formattedTimestamp).json"
$NewBackupPath = Join-Path "D:\gemini_context\context_history" $NewBackupFileName

# Manually build the JSON to avoid serialization issues
Write-Log "Manually constructing JSON to avoid serialization errors..."

# 1. Escape each line and wrap in quotes
$jsonLines = foreach ($line in $lines) {
    $escapedLine = $line -replace '\\', '\\\\' -replace '"', '\"' -replace '`b', '`b' -replace '`f', '`f' -replace '`n', '`n' -replace '`r', '`r' -replace '`t', '`t'
    '"' + $escapedLine + '"'
}

# 2. Join the lines into a JSON array string
$contentAsJsonArray = '[' + ($jsonLines -join ',') + ']'

# 3. Escape the transcript path
$escapedPath = $TranscriptPath -replace '\\', '\\\\'

# 4. Construct the final JSON object string
$finalJson = @"
{
    "raw_transcript_content": $contentAsJsonArray,
    "timestamp": "$transcriptStartTime", # Use extracted timestamp here
    "original_transcript_path": "$escapedPath"
}
"@

# 5. Write to file
Write-Host "[INFO] Saving to JSON backup: $NewBackupPath"
$finalJson | Set-Content -Path $NewBackupPath -Encoding UTF8
Write-Host "[SUCCESS] Successfully wrote JSON backup to: $NewBackupPath"

# Call the context indexing script to update context_index.json with the new session backup
Write-Log "Calling summarize-context.ps1 to update context_index.json with new session backup: $NewBackupPath"
& "D:\summarize-context.ps1" -NewSessionBackupPath $NewBackupPath -ShowProgressBar
Write-Log "summarize-context.ps1 call finished."


Write-Log "--- Transcript Processing Finished ---"

Write-Host "Transcript processed and context.json updated successfully."
