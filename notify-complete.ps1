$ErrorActionPreference = 'SilentlyContinue'

# Claude Code Stop hook: pop a Windows toast in the bottom-right corner when
# Claude finishes responding. The toast shows the project name (from the
# session cwd) and the user's question that this response answered (read from
# the transcript's last "last-prompt" entry, whose path is passed on stdin).
# Clicking the toast asks Windows to launch <scheme>://file/<cwd> - or
# <scheme>://file/<workspace file> when the project lives inside a multi-root
# workspace - which the editor's URL handler answers by focusing that window.
#
# IMPORTANT: keep this file PURE ASCII. Windows PowerShell 5.1 reads .ps1
# files as ANSI (GBK) on Chinese Windows, which corrupts non-ASCII source
# bytes and breaks parsing. Chinese display text is built from [char] code
# points at runtime, so the source stays ASCII while the rendered text is
# Chinese. The transcript is read with -Encoding UTF8 for the same reason.

# --- Config ---
# URL scheme used when the toast is clicked: Windows launches
# <scheme>://file/<project folder or workspace file>, and the editor's
# registered protocol handler focuses the matching window (or opens a new one).
# Change to 'vscode-insiders' or 'cursor' if you use those editors.
$editorScheme = 'vscode'

# --- Read hook input from stdin (JSON: cwd, transcript_path, ...) ---
# Read raw bytes and decode as UTF-8 ourselves. Windows PowerShell 5.1 would
# otherwise decode piped stdin with the OEM codepage (GBK on Chinese Windows),
# corrupting the non-ASCII path in transcript_path.
$rawIn = ''
try {
    $inStream = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $inStream.CopyTo($ms)
    $rawIn = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    $ms.Dispose()
} catch { }
$hook = $null
if ($rawIn) { try { $hook = $rawIn | ConvertFrom-Json } catch { $hook = $null } }

$projectName = ''
$projectDir = ''
$transcriptPath = ''
if ($hook) {
    if ($hook.cwd) {
        $projectDir = [string]$hook.cwd
        $projectName = Split-Path $projectDir -Leaf
    }
    if ($hook.transcript_path) { $transcriptPath = $hook.transcript_path }
}
# Fallback: hooks run with cwd = the session's working directory.
if (-not $projectName) {
    $projectDir = (Get-Location).Path
    $projectName = Split-Path $projectDir -Leaf
}

# --- Extract the user's question (not the model's answer) ---
# Preferred source: the last "last-prompt" transcript entry, which stores the
# user's raw prompt without injected context. Fallback: parse the last real
# user message and keep its text blocks that are not injected context (those
# start with "<", e.g. <ide_opened_file>, <system-reminder>).
$snippet = ''
if ($transcriptPath -and (Test-Path -LiteralPath $transcriptPath)) {
    try {
        $lines = Get-Content -LiteralPath $transcriptPath -Encoding UTF8 -Tail 200
        for ($i = $lines.Count - 1; $i -ge 0 -and -not $snippet; $i--) {
            $line = $lines[$i]
            if (-not $line) { continue }
            # Cheap pre-filters: skip lines that are neither a prompt marker nor
            # a user message, and skip tool-result user entries (huge, not prompts).
            if ($line -notlike '*"type":"last-prompt"*' -and $line -notlike '*"type":"user"*') { continue }
            if ($line -like '*"type":"tool_result"*') { continue }
            $obj = $null
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            if (-not $obj) { continue }

            if ($obj.type -eq 'last-prompt' -and $obj.lastPrompt) {
                $snippet = $obj.lastPrompt
            } elseif ($obj.type -eq 'user') {
                $content = $obj.message.content
                if (-not $content) { continue }
                if ($content -is [string]) {
                    if ($content -and -not $content.StartsWith('<')) { $snippet = $content }
                } else {
                    $parts = @()
                    foreach ($block in $content) {
                        if ($block.type -eq 'text' -and $block.text -and -not $block.text.StartsWith('<')) { $parts += $block.text }
                    }
                    if ($parts.Count -gt 0) { $snippet = ($parts -join ' ') }
                }
            }
        }
    } catch { }
}

# --- Clean up the snippet for one-line display ---
if ($snippet) {
    $snippet = ($snippet -replace '\s+', ' ').Trim()
    if ($snippet.Length -gt 150) { $snippet = $snippet.Substring(0, 150) + '...' }
}

# --- Build title and body ---
# doneLabel = "OK sign + space + hui hua yi wan cheng" = [OK sign + 会话已完成]
$doneLabel = [char]0x2705 + ' ' + [char]0x4F1A + [char]0x8BDD + [char]0x5DF2 + [char]0x5B8C + [char]0x6210
if ($snippet) {
    $body = [char]0x2705 + ' ' + $snippet
} else {
    $body = $doneLabel
}

if ($projectName) {
    if ($projectName.Length -gt 40) { $projectName = $projectName.Substring(0, 40) + '...' }
    $title = 'Claude Code  -  ' + $projectName
} else {
    $title = 'Claude Code'
}

# XML-escape dynamic text so <, >, &, quotes in the snippet can't break the toast.
$titleXml = [System.Security.SecurityElement]::Escape($title)
$bodyXml = [System.Security.SecurityElement]::Escape($body)

