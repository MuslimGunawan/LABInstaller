# ==============================================================================
# LABInstaller - UI Menu Interaktif (v1.0.1)
# Antarmuka konsol untuk instalasi pintar, scan cepat, konfigurasi port, & verifikasi file
# ==============================================================================

function Start-SmartInstallation {
    param (
        [string]$ScriptRootDirectory
    )

    # Deteksi dinamis: cek apakah ada residu web stack, service liar, atau PATH lama di drive mana pun
    $auditQuick = Find-LegacyLabStackLocations -Silent
    $hasLegacyStack = ($auditQuick.Services.Count -gt 0) -or 
                      ($auditQuick.Processes.Count -gt 0) -or 
                      ($auditQuick.DiscoveredPaths.Count -gt 0) -or 
                      ($auditQuick.PathPollutions.Count -gt 0)

    if ($hasLegacyStack) {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host " PERHATIAN: Terdeteksi residu web server / service / PATH lama!" -ForegroundColor Yellow
        Write-Host "   - Service Windows : $($auditQuick.Services.Count) service" -ForegroundColor DarkYellow
        Write-Host "   - Proses aktif    : $($auditQuick.Processes.Count) proses" -ForegroundColor DarkYellow
        Write-Host "   - Folder lama     : $($auditQuick.DiscoveredPaths.Count) lokasi (termasuk drive non-C)" -ForegroundColor DarkYellow
        Write-Host "   - Polusi PATH     : $($auditQuick.PathPollutions.Count) entri" -ForegroundColor DarkYellow
        Write-Host "   (Catatan: Clean Purge HANYA membersihkan web server & database lama. IDE seperti NetBeans/Arduino TIDAK disentuh)" -ForegroundColor Gray
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host ""
        $purgePrompt = Read-Host "Ingin jalankan CLEAN PURGE (Reset Fresh Web Server XAMPP/Laragon/PHP/MySQL)? (Y/N)"
        if ($purgePrompt -match '^(y|ya|yes)$') {
            Invoke-CleanPurgeLegacyLabStack -Force
        }
    }

    Write-LogStep "MEMULAI ANALISIS SISTEM & PINDAI CEPAT STATUS SOFTWARE..."
    $manifestPackages = Load-AllManifestPackages -ManifestDir (Join-Path -Path $ScriptRootDirectory -ChildPath "manifests")

    if ($manifestPackages.Count -eq 0) {
        Write-LogError "Tidak ada manifest paket yang ditemukan di folder 'manifests'."
        return
    }

    # Muat cache Registry Windows secara instan (offline & anti-hang)
    Initialize-RegistryCache -ForceRefresh | Out-Null

    Write-Host ""
    Write-Host "Memindai $($manifestPackages.Count) paket sesuai urutan prioritas dependensi..." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

    $scanResults = @()
    foreach ($pkg in $manifestPackages) {
        $status = Get-PackageStatus -Package $pkg
        $scanResults += $status

        $tagColor = switch ($status.Status) {
            "NOT_INSTALLED"    { [ConsoleColor]::Yellow }
            "UPDATE_AVAILABLE" { [ConsoleColor]::Magenta }
            "UP_TO_DATE"       { [ConsoleColor]::Green }
            Default            { [ConsoleColor]::White }
        }

        Write-Host " [P$($status.Priority)] " -NoNewline -ForegroundColor DarkCyan
        Write-Host "$($status.Name.PadRight(35)) : " -NoNewline -ForegroundColor Gray
        Write-Host "[$($status.Status)]" -ForegroundColor $tagColor
    }

    # Tampilkan Tabel Ringkasan
    Write-Host ""
    Write-Host "========================== RINGKASAN STATUS ==========================" -ForegroundColor Cyan
    $table = $scanResults | Select-Object @{Name="Prioritas"; Expression={"P" + $_.Priority}},
                                          @{Name="Software"; Expression={$_.Name}},
                                          @{Name="Kategori"; Expression={$_.Category}},
                                          @{Name="Status Tindakan"; Expression={
                                              switch ($_.Status) {
                                                  "NOT_INSTALLED"    { "Akan Diinstall" }
                                                  "UPDATE_AVAILABLE" { "Akan Ditukar/Update" }
                                                  "UP_TO_DATE"       { "Lewati (Sudah Pas)" }
                                                  Default            { $_.Status }
                                              }
                                          }},
                                          @{Name="Versi Terpasang"; Expression={$_.InstalledVersion}},
                                          @{Name="Versi Target"; Expression={$_.TargetVersion}}
    $table | Format-Table -AutoSize
    Write-Host "======================================================================" -ForegroundColor Cyan

    $needAction = $scanResults | Where-Object { $_.Status -ne "UP_TO_DATE" }
    if ($needAction.Count -eq 0) {
        Write-LogSuccess "SEMUA SOFTWARE SUDAH TERPASANG DAN UP-TO-DATE! Tidak ada instalasi baru yang diperlukan."
        
        # Tetap jalankan konfigurasi port dan environment
        Write-Host ""
        $cfgConfirm = Read-Host "Apakah ingin menjalankan optimasi konfigurasi port & php.ini sekarang? (Y/N)"
        if ($cfgConfirm -match '^(y|ya|yes)$') {
            Start-FullEnvironmentConfiguration
        }
        Write-Host ""
        Write-Host "Tekan Enter untuk kembali ke menu utama..." -ForegroundColor Gray
        [void][System.Console]::ReadLine()
        return
    }

    Write-Host ""
    $confirm = Read-Host "Apakah Anda ingin mengeksekusi instalasi pintar untuk $($needAction.Count) paket di atas? (Y/N)"
    if ($confirm -notmatch '^(y|ya|yes)$') {
        Write-LogWarning "Instalasi dibatalkan oleh pengguna."
        Start-Sleep -Seconds 2
        return
    }

    # Eksekusi Instalasi Sesuai Prioritas
    $successCount = 0
    $skipCount = 0
    $failCount = 0

    foreach ($item in $scanResults) {
        Write-Host ""
        if ($item.Status -eq "UP_TO_DATE") {
            Write-LogSkip "$($item.Name) sudah terpasang dengan versi pas ($($item.InstalledVersion)). Dilewati."
            $skipCount++
            continue
        }

        $raw = $item.RawPackage
        $isUpgrade = ($item.Status -eq "UPDATE_AVAILABLE")
        $success = $false

        $success = Invoke-PackageInstall -Package $raw -IsUpgrade:$isUpgrade

        # Jalankan post-install handler jika ada dan proses berhasil
        if ($success -and $raw.postInstallHandler) {
            $postHandler = $raw.postInstallHandler
            if (Get-Command $postHandler -ErrorAction SilentlyContinue) {
                & $postHandler
            }
        }

        if ($success) {
            $successCount++
        } else {
            $failCount++
        }
    }

    Refresh-CurrentSessionEnvironment

    # Konfigurasi otomatis port & environment pasca instalasi
    Write-Host ""
    Start-FullEnvironmentConfiguration

    Write-Host ""
    Write-Host "========================== HASIL INSTALASI PINTAR ==========================" -ForegroundColor Cyan
    Write-Host " Berhasil Diproses : $successCount" -ForegroundColor Green
    Write-Host " Dilewati (Pas)    : $skipCount" -ForegroundColor DarkYellow
    Write-Host " Gagal/Error       : $failCount" -ForegroundColor Red
    Write-Host " Log Lengkap       : $($global:LabLogFile)" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tekan Enter untuk kembali ke menu utama..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
}

