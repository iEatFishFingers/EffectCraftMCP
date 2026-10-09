# Troubleshooting

Start by running `scripts\verify.bat`. It checks each part of the connection and tells you which part is broken.

## The launcher didn't start EffectCraft

The launcher writes a log to `%LOCALAPPDATA%\EffectCraft-MCP\ec-mcp.log` and to stderr (Claude shows that in its MCP server log). It records when it started the app, when the port opened and why it gave up.

- **"is not installed at ..."**: EffectCraft lives somewhere else. Add `-InstallDir "D:\path\to\EffectCraft"` to the entry's args, or rerun `install-mcp.bat -CliPath "D:\path\effectcraft-cli.exe"`.
- **"did not open port ... within 90 s"**: the app started but didn't open the control port. Another program may hold the port (`netstat -ano | findstr 9877`), or the window failed to start. Start `effectcraft.exe --control 9877` from a terminal to see its messages, or pick another port with `install-mcp.bat -Port 9878`.
- **The app opened, but the first call timed out**: the first frame of a big project can take a while. Ask again.
- **Run `scripts\verify.bat -Deep`** to see the same steps with a clear pass or fail.

## EffectCraft tools don't appear in Claude at all

**Cause:** the Claude desktop app hasn't loaded the new config entry.

- **Claude is still running in the tray.** Right-click the tray icon, choose **Quit**, and reopen Claude. Closing the window doesn't reload the config. *This was the cause of the first failed attempt on this PC.*
- **The file wasn't saved, or was saved as `.txt`.** It must be named `claude_desktop_config.json`.
- **The entry is outside `"mcpServers"`.** It has to sit next to the other servers inside that block.
- **The JSON is invalid.** Common mistakes are a missing comma between server entries, single backslashes in the path (use `C:\\Program Files\\...`), and a trailing comma after the last entry. `install-mcp.ps1` refuses to touch a file it can't parse and tells you so.
- **Microsoft Store install of Claude.** That version reads its config from `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`. **Settings → Developer → Edit Config** always opens the right file. You can also pass that path to `install-mcp.bat -ConfigPath "..."`.

To check from a chat, ask Claude what state the local MCP servers are in. If `effectcraft` isn't listed at all, the config hasn't been read. If it's listed as `failed`, see the next section.

## Tools appear, but calls fail or time out

**Cause:** the bridge can't reach the app.

- **EffectCraft was opened from the Start menu or taskbar.** It needs `--control 9877`. With the launcher, Claude says so and you just close that window (save first) and ask again: the launcher reopens it with the port. With `-Direct`, reopen it with the **EffectCraft (Claude)** shortcut or `scripts\launch-effectcraft.bat`.
- **EffectCraft isn't running.** Bridge mode needs the window open.
- **The ports don't match.** The number after `--control` must be the same as the one after `--bridge`.
- **Another program is using port 9877.** Run `netstat -ano | findstr 9877` to check. Pick another port and change it in both places (see [setup.md](setup.md#changing-the-port)).
- **A firewall prompt was dismissed.** The connection only goes to `127.0.0.1`, so it normally isn't blocked. If Windows Firewall asked about EffectCraft, allowing **private networks** is enough.

## The server is listed as failed

- **The path in `"command"` is wrong.** Check that `C:\Program Files\EffectCraft\effectcraft-cli.exe` exists. If you used the portable zip, it'll be wherever you unzipped it.
- **Test the CLI on its own:** run `"C:\Program Files\EffectCraft\effectcraft-cli.exe" info --json` in a terminal. It should print JSON. If it doesn't, reinstall EffectCraft.

## Changes don't show up in the window

You're probably connected to a **headless** server (`"args": ["mcp"]` with no `--bridge`). Headless mode edits its own in-memory project. Switch the args to `["mcp", "--bridge", "9877"]`.

## Undoing something Claude did

Every MCP edit is a normal undo step, so press **Ctrl+Z** in EffectCraft or ask Claude to `undo`. Changes made with `batch` are a single undo step.

## Scripts can't write files

That's on purpose. Turn on **Preferences ▸ Scripting & Expressions ▸ Allow Scripts to Write Files and Access Network** only if you trust the script.

## Upgrading EffectCraft

The MSI installs to the same folder, so the config keeps working. After an upgrade, run `verify.bat` and ask Claude for `get_state` to confirm the version. New commands appear automatically through `list_commands`.

## Still stuck

- EffectCraft issues: <https://github.com/storytold/effectcraft/issues>
- ArtCraft Discord: <https://discord.gg/artcraft>
