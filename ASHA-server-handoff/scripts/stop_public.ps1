# Windows version of scripts/stop_public.sh: stops the tunnel, the keep-awake helper and the backend started by start_public.ps1.
$Run = Join-Path (Split-Path -Parent $PSScriptRoot) "run"
foreach ($name in @("tunnel", "awake", "backend")) {
    $f = Join-Path $Run "$name.pid"
    if (Test-Path $f) {
        $id = [int](Get-Content $f)
        if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            Write-Host "stopped $name (pid $id)"
        }
        Remove-Item $f -ErrorAction SilentlyContinue
    }
}
Remove-Item (Join-Path $Run "public_url.txt") -ErrorAction SilentlyContinue
Write-Host "Public access is off. Phones keep working offline and will sync when the server is back."
