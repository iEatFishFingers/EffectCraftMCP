@echo off
rem Adds EffectCraft to Claude's MCP config and makes a desktop shortcut.
rem Any options are passed to install-mcp.ps1 (e.g. -Port 9878, -Headless, -NoShortcut).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-mcp.ps1" %*
pause
