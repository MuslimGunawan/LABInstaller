# ==============================================================================
# LABInstaller - UI Menu Interaktif (v1.0.1)
# Antarmuka konsol untuk instalasi pintar, scan cepat, konfigurasi port, & verifikasi file
# ==============================================================================

function Start-SmartInstallation {
    param (
        [string]$ScriptRootDirectory
    )

    # Deteksi apakah ada residu web stack lama (Laragon, XAMPP, PHP lama)
    $hasLegacyStack = (Test-Path "C:\laragon") -or (Test-Path "C:\xampp") -or (Test-Path "C:\php")
    if ($hasLegacyStack) {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host " PERHATIAN: Ditemukan instalasi web stack lama di C:\ (Laragon/XAMPP/PHP)!" -ForegroundColor Yellow
        Write-Host " File terkunci, service zombie, atau PATH lama dapat memicu konflik." -ForegroundColor DarkYellow
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host ""
        $purgePrompt = Read-Host "Ingin jalankan CLEAN PURGE (Hapus Total & Reset Fresh) sekarang? (Y/N)"
        if ($purgePrompt -match '^(y|ya|yes)$') {
            Invoke-CleanPurgeLegacyLabStack
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
