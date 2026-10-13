# ==============================================================================
# LABInstaller - Core PostInstaller & Custom Tooling Handlers
# Logika khusus untuk Java (JAVA_HOME), Python, PHP, Composer, Laravel, Flutter, Laragon, XAMPP
# ==============================================================================

function Setup-PythonEnvironment {
    Write-LogStep "Mengonfigurasi environment Python..."
    Refresh-CurrentSessionEnvironment

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

    $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
    $phpDir = $null

    if ($phpCmd) {
        $phpDir = Split-Path -Parent $phpCmd.Source
    } else {
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

    # Jalankan konfigurasi ekstensi lengkap
    if (Get-Command Configure-AllPhpExtensions -ErrorAction SilentlyContinue) {
        Configure-AllPhpExtensions
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
        Write-LogError "Gagal menginstal Composer - $_"
        return $false
    }
    finally {
        if (Test-Path -Path $installerPath) {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-LaravelInstallerOfficial {
    Write-LogStep "Menginstal Laravel Installer CLI via Composer Global..."
    Refresh-CurrentSessionEnvironment

    $composerCmd = Get-Command "composer" -ErrorAction SilentlyContinue
    if (-not $composerCmd) {
        Write-LogError "Composer belum terdeteksi. Silakan instal Composer terlebih dahulu."
        return $false
    }

    try {
        Write-LogInfo "Menjalankan: composer global require laravel/installer"
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c composer global require laravel/installer" -NoNewWindow -Wait -PassThru

        $composerGlobalBin = Join-Path -Path $env:APPDATA -ChildPath "Composer\vendor\bin"
        if (Test-Path -Path $composerGlobalBin) {
            Add-DirectoryToPath -PathToAdd $composerGlobalBin -Scope "User" | Out-Null
        }

        Refresh-CurrentSessionEnvironment
        Write-LogSuccess "Laravel Installer berhasil diinstal (laravel new ... siap digunakan)."
        return $true
    }
    catch {
        Write-LogError "Gagal menginstal Laravel Installer - $_"
        return $false
    }
}

function Install-FlutterSdkOfficial {
    param (
        [string]$TargetDir = "C:\tools\flutter"
    )

    Write-LogStep "Menginstal Flutter SDK (Channel Stable) resmi..."
    Refresh-CurrentSessionEnvironment

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
            Write-LogError "Gagal menginstal Flutter via Git - $_"
            return $false
        }
    } else {
        Write-LogError "Git diperlukan untuk instalasi resmi Flutter SDK. Mohon instal Git terlebih dahulu."
        return $false
    }
}

function Install-LaragonOfficial {
    Write-LogStep "Mengunduh & Menginstal Laragon 6.0.0 Resmi..."
    Refresh-CurrentSessionEnvironment

    $laragonExe = "C:\laragon\laragon.exe"
    if (Test-Path -Path $laragonExe) {
        Write-LogSuccess "Laragon 6.0.0 sudah terpasang di C:\laragon."
        return $true
    }

    $tempInstaller = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "laragon-wamp.exe"
    $laragonUrl = "https://github.com/leokhoa/laragon/releases/download/6.0.0/laragon-wamp.exe"

    try {
        Write-LogInfo "Mengunduh Laragon 6.0.0 dari GitHub: $laragonUrl..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "LABInstaller")
        $webClient.DownloadFile($laragonUrl, $tempInstaller)

        Write-LogInfo "Memasang Laragon 6.0.0 ke C:\laragon..."
        $process = Start-Process -FilePath $tempInstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"C:\laragon`"" -NoNewWindow -Wait -PassThru

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
    finally {
        if (Test-Path -Path $tempInstaller) {
            Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue
        }
    }
}

function Setup-LaragonEnvironment {
    Write-LogStep "Menyiapkan integrasi lingkungan Laragon..."
    
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
    } catch {}
}

function Setup-XamppEnvironment {
    Write-LogStep "Menyiapkan integrasi XAMPP & pencegahan bentrok port dengan Laragon..."
    if (Get-Command Configure-WebServerPorts -ErrorAction SilentlyContinue) {
        Configure-WebServerPorts
    }
}
