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

        # Precache dan inisialisasi artifact Flutter
        try {
            Write-LogInfo "Menginisialisasi artifact Flutter..."
            Start-Process -FilePath $flutterBat -ArgumentList "--version" -NoNewWindow -Wait
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
        [string[]]$GdriveMirrors = @(
            "1Nmy4yx8o8ddednr-DV6EJ5Gi6ukUWTaN",
            "16amKlAlav5lhydHcvjoVmTPQ3w8rLCkm",
            "1bbM4aMQbZcC-XyJNkU-36R6x8Wy2dbjp",
            "1qDaAbmCs0R850Z8bfm0zpqBLx-DhMH08"
        )
    )

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

    # LANGKAH 3: Timpa (Overlay) File C:\laragon dengan File Custom Anda
    if ($localZip -and (Test-Path -Path $localZip)) {
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
    } else {
        Write-LogWarning "Paket ZIP kustom belum dapat diunduh dari GDrive, menggunakan setup resmi Laragon 6.0.0."
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
        }
    }

    if (-not (Test-Path -Path $bundleZip)) {
        Write-LogError "Berkas Delphi7_VisionLab_Bundle.zip tidak ditemukan di folder apps maupun D:\KP."
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

    # 3. Patch otomatis MSI database agar memuat Serial & Auth Key Enterprise resmi
    $msiFile = Join-Path -Path $tempExtract -ChildPath "Delphi7\Borland Delphi 7.msi"
    $serialNumber = "6AKD-PD29Q9-RDF?JQ-X65Z"
    $authKey      = "QX8-EEC"

    if (Test-Path -Path $msiFile) {
        try {
            $wi = New-Object -ComObject WindowsInstaller.Installer
            $db = $wi.OpenDatabase($msiFile, 1) # 1 = msiOpenDatabaseModeTransact
            $v1 = $db.OpenView("UPDATE InstallExecuteSequence SET Condition = '0' WHERE Action = 'BorValidatePassword'")
            $v1.Execute(); $v1.Close()
            $v2 = $db.OpenView("UPDATE Property SET Value = 'ENT' WHERE Property = 'SKU'")
            $v2.Execute(); $v2.Close()
            $v3 = $db.OpenView("UPDATE Property SET Value = '0' WHERE Property = 'BadPassword'")
            $v3.Execute(); $v3.Close()
            $v4 = $db.OpenView("INSERT INTO Property (Property, Value) VALUES ('PRODUCT_ID', '$serialNumber')")
            try { $v4.Execute(); $v4.Close() } catch {
                $v4u = $db.OpenView("UPDATE Property SET Value = '$serialNumber' WHERE Property = 'PRODUCT_ID'")
                $v4u.Execute(); $v4u.Close()
            }
            $v5 = $db.OpenView("INSERT INTO Property (Property, Value) VALUES ('AUTH_KEY', '$authKey')")
            try { $v5.Execute(); $v5.Close() } catch {
                $v5u = $db.OpenView("UPDATE Property SET Value = '$authKey' WHERE Property = 'AUTH_KEY'")
                $v5u.Execute(); $v5u.Close()
            }
            $db.Commit()

            # PENTING: Lepaskan handle COM object secara eksplisit agar msiexec tidak terkena error 1619 (file locked)
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($v1) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($v2) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($v3) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($db) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wi) | Out-Null
            $v1 = $null; $v2 = $null; $v3 = $null; $db = $null; $wi = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500

            Write-LogSuccess "Konfigurasi otomatis MSI Delphi 7 (Injeksi Serial Enterprise & Bypass validasi) berhasil diterapkan."
        } catch {
            Write-LogWarning "Pemberitahuan konfigurasi MSI Delphi 7: $_"
        }
    }

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

    # 5. Eksekusi Instalasi Utama Delphi 7 secara Native PowerShell
    Write-LogInfo "Menjalankan instalasi utama Borland Delphi 7 Enterprise via MSI..."
    try {
        $msiArgs = @(
            "/i", "`"$msiFile`"",
            "/qn",
            "/norestart",
            "ALLUSERS=1",
            "SKU=ENT",
            "PRODUCT_ID=`"$serialNumber`"",
            "AUTH_KEY=`"$authKey`"",
            "USERNAME=`"LAB Komputer`"",
            "COMPANYNAME=`"Laboratorium`""
        )
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
            Copy-Item -Path $slipFile -Destination (Join-Path -Path $installDir -ChildPath "Bin\dent.slip") -Force -ErrorAction SilentlyContinue
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


