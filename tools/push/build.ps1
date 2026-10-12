# Run the four gates, then build the four trees Studio pulls (see README.md here).
# Usage: powershell -File tools\push\build.ps1 [-NoGates]
param([switch]$NoGates)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$env:PYTHONIOENCODING = 'utf-8'

if (-not $NoGates) {
    $check = Join-Path $env:USERPROFILE '.claude\skills\roblox-code\scripts\check.py'
    $out = py $check --fix 2>&1 | ForEach-Object { "$_" -replace "\x1b\[[0-9;]*m", "" }
    $bad = $out | Where-Object { $_ -notmatch '^\s+PASS ' }
    $last = ($out | Select-Object -Last 1)
    if ($last -notmatch 'all gates green') {
        $bad | Select-Object -Last 40
        Write-Output 'GATES FAILED - nothing built'
        exit 1
    }
    Write-Output (($out | Where-Object { $_ -match 'passed, ' }) -join ' ')
}

New-Item -ItemType Directory -Force (Join-Path $root 'work\push') | Out-Null
foreach ($name in 'Packages', 'Shared', 'Server', 'Client') {
    $o = rojo build "tools\push\$name.project.json" -o "work\push\$name.rbxmx" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "BUILD FAILED $name"; $o; exit 1 }
}
$stamp = Get-Date -Format 'HH:mm:ss'
Write-Output "built 4 trees at $stamp - gates green"

# make sure the local file server Studio pulls from is up
try {
    Invoke-WebRequest 'http://127.0.0.1:34880/Shared.rbxmx' -UseBasicParsing -TimeoutSec 2 | Out-Null
} catch {
    Start-Process -FilePath 'py' -ArgumentList '-m', 'http.server', '34880', '--bind', '127.0.0.1', '--directory', (Join-Path $root 'work\push') -WindowStyle Hidden | Out-Null
    Write-Output 'started file server on 127.0.0.1:34880'
}
