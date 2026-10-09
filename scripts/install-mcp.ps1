<#
.SYNOPSIS
  Registers EffectCraft as an MCP server in the Claude desktop app (Windows).

.DESCRIPTION
  - Finds effectcraft-cli.exe (default: C:\Program Files\EffectCraft).
  - Finds claude_desktop_config.json (normal install or Microsoft Store install).
  - Backs the config up, then adds or updates the "effectcraft" server entry.
    Every other server in the file (Blender, etc.) is left untouched.
  - Creates a desktop shortcut that starts EffectCraft with the control port open.

  Safe to run more than once: it just rewrites the same entry.

.PARAMETER CliPath
  Full path to effectcraft-cli.exe, if it is not in the default location.

.PARAMETER Port
  Control port shared by the app (--control) and the MCP bridge (--bridge). Default 9877.

.PARAMETER ServerName
  Name of the entry under "mcpServers". Default "effectcraft".

.PARAMETER Headless
  Register the headless server (no window, works on .ecproj files) instead of the
  bridge to the running app.

.PARAMETER ConfigPath
  Full path to claude_desktop_config.json, if auto-detection picks the wrong one.

.PARAMETER NoShortcut
  Skip creating the desktop shortcut.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install-mcp.ps1
#>
[CmdletBinding()]
param(
    [string]$CliPath = (Join-Path $env:ProgramFiles 'EffectCraft\effectcraft-cli.exe'),
    [int]$Port = 9877,
    [string]$ServerName = 'effectcraft',
    [switch]$Headless,
    [string]$ConfigPath,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[!!] $msg" -ForegroundColor Yellow }

# --- 1. EffectCraft CLI -------------------------------------------------------
Write-Step 'Looking for effectcraft-cli.exe'
if (-not (Test-Path -LiteralPath $CliPath)) {
    throw "effectcraft-cli.exe not found at '$CliPath'. Install EffectCraft from https://getartcraft.com/apps/effectcraft or pass -CliPath."
}
$CliPath = (Resolve-Path -LiteralPath $CliPath).Path
Write-Ok "Found $CliPath"

# --- 2. Claude config file ----------------------------------------------------
Write-Step 'Looking for claude_desktop_config.json'
if (-not $ConfigPath) {
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
        $ConfigPath = $standard
    } elseif ($storeExists) {
        $ConfigPath = $store
    } else {
        $ConfigPath = $standard
    }
}
Write-Ok "Using $ConfigPath"

$configDir = Split-Path -Parent $ConfigPath
if (-not (Test-Path -LiteralPath $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# --- 3. Read + back up ----------------------------------------------------------
$cfg = $null
if (Test-Path -LiteralPath $ConfigPath) {
    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    if ($raw -and $raw.Trim().Length -gt 0) {
        try {
            $cfg = $raw | ConvertFrom-Json
        } catch {
            throw "claude_desktop_config.json is not valid JSON, so nothing was changed. Fix it (see docs/troubleshooting.md) and run again. Parser said: $($_.Exception.Message)"
        }
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$ConfigPath.bak-$stamp"
    Copy-Item -LiteralPath $ConfigPath -Destination $backup
    Write-Ok "Backup saved to $backup"
}
if (-not $cfg) { $cfg = [pscustomobject]@{} }

# --- 4. Add / update the entry ----------------------------------------------------
if (-not ($cfg.PSObject.Properties.Name -contains 'mcpServers') -or -not $cfg.mcpServers) {
    $cfg | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
}

if ($Headless) {
    $serverArgs = @('mcp')
} else {
    $serverArgs = @('mcp', '--bridge', "$Port")
}

$entry = [pscustomobject]@{
    command = $CliPath
    args    = $serverArgs
}
$cfg.mcpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue $entry -Force

$json = $cfg | ConvertTo-Json -Depth 32
[System.IO.File]::WriteAllText($ConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$names = ($cfg.mcpServers.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
Write-Ok "Wrote '$ServerName' to the config. Servers now listed: $names"

# --- 5. Desktop shortcut ----------------------------------------------------------
if (-not $NoShortcut -and -not $Headless) {
    $appExe = Join-Path (Split-Path -Parent $CliPath) 'effectcraft.exe'
    if (Test-Path -LiteralPath $appExe) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desktop 'EffectCraft (Claude).lnk'
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = $appExe
        $lnk.Arguments = "--control $Port"
        $lnk.WorkingDirectory = Split-Path -Parent $appExe
        $lnk.IconLocation = "$appExe,0"
        $lnk.Description = "EffectCraft with the Claude MCP control port ($Port) open"
        $lnk.Save()
        Write-Ok "Desktop shortcut created: $lnkPath"
    } else {
        Write-Warn2 "effectcraft.exe not found next to the CLI, so no shortcut was made."
    }
}

# --- 6. Next steps -------------------------------------------------------------
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Fully quit Claude: right-click its tray icon > Quit (closing the window is not enough). Reopen it.'
if (-not $Headless) {
    Write-Host "  2. Close EffectCraft, then start it with the 'EffectCraft (Claude)' shortcut or scripts\launch-effectcraft.bat."
}
Write-Host '  3. Run scripts\verify.bat to check everything, then ask Claude to call effectcraft get_state.'
