@echo off
rem Starts EffectCraft with the control port open so Claude's MCP bridge can drive it.
rem Usage: launch-effectcraft.bat [port]     (default port 9877)
rem Close any EffectCraft window first - a copy opened from the Start menu has no control port.
setlocal
set "PORT=9877"
if not "%~1"=="" set "PORT=%~1"
set "EXE=%ProgramFiles%\EffectCraft\effectcraft.exe"
if not exist "%EXE%" (
  echo EffectCraft not found at "%EXE%".
  echo Install it from https://getartcraft.com/apps/effectcraft or edit EXE in this file.
  pause
  exit /b 1
)
start "" "%EXE%" --control %PORT%
endlocal
