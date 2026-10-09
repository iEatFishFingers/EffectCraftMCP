# How it works

```
 Claude (cloud or desktop chat, or Claude Code)
        │  MCP tool calls
        ▼
 Claude app  ── reads its config, starts the server
        │  stdio (JSON-RPC 2.0, one message per line)
        ▼
 powershell ec-mcp.ps1          ← the launcher (this repo)
        │  starts effectcraft.exe --control 9877 if the port is closed
        │  stdio, passed through unchanged
        ▼
 effectcraft-cli.exe mcp --bridge 9877
        │  TCP 127.0.0.1:9877 (JSON lines: control protocol)
        ▼
 effectcraft.exe --control 9877   ← the window you're looking at
```

1. When Claude starts, it reads its config and launches each server as a child process. For EffectCraft that process is `ec-mcp.ps1`.
2. **`ec-mcp.ps1`** starts **`effectcraft-cli mcp --bridge 9877` and relays its stdin and stdout byte for byte. It looks at each request on the way past: the first `tools/call` or `resources/read` (the only requests that need the app) checks the port and, if it's closed, starts `effectcraft.exe --control 9877` and waits for it to open. Handshakes and `tools/list` never launch anything. If the app was closed meanwhile, the next tool call starts it again.
3. **`effectcraft-cli mcp`** is EffectCraft's built-in MCP server. It talks MCP over stdin/stdout and supports protocol versions 2025-06-18, 2025-03-26 and 2024-11-05.
4. With **`--bridge 9877`**, the server doesn't run its own engine. It forwards each call to the **control channel** of the app that's already running on that port. It makes one 5 s connect attempt per call and retries once if the connection went stale, which is why the launcher waits for the port before forwarding.
5. **`effectcraft.exe --control 9877`** opens the control channel. Without that flag, the app runs normally but nothing can drive it. An app started this way opens without taking keyboard focus (macOS) and skips crash recovery, so it's best used as a working session.

With `-Direct`, step 2 is missing and you start the app yourself.

Chats that run in Claude's cloud reach the tools through the desktop app's link to your computer. That's why the desktop app needs to be open, and why the tools show up with a `remote-devices__effectcraft__` prefix in those chats.

## One command system underneath

EffectCraft routes every menu item, shortcut, panel drag and property edit through a single **command registry**, where each command has a stable id such as `comp.new`, `layer.newText` or `effect.apply` and JSON parameters. The MCP tools, the CLI and the control channel are all front ends to that registry, so:

- anything you can do in the UI, Claude can do too (665 commands in 0.6.0)
- every edit Claude makes is a normal undo step, so **Ctrl+Z works** on it
- `list_commands` and `describe_command` let Claude find commands it hasn't used before

## Two modes

| | Bridge (`mcp --bridge 9877`) | Headless (`mcp`) |
|---|---|---|
| Needs the app open | Yes, started with `--control 9877` | No |
| You see changes live | Yes | No |
| Works on | Whatever is open in the window | Its own in-memory session. Start it with `--project file.ecproj` or `--demo` |
| Extra tools | `screenshot`, `ui_*` (click, drag, type, key, inspect), `control` | none |
| Good for | Working together on a shot | Batch edits, renders, CI, templating |

This repo sets up **bridge** mode by default.

## Safety notes

- The control channel listens on your own machine, on port 9877. The bridge connects to `127.0.0.1`.
- Scripts run through `run_script` or `effectcraft-cli script` can read files only in the project's folder, and can't write files or use the network, unless you turn on **Preferences ▸ Scripting & Expressions ▸ Allow Scripts to Write Files and Access Network**.
- EffectCraft has no telemetry and makes no network calls unless you ask it to.

## The same commands without Claude

You can drive the open app from a terminal through the same bridge, which is handy for testing:

```bat
"C:\Program Files\EffectCraft\effectcraft-cli.exe" exec layer.newNull --bridge 9877
"C:\Program Files\EffectCraft\effectcraft-cli.exe" script --eval "app.project.numItems" --bridge 9877
```

Or headless, against a file:

```bat
"C:\Program Files\EffectCraft\effectcraft-cli.exe" info --json
"C:\Program Files\EffectCraft\effectcraft-cli.exe" render --comp Main --out main.mp4 main.ecproj
```
