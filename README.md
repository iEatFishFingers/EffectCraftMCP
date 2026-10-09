# EffectCraft ↔ Claude MCP connection

This repo sets up a connection between [EffectCraft](https://getartcraft.com/apps/effectcraft) and Claude (the desktop app and Claude Code) on Windows. EffectCraft is the open-source, After Effects-style compositor from ArtCraft. Once the connection is set up, Claude can build comps, animate layers, add effects, run expressions and scripts, and render frames inside the EffectCraft window you have open, and you see every change as it happens.

EffectCraft includes its own MCP server, `effectcraft-cli mcp`, so there's nothing to build or install from npm or pip. This repo provides the launcher, installer and checks needed to wire it up, and records how it was set up on this machine with EffectCraft 0.6.0.

## Quick start

1. Install EffectCraft for Windows from <https://getartcraft.com/apps/effectcraft>. It installs to `C:\Program Files\EffectCraft`.
2. Run **`scripts\install-mcp.bat`**. It registers EffectCraft with every Claude it finds (the desktop app and/or Claude Code), after backing up the desktop config.
3. Fully quit Claude from its tray icon (**Quit**, not just closing the window) and reopen it. For Claude Code, start a new session.
4. Ask Claude to use EffectCraft. **The app opens by itself** the first time Claude needs it.
5. Optional: run **`scripts\verify.bat -Deep`**. It runs a real call through the same command Claude uses.

If you'd rather edit the config by hand, follow [docs/setup.md](docs/setup.md).

Options for `install-mcp.bat`:

| Option | Effect |
|---|---|
| `-Target Desktop\|Code\|Both` | Pick which Claude to register with. The default, `Auto`, uses whichever it finds. |
| `-Port 9878` | Use another control port. |
| `-Eager` | Open the app as soon as Claude starts, not at the first tool call. |
| `-Project C:\path\x.ecproj` | Open this project when the app is started for you. |
| `-DryRun` | Show what would change and change nothing. |
| `-Uninstall` | Remove the entry and the copied launcher. |
| `-Direct` | The old setup: no launcher, you start the app with `--control` yourself. |
| `-Headless` | A window-less server that works on a `.ecproj` file. |

## What's in here

| Path | What it is |
|---|---|
| `scripts/install-mcp.bat` / `.ps1` | Registers the `effectcraft` server with Claude desktop and/or Claude Code. It backs the desktop config up first and leaves other servers untouched. |
| `scripts/ec-mcp.ps1` | The launcher Claude actually runs. It proxies to `effectcraft-cli mcp --bridge` and starts EffectCraft with `--control` the first time a tool is used. The installer copies it to `%LOCALAPPDATA%\EffectCraft-MCP`. |
| `scripts/verify.bat` / `.ps1` | Reads what Claude is configured to run and checks every link. `-Deep` performs the MCP handshake and a `get_state` call. |
| `scripts/launch-effectcraft.bat` | Starts EffectCraft with `--control 9877` by hand. Only needed with `-Direct`. |
| `config/` | Example config entries: the launcher (`claude_desktop_config.example.json`), direct bridge and headless. |
| `docs/` | [Setup](docs/setup.md), [how it works](docs/how-it-works.md), [tools reference](docs/tools.md), [troubleshooting](docs/troubleshooting.md). |

## How the app gets its control port

Claude can only drive EffectCraft when the app was started with `--control <port>`. The launcher takes care of that: if the port is already open (you started the app that way) it uses it, otherwise it starts the app. Opening the port only on demand is deliberate. The port has no authentication, and a `--control` session skips crash recovery, so it shouldn't be on for every launch. That's why this repo doesn't set `EFFECTCRAFT_CONTROL_PORT` globally.

## Upstream references

- EffectCraft source: <https://github.com/storytold/effectcraft>
- Agent and MCP docs: <https://github.com/storytold/effectcraft/blob/main/docs/agents.md>
- Control protocol: <https://github.com/storytold/effectcraft/blob/main/docs/control-protocol.md>
