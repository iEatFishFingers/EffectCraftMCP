<#
.SYNOPSIS
  Checks each link in the EffectCraft -> Claude MCP chain and says which one is broken.

.DESCRIPTION
  Reads what Claude is actually configured to run (desktop config and/or Claude Code), so it works
  for the launcher, direct-bridge and headless setups alike.

  -Deep goes one step further: it starts that exact command the way Claude does, performs the MCP
  handshake and calls get_state. In launcher mode that starts EffectCraft if it isn't running.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Deep
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'EffectCraft'),
    [int]$Port = 9877,
    [string]$ServerName = 'effectcraft',
    [string]$ConfigPath,
    [switch]$Deep,
    [int]$DeepTimeoutSec = 120
)

$script:failures = 0
function Pass($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[!!] $msg" -ForegroundColor Red; $script:failures++ }
function Note($msg) { Write-Host "[..] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host "     $msg" -ForegroundColor DarkGray }

$appExe = Join-Path $InstallDir 'effectcraft.exe'
$cliExe = Join-Path $InstallDir 'effectcraft-cli.exe'

function Test-Port([int]$p) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $a = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        return ($a.AsyncWaitHandle.WaitOne(1500) -and $c.Connected)
    } catch { return $false } finally { $c.Close() }
}

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

# 3. Find what Claude will run: desktop config(s), then Claude Code
$entries = @()   # each: @{ where; command; args }

$candidates = @()
if ($ConfigPath) { $candidates = @($ConfigPath) } else {
    $candidates += (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $pkgRoot) {
        Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates += (Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json')
        }
    }
}
$found = @($candidates | Where-Object { Test-Path -LiteralPath $_ })
if ($found.Count -eq 0) {
    Note 'No Claude desktop config found (fine if you only use Claude Code). In Claude: Settings > Developer > Edit Config creates it.'
}
foreach ($path in $found) {
    $cfg = $null
    try { $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
    if (-not $cfg) { Fail "Not valid JSON: $path (check commas and that backslashes are doubled)"; continue }
    if ($cfg.mcpServers -and ($cfg.mcpServers.PSObject.Properties.Name -contains $ServerName)) {
        $e = $cfg.mcpServers.$ServerName
        Pass "Desktop config has '$ServerName': $path"
        $entries += @{ where = 'Claude desktop'; command = $e.command; args = @($e.args) }
    } else {
        Note "No '$ServerName' entry in $path"
    }
}

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $list = (& claude mcp list 2>$null | Out-String)
    if ($list -match "(?m)^\s*$([regex]::Escape($ServerName)):") {
        $line = ($list -split "`r?`n" | Where-Object { $_ -match "^\s*$([regex]::Escape($ServerName)):" } | Select-Object -First 1)
        Pass "Claude Code has '$ServerName'"
        Info $line.Trim()
        if ($found.Count -eq 0 -or $entries.Count -eq 0) {
            $detail = (& claude mcp get $ServerName 2>$null | Out-String)
            $cmd = if ($detail -match '(?m)Command:\s*(.+)') { $Matches[1].Trim() } else { $null }
            $a = if ($detail -match '(?m)Args:\s*(.+)') { $Matches[1].Trim() } else { '' }
            if ($cmd) { $entries += @{ where = 'Claude Code'; command = $cmd; args = @($a -split '\s+' | Where-Object { $_ }) } }
        }
    } else {
        Note "Claude Code has no '$ServerName' server"
    }
}

if ($entries.Count -eq 0) {
    Fail "'$ServerName' isn't registered in any Claude. Run scripts\install-mcp.bat."
}

# 4. Check each entry
$mode = $null
foreach ($e in $entries) {
    $argText = ($e.args -join ' ')
    $cmd = [string]$e.command
    if ($cmd -match 'powershell' -and $argText -match 'ec-mcp\.ps1') {
        $script = ($e.args | Where-Object { $_ -match 'ec-mcp\.ps1$' } | Select-Object -First 1)
        $mode = 'launcher'
        if ($script -and (Test-Path -LiteralPath $script)) { Pass "$($e.where): launcher script exists ($script)" }
        else { Fail "$($e.where): launcher script missing ($script). Run scripts\install-mcp.bat again." }
        if ($argText -match '-Port\s+(\d+)') { $p = [int]$Matches[1]; if ($p -ne $Port) { Info "$($e.where) uses port $p (this check assumed $Port; pass -Port $p)" } }
    } elseif ($argText -match '--bridge\s+(\d+)') {
        $mode = 'direct'
        if (Test-Path -LiteralPath $cmd) { Pass "$($e.where): command exists ($cmd)" } else { Fail "$($e.where): command does not exist ($cmd)" }
        if ([int]$Matches[1] -ne $Port) { Fail "$($e.where) bridges to port $($Matches[1]) but this check used $Port. They must match the app's --control port." }
    } else {
        $mode = 'headless'
        Info "$($e.where): headless mode ($argText). It edits its own session, not the open window."
    }
}

