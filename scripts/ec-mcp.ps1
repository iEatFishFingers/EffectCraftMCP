<#
.SYNOPSIS
  The command Claude runs for the EffectCraft MCP server. Starts EffectCraft for you.

.DESCRIPTION
  A thin stdio proxy in front of `effectcraft-cli mcp --bridge <port>`:

    Claude  <-- MCP over stdio -->  ec-mcp.ps1  <-- stdio -->  effectcraft-cli mcp --bridge
                                        |
                                        +-- starts `effectcraft.exe --control <port>` if nothing
                                            is listening yet, the first time Claude uses a tool

  Why a proxy: the bridge only works when the app was started with --control, and the CLI gives up
  after one 5 s connect attempt. This waits for the app instead, so there is no special shortcut to
  remember and Claude can open the app itself. If you already started EffectCraft with --control
  (or the desktop shortcut), it is used as it is and nothing else is launched.

  The control port is opened only when Claude first needs it (not while you merely chat), because
  the port has no authentication and a --control session skips crash recovery.

  stdout carries MCP messages only. Everything this script says goes to stderr, which Claude
  writes to its MCP log, and to %LOCALAPPDATA%\EffectCraft-MCP\ec-mcp.log.

.PARAMETER Port
  Control port, shared by the app (--control) and the bridge (--bridge). Default 9877.

.PARAMETER InstallDir
  Folder holding effectcraft.exe and effectcraft-cli.exe. Default: C:\Program Files\EffectCraft.

.PARAMETER StartTimeoutSec
  How long to wait for a freshly started app to open the port. Default 90.

.PARAMETER Eager
  Start the app as soon as Claude starts the server, not at the first tool call.

.PARAMETER Project
  A .ecproj to open when this script has to start the app.
#>
[CmdletBinding()]
param(
    [int]$Port = 9877,
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'EffectCraft'),
    [int]$StartTimeoutSec = 90,
    [switch]$Eager,
    [string]$Project
)

$ErrorActionPreference = 'Stop'
$appExe = Join-Path $InstallDir 'effectcraft.exe'
$cliExe = Join-Path $InstallDir 'effectcraft-cli.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'EffectCraft-MCP'
$logFile = Join-Path $logDir 'ec-mcp.log'
function Log([string]$msg) {
    $line = '{0:HH:mm:ss} ec-mcp: {1}' -f (Get-Date), $msg
    [Console]::Error.WriteLine($line)
    try {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt 512KB) {
            Move-Item -LiteralPath $logFile -Destination "$logFile.old" -Force
        }
        Add-Content -LiteralPath $logFile -Value $line
    } catch { }
}

function Test-Port([int]$p) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $a = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        return ($a.AsyncWaitHandle.WaitOne(400) -and $c.Connected)
    } catch { return $false } finally { $c.Close() }
}

$script:appProc = $null
$script:problem = $null
function Ensure-App {
    $script:problem = $null
    if (Test-Port $Port) { return $true }
    # An app opened the normal way has no control port. A second window would split your work
    # in two, so say so instead of starting one.
    $plain = @(Get-CimInstance Win32_Process -Filter "Name='effectcraft.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -notmatch '--control' })
    if ($plain.Count -gt 0) {
        $script:problem = "EffectCraft is already open, but without its control port, so Claude can't reach it. Save your work, close that EffectCraft window, then ask again and it will be reopened for Claude."
        Log $script:problem
        return $false
    }
    if (-not (Test-Path -LiteralPath $appExe)) {
        Log "EffectCraft is not installed at '$appExe' (set -InstallDir in the Claude config)."
        return $false
    }
    $argList = @('--control', "$Port")
    if ($Project) { $argList += $Project }
    Log "Nothing on port $Port; starting EffectCraft."
    # ShellExecute start: the app does not inherit our stdio pipes, so it outlives this script.
    $script:appProc = Start-Process -FilePath $appExe -ArgumentList $argList -WorkingDirectory $InstallDir -PassThru
    $deadline = (Get-Date).AddSeconds($StartTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port $Port) { Log 'EffectCraft is ready.'; return $true }
        if ($script:appProc.HasExited) {
            # A second copy hands off to the first, or the window failed: either way look again.
            Start-Sleep -Milliseconds 800
            if (Test-Port $Port) { Log 'EffectCraft is ready.'; return $true }
            Log "EffectCraft exited (code $($script:appProc.ExitCode)) before opening port $Port."
            return $false
        }
        Start-Sleep -Milliseconds 250
    }
    Log "EffectCraft did not open port $Port within $StartTimeoutSec s."
    return $false
}

if (-not (Test-Path -LiteralPath $cliExe)) {
    Log "effectcraft-cli.exe not found at '$cliExe'. Install EffectCraft from https://getartcraft.com/apps/effectcraft."
    exit 1
}

# --- the real MCP server, with raw byte streams so UTF-8 passes through untouched ---------------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $cliExe
$psi.Arguments = "mcp --bridge $Port"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
# .NET Framework encodes a redirected stdin with Console.InputEncoding and, for UTF-8, writes a BOM
# before the first line, which the MCP server rejects as a parse error. We write raw bytes
# ourselves, so pick an encoding with no preamble for the child's stdin writer.
try { [Console]::InputEncoding = [System.Text.Encoding]::GetEncoding(28591) } catch { }
$cli = [System.Diagnostics.Process]::Start($psi)

$stdout = [Console]::OpenStandardOutput()
$stderr = [Console]::OpenStandardError()
$pumpOut = $cli.StandardOutput.BaseStream.CopyToAsync($stdout)
$pumpErr = $cli.StandardError.BaseStream.CopyToAsync($stderr)
$toCli = $cli.StandardInput.BaseStream
$utf8 = New-Object System.Text.UTF8Encoding($false)
$reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)

if ($Eager) { [void](Ensure-App) }

# Tool calls and resource reads are the only requests that touch the app.
$needsApp = '"method"\s*:\s*"(tools/call|resources/read)"'

try {
    while ($null -ne ($line = $reader.ReadLine())) {
        # Checked on every call, so an app you closed meanwhile is started again.
        if ($line -match $needsApp -and -not (Ensure-App)) {
            if ($script:problem -and $line -match '"method"\s*:\s*"tools/call"') {
                # Answer in place of the server, so Claude can tell you what to do.
                $id = $null
                try { $id = ($line | ConvertFrom-Json).id } catch { }
                if ($null -ne $id) {
                    $reply = @{ jsonrpc = '2.0'; id = $id; result = @{ isError = $true; content = @(@{ type = 'text'; text = $script:problem }) } } | ConvertTo-Json -Depth 6 -Compress
                    $rb = $utf8.GetBytes($reply + "`n")
                    $stdout.Write($rb, 0, $rb.Length); $stdout.Flush()
                    continue
                }
            }
            Log 'Forwarding anyway; the tool call will report that the app is unreachable.'
        }
        $bytes = $utf8.GetBytes($line + "`n")
        $toCli.Write($bytes, 0, $bytes.Length)
        $toCli.Flush()
        if ($cli.HasExited) { break }
    }
} catch {
    Log "Proxy stopped: $($_.Exception.Message)"
} finally {
    try { $toCli.Close() } catch { }
    [void]$cli.WaitForExit(5000)
    try { [void]$pumpOut.Wait(2000) } catch { }
}