function Show-SystemScanOnly {
    param ([string]$ScriptRootDirectory)

    Write-LogStep "PINDAI CEPAT STATUS SOFTWARE SAAT INI..."
    $manifestPackages = Load-AllManifestPackages -ManifestDir (Join-Path -Path $ScriptRootDirectory -ChildPath "manifests")
    
    # Inisialisasi cache Registry Windows instan
    Initialize-RegistryCache | Out-Null

    $scanResults = @()
    foreach ($pkg in $manifestPackages) {
        $scanResults += Get-PackageStatus -Package $pkg
    }

    Write-Host ""
    Write-Host "======================= HASIL PEMERIKSAAN =======================" -ForegroundColor Cyan
    $table = $scanResults | Select-Object @{Name="Prioritas"; Expression={"P" + $_.Priority}},
                                          @{Name="Software"; Expression={$_.Name}},
                                          @{Name="Status"; Expression={$_.Status}},
                                          @{Name="Versi Aktif"; Expression={$_.InstalledVersion}},
                                          @{Name="Versi Target"; Expression={$_.TargetVersion}}
    $table | Format-Table -AutoSize
    Write-Host "=================================================================" -ForegroundColor Cyan

    Write-Host "Tekan Enter untuk kembali ke menu..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
}

function Show-UpdateMenuDialog {
    param (
        [string]$ScriptRootDirectory,
        [PSCustomObject]$Config
    )

    Write-LogStep "MEMERIKSA PEMBARUAN SISTEM DARI GITHUB..."
    $remoteVerUrl = $Config.system.rawVersionUrl
    $archiveUrl   = $Config.system.archiveUrl

    $updateInfo = Check-ForSystemUpdate -RemoteVersionUrl $remoteVerUrl -ArchiveUrl $archiveUrl

    Write-Host ""
    Write-Host "Versi Terpasang Saat Ini : v$($updateInfo.LocalVersion)" -ForegroundColor White
    Write-Host "Versi di GitHub          : v$($updateInfo.RemoteVersion)" -ForegroundColor White
    Write-Host "Status                   : $($updateInfo.Message)" -ForegroundColor $(if ($updateInfo.HasUpdate) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green })
    Write-Host ""

    # Tawarkan Double Verification integritas berkas
    Write-Host "PILIHAN VERIFIKASI PEMBARUAN:" -ForegroundColor Yellow
    Write-Host " [1] Jalankan Double Verification (Uji Integritas Berkas Lokal)" -ForegroundColor Cyan
    if ($updateInfo.HasUpdate) {
        Write-Host " [2] Unduh & Terapkan Pembaruan Sekarang (v$($updateInfo.RemoteVersion))" -ForegroundColor Green
    }
    Write-Host " [0] Kembali ke Menu Utama" -ForegroundColor DarkGray
    Write-Host ""

    $subChoice = Read-Host "Pilih opsi (0-2)"
    if ($subChoice -eq "1") {
        Test-SystemFileIntegrity -ScriptRootDirectory $ScriptRootDirectory
        Write-Host ""
        Write-Host "Tekan Enter untuk lanjut..." -ForegroundColor Gray
        [void][System.Console]::ReadLine()
    }
    elseif ($subChoice -eq "2" -and $updateInfo.HasUpdate) {
        $applied = Invoke-SystemUpdate -UpdateInfo $updateInfo -ScriptRootDirectory $ScriptRootDirectory
        if ($applied) {
            Write-Host ""
            Write-Host "Memulai ulang LABInstaller dengan versi terbaru..." -ForegroundColor Green
            Start-Sleep -Seconds 2
            return $true
        }
    }

    return $false
}

