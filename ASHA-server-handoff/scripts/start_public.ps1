# Windows version of scripts/start_public.sh: makes this PC's ASHA server reachable from phones on ANY network over HTTPS (Cloudflare Tunnel).
#
#   powershell -ExecutionPolicy Bypass -File scripts\start_public.ps1                    quick tunnel (free, new address every start)
#   $env:TUNNEL_NAME="asha"; $env:TUNNEL_HOSTNAME="asha.example.org"; powershell -ExecutionPolicy Bypass -File scripts\start_public.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\stop_public.ps1
#
# Needs: cloudflared (winget install --id Cloudflare.cloudflared), Python 3.11 venv set up (see README "Windows").
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Be = Join-Path $Root "health-worker-backend"
$Run = Join-Path $Root "run"
$Port = if ($env:PORT) { [int]$env:PORT } else { 8000 }
$Wait = if ($env:PUBLIC_WAIT_SECONDS) { [int]$env:PUBLIC_WAIT_SECONDS } else { 120 }
New-Item -ItemType Directory -Force -Path $Run | Out-Null

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Get-Health($url) {
    try { $r = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 6; return ($r.status -eq "ok") } catch { return $false }
}
function Alive($pidFile) {
    if (-not (Test-Path $pidFile)) { return $false }
    return [bool](Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue)
}

$Py = Join-Path $Be ".venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { Fail "No Python venv at $Py. Set it up first (README, 'Windows')." }
$Cf = if ($env:CLOUDFLARED) { $env:CLOUDFLARED } else { (Get-Command cloudflared -ErrorAction SilentlyContinue).Source }
if (-not $Cf) { Fail "cloudflared is not installed. Run: winget install --id Cloudflare.cloudflared   (then open a new PowerShell window)" }
if (-not (Test-Path (Join-Path $Be ".env"))) { Fail "No health-worker-backend\.env yet. Copy .env.example to .env and set SECRET_KEY, DEVICE_HASH_SALT, AUTH_MODE=api_key." }

Push-Location $Be
try {
    $mode = & $Py -c "from app.core.config import get_settings as g; print(g().auth_mode)"
    if ($mode.Trim() -ne "api_key") { Fail "AUTH_MODE is '$mode' in .env. Set AUTH_MODE=api_key before exposing the server to the internet." }

    # ------------------------------------------------------------ 1. backend on 127.0.0.1 only
    $local = "http://127.0.0.1:$Port"
    if (Get-Health $local) {
        Write-Host "Backend already answering on $local (reusing it)."
    } else {
        Write-Host "Starting the backend on $local ..."
        $p = Start-Process -FilePath $Py -WorkingDirectory $Be -WindowStyle Hidden -PassThru `
            -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$Port", "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1") `
            -RedirectStandardOutput (Join-Path $Run "backend.out.log") -RedirectStandardError (Join-Path $Run "backend.log")
        Set-Content -Path (Join-Path $Run "backend.pid") -Value $p.Id
        $ok = $false
        for ($i = 0; $i -lt 60; $i++) { if (Get-Health $local) { $ok = $true; break }; if ($p.HasExited) { break }; Start-Sleep -Milliseconds 500 }
        if (-not $ok) { Get-Content (Join-Path $Run "backend.log") -Tail 20; Fail "the backend did not start (run\backend.log)" }
    }

    # ------------------------------------------------------------ 2. tunnel
    $tpid = Join-Path $Run "tunnel.pid"
    if (Alive $tpid) { Stop-Process -Id ([int](Get-Content $tpid)) -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }
    Remove-Item (Join-Path $Run "public_url.txt") -ErrorAction SilentlyContinue
    $tlog = Join-Path $Run "tunnel.log"
    if ($env:TUNNEL_NAME) {
        if (-not $env:TUNNEL_HOSTNAME) { Fail "TUNNEL_NAME is set: also set TUNNEL_HOSTNAME (e.g. asha.example.org)" }
        $cfArgs = @("tunnel", "--no-autoupdate", "run", "--url", $local, $env:TUNNEL_NAME)
        $Url = "https://$($env:TUNNEL_HOSTNAME)"
    } else {
        $cfArgs = @("tunnel", "--no-autoupdate", "--url", $local)
        $Url = $null
    }
    Write-Host "Starting cloudflared ..."
    $t = Start-Process -FilePath $Cf -ArgumentList $cfArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $Run "tunnel.out.log") -RedirectStandardError $tlog
    Set-Content -Path $tpid -Value $t.Id
    if (-not $Url) {
        for ($i = 0; $i -lt 60 -and -not $Url; $i++) {
            Start-Sleep 1
            if (Test-Path $tlog) {
                $m = Select-String -Path $tlog -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches |
                    ForEach-Object { $_.Matches.Value } | Where-Object { $_ -notlike "https://api.*" } | Select-Object -First 1
                if ($m) { $Url = $m }
            }
            if ($t.HasExited) { break }
        }
        if (-not $Url) { Get-Content $tlog -Tail 20; Fail "cloudflared did not report an address (run\tunnel.log)." }
    }

    # ------------------------------------------------------------ 3. wait until it answers from the internet
    Write-Host "Waiting for $Url/health through the tunnel (a new quick-tunnel name can take 10-30 s) ..."
    $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = $false
    while ($sw.Elapsed.TotalSeconds -lt $Wait) {
        if (Get-Health $Url) { $ok = $true; break }
        if ($t.HasExited) { Get-Content $tlog -Tail 20; Fail "cloudflared exited (run\tunnel.log)" }
        Start-Sleep 2
    }
    if (-not $ok) { Fail "$Url/health did not answer within $Wait s. The tunnel is still running; check run\tunnel.log." }
    Set-Content -Path (Join-Path $Run "public_url.txt") -Value $Url

    # ------------------------------------------------------------ 4. keep Windows awake while the tunnel runs (no admin rights needed)
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED, renewed every 30 s by a hidden helper that ends when cloudflared ends. Passed as -EncodedCommand
    # (UTF-16LE base64) so no quoting can break the C# signature.
    $helper = @'
Add-Type -Name P -Namespace W -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
while (Get-Process -Id __TPID__ -ErrorAction SilentlyContinue) { [W.P]::SetThreadExecutionState([uint32]2147483649) | Out-Null; Start-Sleep 30 }
'@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($helper.Replace("__TPID__", "$($t.Id)")))
    $awake = Start-Process -FilePath "powershell" -WindowStyle Hidden -PassThru -ArgumentList @("-NoProfile", "-EncodedCommand", $enc)
    Set-Content -Path (Join-Path $Run "awake.pid") -Value $awake.Id

    Write-Host ""
    Write-Host "================================================================"
    Write-Host " Server address for the phone app (Settings > Server address):"
    Write-Host ""
    Write-Host "     $Url" -ForegroundColor Green
    Write-Host ""
    Write-Host " Then paste the phone's API key (website > Phones & users > Generate key)."
    Write-Host " Website: $Url   (also $local on this PC)"
    if (-not $env:TUNNEL_NAME) { Write-Host " NOTE: a quick tunnel gets a NEW address every start: update the phones (or use a named tunnel / Render)." }
    Write-Host " Windows is kept awake while the tunnel runs (lid closed still sleeps: see docs/PUBLIC_ACCESS.md)."
    Write-Host " Stop: powershell -ExecutionPolicy Bypass -File scripts\stop_public.ps1"
    Write-Host "================================================================"
    & $Py -c "import sys, segno; segno.make(sys.argv[1], error='m').terminal(compact=True)" $Url 2>$null
} finally {
    Pop-Location
}
