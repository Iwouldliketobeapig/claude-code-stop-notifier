#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

# Claude Code Stop Notifier - smoke test.
# Builds a tiny sample transcript containing a "last-prompt" entry, then pipes
# a sample Stop-hook JSON (pointing at it) into notify-complete.ps1. A toast
# should pop in the bottom-right corner with the sample project name + question.
#
# IMPORTANT: keep this file PURE ASCII.

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$notifier = Join-Path $scriptRoot 'notify-complete.ps1'
if (-not (Test-Path -LiteralPath $notifier)) {
    Write-Host "ERROR: notify-complete.ps1 not found next to test.ps1." -ForegroundColor Red
    exit 1
}

# Sample transcript lives under the repo (test-output/) and is cleaned up
# afterwards; the pipe itself is switched to UTF-8 below for non-ASCII paths.
$tmpDir = Join-Path $scriptRoot 'test-output'
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
$transcript = Join-Path $tmpDir 'sample.jsonl'

# Minimal transcript: one last-prompt entry (what notify-complete.ps1 reads).
$sampleLine = '{"type":"last-prompt","lastPrompt":"Summarize the auth module and add unit tests","leafUuid":"test-leaf","sessionId":"test-session"}'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($transcript, $sampleLine + "`n", $utf8NoBom)

# Sample Stop-hook input. cwd = the repo root, so the toast title shows this
# repo's name and CLICKING the toast jumps to this project's editor window
# (exercises the click-to-open URL). transcript_path -> our sample file.
$hook = [PSCustomObject]@{
    session_id       = 'test-session'
    transcript_path  = $transcript
    cwd              = $scriptRoot
    hook_event_name  = 'Stop'
    stop_hook_active = $false
}
$hookJson = $hook | ConvertTo-Json -Compress

# Pipe as UTF-8 so a non-ASCII repo path survives the PS->PS pipe (the
# notifier decodes stdin as UTF-8; PS 5.1's default $OutputEncoding is ASCII).
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$repoName = Split-Path $scriptRoot -Leaf
Write-Host "Piping sample hook JSON to notify-complete.ps1..."
Write-Host "  Expected toast title: Claude Code  -  $repoName"
Write-Host "  Expected toast body:  [checkmark] Summarize the auth module and add unit tests"
Write-Host "  Click the toast: it should focus this repo's editor window."
Write-Host ""

$hookJson | powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File $notifier

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done. Cleaned up $tmpDir."
