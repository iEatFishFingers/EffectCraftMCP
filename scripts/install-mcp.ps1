<#
.SYNOPSIS
  Registers EffectCraft as an MCP server in Claude (desktop app and/or Claude Code) on Windows.

.DESCRIPTION
  By default Claude runs scripts\ec-mcp.ps1 (copied to %LOCALAPPDATA%\EffectCraft-MCP), which
  starts EffectCraft with its control port the first time Claude uses a tool. No special shortcut,
  no "start it the right way" rule.

  - Finds effectcraft-cli.exe (default: C:\Program Files\EffectCraft).
  - Claude desktop: finds claude_desktop_config.json (normal or Microsoft Store install), backs it
    up, then adds or updates the "effectcraft" entry. Other servers are left untouched.
  - Claude Code: runs `claude mcp add --scope user`.
  - Safe to run more than once: it rewrites the same entry.

.PARAMETER Target
  Auto (default): every Claude you have. Desktop, Code, or Both to force.

.PARAMETER Direct
  Register `effectcraft-cli mcp --bridge <port>` as before, with no launcher. You then have to
  start the app yourself with --control (the old desktop shortcut is made for that).

.PARAMETER Headless
  Register the headless server (no window, works on .ecproj files; -Project to preload one).

.PARAMETER Eager
  Launcher mode: start EffectCraft when Claude starts, not at the first tool call.

.PARAMETER Project
  Launcher: a .ecproj to open when the launcher starts the app. Headless: the project to serve.

.PARAMETER Port
  Control port shared by the app (--control) and the bridge (--bridge). Default 9877.

.PARAMETER CliPath
  Full path to effectcraft-cli.exe, if it is not in the default location.

.PARAMETER ServerName
  Name of the entry. Default "effectcraft".

.PARAMETER ConfigPath
  Full path to claude_desktop_config.json, if auto-detection picks the wrong one.

.PARAMETER DryRun
  Print what would change and change nothing.

.PARAMETER Uninstall
  Remove the entry (from the targets) and the copied launcher.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install-mcp.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install-mcp.ps1 -Target Code -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Desktop', 'Code', 'Both')][string]$Target = 'Auto',
    [string]$CliPath = (Join-Path $env:ProgramFiles 'EffectCraft\effectcraft-cli.exe'),
    [int]$Port = 9877,
    [string]$ServerName = 'effectcraft',
    [switch]$Direct,
    [switch]$Headless,
    [switch]$Eager,
    [string]$Project,
    [string]$ConfigPath,
    [switch]$NoShortcut,
    [switch]$DryRun,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[!!] $msg" -ForegroundColor Yellow }
function Write-Dry($msg)  { Write-Host "[dry-run] $msg" -ForegroundColor Magenta }

if ($Direct -and $Headless) { throw '-Direct and -Headless are different modes; pick one.' }
if ($Eager -and ($Direct -or $Headless)) { throw '-Eager only applies to the launcher mode.' }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installedDir = Join-Path $env:LOCALAPPDATA 'EffectCraft-MCP'
$launcherSrc = Join-Path $here 'ec-mcp.ps1'
$launcherDst = Join-Path $installedDir 'ec-mcp.ps1'

# --- 1. EffectCraft CLI -------------------------------------------------------
if (-not $Uninstall) {
    Write-Step 'Looking for effectcraft-cli.exe'
    if (-not (Test-Path -LiteralPath $CliPath)) {
        throw "effectcraft-cli.exe not found at '$CliPath'. Install EffectCraft from https://getartcraft.com/apps/effectcraft or pass -CliPath."
    }
    $CliPath = (Resolve-Path -LiteralPath $CliPath).Path
    Write-Ok "Found $CliPath"
}
$installDir = Split-Path -Parent $CliPath