# --- Multi-root workspace detection ---
# A VS Code window running a .code-workspace is keyed by the workspace FILE,
# not by any folder inside it: only <scheme>://file/<workspace file> focuses
# that window, while <scheme>://file/<folder> reopens the folder standalone.
# So when the project dir is covered by a .code-workspace file (found by
# walking up from the project dir), target the workspace file instead.
function Get-NormalizedDirPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    $p = $Path -replace '/', '\'
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\').ToLowerInvariant()
}

function Test-WorkspaceCoversDir {
    param([string]$WorkspaceFile, [string]$Dir)
    # .code-workspace files are JSONC (comments allowed), so rather than
    # parsing JSON, pull every "path": "..." value out with a regex - enough
    # for a folders-membership check.
    $text = ''
    try { $text = [System.IO.File]::ReadAllText($WorkspaceFile, [System.Text.Encoding]::UTF8) } catch { return $false }
    if (-not $text) { return $false }
    $wsDir = Split-Path -Parent $WorkspaceFile
    $target = Get-NormalizedDirPath $Dir
    foreach ($m in [regex]::Matches($text, '"path"\s*:\s*"((?:[^"\\]|\\.)*)"')) {
        # Unescape the JSON string forms that can appear in paths.
        $p = $m.Groups[1].Value -replace '\\\\', '\' -replace '\\/', '/'
        # Entries may be relative to the workspace file's own directory.
        if ($p -notmatch '^([a-zA-Z]:[\\/]|\\\\)') { $p = Join-Path $wsDir $p }
        $p = Get-NormalizedDirPath $p
        if ($p -and ($target -eq $p -or $target.StartsWith($p + '\'))) { return $true }
    }
    return $false
}

$workspaceFile = ''
if ($projectDir) {
    $dir = $projectDir.TrimEnd('\')
    for ($i = 0; $i -lt 8 -and $dir -and -not $workspaceFile; $i++) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.code-workspace' -File)) {
            # VS Code's own check is case-sensitive, so keep the same semantics.
            if ($f.Extension -ceq '.code-workspace' -and (Test-WorkspaceCoversDir $f.FullName $projectDir)) {
                $workspaceFile = $f.FullName
                break
            }
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
}

# --- Click-to-jump URL: <scheme>://file/<project folder or workspace file> ---
# Use forward slashes and keep ':' and '/' literal (the encodeURI-style form
# VS Code's own links use); EscapeUriString covers spaces, Chinese and other
# unsafe chars as UTF-8 percent-escapes. '#' and '?' would cut the URL short
# (fragment/query), so escape those two by hand afterwards.
$launchUrl = ''
$launchTarget = $projectDir
if ($workspaceFile) { $launchTarget = $workspaceFile }
if ($launchTarget) {
    $p = $launchTarget -replace '\\', '/'
    $launchUrl = $editorScheme + '://file/' + [Uri]::EscapeUriString($p)
    $launchUrl = $launchUrl -replace '#', '%23' -replace '\?', '%3F'
}
$launchXml = [System.Security.SecurityElement]::Escape($launchUrl)

# Test seam: when CCSN_DEBUG_URL is set, print the click URL and exit before
# showing any toast. test-workspace.ps1 uses this to assert URL selection.
if ($env:CCSN_DEBUG_URL) { Write-Output $launchUrl; exit 0 }

# --- Show the toast (fallback to a tray balloon if WinRT is unavailable) ---
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    # Use Windows PowerShell's own registered AUMID so the toast actually displays.
    $AppID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

    # Click-to-jump wiring, in two places - some Windows builds drop the
    # body-click activation, the button is the reliable path:
    # - root launch attr: clicking the toast body opens the URL
    # - <actions> button: the same URL as an explicit "open project" button
    # openLabel = "da kai xiang mu" = [open the project] = 打开项目
    $toastOpen = '<toast>'
    $actionsXml = ''
    if ($launchUrl) {
        $toastOpen = '<toast activationType="protocol" launch="' + $launchXml + '">'
        $openLabel = [string]([char]0x6253) + [char]0x5F00 + [char]0x9879 + [char]0x76EE
        $actionsXml = '  <actions>' + "`n" +
            '    <action activationType="protocol" arguments="' + $launchXml + '" content="' + $openLabel + '"/>' + "`n" +
            '  </actions>'
    }

    $XmlString = @"
$toastOpen
  <visual>
    <binding template="ToastGeneric">
      <text>$titleXml</text>
      <text>$bodyXml</text>
    </binding>
  </visual>
$actionsXml
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@

    $Xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $Xml.LoadXml($XmlString)
    $Toast = [Windows.UI.Notifications.ToastNotification]::new($Xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID).Show($Toast)
}
catch {
    # Balloon fallback (WinRT unavailable): no click-to-jump here - the icon
    # is disposed a few seconds in, before any click handler could run. The
    # toast path above is the normal case on Windows 10/11.
    Add-Type -AssemblyName System.Windows.Forms
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = $title
    $n.BalloonTipText = $body
    $n.Visible = $true
    $n.ShowBalloonTip(5000)
    Start-Sleep -Seconds 6
    $n.Dispose()
}
