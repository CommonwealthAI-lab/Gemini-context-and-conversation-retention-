# summarize-context.ps1
# This script summarizes all historical context files and creates a concise, metadata-rich context_index.json for the next session.

param(
    [string]$NewSessionBackupPath = "",
    [switch]$ShowProgressBar
)

# --- Configuration ---
$ContextHistoryPath = "D:\gemini_context\context_history"
$ContextIndexPath = "D:\gemini_context\context_index.json"
$LogFile = "D:\gemini_context\summarize-context.log"

# --- Functions ---
function Write-Log($Message) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File -FilePath $LogFile -Append
}

function Summarize-ConversationHistory($RawTranscriptContent) {
    # If RawTranscriptContent is empty, return immediately
    if ([string]::IsNullOrEmpty($RawTranscriptContent)) {
        Write-Log "WARNING: Summarize-ConversationHistory received empty RawTranscriptContent."
        return [PSCustomObject]@{ Description = "Empty raw transcript content."; TotalTurns = 0 }
    }

    # --- Robust Conversation Parser ---
    # This parser uses a state machine to reliably separate user and agent turns, even with multi-line content.
    $conversationHistory = [System.Collections.ArrayList]::new()
    
    # --- Locate Conversation Block ---
    $allLines = $RawTranscriptContent.Split([System.Environment]::NewLine)
    Write-Log "Summarize-ConversationHistory: allLines.Length = $($allLines.Length)"

    $startIndex = 0
    for ($i = 0; $i -lt $allLines.Length; $i++) {
        if ($allLines[$i] -like "*Launching Gemini...*") {
            $startIndex = $i + 1
            break
        }
    }

    # If no marker is found, as a fallback, start after the PowerShell header
    if ($startIndex -eq 0) {
        for ($i = 0; $i -lt $allLines.Length; $i++) {
            if ($allLines[$i] -like "**********************" -and $i -lt ($allLines.Length - 1) -and $allLines[$i+1] -like "Transcript started*") {
                $startIndex = $i + 2
                break
            }
        }
    }
    Write-Log "Summarize-ConversationHistory: startIndex = $startIndex"

    $lines = @()
    if ($startIndex -lt $allLines.Length) {
        $lines = $allLines[$startIndex..($allLines.Length-1)]
    }
    Write-Log "Summarize-ConversationHistory: lines.Length = $($lines.Length)"

    if ($lines.Length -eq 0) {
        Write-Log "WARNING: No conversation lines found after markers in RawTranscriptContent."
        return [PSCustomObject]@{ Description = "No conversation lines found after markers."; TotalTurns = 0 }
    }

    $currentUserMessage = $null
    $currentGeminiResponse = $null
    $state = "Seeking" # States: Seeking, InUserMessage, InGeminiResponse

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine.StartsWith("> ")) {
            if ($currentUserMessage -ne $null) {
                $turn = [PSCustomObject]@{ user = $currentUserMessage.Trim(); gemini = if ($currentGeminiResponse) { $currentGeminiResponse.Trim() } else { "" } }
                $conversationHistory.Add($turn) | Out-Null
            }
            $currentUserMessage = $trimmedLine.Substring(2); $currentGeminiResponse = $null; $state = "InUserMessage"
        } elseif ($trimmedLine.StartsWith("✦ ")) {
            if ($currentUserMessage -ne $null) { $currentGeminiResponse = $trimmedLine.Substring(2); $state = "InGeminiResponse" }
            else { if($currentGeminiResponse -ne $null){ $turn = [PSCustomObject]@{ user = ""; gemini = $currentGeminiResponse.Trim() }; $conversationHistory.Add($turn) | Out-Null }; $currentGeminiResponse = $trimmedLine.Substring(2); $state = "InGeminiResponse" }
        } else {
            if ($state -eq "InGeminiResponse") { $currentGeminiResponse += "`n" + $line }
            elseif ($state -eq "InUserMessage") { $currentUserMessage += "`n" + $line }
        }
    }
    if ($currentUserMessage -ne $null) { $turn = [PSCustomObject]@{ user = $currentUserMessage.Trim(); gemini = if ($currentGeminiResponse) { $currentGeminiResponse.Trim() } else { "" } }; $conversationHistory.Add($turn) | Out-Null }
    elseif($currentGeminiResponse -ne $null) { $turn = [PSCustomObject]@{ user = ""; gemini = $currentGeminiResponse.Trim() }; $conversationHistory.Add($turn) | Out-Null }

    $turnCount = $conversationHistory.Count
    if ($turnCount -eq 0) {
        return [PSCustomObject]@{ Description = "No conversation turns found."; TotalTurns = 0 }
    }

    # --- Metadata Extraction ---
    $fullText = $conversationHistory | ForEach-Object { "$($_.user)`n$($_.gemini)" } | Out-String
    
    # --- NEW: Tool Usage and Outcome Analysis ---
    # This block counts tool calls and their results (success, fail, cancel).
    $toolCallMatches = [regex]::Matches($fullText, '╭────────────────────────────────────────────────────────────────────────────────────────────────────────────╮')
    $toolCalls = $toolCallMatches.Count
    $toolSuccesses = [regex]::Matches($fullText, '✓\s+([a-zA-Z_]+)').Count
    $toolFails = [regex]::Matches($fullText, 'x\s+([a-zA-Z_]+)').Count
    $toolCancels = [regex]::Matches($fullText, '-\s+([a-zA-Z_]+)').Count # Pattern for cancelled operations
    $toolsUsed = [System.Collections.Generic.HashSet[string]]::new()
    [regex]::Matches($fullText, '(?:✓|x|-)\s+([a-zA-Z_]+)') | ForEach-Object { $toolsUsed.Add($_.Groups[1].Value) | Out-Null }


    # --- NEW: Error Detection ---
    # This block flags the session if common error patterns are found.
    $containsErrors = $fullText -match "(\[API Error:\]|Failed|Error:|Traceback)"

    # --- NEW: Key File Mentions ---
    # This block finds all file paths mentioned in the conversation.
    $fileMentions = [regex]::Matches($fullText, '([a-zA-Z]:\\[^`"''\s\r\n\t:]+|\.\\[^`"''\s\r\n\t:]+|\b[a-zA-Z0-9_.-]+\.(ps1|json|txt|md|js|ts|py)\b)') |
        ForEach-Object { $_.Groups[1].Value } |
        Group-Object |
        Sort-Object Count -Descending |
        Select-Object -First 5 -ExpandProperty Name

    # --- NEW: Codeword Extraction ---
    # This block specifically finds the last codeword and its philosophy.
    $codeword = $null
    $codewordPhilosophy = $null
    # Iterate through conversation history in reverse to find the latest codeword
    for ($i = $conversationHistory.Count - 1; $i -ge 0; $i--) {
        $turn = $conversationHistory[$i]
        if ($turn.gemini -match "new codeword: ([a-zA-Z0-9_.-]+)") {
            $codeword = $Matches[1]
        }
        if ($turn.gemini -match "Philosophy:\s*([\s\S]+)") {
            $codewordPhilosophy = $Matches[1].Trim()
        }
        # If both are found, we can break early
        if ($codeword -and $codewordPhilosophy) { break }
    }


    # --- Keyword and Summary Generation ---
    $words = $fullText.ToLower() -split '[^a-zA-Z]+' | Where-Object { $_.Length -gt 4 } | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 Name
    $topKeywords = $words.Name
    $summaryText = "A $turnCount-turn conversation. Key topics appear to be: $($topKeywords -join ', ')."

    # --- NEW: Keyword Hotspot Detection ---
    # This block finds the most keyword-dense part of the conversation to serve as a topic summary.
    $hotspotTurns = @()
    if ($turnCount -gt 5 -and $topKeywords.Count -gt 0) {
        $bestScore = 0
        $bestChunkIndex = 0
        $chunkSize = 5 # Analyze 5 turns at a time (e.g., 2 user, 3 gemini)
        for ($i = 0; $i -le $turnCount - $chunkSize; $i++) {
            $chunkText = $conversationHistory[$i..([System.Math]::Min($i + $chunkSize - 1, $turnCount -1))] | ForEach-Object { "$($_.user) $($_.gemini)" } | Out-String
            $score = ([regex]::Matches($chunkText, "($($topKeywords -join '|'))", "IgnoreCase")).Count
            if ($score -gt $bestScore) { $bestScore = $score; $bestChunkIndex = $i }
        }
        # Ensure we don't go out of bounds if the best chunk is near the end
        $hotspotTurns = $conversationHistory[$bestChunkIndex..([System.Math]::Min($bestChunkIndex + $chunkSize - 1, $turnCount - 1))]
    }


    # --- Final Summary Object Construction ---
    # This uses [PSCustomObject] to ensure clean JSON output.
    $summary = [PSCustomObject]@{
        TotalTurns   = $turnCount
        Summary      = $summaryText
        Keywords     = $topKeywords
        LastTurns    = $conversationHistory[([System.Math]::Max(0, $turnCount - 6))..$($turnCount - 1)] # Increased to 6
        HotspotTurns = $hotspotTurns
        ToolUsage    = [PSCustomObject]@{
            CallCount   = $toolCalls
            Successes   = $toolSuccesses
            Fails       = $toolFails
            Cancels     = $toolCancels
            ToolsUsed   = ($toolsUsed | Sort-Object) # Sort tools for consistent output
        }
        FileMentions = $fileMentions
        ContainsErrors = $containsErrors
    }
    if ($codeword) { $summary | Add-Member -MemberType NoteProperty -Name "Codeword" -Value $codeword }
    if ($codewordPhilosophy) { $summary | Add-Member -MemberType NoteProperty -Name "CodewordPhilosophy" -Value $codewordPhilosophy }

    return $summary
}

