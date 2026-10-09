# Setup (Windows)

This is the manual version of what `scripts\install-mcp.bat` does, in the order it was done on this machine.

## What you need

| Thing | Where it was on this PC |
|---|---|
| EffectCraft 0.6.0 (Windows x64 MSI) | `C:\Program Files\EffectCraft\effectcraft.exe` |
| EffectCraft CLI (installed with the MSI on Windows) | `C:\Program Files\EffectCraft\effectcraft-cli.exe` |
| Claude desktop app | Config at `%APPDATA%\Claude\claude_desktop_config.json` |

You don't need Rust, Node or Python. The MSI ships the CLI already built.

> On macOS the CLI is a separate download (`effectcraft-cli-<ver>-macos-universal.zip`). On Linux it comes in the same packages as the app.

> **Recommended:** run `scripts\install-mcp.bat`. It does steps 2 and 3 for you and uses the launcher `ec-mcp.ps1`, so step 1 isn't needed: EffectCraft opens itself when Claude first uses it. Below is the manual, **direct bridge** setup (the `-Direct` option), where you start the app yourself. To add the launcher by hand instead, use this entry:
>
> ```json
> "effectcraft": {
>   "command": "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
>   "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
>            "C:\Users\YOU\AppData\Local\EffectCraft-MCP\ec-mcp.ps1", "-Port", "9877"]
> }
> ```
>
> For **Claude Code**: `claude mcp add --scope user effectcraft -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\EffectCraft-MCP\ec-mcp.ps1" -Port 9877`

## Step 1: Start EffectCraft with the control port

The bridge connects to a TCP control channel that the app opens only when it's started with `--control <port>`.

1. Save your work and close EffectCraft.
2. Press **Win + R**, paste the line below, and press Enter:

   ```
   "C:\Program Files\EffectCraft\effectcraft.exe" --control 9877
   ```

`scripts\launch-effectcraft.bat` and the **EffectCraft (Claude)** desktop shortcut do the same thing.

## Step 2: Add the server to Claude's config

1. In Claude, go to **Settings → Developer → Edit Config**. That opens `claude_desktop_config.json`.
2. Add an `effectcraft` entry inside `"mcpServers"`. If other servers are already listed (Blender was on this PC), put a comma after the previous entry and add this one next to them:

   ```json
   {
     "mcpServers": {
       "Blender": { "...": "leave as it was" },
       "effectcraft": {
         "command": "C:\\Program Files\\EffectCraft\\effectcraft-cli.exe",
         "args": ["mcp", "--bridge", "9877"]
       }
     }
   }
   ```

   Keep the double backslashes, because JSON requires them.
3. Save the file and keep the `.json` extension.

## Step 3: Fully restart Claude

Closing the window isn't enough, because Claude keeps running in the system tray. Right-click the tray icon (near the clock, possibly under **^**), choose **Quit**, then reopen Claude.

The first attempt on this PC failed for this reason. The Claude app listed only Blender and reddit-vibe as local servers, and `effectcraft` didn't appear at all, even as failed, until Claude had been fully restarted.

## Step 4: Check it

- Run `scripts\verify.bat`.
- In Claude, ask it to call **`get_state`** on EffectCraft. A working connection returns the app version (0.6.0), command and effect counts (665 commands and 306 effects here) and the editor state.
- Ask for a **`screenshot`**. It should show your EffectCraft window.

When it worked on this PC, Claude listed 31 EffectCraft tools, prefixed `effectcraft__` (see [tools.md](tools.md)).

## Changing the port

The port is arbitrary, but the app and the config have to use the same one. To use 9878, for example:

- App: `effectcraft.exe --control 9878`, or `launch-effectcraft.bat 9878`
- Config: `"args": ["mcp", "--bridge", "9878"]`, or `install-mcp.bat -Port 9878`

## Optional: headless server too

You can also register a second, headless server that works on project files without a window. It's useful for batch jobs and renders while the app is closed. See `config/claude_desktop_config.headless.example.json` and [how-it-works.md](how-it-works.md#two-modes). Give it a different name, such as `effectcraft-headless`, so both can be registered at once.
