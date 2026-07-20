#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

# Claude Code Stop Notifier - uninstaller.
# Removes the Stop hook entry that references notify-complete.ps1 from
# ~/.claude/settings.json and deletes the copied script. All other settings
# and hooks are preserved.
#
# IMPORTANT: keep this file PURE ASCII.

$claudeDir    = Join-Path $HOME '.claude'
$settingsPath = Join-Path $claudeDir 'settings.json'
$destScript   = Join-Path $claudeDir 'hooks\notify-complete.ps1'

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Host "No settings.json found at $settingsPath - nothing to uninstall from settings."
} else {
    try {
        $raw = [System.IO.File]::ReadAllText($settingsPath)
        $settings = $raw | ConvertFrom-Json
    } catch {
        Write-Host "ERROR: Could not parse $settingsPath ($($_.Exception.Message)). Aborting." -ForegroundColor Red
        exit 1
    }

    if ($settings -and ($settings.PSObject.Properties.Name -contains 'hooks') -and $settings.hooks -and ($settings.hooks.PSObject.Properties.Name -contains 'Stop')) {
        # Keep only Stop entries that do NOT reference notify-complete.ps1.
        $kept = @()
        foreach ($entry in $settings.hooks.Stop) {
            $refs = $false
            if ($entry -and $entry.hooks) {
                foreach ($h in $entry.hooks) {
                    if ($h.command -like '*notify-complete.ps1*') { $refs = $true; break }
                }
            }
            if (-not $refs) { $kept += $entry }
        }

        if ($kept.Count -eq 0) {
            # Our entry was the only one - drop the Stop key entirely.
            try { $settings.hooks.PSObject.Properties.Remove('Stop') } catch { $settings.hooks.Stop = @() }
            Write-Host "Removed Stop hook (it only contained notify-complete.ps1)."
        } else {
            $settings.hooks.Stop = $kept
            Write-Host "Removed notify-complete.ps1 from Stop hook; kept $($kept.Count) other Stop entry/entries."
        }

        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak" -Force
        $json = $settings | ConvertTo-Json -Depth 10
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
        Write-Host "Updated: $settingsPath (backup at $settingsPath.bak)"
    } else {
        Write-Host "No Stop hook referencing notify-complete.ps1 found in $settingsPath."
    }
}

if (Test-Path -LiteralPath $destScript) {
    Remove-Item -LiteralPath $destScript -Force
    Write-Host "Deleted: $destScript"
} else {
    Write-Host "No copied script found at $destScript."
}

Write-Host ""
Write-Host "Uninstalled. Restart Claude Code to apply." -ForegroundColor Green
