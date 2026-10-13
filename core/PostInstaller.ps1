# ==============================================================================
# LABInstaller - Core PostInstaller & Custom Tooling Handlers
# Logika khusus untuk Java (JAVA_HOME), Python, PHP, Composer, Laravel, Flutter SDK
# ==============================================================================

function Setup-PythonEnvironment {
    Write-LogStep "Mengonfigurasi environment Python..."
    Refresh-CurrentSessionEnvironment

    # Cari instalasi Python
    $pythonCmd = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $pythonDir = Split-Path -Parent $pythonCmd.Source
        $scriptsDir = Join-Path -Path $pythonDir -ChildPath "Scripts"

        Add-DirectoryToPath -PathToAdd $pythonDir -Scope "Machine" | Out-Null
        if (Test-Path -Path $scriptsDir) {
            Add-DirectoryToPath -PathToAdd $scriptsDir -Scope "Machine" | Out-Null
        }
        Write-LogSuccess "Environment Python & Pip berhasil dikonfigurasi."
    }
}

function Setup-JavaEnvironment {
    Write-LogStep "Mengonfigurasi JAVA_HOME dan PATH untuk Java SDK..."
    Refresh-CurrentSessionEnvironment

    # Deteksi folder JDK di Program Files
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
        # Fallback via Get-Command java
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
    Write-LogStep "Mengonfigurasi environment PHP & php.ini..."
    Refresh-CurrentSessionEnvironment

    $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
    $phpDir = $null

    if ($phpCmd) {
        $phpDir = Split-Path -Parent $phpCmd.Source
    } else {
        # Coba cari lokasi winget portable package untuk PHP
        $wingetPackagesRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        if (Test-Path -Path $wingetPackagesRoot) {
            $phpCandidate = Get-ChildItem -Path $wingetPackagesRoot -Recurse -Filter "php.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($phpCandidate) {
                $phpDir = Split-Path -Parent $phpCandidate.FullName
                Add-DirectoryToPath -PathToAdd $phpDir -Scope "Machine" | Out-Null
            }
        }
    }

    if ($phpDir) {
        # Pastikan php.ini ada dan ekstensi dasar aktif
        $iniPath = Join-Path -Path $phpDir -ChildPath "php.ini"
        $iniDevPath = Join-Path -Path $phpDir -ChildPath "php.ini-development"
        $iniProdPath = Join-Path -Path $phpDir -ChildPath "php.ini-production"

        if (-not (Test-Path -Path $iniPath)) {
            $srcIni = if (Test-Path -Path $iniDevPath) { $iniDevPath } elseif (Test-Path -Path $iniProdPath) { $iniProdPath } else { $null }
            if ($srcIni) {
                Copy-Item -Path $srcIni -Destination $iniPath -Force
                Write-LogInfo "Membuat php.ini dari $($srcIni | Split-Path -Leaf)..."
                
                # Mengaktifkan ekstensi penting: curl, mbstring, openssl, pdo_mysql, fileinfo
                $content = Get-Content -Path $iniPath -Raw
                $content = $content -replace ';extension=curl', 'extension=curl'
                $content = $content -replace ';extension=mbstring', 'extension=mbstring'
                $content = $content -replace ';extension=openssl', 'extension=openssl'
                $content = $content -replace ';extension=pdo_mysql', 'extension=pdo_mysql'
                $content = $content -replace ';extension=fileinfo', 'extension=fileinfo'
                Set-Content -Path $iniPath -Value $content -Encoding UTF8
                Write-LogSuccess "Ekstensi penting (curl, mbstring, openssl, pdo_mysql, fileinfo) telah diaktifkan di php.ini."
            }
        }
        Write-LogSuccess "PHP berhasil dikonfigurasi di: $phpDir"
    }
}