# 5. The app's control port
if ($mode -eq 'launcher') {
    if (Test-Port $Port) { Pass "EffectCraft is running with its control port open ($Port)" }
    else { Note "EffectCraft isn't running. That's fine: the launcher starts it when Claude first uses a tool." }
} elseif ($mode -eq 'direct') {
    if (Test-Port $Port) { Pass "EffectCraft is listening on port $Port" }
    else { Fail "Nothing is listening on port $Port. Start EffectCraft with scripts\launch-effectcraft.bat (or the desktop shortcut), not the Start menu. Or switch to the launcher: scripts\install-mcp.bat." }
}

# 6. Deep: run the configured command like Claude does
if ($Deep -and $entries.Count -gt 0 -and $mode -ne 'headless') {
    $e = $entries[0]
    Write-Host ''
    Write-Host "Deep check: running $($e.where)'s command ..." -ForegroundColor Cyan
    $quoted = ($e.args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $e.command
    $psi.Arguments = $quoted
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try { [Console]::InputEncoding = [System.Text.Encoding]::GetEncoding(28591) } catch { }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $send = {
        param($json)
        $b = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
        $p.StandardInput.BaseStream.Write($b, 0, $b.Length)
        $p.StandardInput.BaseStream.Flush()
    }
    $readReply = {
        param($id, $sec)
        $deadline = (Get-Date).AddSeconds($sec)
        while ((Get-Date) -lt $deadline) {
            if (-not $script:lineTask) { $script:lineTask = $p.StandardOutput.ReadLineAsync() }
            if ($script:lineTask.Wait(500)) {
                $l = $script:lineTask.Result; $script:lineTask = $null
                if ($null -eq $l) { return $null }
                try { $o = $l | ConvertFrom-Json } catch { continue }
                if ($o.id -eq $id) { return $o }
            }
        }
        return $null
    }
    try {
        & $send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ec-verify","version":"1"}}}'
        $r = & $readReply 1 20
        if ($r -and $r.result) { Pass "MCP handshake OK ($($r.result.serverInfo.name) $($r.result.serverInfo.version))" } else { Fail 'No reply to the MCP initialize request.' }
        & $send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        & $send '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        $r = & $readReply 2 20
        if ($r -and $r.result.tools) { Pass "$($r.result.tools.Count) tools offered" } else { Fail 'No tool list came back.' }
        Info "get_state may take a while if the app has to start (up to $DeepTimeoutSec s) ..."
        & $send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_state","arguments":{}}}'
        $r = & $readReply 3 $DeepTimeoutSec
        if ($r -and $r.result -and -not $r.result.isError) {
            $txt = $r.result.content[0].text
            $ver = $null; $live = $false
            try {
                $st = $txt | ConvertFrom-Json
                $ver = $st.app.version
                # Only the live window reports UI state such as its view layout.
                $live = [bool]($st.state -and ($st.state.PSObject.Properties.Name -contains 'view_layout'))
            } catch { }
            if ($live) { Pass "get_state answered from the live EffectCraft window (version $ver)" }
            else { Fail "get_state answered, but not from a live window (version $ver). Check the entry has --bridge." }
        } elseif ($r) {
            Fail "get_state failed: $($r.result.content[0].text)$($r.error.message)"
        } else {
            Fail "get_state didn't answer within $DeepTimeoutSec s."
        }
    } finally {
        try { $p.StandardInput.Close() } catch { }
        if (-not $p.WaitForExit(5000)) { try { $p.Kill() } catch { } }
        $errTxt = ''
        try { if ($errTask.Wait(1000)) { $errTxt = $errTask.Result.Trim() } } catch { }
        if ($errTxt) { Info 'server log:'; $errTxt -split "`r?`n" | ForEach-Object { Info "  $_" } }
    }
}

Write-Host ''
if ($script:failures -eq 0) {
    Write-Host 'All checks passed. If Claude still has no EffectCraft tools, fully quit Claude from the tray and reopen it (Claude Code: start a new session).' -ForegroundColor Green
    if (-not $Deep) { Write-Host 'Add -Deep to also run a real call through the configured command.' -ForegroundColor DarkGray }
} else {
    Write-Host "$($script:failures) check(s) failed. See docs\troubleshooting.md." -ForegroundColor Red
}
exit $script:failures
