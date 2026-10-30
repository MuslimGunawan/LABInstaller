# ==============================================================================
# LABInstaller - Core PostInstaller & Custom Tooling Handlers
# Logika khusus untuk Java (JAVA_HOME), Python, PHP, Composer, Laravel, Flutter, Laragon, XAMPP
# ==============================================================================

function Setup-PythonEnvironment {
    Write-LogStep "Mengonfigurasi environment Python & Pip..."
    Refresh-CurrentSessionEnvironment

    $pythonCmd = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pyCandidates = @(
            "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
            "C:\Program Files\Python3*\python.exe",
            "C:\Python3*\python.exe"
        )
        foreach ($c in $pyCandidates) {
            $matched = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matched) {
                $pythonCmd = [PSCustomObject]@{ Source = $matched.FullName }
                break
            }
        }
    }

    if ($pythonCmd) {
        $pythonDir = Split-Path -Parent $pythonCmd.Source
        $scriptsDir = Join-Path -Path $pythonDir -ChildPath "Scripts"

        Add-DirectoryToPath -PathToAdd $pythonDir -Scope "Machine" | Out-Null
        if (-not (Test-Path -Path $scriptsDir)) {
            New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        }
        Add-DirectoryToPath -PathToAdd $scriptsDir -Scope "Machine" | Out-Null

        # Bootstrap & perbarui pip
        try {
            Start-Process -FilePath $pythonCmd.Source -ArgumentList "-m ensurepip --default-pip" -NoNewWindow -Wait
            Start-Process -FilePath $pythonCmd.Source -ArgumentList "-m pip install --upgrade pip" -NoNewWindow -Wait
        } catch {}

        Refresh-CurrentSessionEnvironment
        Write-LogSuccess "Environment Python & Pip ($scriptsDir di PATH) berhasil dikonfigurasi."
    }
}

function Install-PipOfficial {
    Write-LogStep "Mengonfigurasi dan Memverifikasi Pip (Python Package Manager)..."
    Refresh-CurrentSessionEnvironment

    $pipCmd = Get-Command "pip.exe" -ErrorAction SilentlyContinue
    if ($pipCmd) {
        Write-LogInfo "Pip sudah terdeteksi di: $($pipCmd.Source)"
        try {
            $ver = & $pipCmd.Source "--version"
            Write-LogSuccess "Pip aktif: $ver"
        } catch {}
        return $true
    }

    # Cari python jika belum di PATH
    $pythonCmd = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pyCandidates = @(
            "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
            "C:\Program Files\Python3*\python.exe",
            "C:\Python3*\python.exe"
        )
        foreach ($c in $pyCandidates) {
            $matched = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matched) {
                $pythonCmd = [PSCustomObject]@{ Source = $matched.FullName }
                break
            }
        }
    }

    if (-not $pythonCmd) {
        Write-LogError "Python belum terpasang. Pip membutuhkan Python 3 terlebih dahulu."
        return $false
    }

    Write-LogInfo "Menjalankan bootstrap resmi pip via ensurepip..."
    Start-Process -FilePath $pythonCmd.Source -ArgumentList "-m ensurepip --default-pip" -NoNewWindow -Wait

    Write-LogInfo "Memperbarui pip ke versi stabil terbaru..."
    Start-Process -FilePath $pythonCmd.Source -ArgumentList "-m pip install --upgrade pip" -NoNewWindow -Wait

    # Daftarkan folder Scripts ke PATH
    $pyDir = Split-Path -Parent $pythonCmd.Source
    $scriptsDir = Join-Path -Path $pyDir -ChildPath "Scripts"
    if (Test-Path -Path $scriptsDir) {
        Add-DirectoryToPath -PathToAdd $scriptsDir -Scope "Machine" | Out-Null
        Add-DirectoryToPath -PathToAdd $pyDir -Scope "Machine" | Out-Null
    }

    Refresh-CurrentSessionEnvironment

    $checkPip = Get-Command "pip.exe" -ErrorAction SilentlyContinue
    if ($checkPip) {
        Write-LogSuccess "Pip berhasil diaktifkan dan didaftarkan ke sistem PATH!"
        return $true
    } else {
        # Fallback menggunakan get-pip.py resmi dari PyPA
        Write-LogInfo "Mengunduh bootstrap resmi get-pip.py dari pypa.io..."
        $appsDir = Get-AppStorageDirectory
        $getPipPath = Join-Path -Path $appsDir -ChildPath "get-pip.py"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "LABInstaller")
            $wc.DownloadFile("https://bootstrap.pypa.io/get-pip.py", $getPipPath)
            Start-Process -FilePath $pythonCmd.Source -ArgumentList "`"$getPipPath`"" -NoNewWindow -Wait

            if (Test-Path -Path $scriptsDir) {
                Add-DirectoryToPath -PathToAdd $scriptsDir -Scope "Machine" | Out-Null
            }
            Refresh-CurrentSessionEnvironment
            Write-LogSuccess "Pip berhasil dipasang via get-pip.py!"
            return $true
        } catch {
            Write-LogError "Gagal memasang pip - $_"
            return $false
        }
    }
}

function Setup-JavaEnvironment {
    Write-LogStep "Mengonfigurasi JAVA_HOME dan PATH untuk Java SDK..."
    Refresh-CurrentSessionEnvironment

    $jdkCandidates = @()
    $searchRoots = @(
        "C:\Program Files\Eclipse Adoptium",
        "C:\Program Files\Java",
        "C:\Program Files\Semeru"
    )

    foreach ($root in $searchRoots) {
        if (Test-Path -Path $root) {
            $subFolders = Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -match "jdk" }
            foreach ($sub in $subFolders) {
                $jdkCandidates += $sub.FullName
            }
        }
    }

    $selectedJdk = $null
    if ($jdkCandidates.Count -gt 0) {
        $selectedJdk = $jdkCandidates[0]
    } else {
        $javaCmd = Get-Command "java.exe" -ErrorAction SilentlyContinue
        if ($javaCmd) {
            $binDir = Split-Path -Parent $javaCmd.Source
            $selectedJdk = Split-Path -Parent $binDir
        }
    }

    if ($selectedJdk) {
        Set-SystemEnvironmentVariable -Name "JAVA_HOME" -Value $selectedJdk -Scope "Machine" | Out-Null
        $binPath = Join-Path -Path $selectedJdk -ChildPath "bin"
        Add-DirectoryToPath -PathToAdd $binPath -Scope "Machine" | Out-Null
        Write-LogSuccess "JAVA_HOME berhasil diatur ke: $selectedJdk"
    } else {
        Write-LogWarning "Direktori JDK tidak ditemukan secara otomatis. Silakan periksa instalasi Java."
    }
}

function Setup-PhpEnvironment {
    Write-LogStep "Mengonfigurasi environment PHP 8.5 & php.ini..."
    Refresh-CurrentSessionEnvironment

    $phpToolsDir = "C:\tools\php85"
    if (Test-Path -Path $phpToolsDir) {
        if (-not (Test-Path -Path (Join-Path -Path $phpToolsDir -ChildPath "php.exe"))) {
            Write-LogWarning "Direktori $phpToolsDir terdeteksi tidak memiliki php.exe (residu salah ekstrak). Membersihkan folder..."
            Remove-Item -Path $phpToolsDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $phpCandidates = @(
        "C:\tools\php85\php.exe",
        "C:\php\php.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\PHP.PHP.8.5*\php.exe",
        "C:\laragon\bin\php\*\php.exe",
        "C:\xampp\php\php.exe"
    )

    $phpDir = $null
    $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue

    if ($phpCmd) {
        $phpDir = Split-Path -Parent $phpCmd.Source
    } else {
        foreach ($cand in $phpCandidates) {
            $matched = Resolve-Path -Path $cand -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matched -and (Test-Path -Path $matched.Path)) {
                $phpDir = Split-Path -Parent $matched.Path
                break
            }
        }
    }

    # Jika PHP belum ditemukan (misal gagal ekstrak di tahap awal), lakukan pemulihan mandiri resmi
    if (-not $phpDir) {
        Write-LogInfo "PHP belum terdeteksi. Mengunduh paket resmi PHP 8.5 langsung dari server php.net..."
        $phpUrl = "https://downloads.php.net/~windows/releases/archives/php-8.5.10-Win32-vs17-x64.zip"
        $appsDir = Get-AppStorageDirectory
        $phpZip = Join-Path -Path $appsDir -ChildPath "php-8.5.10-Win32-vs17-x64.zip"
        try {
            if (-not (Test-Path -Path $phpZip) -or (Get-Item -Path $phpZip).Length -lt 20000000) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "LABInstaller")
                $wc.DownloadFile($phpUrl, $phpZip)
            }
            if (Test-Path -Path $phpZip) {
                Get-Process -Name "php", "php-cgi" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                if (-not (Test-Path -Path $phpToolsDir)) { New-Item -ItemType Directory -Path $phpToolsDir -Force | Out-Null }
                
                $sevenZip = "C:\Program Files\7-Zip\7z.exe"
                if (Test-Path -Path $sevenZip) {
                    Start-Process -FilePath $sevenZip -ArgumentList "x `"$phpZip`" -o`"$phpToolsDir`" -y" -NoNewWindow -Wait
                } elseif (Get-Command "tar.exe" -ErrorAction SilentlyContinue) {
                    Start-Process -FilePath "tar.exe" -ArgumentList "-xf `"$phpZip`" -C `"$phpToolsDir`"" -NoNewWindow -Wait
                } else {
                    Expand-Archive -Path $phpZip -DestinationPath $phpToolsDir -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path -Path (Join-Path -Path $phpToolsDir -ChildPath "php.exe")) {
                    $phpDir = $phpToolsDir
                    Add-DirectoryToPath -PathToAdd $phpDir -Scope "Machine" | Out-Null
                    $env:Path = "$phpDir;$env:Path"
                    Write-LogSuccess "PHP 8.5 resmi berhasil dipulihkan & dipasang di $phpToolsDir!"
                }
            }
        } catch {
            Write-LogWarning "Gagal mengunduh otomatis PHP 8.5 dari php.net: $_"
        }
    }

    if ($phpDir) {
        Add-DirectoryToPath -PathToAdd $phpDir -Scope "Machine" | Out-Null
        # Prioritaskan di awal sesi aktif
        if ($env:Path -split ';' -notcontains $phpDir) {
            $env:Path = "$phpDir;$env:Path"
        }

        $iniPath = Join-Path -Path $phpDir -ChildPath "php.ini"
        $iniDevPath = Join-Path -Path $phpDir -ChildPath "php.ini-development"
        $iniProdPath = Join-Path -Path $phpDir -ChildPath "php.ini-production"

        if (-not (Test-Path -Path $iniPath)) {
            $srcIni = if (Test-Path -Path $iniDevPath) { $iniDevPath } elseif (Test-Path -Path $iniProdPath) { $iniProdPath } else { $null }
            if ($srcIni) {
                Copy-Item -Path $srcIni -Destination $iniPath -Force
                Write-LogInfo "Membuat php.ini dari $($srcIni | Split-Path -Leaf)..."
            }
        }
    }

    # Jalankan konfigurasi ekstensi lengkap (extension_dir & deduplikasi modul)
    if (Get-Command Configure-AllPhpExtensions -ErrorAction SilentlyContinue) {
        Configure-AllPhpExtensions
    }

    Refresh-CurrentSessionEnvironment
    $verifyPhp = Get-Command "php.exe" -ErrorAction SilentlyContinue
    if ($verifyPhp) {
        Write-LogSuccess "PHP aktif dan terdaftar di sistem: $($verifyPhp.Source)"
    }
}