# --- 2. What to register ---------------------------------------------------------
# $command / $serverArgs are what Claude will run, whichever mode.
if ($Headless) {
    $command = $CliPath
    $serverArgs = @('mcp')
    if ($Project) { $serverArgs += @('--project', $Project) }
    $mode = 'headless (no window)'
} elseif ($Direct) {
    $command = $CliPath
    $serverArgs = @('mcp', '--bridge', "$Port")
    $mode = "direct bridge to port $Port (start the app with --control $Port yourself)"
} else {
    $command = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $serverArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcherDst, '-Port', "$Port")
    if ($installDir -ne (Join-Path $env:ProgramFiles 'EffectCraft')) { $serverArgs += @('-InstallDir', $installDir) }
    if ($Eager) { $serverArgs += '-Eager' }
    if ($Project) { $serverArgs += @('-Project', $Project) }
    $mode = "launcher on port $Port (starts EffectCraft when Claude first needs it)"
}

# --- 3. Which Claudes ---------------------------------------------------------------
function Find-DesktopConfig {
    $standard = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
    $store = $null
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $pkgRoot) {
        $pkg = Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) { $store = Join-Path $pkg.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' }
    }
    $standardExists = Test-Path -LiteralPath $standard
    $storeExists = $store -and (Test-Path -LiteralPath $store)
    if ($standardExists -and $storeExists) {
        Write-Warn2 "Two configs found. Using '$standard'."
        Write-Warn2 "If EffectCraft does not appear in Claude, rerun with -ConfigPath '$store'."
        return $standard
    }
    if ($storeExists) { return $store }
    return $standard
}

$claudeCode = Get-Command claude -ErrorAction SilentlyContinue
$desktopDirExists = $false
if (-not $ConfigPath) {
    $guess = Find-DesktopConfig
    $desktopDirExists = (Test-Path -LiteralPath (Split-Path -Parent $guess))
} else {
    $guess = $ConfigPath
    $desktopDirExists = $true
}

$doDesktop = $false; $doCode = $false
switch ($Target) {
    'Desktop' { $doDesktop = $true }
    'Code'    { $doCode = $true }
    'Both'    { $doDesktop = $true; $doCode = $true }
    'Auto'    {
        $doDesktop = $desktopDirExists
        $doCode = [bool]$claudeCode
        if (-not $doDesktop -and -not $doCode) { $doDesktop = $true }
    }
}
if ($doCode -and -not $claudeCode) { throw "Target includes Claude Code but the 'claude' command isn't on PATH." }
if (-not $Uninstall) { Write-Step "Mode: $mode" }

# --- 4. Launcher copy ----------------------------------------------------------------
if (-not $Uninstall -and -not $Direct -and -not $Headless) {
    if (-not (Test-Path -LiteralPath $launcherSrc)) { throw "Missing $launcherSrc" }
    if ($DryRun) {
        Write-Dry "copy $launcherSrc -> $launcherDst"
    } else {
        New-Item -ItemType Directory -Path $installedDir -Force | Out-Null
        Copy-Item -LiteralPath $launcherSrc -Destination $launcherDst -Force
        Write-Ok "Launcher installed at $launcherDst"
    }
}

