@echo off
rem Checks the app, CLI, control port and Claude config. Options go to verify.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" %*
pause