# --- Main ---
Write-Log "--- Starting Context Summarization ---"
$AllSessionSummaries = [System.Collections.ArrayList]::new()
if ($ShowProgressBar) { Write-Progress -Activity "Indexing Context History" -Status "Scanning for historical files..." -PercentComplete 0 }

$HistoricalFiles = Get-ChildItem -Path $ContextHistoryPath -Filter "session_backup_*.json" -File | Sort-Object Name -Descending
if ($ShowProgressBar) { Write-Progress -Activity "Indexing Context History" -Status "Found $($HistoricalFiles.Count) historical session files." -PercentComplete 10 }
Write-Log "Found $($HistoricalFiles.Count) historical session files."

$totalFiles = $HistoricalFiles.Count; $fileCounter = 0
foreach ($File in $HistoricalFiles) {
    $fileCounter++
    if ($ShowProgressBar) { $percentComplete = 10 + (($fileCounter / $totalFiles) * 90); Write-Progress -Activity "Indexing Context History" -Status "Processing file $($fileCounter) of $($totalFiles): $($File.Name)" -PercentComplete $percentComplete }
    Write-Log "Processing historical file: $($File.FullName)"
    try {
                    $FileContent = Get-Content $File.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
                    Write-Log "Type of raw_transcript_content: $($FileContent.raw_transcript_content.GetType().Name)"
                    if ($FileContent.raw_transcript_content -is [System.Array]) {
                        Write-Log "raw_transcript_content is an array. Length: $($FileContent.raw_transcript_content.Length). First element: $($FileContent.raw_transcript_content[0])"
                        $transcriptText = $FileContent.raw_transcript_content -join "`n"
                    } else {
                        Write-Log "raw_transcript_content is NOT an array. Content: $($FileContent.raw_transcript_content | Select-Object -First 100)"
                        $transcriptText = $FileContent.raw_transcript_content
                    }
                    Write-Log "Length of ${transcriptText.Length}"
                    $summary = Summarize-ConversationHistory($transcriptText)
            $sessionEntry = [PSCustomObject]@{ Timestamp = $FileContent.timestamp; FilePath = $File.FullName; FileName = $File.Name; Summary = $summary }
            $AllSessionSummaries.Add($sessionEntry) | Out-Null
            Write-Log "Successfully processed file: $($File.Name)"
    } catch { Write-Log "ERROR: Failed to process $($File.FullName). Error: $($_.Exception.Message)" }
} # This closes the foreach loop

$ContextIndex = @{ last_updated = (Get-Date).ToString("o"); total_sessions = $AllSessionSummaries.Count; HistoricalSessions = $AllSessionSummaries | ForEach-Object { $_ } }
Write-Log "Saving updated context index to $ContextIndexPath"
$ContextIndex | ConvertTo-Json -Depth 10 | Set-Content -Path $ContextIndexPath -Encoding UTF8
if ($ShowProgressBar) { Write-Progress -Activity "Indexing Context History" -Status "All files processed." -PercentComplete 100 -Completed }
Write-Log "--- Context Indexing Finished ---"
Write-Host "Context indexing complete. New context_index.json created/updated."