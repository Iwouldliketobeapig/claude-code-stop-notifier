$ErrorActionPreference = 'SilentlyContinue'

# Claude Code Stop hook: pop a Windows toast in the bottom-right corner when
# Claude finishes responding. The toast shows the project name (from the
# session cwd) and the user's question that this response answered (read from
# the transcript's last "last-prompt" entry, whose path is passed on stdin).
#
# IMPORTANT: keep this file PURE ASCII. Windows PowerShell 5.1 reads .ps1
# files as ANSI (GBK) on Chinese Windows, which corrupts non-ASCII source
# bytes and breaks parsing. Chinese display text is built from [char] code
# points at runtime, so the source stays ASCII while the rendered text is
# Chinese. The transcript is read with -Encoding UTF8 for the same reason.

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
$transcriptPath = ''
if ($hook) {
    if ($hook.cwd) { $projectName = Split-Path $hook.cwd -Leaf }
    if ($hook.transcript_path) { $transcriptPath = $hook.transcript_path }
}
# Fallback: hooks run with cwd = the session's working directory.
if (-not $projectName) { $projectName = Split-Path (Get-Location) -Leaf }

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

# --- Show the toast (fallback to a tray balloon if WinRT is unavailable) ---
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    # Use Windows PowerShell's own registered AUMID so the toast actually displays.
    $AppID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

    $XmlString = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$titleXml</text>
      <text>$bodyXml</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@

    $Xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $Xml.LoadXml($XmlString)
    $Toast = [Windows.UI.Notifications.ToastNotification]::new($Xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID).Show($Toast)
}
catch {
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
