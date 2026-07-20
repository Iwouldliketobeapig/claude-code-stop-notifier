#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

# Claude Code Stop Notifier - installer.
# Copies notify-complete.ps1 to ~/.claude/hooks/ and idempotently adds the
# Stop hook to ~/.claude/settings.json, preserving all existing settings.
#
# IMPORTANT: keep this file PURE ASCII (see notify-complete.ps1 header).

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$sourceScript = Join-Path $scriptRoot 'notify-complete.ps1'
if (-not (Test-Path -LiteralPath $sourceScript)) {
    Write-Host "ERROR: notify-complete.ps1 not found next to install.ps1 ($scriptRoot)." -ForegroundColor Red
    exit 1
}

$claudeDir    = Join-Path $HOME '.claude'
$hooksDir     = Join-Path $claudeDir 'hooks'
$settingsPath = Join-Path $claudeDir 'settings.json'
$destScript   = Join-Path $hooksDir 'notify-complete.ps1'

# --- 1. Copy the notifier script to a stable location ---
if (-not (Test-Path -LiteralPath $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}
Copy-Item -LiteralPath $sourceScript -Destination $destScript -Force
Write-Host "Copied notifier to: $destScript"

# --- 2. Load existing settings.json (or start fresh) ---
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $raw = [System.IO.File]::ReadAllText($settingsPath)
        $settings = $raw | ConvertFrom-Json
    } catch {
        Write-Host "ERROR: Could not parse $settingsPath ($( $_.Exception.Message )). Aborting to avoid corrupting it; the notifier script was still copied." -ForegroundColor Red
        exit 1
    }
}
if (-not $settings) { $settings = [PSCustomObject]@{} }

# --- 3. Ensure hooks.Stop exists ---
if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{})
}
if (-not ($settings.hooks.PSObject.Properties.Name -contains 'Stop')) {
    $settings.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue @()
}

# --- 4. Idempotency: is our notifier already wired in the Stop hook? ---
$already = $false
foreach ($entry in $settings.hooks.Stop) {
    if ($entry -and $entry.hooks) {
        foreach ($h in $entry.hooks) {
            if ($h.command -like '*notify-complete.ps1*') { $already = $true; break }
        }
    }
    if ($already) { break }
}

$cmd = 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $destScript + '"'

if ($already) {
    Write-Host "Stop hook already references notify-complete.ps1 in $settingsPath - nothing to add."
} else {
    # Back up, then append our entry (preserve all existing hooks/keys).
    if (Test-Path -LiteralPath $settingsPath) {
        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak" -Force
        Write-Host "Backed up settings to: $settingsPath.bak"
    }
    $newEntry = [PSCustomObject]@{
        hooks = @([PSCustomObject]@{ type = 'command'; command = $cmd })
    }
    $settings.hooks.Stop = @($settings.hooks.Stop) + $newEntry

    # Write back as UTF-8 WITHOUT BOM (a BOM can break JSON parsing) and with
    # enough depth so the nested hooks structure is not flattened.
    $json = $settings | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
    Write-Host "Added Stop hook to: $settingsPath"
}

Write-Host ""
Write-Host "Done. Restart Claude Code for the hook to take effect." -ForegroundColor Green
Write-Host "Verify with:  powershell -ExecutionPolicy Bypass -File test.ps1"