function Install-ComposerOfficial {
    Write-LogStep "Mengunduh & Menginstal Composer resmi untuk Windows..."
    Refresh-CurrentSessionEnvironment

    $tempDir = [System.IO.Path]::GetTempPath()
    $installerPath = Join-Path -Path $tempDir -ChildPath "Composer-Setup.exe"
    $composerUrl = "https://getcomposer.org/Composer-Setup.exe"

    try {
        Write-LogInfo "Mengunduh installer dari: $composerUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object System.Net.WebClient).DownloadFile($composerUrl, $installerPath)

        Write-LogInfo "Menjalankan Composer-Setup.exe secara silent..."
        $process = Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /ALLUSERS" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-LogSuccess "Composer berhasil diinstal secara resmi."
            # Daftarkan direktori Composer ke PATH
            $composerBin = "C:\ProgramData\ComposerSetup\bin"
            if (Test-Path -Path $composerBin) {
                Add-DirectoryToPath -PathToAdd $composerBin -Scope "Machine" | Out-Null
            }
            Refresh-CurrentSessionEnvironment
            return $true
        } else {
            Write-LogError "Installer Composer selesai dengan kode keluar: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Gagal menginstal Composer: $_"
        return $false
    }
    finally {
        if (Test-Path -Path $installerPath) {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-LaravelInstallerOfficial {
    Write-LogStep "Menginstal Laravel Installer resmi via Composer Global..."
    Refresh-CurrentSessionEnvironment

    $composerCmd = Get-Command "composer" -ErrorAction SilentlyContinue
    if (-not $composerCmd) {
        Write-LogError "Composer belum terdeteksi. Silakan instal Composer terlebih dahulu."
        return $false
    }

    try {
        Write-LogInfo "Menjalankan: composer global require laravel/installer"
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c composer global require laravel/installer" -NoNewWindow -Wait -PassThru

        # Tambahkan folder Composer global vendor bin ke PATH pengguna/sistem
        $composerGlobalBin = Join-Path -Path $env:APPDATA -ChildPath "Composer\vendor\bin"
        if (Test-Path -Path $composerGlobalBin) {
            Add-DirectoryToPath -PathToAdd $composerGlobalBin -Scope "User" | Out-Null
        }

        Refresh-CurrentSessionEnvironment
        Write-LogSuccess "Laravel Installer berhasil diinstal dan didaftarkan ke sistem PATH."
        return $true
    }
    catch {
        Write-LogError "Gagal menginstal Laravel Installer: $_"
        return $false
    }
}

function Install-FlutterSdkOfficial {
    param (
        [string]$TargetDir = "C:\tools\flutter"
    )

    Write-LogStep "Menginstal Flutter SDK (Channel Stable) resmi..."
    Refresh-CurrentSessionEnvironment

    # Cek ketersediaan Git
    $gitCmd = Get-Command "git" -ErrorAction SilentlyContinue

    if (Test-Path -Path (Join-Path -Path $TargetDir -ChildPath "bin\flutter.bat")) {
        Write-LogInfo "Flutter SDK sudah ada di $TargetDir. Memeriksa pembaruan..."
        $binDir = Join-Path -Path $TargetDir -ChildPath "bin"
        Add-DirectoryToPath -PathToAdd $binDir -Scope "Machine" | Out-Null
        
        Write-LogInfo "Menjalankan flutter upgrade..."
        Start-Process -FilePath (Join-Path -Path $binDir -ChildPath "flutter.bat") -ArgumentList "upgrade" -NoNewWindow -Wait
        Write-LogSuccess "Flutter SDK berhasil diperbarui."
        return $true
    }

    if ($gitCmd) {
        try {
            $parentDir = Split-Path -Parent $TargetDir
            if (-not (Test-Path -Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }

            Write-LogInfo "Mengkloning Flutter repository resmi ke: $TargetDir"
            $gitProcess = Start-Process -FilePath $gitCmd.Source -ArgumentList "clone -b stable https://github.com/flutter/flutter.git `"$TargetDir`"" -NoNewWindow -Wait -PassThru

            if ($gitProcess.ExitCode -eq 0) {
                $binDir = Join-Path -Path $TargetDir -ChildPath "bin"
                Add-DirectoryToPath -PathToAdd $binDir -Scope "Machine" | Out-Null
                Refresh-CurrentSessionEnvironment
                Write-LogSuccess "Flutter SDK berhasil diinstal via Git Clone resmi."
                return $true
            } else {
                Write-LogError "Git clone Flutter gagal dengan kode: $($gitProcess.ExitCode)"
                return $false
            }
        }
        catch {
            Write-LogError "Gagal menginstal Flutter via Git: $_"
            return $false
        }
    } else {
        Write-LogError "Git diperlukan untuk instalasi resmi Flutter SDK. Mohon instal Git terlebih dahulu."
        return $false
    }
}

