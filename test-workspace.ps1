#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

# Claude Code Stop Notifier - workspace URL selection test.
# Builds fixture folders + .code-workspace files under %TEMP%, feeds mock Stop
# hook payloads to notify-complete.ps1 with CCSN_DEBUG_URL=1 (so the script
# prints the click URL instead of popping a toast), and asserts which target
# the URL points at:
#   - plain folder                    -> the folder itself
#   - folder covered by a workspace   -> the .code-workspace FILE (a running
#     workspace window is keyed by its workspace file, so only that URL can
#     focus it; a folder URL would open the folder standalone)
#
# IMPORTANT: keep this file PURE ASCII (PS 5.1 misreads non-ASCII .ps1 bytes
# on Chinese Windows). The Chinese fixture name is built from code points.

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$notifier = Join-Path $scriptRoot 'notify-complete.ps1'
if (-not (Test-Path -LiteralPath $notifier)) {
    Write-Host "ERROR: notify-complete.ps1 not found next to test-workspace.ps1." -ForegroundColor Red
    exit 1
}

# --- Fixture tree (under %TEMP%, cleaned up at the end) ---
# root/
#   projA/src/            workspace root folder + a subdir
#   projB/                second workspace root folder
#   team.code-workspace   folders: ["projA", "projB"]   (relative paths)
#   plain/                not covered by any workspace
#     stray.code-workspace  folders: ["../projA"]  (covers projA, NOT plain/)
#   selfcontained/
#     app.code-workspace  folders: ["."]            (covers its own dir)
#   <zhProj>/sub/         Chinese-named workspace root folder + subdir
#   cn.code-workspace     folders: ["<zhProj>"]
$zhProj = [string]([char]0x4E2D) + [char]0x6587 + [char]0x9879 + [char]0x76EE  # zhong wen xiang mu

$root = Join-Path $env:TEMP ('ccsn-ws-test-' + $PID)
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $root 'projA\src') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'projB') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'plain') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'selfcontained') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root ($zhProj + '\sub')) -Force | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-WsFile([string]$path, [string[]]$folders) {
    $entries = ($folders | ForEach-Object { '{"path": ' + ($_ | ConvertTo-Json) + '}' }) -join ','
    [System.IO.File]::WriteAllText($path, '{"folders":[' + $entries + '],"settings":{}}', $utf8NoBom)
}
Write-WsFile (Join-Path $root 'team.code-workspace') @('projA', 'projB')
Write-WsFile (Join-Path $root 'plain\stray.code-workspace') @('../projA')
Write-WsFile (Join-Path $root 'selfcontained\app.code-workspace') @('.')
Write-WsFile (Join-Path $root 'cn.code-workspace') @($zhProj)

# --- Helpers ---
function Get-ExpectedUrl([string]$target) {
    # Mirror of the URL form the notifier produces.
    $p = $target -replace '\\', '/'
    $u = 'vscode://file/' + [Uri]::EscapeUriString($p)
    return $u -replace '#', '%23' -replace '\?', '%3F'
}

$env:CCSN_DEBUG_URL = '1'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)  # keep Chinese cwd intact PS->PS
function Get-NotifierUrl([string]$cwd) {
    $json = (@{ cwd = $cwd } | ConvertTo-Json -Compress)
    $out = $json | powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File $notifier
    return ($out | Out-String).Trim()
}

$failures = 0
function Assert-Url([string]$name, [string]$cwd, [string]$expectedTarget) {
    $expected = Get-ExpectedUrl $expectedTarget
    $actual = Get-NotifierUrl $cwd
    if ($actual -eq $expected) {
        Write-Host "PASS  $name"
    } else {
        $script:failures++
        Write-Host "FAIL  $name" -ForegroundColor Red
        Write-Host "    cwd:      $cwd"
        Write-Host "    expected: $expected"
        Write-Host "    actual:   $actual"
    }
}

# --- Cases ---
Assert-Url 'plain folder (stray non-covering workspace next to it) -> folder URL' `
    (Join-Path $root 'plain') (Join-Path $root 'plain')

Assert-Url 'folder covered by workspace in parent dir -> workspace file URL' `
    (Join-Path $root 'projA') (Join-Path $root 'team.code-workspace')

Assert-Url 'subdir of a workspace root -> workspace file URL' `
    (Join-Path $root 'projA\src') (Join-Path $root 'team.code-workspace')

Assert-Url 'workspace file inside cwd with folders:["."] -> workspace file URL' `
    (Join-Path $root 'selfcontained') (Join-Path $root 'selfcontained\app.code-workspace')

Assert-Url 'Chinese-named folder covered by workspace -> escaped workspace file URL' `
    (Join-Path $root ($zhProj + '\sub')) (Join-Path $root 'cn.code-workspace')

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

if ($failures -gt 0) {
    Write-Host ""
    Write-Host "$failures of 5 cases FAILED." -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "All 5 cases passed." -ForegroundColor Green
exit 0
