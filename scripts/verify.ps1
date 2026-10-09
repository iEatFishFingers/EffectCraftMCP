<#
.SYNOPSIS
  Checks each link in the EffectCraft -> Claude MCP chain and says which one is broken.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'EffectCraft'),
    [int]$Port = 9877,
    [string]$ServerName = 'effectcraft',
    [string]$ConfigPath
)

$script:failures = 0
function Pass($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[!!] $msg" -ForegroundColor Red; $script:failures++ }
function Info($msg) { Write-Host "     $msg" -ForegroundColor DarkGray }

$appExe = Join-Path $InstallDir 'effectcraft.exe'
$cliExe = Join-Path $InstallDir 'effectcraft-cli.exe'

# 1. Programs installed
if (Test-Path -LiteralPath $appExe) { Pass "App found: $appExe" } else { Fail "App missing: $appExe" }
if (Test-Path -LiteralPath $cliExe) { Pass "CLI found: $cliExe" } else { Fail "CLI missing: $cliExe" }

# 2. CLI runs
if (Test-Path -LiteralPath $cliExe) {
    try {
        $out = & $cliExe info --json 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $ver = $null
            try { $ver = ($out | ConvertFrom-Json).version } catch { }
            if ($ver) { Pass "CLI runs (EffectCraft $ver)" } else { Pass 'CLI runs' }
        } else {
            Fail "CLI exited with code $LASTEXITCODE"
            Info $out.Trim()
        }
    } catch {
        Fail "CLI could not start: $($_.Exception.Message)"
    }
}

# 3. App is listening on the control port
$client = New-Object System.Net.Sockets.TcpClient
try {
    $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    $connected = $async.AsyncWaitHandle.WaitOne(1500) -and $client.Connected
    if ($connected) {
        Pass "EffectCraft is listening on port $Port"
    } else {
        Fail "Nothing is listening on port $Port. Start EffectCraft with scripts\launch-effectcraft.bat (or the desktop shortcut), not the Start menu."
    }
} catch {
    Fail "Nothing is listening on port $Port. Start EffectCraft with scripts\launch-effectcraft.bat."
} finally {
    $client.Close()
}

# 4. Claude config has the entry
if (-not $ConfigPath) {
    $candidates = @(Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $pkgRoot) {
        Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates += (Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json')
        }
    }
    $ConfigPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $ConfigPath -or -not (Test-Path -LiteralPath $ConfigPath)) {
    Fail 'claude_desktop_config.json not found. In Claude: Settings > Developer > Edit Config creates it.'
} else {
    Pass "Config found: $ConfigPath"
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } catch { }
    if (-not $cfg) {
        Fail 'Config is not valid JSON (check commas and that backslashes are doubled).'
    } elseif (-not $cfg.mcpServers -or -not ($cfg.mcpServers.PSObject.Properties.Name -contains $ServerName)) {
        Fail "Config has no '$ServerName' entry under mcpServers. Run scripts\install-mcp.bat."
    } else {
        $entry = $cfg.mcpServers.$ServerName
        Pass "Config has an '$ServerName' entry"
        if (Test-Path -LiteralPath $entry.command) { Pass "Entry command exists: $($entry.command)" } else { Fail "Entry command does not exist: $($entry.command)" }
        $argText = ($entry.args -join ' ')
        if ($argText -match "--bridge\s+$Port") {
            Pass "Entry bridges to port $Port"
        } elseif ($argText -match '--bridge\s+(\d+)') {
            Fail "Entry bridges to port $($Matches[1]) but this check used $Port. They must match the app's --control port."
        } else {
            Info "Entry args: $argText (headless mode: it will not drive the open window)"
        }
    }
}

Write-Host ''
if ($script:failures -eq 0) {
    Write-Host 'All checks passed. If Claude still has no EffectCraft tools, fully quit Claude from the tray and reopen it.' -ForegroundColor Green
} else {
    Write-Host "$($script:failures) check(s) failed. See docs\troubleshooting.md." -ForegroundColor Red
}
exit $script:failures
