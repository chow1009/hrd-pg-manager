# HostelHub remote control bridge
# Safe allowlist bridge: only named HostelHub actions are executable.
$ErrorActionPreference = 'Stop'

$RepoRawBase = 'https://cdn.jsdelivr.net/gh/chow1009/hrd-pg-manager@hostelhub-agent/agent-control'
$StateDir = Join-Path $env:LOCALAPPDATA 'HostelHub-Agent'
$StateFile = Join-Path $StateDir 'last-command-id.txt'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Get-ProjectRoot {
    $appRoot = Join-Path $env:USERPROFILE 'OneDrive\Desktop\app'
    $preferredNames = @(
        'HRD-HOSTELS-V46.6.2-CHH-FORGOT-PASSWORD-SHOW',
        'HRD-HOSTELS-V46.6.2-CHH-FINAL-2026-09-22 (1)',
        'HRD-HOSTELS-V46.6.2-CHH-FORGOT-PASSWORD',
        'HRD-HOSTELS-V46.6.2-TENANT-DETAIL-FIX'
    )
    foreach ($name in $preferredNames) {
        $p = Join-Path $appRoot $name
        if (Test-Path (Join-Path $p 'package.json')) { return $p }
    }

    foreach ($shortRoot in @('C:\HH-HOSTELS','C:\HH-HOSTELS-QA')) {
        if (Test-Path (Join-Path $shortRoot 'package.json')) { return $shortRoot }
    }

    $candidates = Get-ChildItem -Path $appRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'HRD-HOSTELS-V46.6.2*' } |
        Sort-Object LastWriteTime -Descending
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c.FullName 'package.json')) { return $c.FullName }
    }
    throw "Could not find a HostelHub folder containing package.json under $appRoot"
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
                $pkgJson = Join-Path $root 'package.json'
                if (Test-Path $pkgJson) {
                    Write-Host '--- PACKAGE.JSON EXPO CONFIG ---' -ForegroundColor Yellow
                    $p = Get-Content $pkgJson -Raw -ErrorAction SilentlyContinue
                    if ($p) {
                        $j = $p | ConvertFrom-Json
                        if ($j.expo) {
                            Write-Host (($j.expo | ConvertTo-Json -Depth 10))
                        } else {
                            Write-Host 'No root-level expo key in package.json'
                        }
                    }
                }
                foreach ($cfg in @('app.json','app.config.js','app.config.ts')) {
                    $cfgPath = Join-Path $root $cfg
                    if (Test-Path $cfgPath) {
                        Write-Host ("--- {0} ---" -f $cfg) -ForegroundColor Yellow
                        Get-Content $cfgPath -Raw
                    }
                }
                Write-Host '--- EXPO CONFIG FILES ---' -ForegroundColor Yellow
                foreach ($cfg in @('package.json','app.json','app.config.js','app.config.ts')) {
                    $cfgPath = Join-Path $root $cfg
                    if (Test-Path $cfgPath) {
                        Write-Host ("### {0}" -f $cfg) -ForegroundColor Cyan
                        try {
                            if ($cfg -eq 'package.json') {
                                $pj = Get-Content $cfgPath -Raw | ConvertFrom-Json
                                if ($null -ne $pj.expo) {
                                    $pj.expo | ConvertTo-Json -Depth 20 | Write-Host
                                } else {
                                    Write-Host 'No root-level expo object in package.json'
                                }
                            } else {
                                Get-Content $cfgPath -Raw | Write-Host
                            }
                        } catch {
                            Write-Host ("Could not parse {0}: {1}" -f $cfg, $_.Exception.Message) -ForegroundColor Yellow
                        }
                    }
                }
                $adb = Get-AdbPath
                if ($adb) {
                    Write-Host "ADB: $adb" -ForegroundColor Yellow
                    & $adb devices
                    $pkg = (& $adb shell pm list packages 2>$null | Select-String 'com.hrdhostels.app')
                    if ($pkg) {
                        Write-Host "HostelHub package is installed." -ForegroundColor Green
                        & $adb shell am force-stop com.hrdhostels.app
                        & $adb shell monkey -p com.hrdhostels.app 1
                        Start-Sleep -Seconds 5
                        Write-Host "HostelHub launch requested on emulator-5554." -ForegroundColor Green
                    } else {
                        Write-Host "HostelHub package com.hrdhostels.app is NOT installed." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "ADB not found in PATH or standard Android SDK locations" -ForegroundColor Yellow
                }
                $log = Join-Path $root 'android-build.log'
                if (Test-Path $log) {
                    Write-Host '--- ANDROID BUILD LOG TAIL ---' -ForegroundColor Yellow
                    $lines = Get-Content $log -ErrorAction SilentlyContinue
                    if ($lines.Count -gt 0) {
                        $start = [Math]::Max(0, $lines.Count - 220)
                        Write-Host (($lines[$start..($lines.Count-1)]) -join [Environment]::NewLine)
                    }
                    Write-Host '--- END ANDROID BUILD LOG TAIL ---' -ForegroundColor Yellow
                }
            }
            'install' {
                npm install --no-audit --no-fund
            }
            'expo-start' {
                Start-Process powershell -ArgumentList '-NoExit','-Command',"Set-Location -LiteralPath '$root'; npx expo start --android"
                Write-Host "Expo start launched in a new PowerShell window." -ForegroundColor Green
            }
            'launch-installed' {
                $adb = Get-AdbPath
                if (-not $adb) { throw 'ADB executable was not found.' }
                $devices = & $adb devices | Select-String '\tdevice$'
                if (-not $devices) { throw 'No Android device is connected to ADB.' }
                $installed = & $adb shell pm list packages | Select-String 'com.hrdhostels.app'
                if (-not $installed) { throw 'com.hrdhostels.app is not installed on the connected emulator.' }
                Write-Host 'HostelHub is installed. Launching it directly...' -ForegroundColor Cyan
                & $adb shell am force-stop com.hrdhostels.app
                & $adb shell monkey -p com.hrdhostels.app 1
                Start-Sleep -Seconds 5
                Write-Host 'HostelHub launch command completed.' -ForegroundColor Green
            }
            'android-start-emulator' {
                $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
                $emu = Join-Path $sdk 'emulator\emulator.exe'
                if (-not (Test-Path $emu)) { throw "Android emulator executable not found at $emu" }

                $avds = & $emu -list-avds 2>&1 | Where-Object { $_ -and $_ -notmatch '^INFO|^WARNING' }
                if (-not $avds) { throw 'No Android Virtual Devices are configured. Open Android Studio > Device Manager and create an emulator.' }

                $adb = Get-AdbPath
                if (-not $adb) { throw 'ADB executable was not found.' }

                Write-Host 'Current ADB devices:' -ForegroundColor Yellow
                & $adb devices

                $chosen = $avds | Select-Object -First 1
                Write-Host "Starting AVD: $chosen" -ForegroundColor Cyan
                Start-Process -FilePath $emu -ArgumentList @('-avd',$chosen,'-netdelay','none','-netspeed','full')

                & $adb wait-for-device
                $deadline = (Get-Date).AddMinutes(2)
                $boot = '0'
                do {
                    Start-Sleep -Seconds 5
                    $boot = (& $adb shell getprop sys.boot_completed 2>$null | Select-Object -First 1).Trim()
                    if ($boot -eq '1') { break }
                } while ((Get-Date) -lt $deadline)

                if ($boot -ne '1') { throw "Android emulator '$chosen' did not finish booting within 2 minutes." }
                Write-Host "Android emulator '$chosen' is READY." -ForegroundColor Green
                & $adb devices
            }
            'android-build-install' {
                $adb = Get-AdbPath
                if (-not $adb) { throw 'ADB executable was not found.' }
                $devices = & $adb devices | Select-String '\tdevice$'
                if (-not $devices) { throw 'No Android emulator/device is connected to ADB.' }

                $apk = Get-ChildItem -Path (Join-Path $root 'android') -Filter 'app-debug.apk' -File -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1

                if (-not $apk) {
                    Write-Host 'No debug APK found. Building Android app...' -ForegroundColor Cyan
                    npx expo run:android
                    if ($LASTEXITCODE -ne 0) { throw "npx expo run:android failed with exit code $LASTEXITCODE" }
                    $apk = Get-ChildItem -Path (Join-Path $root 'android') -Filter 'app-debug.apk' -File -Recurse -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                }

                if (-not $apk) { throw 'Android build completed but app-debug.apk could not be found.' }
                Write-Host "Installing APK: $($apk.FullName)" -ForegroundColor Cyan
                & $adb install -r $apk.FullName
                if ($LASTEXITCODE -ne 0) { throw "adb install failed with exit code $LASTEXITCODE" }
                & $adb shell am force-stop com.hrdhostels.app
                & $adb shell monkey -p com.hrdhostels.app 1
                Start-Sleep -Seconds 5
                Write-Host 'HostelHub APK installed and launch requested.' -ForegroundColor Green
            }
            'show-build-log' {
                $log = Join-Path $root 'android-build.log'
                if (-not (Test-Path $log)) { throw 'android-build.log does not exist in the project root.' }
                Write-Host '--- ANDROID BUILD LOG: LAST 220 LINES ---' -ForegroundColor Yellow
                $lines = Get-Content $log -ErrorAction Stop
                if ($lines.Count -gt 0) {
                    $start = [Math]::Max(0, $lines.Count - 220)
                    Write-Host (($lines[$start..($lines.Count-1)]) -join [Environment]::NewLine)
                }
                Write-Host '--- END ANDROID BUILD LOG ---' -ForegroundColor Yellow
            }
            'android-fix-sdk' {
                $sdkCandidates = @()
                if ($env:ANDROID_SDK_ROOT) { $sdkCandidates += $env:ANDROID_SDK_ROOT }
                if ($env:ANDROID_HOME) { $sdkCandidates += $env:ANDROID_HOME }
                $sdkCandidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
                $sdk = $null
                foreach ($p in ($sdkCandidates | Select-Object -Unique)) {
                    if ($p -and (Test-Path (Join-Path $p 'platform-tools\adb.exe'))) { $sdk = (Resolve-Path $p).Path; break }
                }
                if (-not $sdk) { throw 'Android SDK not found in ANDROID_SDK_ROOT, ANDROID_HOME, or %LOCALAPPDATA%\Android\Sdk.' }

                $env:ANDROID_HOME = $sdk
                $env:ANDROID_SDK_ROOT = $sdk
                [Environment]::SetEnvironmentVariable('ANDROID_HOME',$sdk,'User')
                [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT',$sdk,'User')
                $localProps = Join-Path (Join-Path $root 'android') 'local.properties'
                Set-Content -Path $localProps -Value ("sdk.dir=" + ($sdk -replace '\\','/')) -Encoding ascii
                Write-Host "Android SDK configured: $sdk" -ForegroundColor Green

                $ndkVersion = '27.1.12297006'
                $ndk = Join-Path $sdk ("ndk\{0}" -f $ndkVersion)
                $sourceProps = Join-Path $ndk 'source.properties'

                if (-not (Test-Path $sourceProps)) {
                    Write-Host "NDK $ndkVersion is incomplete. Using resumable official Google NDK download..." -ForegroundColor Yellow

                    if (Test-Path $ndk) { Remove-Item $ndk -Recurse -Force -ErrorAction SilentlyContinue }

                    $zip = Join-Path $env:TEMP 'android-ndk-r27b-windows.zip'
                    $url = 'https://dl.google.com/android/repository/android-ndk-r27b-windows.zip'

                    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
                        throw 'curl.exe is required for the resumable NDK download and was not found.'
                    }

                    $curlArgs = @(
                        '-L','--fail','--http1.1',
                        '--retry','20','--retry-delay','5','--retry-all-errors',
                        '--continue-at','-',
                        '--output',$zip,
                        $url
                    )
                    & curl.exe @curlArgs
                    if ($LASTEXITCODE -ne 0) {
                        throw "NDK download failed with exit code $LASTEXITCODE. The partial archive is retained at $zip for resume."
                    }

                    Write-Host "NDK archive downloaded. Validating archive..." -ForegroundColor Cyan
                    $seven = Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
                    if (-not $seven) {
                        $sevenCandidates = @(
                            "$env:ProgramFiles\7-Zip\7z.exe",
                            "$env:ProgramFiles\7-Zip\7z.exe",
                            "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
                        )
                        $seven = $sevenCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
                    }
                    if (-not $seven) {
                        Write-Host "7-Zip not found. Installing it..." -ForegroundColor Yellow
                        winget install --id 7zip.7zip --exact --silent --accept-package-agreements --accept-source-agreements
                        $seven = Get-ChildItem "$env:ProgramFiles" -Filter '7z.exe' -File -Recurse -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty FullName -First 1
                    }
                    if (-not $seven) { throw "7-Zip could not be located after installation." }

                    & $seven t $zip *> (Join-Path $env:TEMP 'hostelhub-ndk-7z-test.log')
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "Downloaded NDK archive failed integrity test. Deleting and performing a fresh download..." -ForegroundColor Yellow
                        Remove-Item $zip -Force -ErrorAction SilentlyContinue
                        & curl.exe @curlArgs
                        if ($LASTEXITCODE -ne 0) { throw "Fresh NDK download failed with exit code $LASTEXITCODE" }
                        & $seven t $zip *> (Join-Path $env:TEMP 'hostelhub-ndk-7z-test.log')
                        if ($LASTEXITCODE -ne 0) { throw "Fresh NDK archive failed integrity test." }
                    }

                    Write-Host "NDK archive integrity verified. Extracting..." -ForegroundColor Cyan
                    $extractRoot = Join-Path $env:TEMP 'hostelhub-ndk-extract'
                    if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue }
                    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

                    & $seven x $zip "-o$extractRoot" -y
                    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to extract the NDK archive." }

                    $prop = Get-ChildItem $extractRoot -Filter 'source.properties' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $prop) { throw "Extracted NDK archive did not contain source.properties." }

                    $sourceDir = $prop.Directory.FullName
                    New-Item -ItemType Directory -Force -Path (Split-Path $ndk -Parent) | Out-Null
                    if (Test-Path $ndk) { Remove-Item $ndk -Recurse -Force -ErrorAction SilentlyContinue }
                    Move-Item -Path $sourceDir -Destination $ndk -Force
                    Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
                if (-not (Test-Path $sourceProps)) {
                    throw "NDK $ndkVersion is still incomplete at $ndk"
                }

                Write-Host "NDK $ndkVersion is READY." -ForegroundColor Green
                & (Join-Path $sdk 'platform-tools\adb.exe') devices
            }
            'android-dev-build' {
                Write-Host "Building and launching the real Android HostelHub app..." -ForegroundColor Cyan
                $buildLog = Join-Path $root 'android-build.log'
                if (Test-Path $buildLog) { Remove-Item $buildLog -Force }
                npx expo run:android *> $buildLog
                $exit = $LASTEXITCODE
                Write-Host "Android build exit code: $exit" -ForegroundColor Yellow
                if (Test-Path $buildLog) {
                    Write-Host '--- Android build tail ---' -ForegroundColor Yellow
                    $lines = Get-Content $buildLog -ErrorAction SilentlyContinue
                    if ($lines.Count -gt 0) {
                        $start = [Math]::Max(0,$lines.Count-220)
                        Write-Host (($lines[$start..($lines.Count-1)]) -join [Environment]::NewLine)
                    }
                    Write-Host '--- End Android build tail ---' -ForegroundColor Yellow
                }
                if ($exit -ne 0) { throw "Android build failed with exit code $exit. See android-build.log in the project root." }
            }
            'android-ui-smoke' {
                $adb = Get-AdbPath
                if (-not $adb) { throw 'ADB is not installed or not found in standard Android SDK locations.' }
                & $adb devices
                & $adb shell am force-stop com.hrdhostels.app
                & $adb shell monkey -p com.hrdhostels.app 1
                Start-Sleep -Seconds 8
                $dump = & $adb shell uiautomator dump /sdcard/hostelhub-window.xml 2>&1
                Write-Host ($dump -join [Environment]::NewLine)
                $xml = & $adb shell cat /sdcard/hostelhub-window.xml 2>&1
                Write-Host '--- UI DUMP ---' -ForegroundColor Yellow
                Write-Host ($xml -join [Environment]::NewLine)
                if (($xml -join '') -match 'AI Hostel Manager') {
                    Write-Host 'ANDROID UI SMOKE: LOGIN SCREEN DETECTED' -ForegroundColor Green
                } elseif (($xml -join '') -match 'Owner command center') {
                    Write-Host 'ANDROID UI SMOKE: DASHBOARD DETECTED' -ForegroundColor Green
                } else {
                    throw 'ANDROID UI SMOKE: expected HostelHub login/dashboard text was not detected.'
                }
            }
            'qa-release' {
                if (Test-Path (Join-Path $root 'package.json')) {
                    npm run qa:release
                } else {
                    throw 'package.json missing'
                }
            }
            'install-java' {
                Write-Host "Installing Java 17 (Temurin)..." -ForegroundColor Cyan
                winget install --id EclipseAdoptium.Temurin.17.JDK --exact --silent --accept-package-agreements --accept-source-agreements
                $javaRoots = @(
                    'C:\Program Files\Eclipse Adoptium',
                    'C:\Program Files\Eclipse Adoptium\'
                )
                $jdk = $null
                foreach ($jr in ($javaRoots | Select-Object -Unique)) {
                    if (Test-Path $jr) {
                        $jdk = Get-ChildItem -Path $jr -Directory -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending |
                            Select-Object -First 1
                        if ($jdk) { break }
                    }
                }
                if (-not $jdk) { throw 'Temurin JDK 17 installed but its installation directory could not be located.' }
                [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk.FullName, 'User')
                $userPath = [Environment]::GetEnvironmentVariable('Path','User')
                $javaBin = Join-Path $jdk.FullName 'bin'
                $parts = @()
                if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $javaBin } }
                $parts += $javaBin
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                $env:JAVA_HOME = $jdk.FullName
                $env:Path = "$javaBin;$env:Path"
                Write-Host "JAVA_HOME=$env:JAVA_HOME" -ForegroundColor Green
                java -version
            }
            'install-maestro' {
                $maestroVersion = '2.10.0'
                $installRoot = 'C:\maestro'
                $zip = Join-Path $env:TEMP 'maestro.zip'
                $url = "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$maestroVersion/maestro.zip"
                $expectedSha = '29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991'

                Write-Host "Downloading Maestro CLI $maestroVersion with resumable curl..." -ForegroundColor Cyan
                if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is required and was not found.' }

                $curlArgs = @(
                    '-L','--fail','--http1.1',
                    '--retry','10','--retry-delay','3','--retry-all-errors',
                    '--continue-at','-',
                    '--output',$zip,
                    $url
                )
                & curl.exe @curlArgs
                if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE. A partially downloaded file may remain at $zip." }

                $actualSha = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualSha -ne $expectedSha) {
                    throw "Maestro ZIP checksum mismatch. Expected $expectedSha but received $actualSha."
                }

                Write-Host "Maestro ZIP checksum verified." -ForegroundColor Green
                if (Test-Path $installRoot) { Remove-Item $installRoot -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
                Expand-Archive -Path $zip -DestinationPath $installRoot -Force

                $maestroBat = Get-ChildItem -Path $installRoot -Filter 'maestro.bat' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $maestroBat) { throw "Maestro ZIP extracted but maestro.bat was not found under $installRoot" }

                $maestroBin = $maestroBat.Directory.FullName
                Write-Host "Maestro binary directory: $maestroBin" -ForegroundColor Green

                $userPath = [Environment]::GetEnvironmentVariable('Path','User')
                $parts = @()
                if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $maestroBin } }
                $parts += $maestroBin
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                $env:Path = "$maestroBin;$env:Path"

                & $maestroBat --version
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
            'full-regression' {
                Write-Host '=== HOSTELHUB FULL REGRESSION START ===' -ForegroundColor Cyan
                if (-not (Test-Path (Join-Path $root 'package.json'))) { throw 'package.json missing.' }

                Write-Host '--- 1. Source/config checks ---' -ForegroundColor Yellow
                $pkgText = Get-Content (Join-Path $root 'package.json') -Raw
                $appFiles = Get-ChildItem $root -Recurse -File -Include *.js,*.jsx,*.ts,*.tsx -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '\\node_modules\\|\\android\\build\\|\\android\\app\\build\\' }
                $allText = ($appFiles | ForEach-Object { Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue }) -join [Environment]::NewLine
                if ($allText -notmatch 'Forgot password|Forgot Password') { throw 'Forgot-password UI/source check failed.' }
                if ($allText -notmatch 'Show|Hide') { throw 'Show/Hide password UI/source check failed.' }
                Write-Host 'Forgot-password and Show/Hide password checks passed.' -ForegroundColor Green

                Write-Host '--- 2. QA ignore hygiene ---' -ForegroundColor Yellow
                $gitignore = Join-Path $root '.gitignore'
                if (-not (Test-Path $gitignore)) { New-Item -ItemType File -Path $gitignore -Force | Out-Null }
                $gi = Get-Content $gitignore -Raw -ErrorAction SilentlyContinue
                $giLines = @()
                if ($gi) { $giLines = $gi -split [Environment]::NewLine }
                if (-not ($giLines -contains '.expo/')) {
                    Add-Content -Path $gitignore -Value '.expo/'
                    Write-Host 'Added .expo/ to root .gitignore.' -ForegroundColor Green
                }

                Write-Host '--- 3. Short-path QA workspace ---' -ForegroundColor Yellow
                $qaRoot = 'C:\HH-HOSTELS-QA'
                if (Test-Path $qaRoot) { Remove-Item $qaRoot -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Force -Path $qaRoot | Out-Null
                robocopy $root $qaRoot /E /XJ /XD node_modules android\build android\app\build android\.gradle android\app\.cxx .git | Out-Host
                if ($LASTEXITCODE -gt 7) { throw "robocopy failed with exit code $LASTEXITCODE" }

                Push-Location $qaRoot
                try {
                    Write-Host "QA workspace: $qaRoot" -ForegroundColor Cyan
                    $qaGitignore = Join-Path $qaRoot '.gitignore'
                    if (-not (Test-Path $qaGitignore)) { New-Item -ItemType File -Path $qaGitignore -Force | Out-Null }
                    $qaGi = Get-Content $qaGitignore -Raw -ErrorAction SilentlyContinue
                    $qaGiLines = @()
                    if ($qaGi) { $qaGiLines = $qaGi -split [Environment]::NewLine }
                    if (-not ($qaGiLines -contains '.expo/')) {
                        Add-Content -Path $qaGitignore -Value '.expo/'
                        Write-Host 'Added .expo/ to QA workspace .gitignore.' -ForegroundColor Green
                    }

                    Write-Host '--- 4. Dependencies ---' -ForegroundColor Yellow
                    npm install --no-audit --no-fund
                    if ($LASTEXITCODE -ne 0) { throw "npm install failed with exit code $LASTEXITCODE" }

                    Write-Host '--- 5. Expo doctor ---' -ForegroundColor Yellow
                    npx expo-doctor
                    if ($LASTEXITCODE -ne 0) { throw "Expo Doctor failed with exit code $LASTEXITCODE" }

                    Write-Host '--- 6. Release QA ---' -ForegroundColor Yellow
                    if ((Get-Content (Join-Path $qaRoot 'package.json') -Raw) -match '"qa:release"') {
                        npm run qa:release
                        if ($LASTEXITCODE -ne 0) { throw "qa:release failed with exit code $LASTEXITCODE" }
                    }

                    Write-Host '--- 7. Expo config ---' -ForegroundColor Yellow
                    npx expo config --type public
                    if ($LASTEXITCODE -ne 0) { throw "Expo config failed with exit code $LASTEXITCODE" }

                    Write-Host '--- 8. Android device/emulator ---' -ForegroundColor Yellow
                    $adb = Get-AdbPath
                    if (-not $adb) { throw 'ADB executable was not found.' }
                    $ready = & $adb devices | Select-String '\tdevice$'
                    if (-not $ready) {
                        $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
                        $emu = Join-Path $sdk 'emulator\emulator.exe'
                        $avd = (& $emu -list-avds | Where-Object { $_ -and $_ -notmatch '^INFO|^WARNING' } | Select-Object -First 1)
                        if (-not $avd) { throw 'No Android AVD available.' }
                        Start-Process -FilePath $emu -ArgumentList @('-avd',$avd,'-netdelay','none','-netspeed','full')
                        & $adb wait-for-device
                        $deadline = (Get-Date).AddMinutes(2)
                        $boot = '0'
                        do {
                            Start-Sleep -Seconds 5
                            $boot = (& $adb shell getprop sys.boot_completed 2>$null | Select-Object -First 1).Trim()
                            if ($boot -eq '1') { break }
                        } while ((Get-Date) -lt $deadline)
                        if ($boot -ne '1') { throw "Emulator $avd did not finish booting." }
                    }
                    & $adb devices

                    Write-Host '--- 9. Native build + install ---' -ForegroundColor Yellow
                    $buildLog = Join-Path $qaRoot 'android-build-regression.log'
                    if (Test-Path $buildLog) { Remove-Item $buildLog -Force }
                    npx expo run:android *> $buildLog
                    $exit = $LASTEXITCODE
                    if (Test-Path $buildLog) { Get-Content $buildLog -Tail 160 | Write-Host }
                    if ($exit -ne 0) { throw "Native Android build failed with exit code $exit." }

                    $installed = & $adb shell pm list packages | Select-String 'com.hrdhostels.app'
                    if (-not $installed) { throw 'com.hrdhostels.app not installed after native build.' }

                    Write-Host '--- 10. Native login smoke ---' -ForegroundColor Yellow
                    & $adb shell am force-stop com.hrdhostels.app
                    & $adb shell monkey -p com.hrdhostels.app 1
                    Start-Sleep -Seconds 8
                    & $adb shell uiautomator dump /sdcard/hostelhub-window.xml 2>&1 | Out-Host
                    $xml = & $adb shell cat /sdcard/hostelhub-window.xml 2>&1
                    $joined = $xml -join ''
                    if (($joined -notmatch 'AI Hostel Manager') -and ($joined -notmatch 'HRD HOSTELS')) {
                        throw 'Native login screen not detected.'
                    }

                    Write-Host '--- 11. Full Maestro regression ---' -ForegroundColor Yellow
                    $maestro = Get-Command maestro -ErrorAction SilentlyContinue
                    $flow = Join-Path $qaRoot '.maestro\08_full_regression.yml'
                    if ($maestro -and (Test-Path $flow)) {
                        maestro test $flow
                        if ($LASTEXITCODE -ne 0) { throw "Maestro full regression failed with exit code $LASTEXITCODE" }
                    } else {
                        Write-Host 'Maestro CLI/flow not available; native smoke passed, full interactive Maestro coverage was not executed.' -ForegroundColor Yellow
                    }

                    Write-Host '=== HOSTELHUB FULL REGRESSION COMPLETE ===' -ForegroundColor Green
                }
                finally {
                    Pop-Location
                }
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

function Publish-RemoteResult {
    param([int]$Id,[string]$Action,[string]$Status,[string]$Message = '')
    $gh = Get-GhPath
    if (-not $gh) { return }
    $payload = @{ id=$Id; action=$Action; status=$Status; message=$Message; timestamp=(Get-Date).ToString('o'); machine=$env:COMPUTERNAME; project=(Get-ProjectRoot) } | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $api = 'repos/chow1009/hrd-pg-manager/contents/agent-control/status.json'
    try {
        $existing = & $gh api ($api + '?ref=hostelhub-agent') 2>$null | ConvertFrom-Json
        if ($existing.sha) { & $gh api $api --method PUT -f message=("agent status #{0} {1}" -f $Id,$Status) -f content=$encoded -f branch='hostelhub-agent' -f sha=$existing.sha | Out-Null }
        else { & $gh api $api --method PUT -f message=("create agent status #{0}" -f $Id) -f content=$encoded -f branch='hostelhub-agent' | Out-Null }
    } catch { Write-Host ("Remote status publish failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
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
            Publish-RemoteResult -Id $id -Action ([string]$cmd.action) -Status 'RUNNING' -Message 'Command accepted by HostelHub Agent.'
            try {
                Invoke-Action -Action ([string]$cmd.action)
                Set-Content -Path $StateFile -Value $id -Encoding ascii
                $resultFile = Join-Path $StateDir 'last-result.json'
                @{ id=$id; action=[string]$cmd.action; status='PASS'; timestamp=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -Path $resultFile -Encoding utf8
                Publish-RemoteResult -Id $id -Action ([string]$cmd.action) -Status 'PASS' -Message 'Command completed successfully.'
                Write-Host ("Command #{0} completed." -f $id) -ForegroundColor Green
            } catch {
                $err = $_.Exception.Message
                Set-Content -Path $StateFile -Value $id -Encoding ascii
                $resultFile = Join-Path $StateDir 'last-result.json'
                @{ id=$id; action=[string]$cmd.action; status='FAIL'; message=$err; timestamp=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -Path $resultFile -Encoding utf8
                Publish-RemoteResult -Id $id -Action ([string]$cmd.action) -Status 'FAIL' -Message $err
                Write-Host ("Command #{0} FAILED: {1}" -f $id, $err) -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host ("Bridge poll error: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }

    Start-Sleep -Seconds 5
}
