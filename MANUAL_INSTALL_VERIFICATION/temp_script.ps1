$TranscriptPath = "D:\gemini_context\context_history\context to be added.txt"
Write-Host "--> Reading file..."
$ConversationContent = Get-Content $TranscriptPath -Raw
Write-Host "--> File read. Length: $($ConversationContent.Length)"

# Test 1: Write raw content to a text file
Write-Host "--> Test 1: Writing raw content to D:\temp_raw_output.txt..."
$ConversationContent | Set-Content "D:\temp_raw_output.txt"
Write-Host "--> Test 1 complete."

# Test 2: Convert a small part of the content to JSON
Write-Host "--> Test 2: Converting first 1000 characters to JSON..."
$SmallContent = $ConversationContent.Substring(0, 1000)
$SmallSessionContext = @{ raw_transcript_content = $SmallContent }
$SmallSessionContext | ConvertTo-Json -Depth 10 | Set-Content "D:\temp_small_json.json"
Write-Host "--> Test 2 complete."

Write-Host "--> All tests complete."