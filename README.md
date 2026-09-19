# Claude Code Stop Notifier

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) `Stop` hook that pops a **Windows toast notification** in the bottom-right corner every time Claude finishes responding. The toast shows the **project name** and **your question** that was just answered, so you always know which task completed.

Example toast:

```
Claude Code  -  my-app
✅ Refactor the auth module and add unit tests
```

## Features

- 🔔 Native Windows toast (bottom-right corner) with a sound, on every response completion
- 🖱️ Jump to the project's VS Code window from the toast - click the "打开项目" button (reliable on all builds) or the toast body (works on most builds), via the `vscode://` URL protocol
- 🗂️ Workspace-aware: if the project belongs to a `.code-workspace` (multi-root), the click targets the workspace file so the running workspace window is focused, instead of reopening the folder standalone
- 📁 Project name in the title, derived from the session's working directory
- ❓ Your question (not the model's answer) in the body, read from the transcript's `last-prompt` entry
- 🛡️ Silent failure - never blocks your Claude Code workflow
- 🔧 Pure PowerShell, zero dependencies (built-in WinRT toast + tray-balloon fallback)
- 🌐 Encoding-safe: works correctly on Chinese (and any other) Windows without garbled text

## How It Works

1. Claude Code fires the `Stop` event each time the main agent finishes responding.
2. The hook receives a JSON object via **stdin** containing `cwd` and `transcript_path`.
3. The script derives the project name from `cwd`, and reads your last question from the transcript's `last-prompt` entry.
4. A Windows toast is shown. If the WinRT toast API is unavailable, it falls back to a tray balloon.
5. The toast is clickable: Windows launches `vscode://file/<cwd>`, and VS Code focuses the window that has the project folder open (or opens a new one). This also works for the toast parked in the notification center. Both the "打开项目" button and the toast body carry the URL - some Windows builds ignore body clicks, hence the explicit button.
6. Multi-root workspaces: a workspace window is keyed by its `.code-workspace` **file**, not by any folder inside it - a folder URL would reopen the folder standalone. So before building the URL, the script walks up from `cwd` looking for `*.code-workspace` files whose `folders` list covers `cwd` (relative entries are resolved against the workspace file's own directory). If one is found, the click URL targets that workspace file instead, which focuses the running workspace window. If the workspace file lives somewhere not above `cwd`, detection can't find it and the folder URL is used as before.

## Requirements

- **Windows 10/11** (uses the WinRT toast API; older systems fall back to a tray balloon)
- **Windows PowerShell 5.1+** (preinstalled on Windows as `powershell.exe`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

> macOS/Linux are not supported by this version (the notifier is a Windows PowerShell script).

## Installation

### Option A: Automated (recommended)

```powershell
git clone https://github.com/<your-username>/claude-code-stop-notifier.git
cd claude-code-stop-notifier
powershell -ExecutionPolicy Bypass -File install.ps1
```

`install.ps1` copies `notify-complete.ps1` to `~/.claude/hooks/` and adds the `Stop` hook to `~/.claude/settings.json`. Your existing settings and hooks are preserved, and a `.bak` backup is created. It is idempotent - re-running it will not duplicate the hook.

Then **restart Claude Code**.

### Option B: Manual

1. Clone the repo, or just copy `notify-complete.ps1` to a stable location such as `~/.claude/hooks/`.
2. Edit your Claude Code settings file:
   - **Global** (all projects): `~/.claude/settings.json`
   - **Project-level** (single project): `.claude/settings.json` in your project root
3. Add the `Stop` hook (replace the path with the real location of `notify-complete.ps1`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:/path/to/notify-complete.ps1\""
          }
        ]
      }
    ]
  }
}
```

4. **Restart Claude Code**.

## Testing

Verify the notifier works without touching your settings:

```powershell
powershell -ExecutionPolicy Bypass -File test.ps1
```

This creates a sample transcript, feeds a mock `Stop` payload to `notify-complete.ps1`, and pops a toast titled `Claude Code  -  demo-app`. You can also run `npm test`.

There is also an automated, non-interactive suite for the click-URL selection (plain folder vs. `.code-workspace` targeting), using fixture folders under `%TEMP%` - no toast pops:

```powershell
powershell -ExecutionPolicy Bypass -File test-workspace.ps1   # or: npm run test:unit
```

## Customization

Open `notify-complete.ps1` and tweak:

- **Editor scheme**: `$editorScheme = 'vscode'` near the top - the URL protocol opened when the toast is clicked. Use `vscode-insiders` for VS Code Insiders, `cursor` for Cursor.
- **Snippet length**: the line `if ($snippet.Length -gt 150)` - change `150` to your preferred max characters.
- **Title format**: the line `$title = 'Claude Code  -  ' + $projectName`.
- **Fallback text** (shown when no question is found): the `$doneLabel` line, built from `[char]` code points.

> ⚠️ **Keep the script pure ASCII.** Windows PowerShell 5.1 reads `.ps1` files as ANSI (GBK on Chinese Windows); non-ASCII source bytes break parsing. Any non-ASCII display text must be built from `[char]0xNNNN` code points, as the existing `$doneLabel` does. If you edit the file in an editor, save it as pure ASCII or UTF-8 **without BOM**.

## Troubleshooting

- **No toast appears**: open *Settings → System → Notifications* and ensure notifications are allowed, and that Focus Assist / Do Not Disturb isn't suppressing them.
- **Toast shows but no question (only the fallback text)**: the transcript path couldn't be read, or no `last-prompt` entry was found. This is expected when Claude Code's transcript format differs.
- **`settings.json` looks reformatted after install**: `install.ps1` rewrites the file as valid JSON - it preserves all keys and values but normalizes indentation. A `.bak` backup is kept.
- **Garbled text after editing the script**: you introduced non-ASCII bytes into the `.ps1`. Revert to pure ASCII (see Customization).
- **Clicking the toast does nothing / opens the wrong editor**: use the "打开项目" button - on some Windows builds body-click activation is dropped while button clicks always work. If the button also opens the wrong editor, set `$editorScheme` at the top of `notify-complete.ps1` to match yours (`vscode-insiders`, `cursor`). Click-to-jump only applies to toasts; the rare tray-balloon fallback is not clickable.
- **VS Code shows a confirmation dialog on click ("An external application wants to open ..." / "外部应用程序想要在...打开...")**: this is VS Code's own protection against external apps opening local paths via `vscode://` links - click Yes/是 to jump. To stop being asked, tick "Allow opening local paths without asking" in that dialog once, or set `"security.promptForLocalFileProtocolHandling": false` in VS Code settings.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

This removes the `Stop` entry referencing `notify-complete.ps1` from `~/.claude/settings.json` (other hooks are preserved; a `.bak` backup is created) and deletes the copied script. Restart Claude Code to apply.

## License

[MIT](LICENSE)
