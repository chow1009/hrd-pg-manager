# HostelHub remote control bridge
# Safe allowlist bridge: only named HostelHub actions are executable.
$ErrorActionPreference = 'Stop'

$RepoRawBase = 'https://cdn.jsdelivr.net/gh/chow1009/hrd-pg-manager@hostelhub-agent/agent-control'
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

function Get-AdbPath {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe') }
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') }
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe') }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($p in ($candidates | Select-Object -Unique)) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
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
                $adb = Get-AdbPath
                if ($adb) {
                    Write-Host "ADB: $adb" -ForegroundColor Yellow
                    & $adb devices
                } else {
                    Write-Host "ADB not found in PATH or standard Android SDK locations" -ForegroundColor Yellow
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
            'install-maestro' {
                $maestroVersion = '2.10.0'
                $installRoot = 'C:\maestro'
                $zip = Join-Path $env:TEMP 'maestro.zip'
                $url = "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$maestroVersion/maestro.zip"
                Write-Host "Installing Maestro CLI $maestroVersion from the official Windows ZIP..." -ForegroundColor Cyan
                if (Test-Path $zip) { Remove-Item $zip -Force }
                Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
                if (Test-Path $installRoot) { Remove-Item $installRoot -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
                Expand-Archive -Path $zip -DestinationPath $installRoot -Force
                $maestroBat = Get-ChildItem -Path $installRoot -Filter 'maestro.bat' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $maestroBat) {
                    $maestroExe = Get-ChildItem -Path $installRoot -Filter 'maestro.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($maestroExe) {
                        $maestroBin = $maestroExe.Directory.FullName
                    } else {
                        throw "Maestro package did not contain maestro.bat or maestro.exe after extraction."
                    }
                } else {
                    $maestroBin = $maestroBat.Directory.FullName
                }
                $targetBin = Join-Path $installRoot 'bin'
                if ($maestroBin -ne $targetBin) {
                    New-Item -ItemType Directory -Force -Path $targetBin | Out-Null
                    Get-ChildItem -Path $maestroBin -Force | Copy-Item -Destination $targetBin -Recurse -Force
                    $maestroBin = $targetBin
                }
                $userPath = [Environment]::GetEnvironmentVariable('Path','User')
                $parts = @()
                if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $maestroBin } }
                $parts += $maestroBin
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                $env:Path = "$maestroBin;$env:Path"
                Write-Host "Maestro installed at $maestroBin" -ForegroundColor Green
                & (Join-Path $maestroBin 'maestro.bat') --version
            }
            'maestro-full' {
                $maestro = Get-Command maestro -ErrorAction SilentlyContinue
                if (-not $maestro) {
                    throw 'Maestro CLI is not installed or not on PATH. Run install-maestro first.'
                }
                maestro test '.maestro/08_full_regression.yml'
            }
            'android-status' {
                $adb = Get-AdbPath
                if (-not $adb) { throw 'ADB is not installed or not found in standard Android SDK locations.' }
                Write-Host "ADB: $adb" -ForegroundColor Yellow
                & $adb devices
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

function Initialize-ControlRepo {
    $controlRoot = Join-Path $StateDir 'control-repo'
    if (-not (Test-Path (Join-Path $controlRoot '.git'))) {
        if (Test-Path $controlRoot) { Remove-Item $controlRoot -Recurse -Force }
        git clone --depth 1 --branch hostelhub-agent 'https://github.com/chow1009/hrd-pg-manager.git' $controlRoot | Out-Host
    }
    return $controlRoot
}

function Get-GhPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
    )
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($p in ($candidates | Select-Object -Unique)) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-CommandFile {
    $gh = Get-GhPath
    if (-not $gh) { throw 'GitHub CLI was not found. Install GitHub CLI and authenticate it first.' }

    $b64 = & $gh api 'repos/chow1009/hrd-pg-manager/contents/agent-control/command.json?ref=hostelhub-agent' --jq .content
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI could not read the command file.' }

    $clean = ($b64 -join '') -replace '\s',''
    $bytes = [Convert]::FromBase64String($clean)
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