function Start-WebServerOnlyFreshInstall {
    param (
        [string]$ScriptRootDirectory
    )

    Show-LabBanner -Version (Get-LocalVersionInfo).version

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "    KHUSUS WEB SERVER: FRESH INSTALL & PORT ISOLATION RESMI      " -ForegroundColor Yellow
    Write-Host "          (Laragon 6.0 + XAMPP 8.2 + phpMyAdmin Auto-Login)       " -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " Tindakan yang akan dieksekusi:" -ForegroundColor White
    Write-Host "   1. Membersihkan (Clean Purge) total residu Laragon, XAMPP, dan Service lama." -ForegroundColor Gray
    Write-Host "   2. Menginstal Laragon 6.0.0 ke C:\laragon (Port Apache 80 & MySQL 3306)." -ForegroundColor Gray
    Write-Host "   3. Menginstal phpMyAdmin 5.2.1 ke Laragon + Auto-Login Root tanpa password." -ForegroundColor Gray
    Write-Host "   4. Mengonfigurasi tombol 'Database' Laragon agar otomatis membuka phpMyAdmin." -ForegroundColor Gray
    Write-Host "   5. Menginstal XAMPP 8.2 ke C:\xampp (Port Apache 8080 & MySQL 3307)." -ForegroundColor Gray
    Write-Host "   6. Mengisolasi port & firewall sehingga Laragon dan XAMPP jalan berdampingan." -ForegroundColor Gray
    Write-Host "   (CATATAN: Aplikasi lain seperti NetBeans/Arduino/VSCode TIDAK AKAN disentuh!)" -ForegroundColor Green
    Write-Host ""

    $confirm = Read-Host "Apakah Anda yakin ingin melakukan Fresh Install khusus Web Server? (Y/N)"
    if ($confirm -notmatch '^(y|ya|yes)$') {
        Write-LogWarning "Proses instalasi web server dibatalkan oleh pengguna."
        Start-Sleep -Seconds 2
        return
    }

    # 1. Bersihkan tuntas instalasi web server sebelumnya
    Write-LogStep "MEMULAI BERSIH TOTAL RESIDU WEB SERVER LAMA..."
    Invoke-CleanPurgeLegacyLabStack -Force

    # 2. Muat manifest servers.json
    $manifestDir = Join-Path -Path $ScriptRootDirectory -ChildPath "manifests"
    $serversJson = Join-Path -Path $manifestDir -ChildPath "servers.json"
    $serverPkgs = Get-Content -Path $serversJson -Raw -Encoding UTF8 | ConvertFrom-Json

    Initialize-RegistryCache -ForceRefresh | Out-Null

    # 3. Instalasi Laragon
    $laragonPkg = $serverPkgs | Where-Object { $_.id -eq "Custom.Laragon" } | Select-Object -First 1
    if ($laragonPkg) {
        Write-Host ""
        Invoke-PackageInstall -Package $laragonPkg | Out-Null
        if ($laragonPkg.postInstallHandler) {
            & $laragonPkg.postInstallHandler
        }
    }

    # 4. Pastikan phpMyAdmin terpasang di Laragon
    Install-LaragonPhpMyAdmin -LaragonDir "C:\laragon" | Out-Null

    # 5. Instalasi XAMPP
    $xamppPkg = $serverPkgs | Where-Object { $_.id -eq "ApacheFriends.Xampp.8.2" } | Select-Object -First 1
    if ($xamppPkg) {
        Write-Host ""
        Invoke-PackageInstall -Package $xamppPkg | Out-Null
        if ($xamppPkg.postInstallHandler) {
            & $xamppPkg.postInstallHandler
        }
    }

    # 6. Konfigurasi Port, Firewall, & phpMyAdmin Isolasi
    Write-Host ""
    Start-FullEnvironmentConfiguration

    Write-Host ""
    Write-Host "========================== HASIL INSTALASI WEB SERVER ==========================" -ForegroundColor Cyan
    Write-LogSuccess "FRESH INSTALL WEB SERVER BERHASIL DILAKUKAN!"
    Write-Host "   - Laragon Web Server : http://localhost/ (Port 80)" -ForegroundColor Green
    Write-Host "   - Laragon phpMyAdmin : http://localhost/phpmyadmin/ (Auto-Login Root)" -ForegroundColor Green
    Write-Host "   - XAMPP Web Server   : http://localhost:8080/ (Port 8080)" -ForegroundColor Yellow
    Write-Host "   - XAMPP phpMyAdmin   : http://localhost:8080/phpmyadmin/ (Port 3307)" -ForegroundColor Yellow
    Write-Host "   - Hak Akses Aplikasi : Run As Administrator Permanen (Desktop & Start Menu)" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tekan Enter untuk kembali ke menu utama..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
}
