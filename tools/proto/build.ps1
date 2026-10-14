# Wardwood prototype build: the four gates, the map prover in wardwood mode, then
# the six trees into work\push-proto, served on 127.0.0.1:34882 for ProtoPull.
# Kept apart from tools\push (work\push, port 34880) so the shared place's
# BonkPull can never pull prototype code.
# Usage: powershell -ExecutionPolicy Bypass -File tools\proto\build.ps1 [-NoGates]
param([switch]$NoGates)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$env:PYTHONIOENCODING = 'utf-8'

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'proto/wardwood') {
    Write-Output "On branch '$branch', not proto/wardwood - nothing built"
    exit 1
}

if (-not $NoGates) {
    $check = Join-Path $env:USERPROFILE '.claude\skills\roblox-code\scripts\check.py'
    $out = py $check 2>&1 | ForEach-Object { "$_" -replace "\x1b\[[0-9;]*m", "" }
    if (($out | Select-Object -Last 1) -notmatch 'all gates green') {
        $out | Where-Object { $_ -notmatch '^\s+PASS ' } | Select-Object -Last 40
        Write-Output 'GATES FAILED - nothing built'
        exit 1
    }
    $prove = lune run tools/map/prove.luau wardwood 2>&1
    if ($LASTEXITCODE -ne 0) { $prove; Write-Output 'WARDWOOD MAP PROOF FAILED - nothing built'; exit 1 }
    Write-Output 'gates green, wardwood map proof PASS'
}

$out = Join-Path $root 'work\push-proto'
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($name in 'Packages', 'Shared', 'Server', 'Client', 'Ui', 'Assets') {
    $o = rojo build "tools\push\$name.project.json" -o "work\push-proto\$name.rbxmx" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "BUILD FAILED $name"; $o; exit 1 }
}
Write-Output ("built 6 prototype trees at {0} from {1}" -f (Get-Date -Format 'HH:mm:ss'), (git rev-parse --short HEAD).Trim())

try {
    Invoke-WebRequest 'http://127.0.0.1:34882/Shared.rbxmx' -UseBasicParsing -TimeoutSec 2 | Out-Null
} catch {
    Start-Process -FilePath 'py' -ArgumentList '-m', 'http.server', '34882', '--bind', '127.0.0.1', '--directory', $out -WindowStyle Hidden | Out-Null
    Write-Output 'started prototype file server on 127.0.0.1:34882'
}
