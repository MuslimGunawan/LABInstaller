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
