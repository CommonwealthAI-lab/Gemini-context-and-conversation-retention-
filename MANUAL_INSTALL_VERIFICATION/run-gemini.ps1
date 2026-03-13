# This script runs the main logic for the Gemini session.
# It is always executed with administrator privileges by start-gemini.ps1.

param(
    [string]$HistoricalBackupPath = ""
)

# --- Configuration ---
$TranscriptFileName = "session_transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$TranscriptPath = "D:\gemini_context\context_history\$TranscriptFileName"
$ProcessTranscriptScript = "D:\process-transcript.ps1"
$ContextJsonPath = "D:\gemini_context\context.json"
$ContextIndexPath = "D:\gemini_context\context_index.json"

# --- Main Logic ---

Write-Host "Starting Gemini session..."

# 2. Change to the D: drive
cd D:\

# --- Conditionally update context index with progress bar ---
Write-Host "Checking context index status..."
$ContextHistoryPath = "D:\gemini_context\context_history"
$ContextIndexFile = "D:\gemini_context\context_index.json"
$IndexNeedsUpdate = $false

# Get last updated time from context_index.json
$lastIndexUpdateTime = $null
if (Test-Path $ContextIndexFile) {
    try {
        $contextIndexContent = Get-Content $ContextIndexFile -Raw | ConvertFrom-Json -ErrorAction Stop
        $lastIndexUpdateTime = [datetime]::Parse($contextIndexContent.last_updated)
    } catch {
        Write-Host "[WARNING] Failed to read or parse context_index.json. Index will be rebuilt." -ForegroundColor Yellow
        $IndexNeedsUpdate = $true
    }
} else {
    Write-Host "[INFO] context_index.json not found. Index will be rebuilt." -ForegroundColor Yellow
    $IndexNeedsUpdate = $true
}

# Get last write time of the most recent session_backup_*.json
$latestBackupFile = Get-ChildItem -Path $ContextHistoryPath -Filter "session_backup_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestBackupWriteTime = $null
if ($latestBackupFile) {
    $latestBackupWriteTime = $latestBackupFile.LastWriteTime
}

# Determine if index needs update
if (-not $IndexNeedsUpdate -and $latestBackupWriteTime -and $lastIndexUpdateTime -lt $latestBackupWriteTime) {
    Write-Host "[INFO] Context index is older than the latest backup file. Index will be rebuilt." -ForegroundColor Yellow
    $IndexNeedsUpdate = $true
} elseif (-not $IndexNeedsUpdate -and -not $latestBackupWriteTime -and -not $lastIndexUpdateTime) {
    # No backups and no index, nothing to do.
    $IndexNeedsUpdate = $false
} elseif (-not $IndexNeedsUpdate) {
    Write-Host "[INFO] Context index is up-to-date." -ForegroundColor Green
}

if ($IndexNeedsUpdate) {
    Write-Host "Updating context index..."
    try {
        & D:\summarize-context.ps1 -ShowProgressBar -ErrorAction Stop > $null
        Write-Host "Context index update completed." -ForegroundColor Green
    } catch {
        Write-Host "[CRITICAL WARNING] Failed to update the context index. The index may be out of date. Starting session anyway." -ForegroundColor Yellow
    }
}



# --- Transcript Handling ---
Write-Host "Handling transcript..."
# Attempt to stop any lingering transcript from a previous session.
Stop-Transcript -ErrorAction SilentlyContinue

# 1. Start a clean transcript with a unique filename in context_history
Write-Host "Starting new transcript: $TranscriptPath..."
Start-Transcript -Path $TranscriptPath -Force

# 3. Launch Gemini with the priming prompt
$PrimingPrompt = "Read 'D:\\gemini_context\\context.json', then immediately execute the steps listed in the 'initialization_sequence' array within that file, in order and without deviation. Then, state the most recent codeword and its philosophy if present, and confirm the next task we had agreed upon. I am ready for your instructions."

# --- Start Gemini CLI ---
Write-Host "Launching Gemini..."
gemini --prompt-interactive $PrimingPrompt

# 4. Stop the transcript
Write-Host "Stopping transcript..."
try {
    Stop-Transcript -ErrorAction Stop
    Write-Host "Transcript stopped successfully." -ForegroundColor Green
} catch {
    Write-Host "Error stopping transcript: $($_.Exception.Message)" -ForegroundColor Red
}

# Give the system a moment to release the file lock before attempting to process the file.
Start-Sleep -Seconds 2

# 5. Process the transcript to update the context file
Write-Host "Processing transcript..."
# Check if the transcript file exists and has content
if (Test-Path -Path $TranscriptPath) {
    $transcriptContent = Get-Content $TranscriptPath -Raw
    if ($transcriptContent.Length -gt 0) {
        Write-Host "Transcript file found and has content. Processing..." -ForegroundColor Green
        try {
            & $ProcessTranscriptScript -TranscriptPath $TranscriptPath
            Write-Host "Transcript processing completed." -ForegroundColor Green
        } catch {
            Write-Host "Error during transcript processing: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Transcript file is empty. Skipping processing." -ForegroundColor Yellow
    }
} else {
    Write-Host "Transcript file not found. Skipping processing." -ForegroundColor Yellow
}
