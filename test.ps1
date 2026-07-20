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

# Use an ASCII path under the repo for the sample transcript so the PS->PS
# pipe stays ASCII (avoids any console-encoding issues with non-ASCII paths).
$tmpDir = Join-Path $scriptRoot 'test-output'
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
$transcript = Join-Path $tmpDir 'sample.jsonl'

# Minimal transcript: one last-prompt entry (what notify-complete.ps1 reads).
$sampleLine = '{"type":"last-prompt","lastPrompt":"Summarize the auth module and add unit tests","leafUuid":"test-leaf","sessionId":"test-session"}'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($transcript, $sampleLine + "`n", $utf8NoBom)

# Sample Stop-hook input. cwd -> project name "demo-app"; transcript_path -> our file.
$hook = [PSCustomObject]@{
    session_id       = 'test-session'
    transcript_path  = $transcript
    cwd              = (Join-Path $tmpDir 'demo-app')
    hook_event_name  = 'Stop'
    stop_hook_active = $false
}
$hookJson = $hook | ConvertTo-Json -Compress

Write-Host "Piping sample hook JSON to notify-complete.ps1..."
Write-Host "  Expected toast title: Claude Code  -  demo-app"
Write-Host "  Expected toast body:  [checkmark] Summarize the auth module and add unit tests"
Write-Host ""

$hookJson | powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File $notifier

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done. Cleaned up $tmpDir."