# --- 5. Claude desktop ---------------------------------------------------------------
if ($doDesktop) {
    Write-Step 'Claude desktop app'
    if (-not $ConfigPath) { $ConfigPath = $guess }
    Write-Ok "Using $ConfigPath"

    $cfg = $null
    $exists = Test-Path -LiteralPath $ConfigPath
    if ($exists) {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw
        if ($raw -and $raw.Trim().Length -gt 0) {
            try { $cfg = $raw | ConvertFrom-Json }
            catch { throw "claude_desktop_config.json is not valid JSON, so nothing was changed. Fix it (see docs/troubleshooting.md) and run again. Parser said: $($_.Exception.Message)" }
        }
    }
    if (-not $cfg) { $cfg = [pscustomobject]@{} }
    $has = ($cfg.PSObject.Properties.Name -contains 'mcpServers') -and $cfg.mcpServers -and ($cfg.mcpServers.PSObject.Properties.Name -contains $ServerName)

    if ($Uninstall) {
        if (-not $has) { Write-Ok "No '$ServerName' entry in the desktop config." }
        elseif ($DryRun) { Write-Dry "remove '$ServerName' from $ConfigPath" }
        else {
            Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $cfg.mcpServers.PSObject.Properties.Remove($ServerName)
            [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok "Removed '$ServerName' from the desktop config."
        }
    } else {
        $entry = [pscustomobject]@{ command = $command; args = $serverArgs }
        if ($DryRun) {
            Write-Dry "write to ${ConfigPath}:"
            Write-Dry (([pscustomobject]@{ $ServerName = $entry } | ConvertTo-Json -Depth 8) -replace "`r?`n", "`n           ")
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) -Force | Out-Null
            if ($exists) {
                $backup = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -LiteralPath $ConfigPath -Destination $backup
                Write-Ok "Backup saved to $backup"
            }
            if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers') -or -not $cfg.mcpServers) {
                $cfg | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.mcpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue $entry -Force
            [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
            $names = ($cfg.mcpServers.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
            Write-Ok "Wrote '$ServerName' to the config. Servers now listed: $names"
        }
    }
}

# --- 6. Claude Code ------------------------------------------------------------------
if ($doCode) {
    Write-Step 'Claude Code'
    $listed = (& claude mcp list 2>$null | Out-String) -match "(?m)^\s*$([regex]::Escape($ServerName)):"
    if ($Uninstall) {
        if (-not $listed) { Write-Ok "Claude Code has no '$ServerName' server." }
        elseif ($DryRun) { Write-Dry "claude mcp remove --scope user $ServerName" }
        else { & claude mcp remove --scope user $ServerName | Out-Null; Write-Ok "Removed '$ServerName' from Claude Code." }
    } else {
        $addArgs = @('mcp', 'add', '--scope', 'user', $ServerName, '--', $command) + $serverArgs
        if ($DryRun) {
            Write-Dry ("claude " + (($addArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '))
        } else {
            if ($listed) { & claude mcp remove --scope user $ServerName | Out-Null }
            & claude @addArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "claude mcp add failed (exit $LASTEXITCODE)." }
            Write-Ok "Added '$ServerName' to Claude Code (user scope, every project)."
        }
    }
}

# --- 7. Cleanup / shortcut -----------------------------------------------------------
if ($Uninstall) {
    if (-not $DryRun -and (Test-Path -LiteralPath $installedDir)) {
        Remove-Item -LiteralPath $installedDir -Recurse -Force
        Write-Ok "Removed $installedDir"
    }
    return
}

if ($Direct -and -not $NoShortcut) {
    $appExe = Join-Path $installDir 'effectcraft.exe'
    if (-not (Test-Path -LiteralPath $appExe)) {
        Write-Warn2 'effectcraft.exe not found next to the CLI, so no shortcut was made.'
    } elseif ($DryRun) {
        Write-Dry 'create the "EffectCraft (Claude)" desktop shortcut'
    } else {
        $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'EffectCraft (Claude).lnk'
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = $appExe
        $lnk.Arguments = "--control $Port"
        $lnk.WorkingDirectory = $installDir
        $lnk.IconLocation = "$appExe,0"
        $lnk.Description = "EffectCraft with the Claude MCP control port ($Port) open"
        $lnk.Save()
        Write-Ok "Desktop shortcut created: $lnkPath"
    }
}

# --- 8. Next steps -------------------------------------------------------------------
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
if ($doDesktop) {
    Write-Host '  - Claude desktop: fully quit it (tray icon > Quit; closing the window is not enough) and reopen it.'
}
if ($doCode) {
    Write-Host '  - Claude Code: start a new session (or run /mcp) to pick up the server.'
}
if ($Direct) {
    Write-Host "  - Start EffectCraft with the 'EffectCraft (Claude)' shortcut so the control port is open."
} elseif (-not $Headless) {
    Write-Host '  - Nothing to launch by hand: ask Claude to use EffectCraft and the app opens on its own.'
}
Write-Host '  - Check it any time with scripts\verify.bat (add -Deep to run a real call).'