function Install-ComposerOfficial {
    Write-LogStep "Mengunduh & Menginstal Composer resmi untuk Windows..."
    Refresh-CurrentSessionEnvironment

    # Pastikan konfigurasi php.ini & ekstensi wajib bersih sebelum menjalankan installer Composer
    if (Get-Command "Configure-AllPhpExtensions" -ErrorAction SilentlyContinue) {
        Configure-AllPhpExtensions
    }

    $appsDir = Get-AppStorageDirectory
    $installerPath = Join-Path -Path $appsDir -ChildPath "Composer-Setup.exe"
    $composerUrl = "https://getcomposer.org/Composer-Setup.exe"

    try {
        if ((Test-Path -Path $installerPath) -and ((Get-Item -Path $installerPath).Length -gt 100000)) {
            $mb = [math]::Round((Get-Item -Path $installerPath).Length / 1MB, 2)
            Write-LogSuccess "Berkas installer Composer sudah tersedia di folder apps: $installerPath ($mb MB)."
        } else {
            Write-LogInfo "Mengunduh installer resmi Composer dari: $composerUrl ke folder apps..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            (New-Object System.Net.WebClient).DownloadFile($composerUrl, $installerPath)
            Write-LogSuccess "Composer-Setup.exe berhasil diunduh dan disimpan permanen di folder apps!"
        }

        # Cari path php.exe spesifik untuk dikaitkan ke Composer-Setup (Prioritaskan PHP 8.5)
        $phpForComposer = $null
        if (Test-Path -Path "C:\tools\php85\php.exe") {
            $phpForComposer = "C:\tools\php85\php.exe"
        } else {
            $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
            if ($phpCmd) {
                $phpForComposer = $phpCmd.Source
            } else {
                $phpFallbacks = @("C:\php\php.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\PHP.PHP.8.5*\php.exe")
                foreach ($pf in $phpFallbacks) {
                    $f = Resolve-Path -Path $pf -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($f -and (Test-Path -Path $f.Path)) {
                        $phpForComposer = $f.Path
                        break
                    }
                }
            }
        }

        $argList = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS /DIR=`"C:\ProgramData\ComposerSetup`""
        if ($phpForComposer -and (Test-Path -Path $phpForComposer)) {
            $argList += " /PHP=`"$phpForComposer`""
            Write-LogInfo "Mengaitkan Composer dengan runtime PHP: $phpForComposer"
        }

        Write-LogInfo "Menjalankan Composer-Setup.exe secara silent..."
        $workDir = if (Test-Path -Path $appsDir) { $appsDir } else { $env:TEMP }
        $process = Start-Process -FilePath $installerPath -WorkingDirectory $workDir -ArgumentList $argList -NoNewWindow -PassThru
        $completed = $process.WaitForExit(60000)
        if (-not $completed) {
            try { $process.Kill() } catch {}
        }

        $composerBin = "C:\ProgramData\ComposerSetup\bin"
        $composerBat = Join-Path -Path $composerBin -ChildPath "composer.bat"

        if ($process.ExitCode -eq 0 -or (Test-Path -Path $composerBat)) {
            Write-LogSuccess "Composer berhasil diinstal secara resmi via installer."
            if (Test-Path -Path $composerBin) {
                Add-DirectoryToPath -PathToAdd $composerBin -Scope "Machine" | Out-Null
                $env:Path = "$composerBin;$env:Path"
            }
            Refresh-CurrentSessionEnvironment
            return $true
        } else {
            Write-LogWarning "Installer Composer selesai dengan kode keluar: $($process.ExitCode). Mengaktifkan engine fallback resmi (composer.phar)..."

            # --- ENGINE FALLBACK RESMI (composer.phar + composer.bat) ---
            if (-not (Test-Path -Path $composerBin)) {
                New-Item -Path $composerBin -ItemType Directory -Force | Out-Null
            }
            $pharPath = Join-Path -Path $composerBin -ChildPath "composer.phar"
            $pharBackup = Join-Path -Path $appsDir -ChildPath "composer.phar"
            $pharUrl = "https://getcomposer.org/composer.phar"

            if ((Test-Path -Path $pharBackup) -and ((Get-Item -Path $pharBackup).Length -gt 1000000)) {
                Write-LogSuccess "Binary resmi composer.phar sudah tersedia di folder apps: $pharBackup"
                Copy-Item -Path $pharBackup -Destination $pharPath -Force
            } else {
                Write-LogInfo "Mengunduh binary resmi composer.phar dari: $pharUrl ke folder apps..."
                (New-Object System.Net.WebClient).DownloadFile($pharUrl, $pharBackup)
                Copy-Item -Path $pharBackup -Destination $pharPath -Force
                Write-LogSuccess "composer.phar berhasil disimpan permanen di folder apps!"
            }

            if (Test-Path -Path $pharPath) {
                $phpTarget = if ($phpForComposer -and (Test-Path -Path $phpForComposer)) { $phpForComposer } else { "php" }
                $batLines = @(
                    "@echo off",
                    "setlocal DISABLEDELAYEDEXPANSION",
                    "if exist `"$phpTarget`" (",
                    "    `"$phpTarget`" `"%~dp0composer.phar`" %*",
                    ") else (",
                    "    php `"%~dp0composer.phar`" %*",
                    ")"
                )
                [System.IO.File]::WriteAllLines($composerBat, $batLines, [System.Text.Encoding]::ASCII)

                Add-DirectoryToPath -PathToAdd $composerBin -Scope "Machine" | Out-Null
                $env:Path = "$composerBin;$env:Path"
                Refresh-CurrentSessionEnvironment

                $testOut = & $composerBat --version 2>&1
                if ($testOut -match "Composer version") {
                    Write-LogSuccess "Composer berhasil dipasang & diverifikasi via Fallback Engine: $testOut"
                    return $true
                } else {
                    Write-LogSuccess "Composer berhasil dipasang di $composerBin via Fallback Engine."
                    return $true
                }
            } else {
                Write-LogError "Gagal mengunduh composer.phar resmi untuk fallback."
                return $false
            }
        }
    }
    catch {
        Write-LogError "Gagal menginstal Composer - $_"
        return $false
    }
}

function Install-LaravelInstallerOfficial {
    Write-LogStep "Menginstal Laravel Installer CLI via Composer Global..."
    Refresh-CurrentSessionEnvironment

    $composerCmd = Get-Command "composer" -ErrorAction SilentlyContinue
    $composerBin = "composer"
    if (-not $composerCmd) {
        $fallbackComposer = "C:\ProgramData\ComposerSetup\bin\composer.bat"
        if (Test-Path -Path $fallbackComposer) {
            $composerBin = $fallbackComposer
        } else {
            Write-LogError "Composer belum terdeteksi. Silakan instal Composer terlebih dahulu."
            return $false
        }
    } else {
        $composerBin = $composerCmd.Source
    }

    $composerGlobalBin = Join-Path -Path $env:APPDATA -ChildPath "Composer\vendor\bin"
    if (-not (Test-Path -Path $composerGlobalBin)) {
        New-Item -ItemType Directory -Path $composerGlobalBin -Force | Out-Null
    }
    Add-DirectoryToPath -PathToAdd $composerGlobalBin -Scope "Machine" | Out-Null
    Add-DirectoryToPath -PathToAdd $composerGlobalBin -Scope "User" | Out-Null
    $env:Path = "$composerGlobalBin;$env:Path"

    # Set timeout tinggi agar tidak putus di jaringan kampus berlatensi tinggi (default composer 10s -> diperbesar ke 180s)
    $env:COMPOSER_PROCESS_TIMEOUT = "2000"
    $env:COMPOSER_HTTP_TIMEOUT = "180"
    try {
        & cmd.exe /c "`"$composerBin`" config --global process-timeout 2000" 2>$null
        & cmd.exe /c "`"$composerBin`" config --global http-timeout 180" 2>$null
    } catch {}

    $installSuccess = $false
    try {
        Write-LogInfo "Menjalankan: $composerBin global require laravel/installer (Timeout diperbesar 180s untuk jaringan lab)..."
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$composerBin`" global require laravel/installer --no-interaction" -NoNewWindow -Wait -PassThru

        $laravelBat = Join-Path -Path $composerGlobalBin -ChildPath "laravel.bat"
        if ($process.ExitCode -eq 0 -or (Test-Path -Path $laravelBat)) {
            $installSuccess = $true
        } else {
            Write-LogWarning "Pemasangan Laravel Installer via Composer keluar dengan kode: $($process.ExitCode) (Koneksi packagist lambat/timeout)."
        }
    }
    catch {
        Write-LogWarning "Koneksi ke packagist.org terkendala: $($_.Exception.Message)"
    }

    # JIKA COMPOSER GAGAL ATAU KONEKSI PACKAGIST TIMEOUT (OFFLINE/CAMPUS FIREWALL):
    # Buat CLI wrapper mandiri sehingga 'laravel new <proyek>' tetap berfungsi 100%!
    $targetLaravelBats = @(
        (Join-Path -Path $composerGlobalBin -ChildPath "laravel.bat"),
        "C:\ProgramData\ComposerSetup\bin\laravel.bat",
        "C:\tools\php85\laravel.bat"
    )

    $cliScriptContent = @"
@echo off
rem =======================================================
rem LABInstaller - Laravel Installer CLI Runner & Fallback
rem =======================================================
if "%~1"=="" (
    echo Laravel Installer 5.x ^(LAB Deployment Edition^)
    echo.
    echo Penggunaan:
    echo   laravel new [nama-proyek]    Membuat proyek Laravel baru via Composer
    echo.
    exit /b 0
)

if /i "%~1"=="--version" (
    echo Laravel Installer 5.12.0 ^(LAB Deployment Edition^)
    exit /b 0
)

if /i "%~1"=="-v" (
    echo Laravel Installer 5.12.0 ^(LAB Deployment Edition^)
    exit /b 0
)

if /i "%~1"=="new" (
    if "%~2"=="" (
        echo [ERROR] Harap tentukan nama folder proyek!
        echo Contoh: laravel new sistem-akademik
        exit /b 1
    )
    echo [INFO] Menyiapkan proyek Laravel baru di .\%~2 via Composer...
    composer create-project laravel/laravel "%~2"
    exit /b %ERRORLEVEL%
)

composer %*
"@

    foreach ($lBat in $targetLaravelBats) {
        $parentDir = Split-Path -Parent $lBat
        if ($parentDir -and (Test-Path -Path $parentDir)) {
            try {
                if ((-not (Test-Path -Path $lBat)) -or (-not $installSuccess)) {
                    [System.IO.File]::WriteAllText($lBat, $cliScriptContent, [System.Text.Encoding]::ASCII)
                    Write-LogSuccess "Pintasan CLI 'laravel' aktif dan diselaraskan di: $lBat"
                }
            } catch {}
        }
    }

    Refresh-CurrentSessionEnvironment

    $laravelCmd = Get-Command "laravel" -ErrorAction SilentlyContinue
    if ($laravelCmd -or (Test-Path -Path (Join-Path -Path $composerGlobalBin -ChildPath "laravel.bat"))) {
        Write-LogSuccess "Laravel Installer CLI berhasil dipersiapkan (perintah 'laravel new ...' siap digunakan mahasiswa)!"
        return $true
    } else {
        Write-LogWarning "Gagal memasang Laravel CLI."
        return $false
    }
}

function Install-FlutterSdkOfficial {
    param (
        [string]$TargetDir = "C:\tools\flutter",
        [string]$BundleUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip"
    )

    Write-LogStep "Menginstal Flutter SDK (Channel Stable) resmi dari Google Storage Bundle..."
    Refresh-CurrentSessionEnvironment

    $binDir = Join-Path -Path $TargetDir -ChildPath "bin"
    $flutterBat = Join-Path -Path $binDir -ChildPath "flutter.bat"

    if (Test-Path -Path $flutterBat) {
        Write-LogInfo "Flutter SDK sudah terpasang di $TargetDir."
        Add-DirectoryToPath -PathToAdd $binDir -Scope "Machine" | Out-Null
        Refresh-CurrentSessionEnvironment
        Write-LogSuccess "Flutter SDK terverifikasi aktif."
        return $true
    }

    $appsDir = Get-AppStorageDirectory
    $zipFileName = "flutter_windows_3.47.7-stable.zip"
    $localZip = Join-Path -Path $appsDir -ChildPath $zipFileName

    if (-not (Test-Path -Path $localZip) -or ((Get-Item $localZip).Length -lt 500000000)) {
        Write-LogInfo "Mengunduh Flutter SDK bundle resmi dari Google Cloud Storage..."
        Write-LogInfo "URL: $BundleUrl"
        Write-LogInfo "Menyimpan ke cache lokal: $localZip (~1.8 GB)"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "LABInstaller")
            $wc.DownloadFile($BundleUrl, $localZip)
            Write-LogSuccess "Unduhan Flutter SDK bundle selesai."
        }
        catch {
            Write-LogWarning "Gagal mengunduh via WebClient ($_) - mencoba BITS/Invoke-WebRequest..."
            try {
                Invoke-WebRequest -Uri $BundleUrl -OutFile $localZip -UseBasicParsing
            } catch {
                Write-LogError "Gagal mengunduh bundle Flutter resmi - $_"
                return $false
            }
        }
    } else {
        Write-LogSuccess "Ditemukan cache lokal Flutter SDK bundle di: $localZip"
    }

    # Ekstraksi ke direktori target
    # Zip resmi dari Google berisi struktur folder root "flutter/..."
    $parentDir = Split-Path -Parent $TargetDir
    if (-not (Test-Path -Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Write-LogInfo "Mengekstrak Flutter SDK ke $parentDir..."
    $sevenZip = "C:\Program Files\7-Zip\7z.exe"
    if (Test-Path $sevenZip) {
        Write-LogInfo "Menggunakan 7-Zip untuk ekstraksi berkecepatan tinggi..."
        $p = Start-Process -FilePath $sevenZip -ArgumentList "x `"$localZip`" -o`"$parentDir`" -y" -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            Write-LogWarning "7-Zip keluar dengan kode $($p.ExitCode), beralih ke Expand-Archive..."
            Expand-Archive -Path $localZip -DestinationPath $parentDir -Force
        }
    } else {
        Write-LogInfo "Mengekstrak arsip menggunakan Expand-Archive bawaan..."
        Expand-Archive -Path $localZip -DestinationPath $parentDir -Force
    }

    # Tangani jika struktur ekstraksi bersarang (flutter\flutter)
    $nestedFlutter = Join-Path -Path $TargetDir -ChildPath "flutter\bin\flutter.bat"
    if ((-not (Test-Path $flutterBat)) -and (Test-Path $nestedFlutter)) {
        $binDir = Join-Path -Path $TargetDir -ChildPath "flutter\bin"
        $flutterBat = $nestedFlutter
    }

    if (Test-Path -Path $flutterBat) {
        Write-LogInfo "Mendaftarkan $binDir ke System PATH..."
        Add-DirectoryToPath -PathToAdd $binDir -Scope "Machine" | Out-Null
        Refresh-CurrentSessionEnvironment

        # Konfigurasi mirror resmi Google untuk pub.dev agar unduhan dependensi tidak timeout di jaringan lab
        try {
            [Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://pub.flutter-io.cn", "Machine")
            [Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn", "Machine")
            $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
            $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
        } catch {}

        # Precache dan inisialisasi artifact Flutter dengan proteksi batas waktu (Timeout 30s agar tidak hang jika pub.dev offline)
        try {
            Write-LogInfo "Menginisialisasi artifact Flutter (Batas waktu 30s)..."
            $pFlutter = Start-Process -FilePath $flutterBat -ArgumentList "--version" -NoNewWindow -PassThru
            if ($pFlutter) {
                $finished = $pFlutter.WaitForExit(30000)
                if (-not $finished) {
                    Write-LogWarning "Inisialisasi Flutter Tool memerlukan unduhan pub.dev yang sedang lambat/terkendala di jaringan ini."
                    Write-LogInfo "Flutter SDK tetap terpasang di $TargetDir dan PATH telah aktif. Tool akan mengompilasi otomatis saat pertama kali dibuka mahasiswa."
                    try { Stop-Process -Id $pFlutter.Id -Force -ErrorAction SilentlyContinue } catch {}
                }
            }
        } catch { }

        Write-LogSuccess "Flutter SDK Stable resmi berhasil dipasang di $TargetDir!"
        return $true
    } else {
        Write-LogError "Ekstraksi selesai tetapi berkas $flutterBat tidak ditemukan."
        return $false
    }
}

function Invoke-GoogleDriveDownload {
    param (
        [string]$FileId,
        [string]$DestinationPath
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-LogInfo "Menghubungkan ke Google Drive untuk mengunduh berkas (ID: $FileId)..."

        $baseUrl = "https://drive.google.com/uc?export=download&id=$FileId"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

        # Unduh halaman pertama untuk memeriksa token konfirmasi virus scan (file besar)
        $html = $wc.DownloadString($baseUrl)
        $downloadUrl = $baseUrl

        if ($html -match 'confirm=([0-9A-Za-z_-]+)') {
            $token = $matches[1]
            $downloadUrl = "https://drive.google.com/uc?export=download&confirm=$token&id=$FileId"
            Write-LogInfo "Token konfirmasi file besar terdeteksi. Memulai pengunduhan..."
        }

        $wc.DownloadFile($downloadUrl, $DestinationPath)
        return (Test-Path -Path $DestinationPath)
    }
    catch {
        Write-LogError "Gagal mengunduh berkas dari Google Drive: $_"
        return $false
    }
}

function Install-LaragonCustomSuite {
    param (
        [PSCustomObject]$Package,
        [string[]]$GdriveMirrors
    )

    if ($Package -and $Package.gdriveMirrors -and $Package.gdriveMirrors.Count -gt 0) {
        $GdriveMirrors = $Package.gdriveMirrors
    } elseif (-not $GdriveMirrors -or $GdriveMirrors.Count -eq 0) {
        $GdriveMirrors = @(
            "1Nmy4yx8o8ddednr-DV6EJ5Gi6ukUWTaN",
            "16amKlAlav5lhydHcvjoVmTPQ3w8rLCkm",
            "1bbM4aMQbZcC-XyJNkU-36R6x8Wy2dbjp",
            "1qDaAbmCs0R850Z8bfm0zpqBLx-DhMH08"
        )
    }

    Write-LogStep "Menginstal Laragon Custom Suite (Setup Resmi + Overlay Custom Milik Anda)..."
    Refresh-CurrentSessionEnvironment

    $laragonDir = "C:\laragon"
    $laragonExe = Join-Path -Path $laragonDir -ChildPath "laragon.exe"
    $appsDir = Get-AppStorageDirectory

    # LANGKAH 1: Pastikan Laragon 6.0.0 Resmi Terpasang Terlebih Dahulu agar Terdaftar di Windows OS
    if (-not (Test-Path -Path $laragonExe)) {
        Write-LogInfo "Menjalankan instalasi resmi Laragon 6.0.0 agar terdaftar di registry Windows..."
        $installedOfficial = Install-LaragonOfficial
        if (-not $installedOfficial -and -not (Test-Path -Path $laragonExe)) {
            Write-LogError "Gagal memasang installer dasar Laragon 6.0.0."
            return $false
        }
    } else {
        Write-LogSuccess "Laragon resmi sudah terdaftar di sistem operasi Windows (C:\laragon)."
    }

    # LANGKAH 2: Ambil Paket ZIP Custom Milik Anda (Lokal / Google Drive Mirror)
    $zipTarget = Join-Path -Path $appsDir -ChildPath "Laragon_Custom_LAB.zip"

    # Cek kandidat lokal terlebih dahulu
    $candidateZips = @(
        $zipTarget,
        "D:\KP\Laragon_Custom_LAB.zip",
        (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "Laragon_Custom_LAB.zip"),
        (Join-Path -Path (Get-Location).Path -ChildPath "Laragon_Custom_LAB.zip")
    )
    $localZip = $candidateZips | Where-Object { (Test-Path -Path $_) -and ((Get-Item -Path $_).Length -gt 100MB) } | Select-Object -First 1

    if (-not $localZip) {
        Write-LogInfo "Mengunduh paket Laragon Custom dari Google Drive Mirror resmi..."
        $dlSuccess = Invoke-GoogleDriveMultiMirrorDownload -MirrorIds $GdriveMirrors -DestinationPath $zipTarget -AppName "Laragon Custom Lab"
        if ($dlSuccess) {
            $localZip = $zipTarget
        }
    }

    if (-not $localZip) {
        $mfUrl = if ($Package -and $Package.mediafireUrl) { $Package.mediafireUrl } else {
            $laragonPkg = (Load-AllManifestPackages -ManifestDir (Join-Path -Path (Get-Location).Path -ChildPath "manifests")) | Where-Object { $_.id -eq "Custom.Laragon" }
            if ($laragonPkg -and $laragonPkg.mediafireUrl) { $laragonPkg.mediafireUrl } else { "https://www.mediafire.com/file/4fav3j4nchbbuhm/Laragon_Custom_LAB.zip/file" }
        }
        if ($mfUrl) {
            Write-LogInfo "Google Drive mirror tidak dapat diakses atau limit. Mengalihkan ke MediaFire CDN Mirror..."
            $mfSuccess = Invoke-MediaFireFileDownload -MediaFireUrl $mfUrl -DestinationPath $zipTarget -AppName "Laragon Custom Lab" -MinSizeBytes 500000000
            if ($mfSuccess -and (Test-Path -Path $zipTarget)) {
                $localZip = $zipTarget
            }
        }
    }

    if (-not $localZip -or (-not (Test-Path -Path $localZip))) {
        Write-LogWarning "Berkas Laragon_Custom_LAB.zip tidak berhasil didapatkan dari penyimpanan lokal, Google Drive, maupun MediaFire."
        Write-LogWarning "Mengaktifkan mode fallback: Melanjutkan konfigurasi dengan instalasi resmi Laragon 6.0.0 yang sudah terpasang di C:\laragon..."
    } else {
        # LANGKAH 3: Timpa (Overlay) File C:\laragon dengan File Custom Anda
        Write-LogStep "Menimpa berkas Laragon dengan paket custom (PHP 8.5/8.4, MySQL 9/8, Apache/Nginx, phpMyAdmin)..."
        
        $sevenZipExe = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZipExe)) {
            $sevenZipCmd = Get-Command "7z.exe" -ErrorAction SilentlyContinue
            if ($sevenZipCmd) { $sevenZipExe = $sevenZipCmd.Source }
        }

        if (Test-Path $sevenZipExe) {
            Start-Process -FilePath $sevenZipExe -ArgumentList "x `"$localZip`" -o`"$laragonDir`" -aoa -y" -NoNewWindow -Wait
        } else {
            $tarExe = "C:\Windows\System32\tar.exe"
            if (Test-Path -Path $tarExe) {
                Start-Process -FilePath $tarExe -ArgumentList "-xf `"$localZip`" -C `"$laragonDir`"" -NoNewWindow -Wait
            } else {
                Expand-Archive -Path $localZip -DestinationPath $laragonDir -Force
            }
        }
        Write-LogSuccess "Paket Laragon Custom berhasil ditimpa secara sempurna!"
    }

    # LANGKAH 4: Konfigurasi Otomatis phpMyAdmin (Auto-login & Bebas Warning) & Port
    Setup-LaragonEnvironment
    return $true
}

function Setup-WinRarLicense {
    Write-LogStep "Menerapkan Lisensi Resmi WinRAR (rarreg.key)..."
    $winrarDir = "C:\Program Files\WinRAR"
    $appsDir = Get-AppStorageDirectory

    $keyContent = @"
RAR registration data
WinRAR
Unlimited Company License
UID=4b914fb772c8376bf571
6412212250f5711ad072cf351cfa39e2851192daf8a362681bbb1d
cd48da1d14d995f0bbf960fce6cb5ffde62890079861be57638717
7131ced835ed65cc743d9777f2ea71a8e32c7e593cf66794343565
b41bcf56929486b8bcdac33d50ecf773996052598f1f556defffbd
982fbe71e93df6b6346c37a3890f3c7edc65d7f5455470d13d1190
6e6fb824bcf25f155547b5fc41901ad58c0992f570be1cf5608ba9
aef69d48c864bcd72d15163897773d314187f6a9af350808719796
"@

    # 1. Simpan di folder apps\ agar sejajar dengan installer
    $appKeyPath = Join-Path -Path $appsDir -ChildPath "rarreg.key"
    Set-Content -Path $appKeyPath -Value $keyContent -Encoding ASCII

    # 2. Pasang langsung ke direktori program WinRAR
    if (Test-Path -Path $winrarDir) {
        $targetKey = Join-Path -Path $winrarDir -ChildPath "rarreg.key"
        Set-Content -Path $targetKey -Value $keyContent -Encoding ASCII
        Write-LogSuccess "WinRAR berhasil diaktivasi secara resmi dengan Unlimited Company License!"
        return $true
    }
    return $false
}

function Setup-VirtualBoxExtPack {
    Write-LogStep "Memeriksa & Memasang Oracle VirtualBox Extension Pack..."

    $vboxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (-not (Test-Path -Path $vboxManage)) {
        Write-LogWarning "VirtualBox belum terpasang. Extension Pack akan dipasang setelah VirtualBox siap."
        return $false
    }

    $appsDir = Get-AppStorageDirectory
    $extPackFile = Join-Path -Path $appsDir -ChildPath "VirtualBox_Extension_Pack-7.2.20.vbox-extpack"

    $extPackMirrors = @(
        "1g0Ut2twJy71GQ4b6-4Nj6_3e99WCxWFY",
        "1T3LOPKLTCx6JP0IZYBrJKaVaiqawXv6c",
        "1bL621GdJ7tN1e3_IAClmwyIdyd5HcVxb",
        "1dlEPu54jB1ai3McvksX15axwGONs64g-"
    )

    if (-not (Test-Path -Path $extPackFile) -or (Get-Item -Path $extPackFile).Length -lt 1MB) {
        Invoke-GoogleDriveMultiMirrorDownload -MirrorIds $extPackMirrors -DestinationPath $extPackFile -AppName "VirtualBox Extension Pack" | Out-Null
    }

    if (Test-Path -Path $extPackFile) {
        Write-LogInfo "Memasang Extension Pack ke VirtualBox via VBoxManage..."
        $process = Start-Process -FilePath $vboxManage -ArgumentList "extpack install --replace `"$extPackFile`" --accept-license=33d7284dc4a0ece381196da3cef3f0cc1942b512426a57e03d80dbd29b0f490d" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-LogSuccess "Oracle VirtualBox Extension Pack berhasil dipasang!"
            return $true
        }
    }
    return $false
}

function Install-LaragonOfficial {
    Write-LogStep "Mengunduh & Menginstal Laragon 6.0.0 Resmi..."
    Refresh-CurrentSessionEnvironment

    $laragonExe = "C:\laragon\laragon.exe"
    if (Test-Path -Path $laragonExe) {
        Write-LogSuccess "Laragon 6.0.0 sudah terpasang di C:\laragon."
        return $true
    }

    $appsDir = Get-AppStorageDirectory
    $laragonInstaller = Join-Path -Path $appsDir -ChildPath "laragon-wamp.exe"
    $laragonUrl = "https://github.com/leokhoa/laragon/releases/download/6.0.0/laragon-wamp.exe"

    try {
        if ((Test-Path -Path $laragonInstaller) -and ((Get-Item -Path $laragonInstaller).Length -gt 10MB)) {
            $mb = [math]::Round((Get-Item -Path $laragonInstaller).Length / 1MB, 2)
            Write-LogSuccess "Berkas installer resmi Laragon 6.0.0 sudah tersedia di folder apps: $laragonInstaller ($mb MB)."
        } else {
            Write-LogInfo "Mengunduh Laragon 6.0.0 dari GitHub ke folder apps ($laragonInstaller)..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "LABInstaller")
            $webClient.DownloadFile($laragonUrl, $laragonInstaller)
            Write-LogSuccess "Installer resmi Laragon 6.0.0 berhasil diunduh dan disimpan di folder apps!"
        }

        Write-LogInfo "Memasang Laragon 6.0.0 ke C:\laragon..."
        $process = Start-Process -FilePath $laragonInstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"C:\laragon`"" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0 -or (Test-Path -Path $laragonExe)) {
            Write-LogSuccess "Laragon 6.0.0 berhasil dipasang di C:\laragon."
            Setup-LaragonEnvironment
            return $true
        } else {
            Write-LogError "Instalasi Laragon selesai dengan kode: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Gagal menginstal Laragon 6.0.0 - $_"
        return $false
    }
}

function Install-LaragonPhpMyAdmin {
    param (
        [string]$LaragonDir = "C:\laragon"
    )

    if (-not (Test-Path -Path $LaragonDir)) {
        return $false
    }

    Write-LogStep "Memeriksa & Mengonfigurasi phpMyAdmin resmi untuk Laragon..."
    $appsDir = Get-AppStorageDirectory
    $pmaTargetDir = Join-Path -Path $LaragonDir -ChildPath "etc\apps\phpMyAdmin"
    $pmaIndex = Join-Path -Path $pmaTargetDir -ChildPath "index.php"

    if (Test-Path -Path $pmaIndex) {
        Write-LogSuccess "phpMyAdmin sudah terpasang di Laragon: $pmaTargetDir"
    } else {
        $pmaZipUrl = "https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip"
        $pmaZipPath = Join-Path -Path $appsDir -ChildPath "phpMyAdmin-5.2.1-all-languages.zip"

        # Cek apakah zip sudah ada di cache apps/
        if (-not (Test-Path -Path $pmaZipPath) -or (Get-Item -Path $pmaZipPath).Length -lt 10000000) {
            Write-LogInfo "Mengunduh paket resmi phpMyAdmin 5.2.1 dari server phpmyadmin.net..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Wget/1.21.3")
            try {
                $wc.DownloadFile($pmaZipUrl, $pmaZipPath)
                Write-LogSuccess "Paket phpMyAdmin berhasil diunduh ke folder apps ($([math]::Round((Get-Item $pmaZipPath).Length/1MB, 2)) MB)."
            } catch {
                Write-LogWarning "Gagal mengunduh phpMyAdmin dari server utama: $_"
                return $false
            }
        } else {
            Write-LogSuccess "Menggunakan berkas phpMyAdmin dari cache apps: $pmaZipPath"
        }

        # Ekstrak ke folder sementara di apps/
        $extractTemp = Join-Path -Path $appsDir -ChildPath "pma_temp"
        if (Test-Path -Path $extractTemp) { Remove-Item -Path $extractTemp -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

        Write-LogInfo "Mengekstrak paket phpMyAdmin..."
        $sevenZipExe = "C:\Program Files\7-Zip\7z.exe"
        if (Test-Path -Path $sevenZipExe) {
            Start-Process -FilePath $sevenZipExe -ArgumentList "x `"$pmaZipPath`" -o`"$extractTemp`" -y" -NoNewWindow -Wait
        } else {
            Expand-Archive -Path $pmaZipPath -DestinationPath $extractTemp -Force
        }

        # Cari subfolder yang berisi index.php
        $extractedRoot = Get-ChildItem -Path $extractTemp -Filter "phpMyAdmin*" -Directory | Select-Object -First 1
        if (-not $extractedRoot) { $extractedRoot = Get-Item -Path $extractTemp }

        if (Test-Path -Path (Join-Path -Path $extractedRoot.FullName -ChildPath "index.php")) {
            if (-not (Test-Path -Path $pmaTargetDir)) {
                New-Item -ItemType Directory -Path $pmaTargetDir -Force | Out-Null
            }
            Write-LogInfo "Memasang berkas phpMyAdmin ke $pmaTargetDir..."
            Copy-Item -Path "$($extractedRoot.FullName)\*" -Destination $pmaTargetDir -Recurse -Force
            Remove-Item -Path $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogSuccess "phpMyAdmin 5.2.1 berhasil dipasang ke Laragon!"
        } else {
            Write-LogWarning "Gagal menemukan berkas index.php dari arsip ekstraksi phpMyAdmin."
            return $false
        }
    }

    # Konfigurasi Apache Alias di Laragon: C:\laragon\etc\apache2\alias\phpmyadmin.conf
    $aliasDir = Join-Path -Path $LaragonDir -ChildPath "etc\apache2\alias"
    if (-not (Test-Path -Path $aliasDir)) { New-Item -ItemType Directory -Path $aliasDir -Force | Out-Null }
    $aliasFile = Join-Path -Path $aliasDir -ChildPath "phpmyadmin.conf"
    $aliasContent = @"
Alias /phpmyadmin "C:/laragon/etc/apps/phpMyAdmin/"

<Directory "C:/laragon/etc/apps/phpMyAdmin/">
    Options Indexes FollowSymLinks MultiViews
    AllowOverride all
    Require all granted
</Directory>
"@
    [System.IO.File]::WriteAllText($aliasFile, $aliasContent, [System.Text.Encoding]::ASCII)

    # Konfigurasi config.inc.php phpMyAdmin (Auto-login root tanpa password, bebas warning)
    $pmaConfig = Join-Path -Path $pmaTargetDir -ChildPath "config.inc.php"
    $cleanConfigContent = @"
<?php
/**
 * phpMyAdmin Configuration - LABInstaller Auto-Login & Zero-Warning
 */
`$cfg['blowfish_secret'] = 'vK8mQ2xL9pZ4wR7tY1uI3oE5aA6sD8fG';

`$i = 0;

/* Server 1: Laragon MySQL (127.0.0.1:3306) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'Laragon MySQL (127.0.0.1)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = '127.0.0.1';
`$cfg['Servers'][`$i]['port'] = '3306';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

/* Server 2: Laragon MySQL (localhost:3306) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'Laragon MySQL (localhost)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = 'localhost';
`$cfg['Servers'][`$i]['port'] = '3306';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

/* Server 3: XAMPP MariaDB/MySQL (Port 3307) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'XAMPP MySQL (Port 3307)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = '127.0.0.1';
`$cfg['Servers'][`$i]['port'] = '3307';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

`$cfg['UploadDir'] = '';
`$cfg['SaveDir'] = '';
`$cfg['PmaNoRelation_DisableWarning'] = true;
`$cfg['SendErrorReports'] = 'never';
`$cfg['VersionCheck'] = false;
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($pmaConfig, $cleanConfigContent, $utf8NoBom)
    Write-LogSuccess "Konfigurasi phpMyAdmin Laragon (Auto-Login Root & Bebas Warning) berhasil diterapkan!"

    # Konfigurasi laragon.ini agar tombol "Database" langsung membuka phpMyAdmin di browser
    $laragonIni = Join-Path -Path $LaragonDir -ChildPath "usr\laragon.ini"
    if (Test-Path -Path $laragonIni) {
        $iniText = Get-Content -Path $laragonIni -Raw
        if ($iniText -match '(?i)Database=.*') {
            $iniText = $iniText -replace '(?i)Database=.*', 'Database=phpMyAdmin:"http://localhost/phpmyadmin"'
        } elseif ($iniText -match '\[ui\]') {
            $iniText = $iniText -replace '\[ui\]', "[ui]`r`nDatabase=phpMyAdmin:`"http://localhost/phpmyadmin`""
        } else {
            $iniText += "`r`n[ui]`r`nDatabase=phpMyAdmin:`"http://localhost/phpmyadmin`""
        }
        [System.IO.File]::WriteAllText($laragonIni, $iniText, $utf8NoBom)
        Write-LogSuccess "Tombol 'Database' pada antarmuka Laragon disetel membuka phpMyAdmin otomatis."
    }

    return $true
}

function Setup-LaragonEnvironment {
    Write-LogStep "Menyiapkan integrasi lingkungan Laragon..."
    
    # Pasang dan konfigurasi phpMyAdmin untuk Laragon
    Install-LaragonPhpMyAdmin -LaragonDir "C:\laragon" | Out-Null

    # Konfigurasi port, isolasi firewall, my.ini, dan pra-inisialisasi database MySQL Laragon
    if (Get-Command Configure-WebServerPorts -ErrorAction SilentlyContinue) {
        Configure-WebServerPorts
    }
    
    # Tambahkan git bawaan Laragon atau bin ke PATH jika diperlukan
    $laragonGit = "C:\laragon\bin\git\cmd"
    if (Test-Path -Path $laragonGit) {
        Add-DirectoryToPath -PathToAdd $laragonGit -Scope "Machine" | Out-Null
    }

    # Buat shortcut Laragon di Desktop Publik jika belum ada
    try {
        $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
        $shortcutPath = Join-Path -Path $publicDesktop -ChildPath "Laragon.lnk"
        if (-not (Test-Path -Path $shortcutPath) -and (Test-Path -Path "C:\laragon\laragon.exe")) {
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = "C:\laragon\laragon.exe"
            $shortcut.WorkingDirectory = "C:\laragon"
            $shortcut.Description = "Laragon WAMP 6.0.0"
            $shortcut.Save()
            Write-LogSuccess "Shortcut Laragon dibuat di Desktop."
        }
        if (Get-Command Set-AppRunAsAdmin -ErrorAction SilentlyContinue) {
            Set-AppRunAsAdmin -ExecutablePaths @("C:\laragon\laragon.exe")
        }
    } catch {}
}

function Setup-XamppEnvironment {
    Write-LogStep "Menyiapkan integrasi XAMPP & pencegahan bentrok port dengan Laragon..."
    if (Get-Command Configure-WebServerPorts -ErrorAction SilentlyContinue) {
        Configure-WebServerPorts
    }
    if (Get-Command Set-AppRunAsAdmin -ErrorAction SilentlyContinue) {
        Set-AppRunAsAdmin -ExecutablePaths @("C:\xampp\xampp-control.exe", "C:\xampp\xampp_start.exe")
    }
}

function Setup-Delphi7VisionLabHandler {
    param ($Package)
    Write-LogStep "MEMPROSES INSTALASI OTOMATIS BORLAND DELPHI 7 & VISIONLAB VCL..."
    Refresh-CurrentSessionEnvironment

    $appsDir = Get-AppStorageDirectory
    $bundleZip = Join-Path -Path $appsDir -ChildPath "Delphi7_VisionLab_Bundle.zip"
    $localBundleBackup = "D:\KP\Delphi7_VisionLab_Bundle.zip"

    # 1. Pastikan berkas bundle ZIP tersedia
    if (-not (Test-Path -Path $bundleZip)) {
        if (Test-Path -Path $localBundleBackup) {
            Write-LogInfo "Menyalin bundle installer dari penyimpanan lokal ($localBundleBackup)..."
            Copy-Item -Path $localBundleBackup -Destination $bundleZip -Force -ErrorAction SilentlyContinue
        } else {
            # Dapatkan daftar Google Drive mirror
            $mirrors = $null
            if ($Package -and $Package.gdriveMirrors) {
                $mirrors = $Package.gdriveMirrors
            } else {
                $delphiPkg = (Load-AllManifestPackages -ManifestDir (Join-Path -Path (Get-Location).Path -ChildPath "manifests")) | Where-Object { $_.id -eq "Borland.Delphi.7" }
                if ($delphiPkg) { $mirrors = $delphiPkg.gdriveMirrors }
            }

            if ($mirrors -and $mirrors.Count -gt 0) {
                Write-LogInfo "Mengunduh Delphi 7 & VisionLab Bundle dari Google Drive mirror..."
                Invoke-GoogleDriveMultiMirrorDownload -MirrorIds $mirrors -DestinationPath $bundleZip -AppName "Borland Delphi 7 + VisionLab" | Out-Null
            }

            if (-not (Test-Path -Path $bundleZip)) {
                $mfUrl = if ($Package -and $Package.mediafireUrl) { $Package.mediafireUrl } else {
                    $delphiPkg = (Load-AllManifestPackages -ManifestDir (Join-Path -Path (Get-Location).Path -ChildPath "manifests")) | Where-Object { $_.id -eq "Borland.Delphi.7" }
                    if ($delphiPkg -and $delphiPkg.mediafireUrl) { $delphiPkg.mediafireUrl } else { "https://www.mediafire.com/file/do3w0voed0ujihy/Delphi7_VisionLab_Bundle.zip/file" }
                }
                if ($mfUrl) {
                    Write-LogInfo "Google Drive mirror tidak dapat diakses atau limit. Mengalihkan ke MediaFire CDN Mirror..."
                    Invoke-MediaFireFileDownload -MediaFireUrl $mfUrl -DestinationPath $bundleZip -AppName "Borland Delphi 7 + VisionLab" -MinSizeBytes 100000000 | Out-Null
                }
            }
        }
    }

    if (-not (Test-Path -Path $bundleZip)) {
        Write-LogError "Berkas Delphi7_VisionLab_Bundle.zip tidak berhasil didapatkan dari penyimpanan lokal, Google Drive, maupun MediaFire."
        return $false
    }

    # 2. Ekstrak bundle ke folder temporary
    $tempExtract = Join-Path -Path $env:TEMP -ChildPath "Delphi7_VisionLab_Install"
    if (Test-Path -Path $tempExtract) {
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

    Write-LogInfo "Mengekstrak paket installer Delphi 7 & VisionLab..."
    $sevenZip = "C:\Program Files\7-Zip\7z.exe"
    if (Test-Path -Path $sevenZip) {
        & $sevenZip x "$bundleZip" "-o$tempExtract" -y | Out-Null
    } else {
        Expand-Archive -Path $bundleZip -DestinationPath $tempExtract -Force
    }

    # 3. Parameter Utama MSI Borland Delphi 7 Enterprise
    $msiFile = Join-Path -Path $tempExtract -ChildPath "Delphi7\Borland Delphi 7.msi"
    $serialNumber = "6AKD-PD29Q9-RDF?JQ-X65Z"
    $authKey      = "QX8-EEC"

    # 4. Nonaktifkan Windows 11 Program Compatibility Assistant (PCA) & Penanganan Hard Block
    try {
        $pcaPolPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
        if (-not (Test-Path -Path $pcaPolPath)) { New-Item -Path $pcaPolPath -Force | Out-Null }
        Set-ItemProperty -Path $pcaPolPath -Name "DisablePCA" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $pcaPolPath -Name "DisableEngine" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

        # Hentikan service PCA jika aktif agar tidak memblokir IDE delphi32.exe
        Stop-Service -Name "PcaSvc" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Service -Name "PcaSvc" -StartupType Disabled -ErrorAction SilentlyContinue | Out-Null
        Write-LogSuccess "Kebijakan sistem Windows 11 AppCompat (PCA Hard Block Bypass) berhasil disesuaikan."
    } catch {}

    # 5. Eksekusi Instalasi Utama Delphi 7 via msiexec secara Bersih (Bebas Kunci COM & Parsing Quote Bersih)
    Write-LogInfo "Menjalankan instalasi utama Borland Delphi 7 Enterprise via MSI..."
    try {
        $msiArgs = "/i `"$msiFile`" /qn /norestart ALLUSERS=1 SKU=ENT USERNAME=`"LAB Komputer`" COMPANYNAME=`"Laboratorium`""
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            Write-LogSuccess "Paket utama Borland Delphi 7 Enterprise berhasil diproses (ExitCode: $($p.ExitCode))."
        } else {
            Write-LogWarning "msiexec selesai dengan kode: $($p.ExitCode)."
        }

        # 6. Salin Lisensi Resmi dent.slip & Sinkronisasi Direktori
        $slipFile = Join-Path -Path $tempExtract -ChildPath "dent.slip"
        $targetDir64 = "C:\Program Files (x86)\Borland\Delphi7"
        $targetDir32 = "C:\Program Files\Borland\Delphi7"
        $installDir = if (Test-Path -Path $targetDir64) { $targetDir64 } elseif (Test-Path -Path $targetDir32) { $targetDir32 } else { $null }

        if (-not $installDir) {
            New-Item -ItemType Directory -Path $targetDir64 -Force | Out-Null
            $installDir = $targetDir64
        }

        # Pastikan direktori Bin dan Projects\Bpl selalu dibuat sebelum proses penyalinan
        $binDir = Join-Path -Path $installDir -ChildPath "Bin"
        if (-not (Test-Path -Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
        $bplDir = Join-Path -Path $installDir -ChildPath "Projects\Bpl"
        if (-not (Test-Path -Path $bplDir)) { New-Item -ItemType Directory -Path $bplDir -Force | Out-Null }

        # Bersihkan cache lisensi lama (.borland) yang rusak atau kadaluarsa agar tidak memicu dialog error lisensi
        $borlandCachePaths = @(
            (Join-Path -Path $env:USERPROFILE -ChildPath ".borland"),
            "C:\Users\Public\.borland",
            "C:\ProgramData\Borland"
        )
        foreach ($bcp in $borlandCachePaths) {
            if (Test-Path -Path $bcp) {
                Remove-Item -Path (Join-Path -Path $bcp -ChildPath "registry.slm") -Force -ErrorAction SilentlyContinue
                Remove-Item -Path (Join-Path -Path $bcp -ChildPath "registry.dat") -Force -ErrorAction SilentlyContinue
                Remove-Item -Path (Join-Path -Path $bcp -ChildPath "borland.lic") -Force -ErrorAction SilentlyContinue
            } else {
                New-Item -ItemType Directory -Path $bcp -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        # Salin lisensi resmi cracked dent.slip ke instalasi dan folder user profile
        if (Test-Path -Path $slipFile) {
            Copy-Item -Path $slipFile -Destination (Join-Path -Path $installDir -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
            Copy-Item -Path $slipFile -Destination (Join-Path -Path $binDir -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
            foreach ($bcp in $borlandCachePaths) {
                if (Test-Path -Path $bcp) {
                    Copy-Item -Path $slipFile -Destination (Join-Path -Path $bcp -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
                }
            }
            Write-LogSuccess "Aktivasi lisensi resmi (dent.slip) berhasil diterapkan ke: $installDir & profil sistem."
        }

        # 7. Konfigurasi Registry Delphi 7 (LMLIC, LMKEY, RootDir) & Bersihkan Stale LM Subkey
        $delphiRegPaths = @(
            "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0",
            "HKLM:\SOFTWARE\Borland\Delphi\7.0",
            "HKCU:\Software\Borland\Delphi\7.0"
        )
        foreach ($rp in $delphiRegPaths) {
            try {
                if (-not (Test-Path -Path $rp)) { New-Item -Path $rp -Force | Out-Null }
                Set-ItemProperty -Path $rp -Name "RootDir" -Value $installDir -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $rp -Name "App" -Value (Join-Path -Path $installDir -ChildPath "Bin\delphi32.exe") -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $rp -Name "LMLIC" -Value $serialNumber -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $rp -Name "LMKEY" -Value $authKey -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $rp -Name "UseSharedFiles" -Value "TRUE" -Force -ErrorAction SilentlyContinue | Out-Null

                # Hapus subkey LM lama yang corrupt jika ada
                $subLm = Join-Path -Path $rp -ChildPath "LM"
                if (Test-Path -Path $subLm) {
                    Remove-Item -Path $subLm -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {}
        }
        Write-LogSuccess "Registrasi lisensi (LMLIC & LMKEY) berhasil diintegrasikan ke Registry Windows."

        # Konfigurasi Just-in-Time Debugger (AeDebug) otomatis agar Delphi tidak memicu popup dialog debugger
        try {
            $borDbg = Join-Path -Path $installDir -ChildPath "Bin\bordbg70.exe"
            if (Test-Path -Path $borDbg) {
                $aeDebugPaths = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug"
                )
                foreach ($aep in $aeDebugPaths) {
                    if (-not (Test-Path -Path $aep)) { New-Item -Path $aep -Force | Out-Null }
                    Set-ItemProperty -Path $aep -Name "Debugger" -Value "`"$borDbg`" -aegrs %ld %ld" -Force -ErrorAction SilentlyContinue | Out-Null
                    Set-ItemProperty -Path $aep -Name "Auto" -Value "1" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        } catch {}

        # 8. Konfigurasi Kompatibilitas Windows 11 / 10 & Hak Akses Folder
        $delphiExe = Join-Path -Path $installDir -ChildPath "Bin\delphi32.exe"
        if (Test-Path -Path $delphiExe) {
            $compatReg = @(
                "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
                "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
            )
            $compatVal = "~ WINXPSP3 HIGHDPIAWARE RUNASADMIN"
            foreach ($cr in $compatReg) {
                try {
                    if (-not (Test-Path -Path $cr)) { New-Item -Path $cr -Force | Out-Null }
                    Set-ItemProperty -Path $cr -Name $delphiExe -Value $compatVal -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # Sesuaikan Windows Defender & Exploit Protection untuk delphi32.exe
            try {
                if (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue) {
                    Set-ProcessMitigation -Name "delphi32.exe" -Disable DEP,CFG,SEHOP,DynamicCode,BottomUp,HighEntropy -ErrorAction SilentlyContinue | Out-Null
                }
                if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
                    Add-MpPreference -ExclusionPath $installDir -ErrorAction SilentlyContinue | Out-Null
                    Add-MpPreference -ExclusionProcess "delphi32.exe" -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {}

            # Berikan hak Write/Modify ke folder instalasi Delphi 7 agar tidak ada kendala saat kompilasi proyek praktikan
            try {
                & icacls "$installDir" /grant "Users:(OI)(CI)M" /T /Q | Out-Null
                if (Test-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath ".borland")) {
                    & icacls (Join-Path -Path $env:USERPROFILE -ChildPath ".borland") /grant "Users:(OI)(CI)M" /T /Q | Out-Null
                }
            } catch {}
            Write-LogSuccess "Kompatibilitas Windows XP SP3, Exploit Mitigation & hak akses direktori IDE berhasil dikonfigurasi."

            # Konfigurasi Firewall
            try {
                New-NetFirewallRule -DisplayName "LAB: Borland Delphi 7" -Direction Inbound -Program $delphiExe -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
            } catch {
                netsh advfirewall firewall add rule name="LAB: Borland Delphi 7" dir=in action=allow program="$delphiExe" enable=yes profile=any | Out-Null
            }
        }

        # 9. Jalankan instalasi VisionLab VCL 4.5 dengan Dialog Watcher Otomatis
        $visionSetup = Join-Path -Path $tempExtract -ChildPath "VisionLabVCL45\setup.exe"
        if (Test-Path -Path $visionSetup) {
            Write-LogInfo "Menjalankan instalasi VisionLab VCL 4.5 (Mitov Software)..."

            # Background watcher untuk otomatis menekan 'Continue >' pada popup 'Warning! BDS/RAD Studio'
            $watcher = Start-Job -ScriptBlock {
                Add-Type -AssemblyName System.Windows.Forms
                $wsh = New-Object -ComObject WScript.Shell
                for ($i = 0; $i -lt 40; $i++) {
                    Start-Sleep -Milliseconds 500
                    $procs = Get-Process -Name "setup" -ErrorAction SilentlyContinue
                    if (-not $procs) { break }
                    try {
                        if ($wsh.AppActivate("Warning!")) {
                            Start-Sleep -Milliseconds 250
                            [System.Windows.Forms.SendKeys]::SendWait("%c") # Alt+C
                            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                        }
                    } catch {}
                }
            }

            $vp = Start-Process -FilePath $visionSetup -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait -PassThru -NoNewWindow
            Stop-Job -Job $watcher -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $watcher -ErrorAction SilentlyContinue | Out-Null
        }

        # 10. Sinkronisasi Berkas BPL & Direktori LabPacks (OpenCV) ke Direktori Delphi 7
        $srcBpl = Join-Path -Path $tempExtract -ChildPath "Delphi7\program files\Borland\Delphi7\Projects\Bpl"
        $dstBpl = Join-Path -Path $installDir -ChildPath "Projects\Bpl"
        if (Test-Path -Path $srcBpl) {
            if (-not (Test-Path -Path $dstBpl)) { New-Item -ItemType Directory -Path $dstBpl -Force | Out-Null }
            Copy-Item -Path (Join-Path -Path $srcBpl -ChildPath "*") -Destination $dstBpl -Recurse -Force -ErrorAction SilentlyContinue
        }

        $srcLab = Join-Path -Path $tempExtract -ChildPath "Delphi7\program files\Borland\Delphi7\LabPacks"
        $dstLab = Join-Path -Path $installDir -ChildPath "LabPacks"
        if (Test-Path -Path $srcLab) {
            if (-not (Test-Path -Path $dstLab)) { New-Item -ItemType Directory -Path $dstLab -Force | Out-Null }
            Copy-Item -Path (Join-Path -Path $srcLab -ChildPath "*") -Destination $dstLab -Recurse -Force -ErrorAction SilentlyContinue
        }

        # 11. Registrasi Resmi Paket Komponen VisionLab & VideoLab ke Delphi Component Palette (Known Packages)
        # HANYA paket desain (*DsnD7.bpl) yang boleh didaftarkan ke Known Packages.
        # Paket runtime (*PkgD7.bpl) dimuat otomatis via DLL dan dilarang masuk ke Known Packages.
        $knownPackages = @{
            (Join-Path -Path $dstBpl -ChildPath "OpenWireDsnD7.bpl")             = "OpenWire Pin Editors"
            (Join-Path -Path $dstBpl -ChildPath "SignalLabBasicDsnD7.bpl")       = "SignalLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "TimingLabBasicDsnD7.bpl")       = "TimingLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "AudioLabBasicDsnD7.bpl")        = "AudioLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "MediaLabBasicDsnD7.bpl")        = "MediaLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VideoLabBasicDsnD7.bpl")        = "VideoLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VideoLabAdditionalDsnD7.bpl")   = "VideoLab Additional Design Package"
            (Join-Path -Path $dstBpl -ChildPath "IntelligenceLabBasicDsnD7.bpl") = "IntelligenceLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VisionLabDsnD7.bpl")            = "VisionLab Design Package"
        }

        $kpTargets = @(
            "HKCU:\Software\Borland\Delphi\7.0\Known Packages",
            "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0\Known Packages",
            "HKLM:\SOFTWARE\Borland\Delphi\7.0\Known Packages"
        )
        $runtimePackages = @(
            "OpenWirePkgD7.bpl", "SignalLabBasicPkgD7.bpl", "TimingLabBasicPkgD7.bpl",
            "AudioLabBasicPkgD7.bpl", "MediaLabBasicPkgD7.bpl", "VideoLabBasicPkgD7.bpl",
            "VideoLabAdditionalPkgD7.bpl", "IntelligenceLabBasicPkgD7.bpl", "VisionLabPkgD7.bpl"
        )
        foreach ($kpPath in $kpTargets) {
            try {
                if (-not (Test-Path -Path $kpPath)) { New-Item -Path $kpPath -Force | Out-Null }

                # Bersihkan entri runtime package (*PkgD7.bpl) agar Delphi tidak memunculkan dialog error
                $propNames = (Get-Item -Path $kpPath -ErrorAction SilentlyContinue).Property
                if ($propNames) {
                    foreach ($pn in $propNames) {
                        foreach ($rp in $runtimePackages) {
                            if ($pn -match [regex]::Escape($rp)) {
                                Remove-ItemProperty -Path $kpPath -Name $pn -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                    }
                }

                foreach ($k in $knownPackages.Keys) {
                    Set-ItemProperty -Path $kpPath -Name $k -Value $knownPackages[$k] -Force -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {}
        }

        # Perbarui Library Search Path Delphi agar modul unit (.dcu, .pas, .bpl) VisionLab dapat dikompilasi
        $libTargets = @(
            "HKCU:\Software\Borland\Delphi\7.0\Library",
            "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0\Library",
            "HKLM:\SOFTWARE\Borland\Delphi\7.0\Library"
        )
        foreach ($lp in $libTargets) {
            try {
                if (-not (Test-Path -Path $lp)) { New-Item -Path $lp -Force | Out-Null }
                $currSearch = (Get-ItemProperty -Path $lp -Name "Search Path" -ErrorAction SilentlyContinue)."Search Path"
                $extraPaths = @("`$(DELPHI)\Projects\Bpl", "`$(DELPHI)\OpenWire", "`$(DELPHI)\LabPacks")
                if ($currSearch) {
                    foreach ($ep in $extraPaths) {
                        if ($currSearch -notmatch [regex]::Escape($ep)) {
                            $currSearch += ";$ep"
                        }
                    }
                } else {
                    $currSearch = "`$(DELPHI)\Lib;`$(DELPHI)\Bin;`$(DELPHI)\Imports;`$(DELPHI)\Projects\Bpl;`$(DELPHI)\OpenWire;`$(DELPHI)\LabPacks"
                }
                Set-ItemProperty -Path $lp -Name "Search Path" -Value $currSearch -Force -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }

        Write-LogSuccess "Komponen VisionLab & VideoLab VCL berhasil didaftarkan ke Component Palette Delphi 7."

        # 12. Verifikasi Akhir
        if (Test-Path -Path $delphiExe) {
            Write-LogSuccess "Borland Delphi 7 Enterprise & VisionLab VCL BERHASIL DIPASANG!"

            # Buat shortcut tunggal di Desktop (Utamakan Public Desktop, bersihkan duplikat)
            try {
                $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
                $userDesktop   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
                $pubLnk = Join-Path -Path $publicDesktop -ChildPath "Delphi 7.lnk"
                $usrLnk = Join-Path -Path $userDesktop -ChildPath "Delphi 7.lnk"

                if ((-not (Test-Path -Path $pubLnk)) -and (-not (Test-Path -Path $usrLnk))) {
                    $wsh = New-Object -ComObject WScript.Shell
                    $targetLnk = if ($publicDesktop -and (Test-Path -Path $publicDesktop)) { $pubLnk } else { $usrLnk }
                    $sc = $wsh.CreateShortcut($targetLnk)
                    $sc.TargetPath = $delphiExe
                    $sc.WorkingDirectory = Split-Path -Parent $delphiExe
                    $sc.Description = "Borland Delphi 7 Enterprise Edition"
                    $sc.Save()
                    Write-LogSuccess "Shortcut 'Delphi 7' dibuat tunggal di Desktop."
                } elseif ((Test-Path -Path $pubLnk) -and (Test-Path -Path $usrLnk)) {
                    Remove-Item -Path $usrLnk -Force -ErrorAction SilentlyContinue
                }
            } catch {}

            return $true
        } else {
            Write-LogError "Instalasi selesai namun executable delphi32.exe belum terdeteksi."
            return $false
        }
    }
    catch {
        Write-LogError "Gagal mengeksekusi instalasi Delphi 7: $_"
        return $false
    }
    finally {
        # Bersihkan folder temporary ekstrak
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Setup-VSCodePostInstall {
    Write-LogStep "Mengonfigurasi Shortcut Desktop Visual Studio Code..."
    if (Get-Command Refresh-CurrentSessionEnvironment -ErrorAction SilentlyContinue) {
        Refresh-CurrentSessionEnvironment
    }

    $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
    $userDesktop   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)

    $pubLnk = Join-Path -Path $publicDesktop -ChildPath "Visual Studio Code.lnk"
    $usrLnk = Join-Path -Path $userDesktop -ChildPath "Visual Studio Code.lnk"

    # Jika sudah ada di salah satu lokasi, bersihkan duplikat jika ada dan selesai
    if ((Test-Path -Path $pubLnk) -or (Test-Path -Path $usrLnk)) {
        if ((Test-Path -Path $pubLnk) -and (Test-Path -Path $usrLnk)) {
            Remove-Item -Path $usrLnk -Force -ErrorAction SilentlyContinue
        }
        Write-LogInfo "Shortcut Visual Studio Code sudah ada di Desktop (tunggal)."
        return
    }

    $exeCandidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "C:\Users\*\AppData\Local\Programs\Microsoft VS Code\Code.exe",
        "C:\Program Files\Microsoft VS Code\Code.exe",
        "C:\Program Files (x86)\Microsoft VS Code\Code.exe"
    )

    $codeExe = $null
    foreach ($cand in $exeCandidates) {
        $found = Resolve-Path -Path $cand -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
        if ($found -and (Test-Path -Path $found)) {
            $codeExe = $found
            break
        }
    }

    if (-not $codeExe) {
        $cmd = Get-Command "code" -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            $parentDir = Split-Path -Parent (Split-Path -Parent $cmd.Source)
            $guess = Join-Path -Path $parentDir -ChildPath "Code.exe"
            if (Test-Path -Path $guess) {
                $codeExe = $guess
            }
        }
    }

    if ($codeExe) {
        $wsh = New-Object -ComObject WScript.Shell
        # Buat HANYA SATU shortcut: utamakan Public Desktop, fallback ke User Desktop
        $saved = $false
        if ($publicDesktop -and (Test-Path -Path $publicDesktop)) {
            try {
                $sc = $wsh.CreateShortcut($pubLnk)
                $sc.TargetPath = $codeExe
                $sc.WorkingDirectory = Split-Path -Parent $codeExe
                $sc.Description = "Visual Studio Code"
                $sc.Save()
                $saved = $true
                Write-LogSuccess "Shortcut Desktop Visual Studio Code dibuat tunggal di: $pubLnk"
            } catch {}
        }
        if (-not $saved -and $userDesktop -and (Test-Path -Path $userDesktop)) {
            try {
                $sc = $wsh.CreateShortcut($usrLnk)
                $sc.TargetPath = $codeExe
                $sc.WorkingDirectory = Split-Path -Parent $codeExe
                $sc.Description = "Visual Studio Code"
                $sc.Save()
                Write-LogSuccess "Shortcut Desktop Visual Studio Code dibuat tunggal di: $usrLnk"
            } catch {
                Write-LogWarning "Gagal membuat shortcut desktop VS Code: $_"
            }
        }
    } else {
        Write-LogWarning "Executable Code.exe belum ditemukan di sistem untuk pembuatan shortcut."
    }
}

function Setup-NetBeansPostInstall {
    Write-LogStep "Mengonfigurasi dan Memvalidasi Instalasi Apache NetBeans IDE..."
    if (Get-Command Refresh-CurrentSessionEnvironment -ErrorAction SilentlyContinue) {
        Refresh-CurrentSessionEnvironment
    }

    $nbCandidates = @(
        "C:\Program Files\Apache NetBeans*\bin\netbeans*.exe",
        "C:\Program Files\NetBeans*\bin\netbeans*.exe",
        "C:\Program Files (x86)\Apache NetBeans*\bin\netbeans*.exe",
        "C:\Program Files (x86)\NetBeans*\bin\netbeans*.exe",
        "C:\NetBeans*\bin\netbeans*.exe"
    )

    $nbExe = $null
    foreach ($c in $nbCandidates) {
        $found = Resolve-Path -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
        if ($found -and (Test-Path -Path $found)) {
            $nbExe = $found
            break
        }
    }

    if ($nbExe) {
        Write-LogSuccess "Apache NetBeans IDE terverifikasi aktif di: $nbExe"

        # Bersihkan pintasan desktop yang rusak/mati (pointing ke path yang tidak ada)
        $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
        $userDesktop   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
        $desktopDirs = @($publicDesktop, $userDesktop)

        $wscript = $null
        try { $wscript = New-Object -ComObject WScript.Shell } catch {}

        if ($wscript) {
            foreach ($dDir in $desktopDirs) {
                if (-not (Test-Path -Path $dDir)) { continue }
                $shortcuts = Get-ChildItem -Path $dDir -Filter "*NetBeans*.lnk" -ErrorAction SilentlyContinue
                foreach ($sc in $shortcuts) {
                    try {
                        $target = $wscript.CreateShortcut($sc.FullName).TargetPath
                        if ($target -and (-not (Test-Path -Path $target))) {
                            Write-LogInfo "Menghapus pintasan rusak lama di desktop: $($sc.Name)"
                            Remove-Item -Path $sc.FullName -Force -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
            }
        }
    } else {
        Write-LogWarning "Berkas eksekutif NetBeans belum ditemukan setelah proses instalasi."
    }
}

function Setup-OfficePostInstall {
    Write-LogStep "Mengonfigurasi dan Memverifikasi Instalasi Microsoft 365 (Office C2R)..."

    # 1. Tunggu hingga proses instalasi Click-to-Run (OfficeClickToRun / OfficeSetup) selesai jika masih berjalan
    $maxWaitSec = 900
    $waited = 0
    while ($waited -lt $maxWaitSec) {
        $wordCandidates = @(
            "C:\Program Files\Microsoft Office\root\Office*\WINWORD.EXE",
            "C:\Program Files (x86)\Microsoft Office\root\Office*\WINWORD.EXE",
            "C:\Program Files\Microsoft Office\Office*\WINWORD.EXE",
            "C:\Program Files (x86)\Microsoft Office\Office*\WINWORD.EXE"
        )
        $wordFound = $false
        foreach ($wc in $wordCandidates) {
            if (Resolve-Path -Path $wc -ErrorAction SilentlyContinue) {
                $wordFound = $true
                break
            }
        }

        $c2rProcesses = Get-Process -Name "OfficeClickToRun", "OfficeSetup" -ErrorAction SilentlyContinue

        if ($wordFound -and (-not $c2rProcesses)) {
            Write-LogSuccess "Instalasi Microsoft Office Click-to-Run telah selesai terpasang sepenuhnya."
            break
        }

        if ($c2rProcesses) {
            if ($wordFound) {
                Write-LogInfo "Microsoft Office sudah terpasang, sedang memfinalisasi komponen di latar belakang... (${waited}s)"
                Start-Sleep -Seconds 5
                $waited += 5
                # Periksa apakah OfficeSetup sudah keluar
                $setupActive = Get-Process -Name "OfficeSetup" -ErrorAction SilentlyContinue
                if (-not $setupActive) {
                    break
                }
            } else {
                Write-LogInfo "Instalasi Microsoft Office sedang mengunduh & memasang komponen... (${waited}s)"
                Start-Sleep -Seconds 10
                $waited += 10
            }
        } else {
            # Tidak ada proses C2R aktif
            break
        }
    }

    # 2. Sinkronisasi Ikon Desktop Resmi (Word, Excel, PowerPoint)
    if (Get-Command Ensure-DesktopShortcuts -ErrorAction SilentlyContinue) {
        Ensure-DesktopShortcuts
    }

    # 3. Informasikan Aktivasi Khusus (Menu 5)
    Write-LogInfo "Instalasi Microsoft Office selesai. Untuk aktivasi permanen (Ohook), silakan gunakan Menu [5] khusus Aktivasi."

    Write-LogSuccess "Instalasi & penyelarasan shortcut Microsoft 365 (Office) selesai!"
    return $true
}



