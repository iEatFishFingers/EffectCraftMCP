# EffectCraft ↔ Claude MCP connection

This repo sets up a connection between [EffectCraft](https://getartcraft.com/apps/effectcraft) and the Claude desktop app on Windows. EffectCraft is the open-source, After Effects-style compositor from ArtCraft. Once the connection is set up, Claude can build comps, animate layers, add effects, run expressions and scripts, and render frames inside the EffectCraft window you have open, and you see every change as it happens.

EffectCraft includes its own MCP server, `effectcraft-cli mcp`, so there's nothing to build or install from npm or pip. This repo provides the config, scripts and notes needed to wire it up, and records how it was set up on this machine on 9 October 2026 with EffectCraft 0.6.0.

## Quick start

1. Install EffectCraft for Windows from <https://getartcraft.com/apps/effectcraft>. It installs to `C:\Program Files\EffectCraft`.
2. Run **`scripts\install-mcp.bat`**. It adds `effectcraft` to Claude's config (after backing the config up) and puts an **EffectCraft (Claude)** shortcut on your desktop.
3. **Fully quit Claude** by right-clicking its tray icon and choosing **Quit**, then reopen it.
4. Close EffectCraft and start it again with the **EffectCraft (Claude)** shortcut or `scripts\launch-effectcraft.bat`.
5. Run **`scripts\verify.bat`**. Every line should show `[OK]`.
6. In Claude, ask: *"Call the EffectCraft get_state tool."*

If you'd rather edit the config by hand, follow [docs/setup.md](docs/setup.md).

## What's in here

| Path | What it is |
|---|---|
| `scripts/install-mcp.bat` / `.ps1` | Adds the `effectcraft` server to `claude_desktop_config.json`. It backs the file up first and leaves other servers untouched. It also makes the desktop shortcut. |
| `scripts/launch-effectcraft.bat` | Starts EffectCraft with `--control 9877` so the bridge can reach it. |
| `scripts/verify.bat` / `.ps1` | Checks each part of the connection (app, CLI, port and config) and reports which part is broken. |
| `config/claude_desktop_config.example.json` | The config entry for bridge mode, which drives the live window. |
| `config/claude_desktop_config.headless.example.json` | An optional headless entry, with no window and working on an `.ecproj` file. |
| `docs/` | Documentation: [setup](docs/setup.md), [how it works](docs/how-it-works.md), [tools reference](docs/tools.md), [troubleshooting](docs/troubleshooting.md). |

## The one rule to remember

Claude can only reach EffectCraft when EffectCraft was **started with `--control 9877`**. A copy opened from the Start menu or taskbar doesn't open that port, so the tools will fail. Use the desktop shortcut instead.

## Upstream references

- EffectCraft source: <https://github.com/storytold/effectcraft>
- Agent and MCP docs: <https://github.com/storytold/effectcraft/blob/main/docs/agents.md>
- Control protocol: <https://github.com/storytold/effectcraft/blob/main/docs/control-protocol.md>
