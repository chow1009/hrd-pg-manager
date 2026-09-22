# HostelHub remote control bridge
# Safe allowlist bridge: only named HostelHub actions are executable.
$ErrorActionPreference = 'Stop'

$RepoApiUrl = 'https://api.github.com/repos/chow1009/hrd-pg-manager/contents/agent-control/command.json?ref=hostelhub-agent'
$StateDir = Join-Path $env:LOCALAPPDATA 'HostelHub-Agent'
$StateFile = Join-Path $StateDir 'last-command-id.txt'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Get-ProjectRoot {
    $appRoot = Join-Path $env:USERPROFILE 'OneDrive\Desktop\app'
    $candidates = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'HRD-HOSTELS-V46.6.2-CHH-FINAL-*' } |
        Sort-Object LastWriteTime -Descending

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c.FullName 'package.json')) { return $c.FullName }
    }
    throw "Could not find FINAL HostelHub folder containing package.json under $appRoot"
}

function Invoke-Action {
    param([string]$Action)

    $root = Get-ProjectRoot
    Push-Location $root
    try {
        Write-Host "HostelHub root: $root" -ForegroundColor Cyan

        switch ($Action) {
            'status' {
                Write-Host "STATUS OK" -ForegroundColor Green
                node --version
                npm --version
                if (Get-Command adb -ErrorAction SilentlyContinue) {
                    Write-Host "ADB:" -ForegroundColor Yellow
                    adb devices
                } else {
                    Write-Host "ADB not found on PATH" -ForegroundColor Yellow
                }
            }
            'install' {
                npm install --no-audit --no-fund
            }
            'expo-start' {
                Start-Process powershell -ArgumentList '-NoExit','-Command',"Set-Location -LiteralPath '$root'; npx expo start --android"
                Write-Host "Expo start launched in a new PowerShell window." -ForegroundColor Green
            }
            'qa-release' {
                if (Test-Path (Join-Path $root 'package.json')) {
                    npm run qa:release
                } else {
                    throw 'package.json missing'
                }
            }
            'maestro-full' {
                if (-not (Get-Command maestro -ErrorAction SilentlyContinue)) {
                    throw 'Maestro CLI is not installed or not on PATH.'
                }
                maestro test '.maestro/08_full_regression.yml'
            }
            'android-status' {
                if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
                    throw 'ADB is not installed or not on PATH.'
                }
                adb devices
            }
            default {
                throw "Blocked action: $Action"
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Get-CommandFile {
    $api = Invoke-RestMethod -Uri $RepoApiUrl -UseBasicParsing -TimeoutSec 15 -Headers @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'HostelHub-Agent-Bridge'
        'Cache-Control' = 'no-cache'
    }
    if (-not $api.content) { throw 'GitHub command file content was empty.' }
    $bytes = [Convert]::FromBase64String(($api.content -replace '\s',''))
    $json = [Text.Encoding]::UTF8.GetString($bytes)
    return ($json | ConvertFrom-Json)
}

Write-Host ''
Write-Host 'HostelHub Agent Bridge is RUNNING' -ForegroundColor Green
Write-Host 'Waiting for remote commands...' -ForegroundColor Cyan
Write-Host 'Close this window only when you want to stop the bridge.' -ForegroundColor DarkGray
Write-Host ''

while ($true) {
    try {
        $cmd = Get-CommandFile
        $id = [int]$cmd.id
        $last = 0
        if (Test-Path $StateFile) {
            $raw = Get-Content $StateFile -Raw -ErrorAction SilentlyContinue
            if ($raw) { [int]::TryParse($raw.Trim(), [ref]$last) | Out-Null }
        }

        if ($id -gt $last) {
            Write-Host ("[{0}] Command #{1}: {2}" -f (Get-Date), $id, $cmd.action) -ForegroundColor Magenta
            try {
                Invoke-Action -Action ([string]$cmd.action)
                Set-Content -Path $StateFile -Value $id -Encoding ascii
                Write-Host ("Command #{0} completed." -f $id) -ForegroundColor Green
            }
            catch {
                Set-Content -Path $StateFile -Value $id -Encoding ascii
                Write-Host ("Command #{0} FAILED: {1}" -f $id, $_.Exception.Message) -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host ("Bridge poll error: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }

    Start-Sleep -Seconds 5
}
