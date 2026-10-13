# ==============================================================================
# LABInstaller - UI Menu Interaktif
# Tampilan antarmuka konsol untuk manajemen instalasi pintar dan pembaruan
# ==============================================================================

function Start-SmartInstallation {
    param (
        [string]$ScriptRootDirectory
    )

    Write-LogStep "MEMULAI ANALISIS SISTEM & PINDAI STATUS SOFTWARE..."
    $manifestPackages = Load-AllManifestPackages -ManifestDir (Join-Path -Path $ScriptRootDirectory -ChildPath "manifests")

    if ($manifestPackages.Count -eq 0) {
        Write-LogError "Tidak ada manifest paket yang ditemukan di folder 'manifests'."
        return
    }

    Write-Host ""
    Write-Host "Sedang memindai $($manifestPackages.Count) paket di sistem Windows..." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

    $scanResults = @()
    foreach ($pkg in $manifestPackages) {
        Write-Host "Mengecek: $($pkg.name)... " -NoNewline -ForegroundColor Gray
        $status = Get-PackageStatus -Package $pkg
        $scanResults += $status

        switch ($status.Status) {
            "NOT_INSTALLED"    { Write-Host "[BELUM TERPASANG]" -ForegroundColor Yellow }
            "UPDATE_AVAILABLE" { Write-Host "[PERLU UPDATE]" -ForegroundColor Magenta }
            "UP_TO_DATE"       { Write-Host "[SUDAH PAS - UP TO DATE]" -ForegroundColor Green }
            Default            { Write-Host "[$($status.Status)]" -ForegroundColor White }
        }
    }

    # Tampilkan Tabel Ringkasan
    Write-Host ""
    Write-Host "========================== RINGKASAN STATUS ==========================" -ForegroundColor Cyan
    $table = $scanResults | Select-Object @{Name="Software"; Expression={$_.Name}},
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
        Write-LogSuccess "SEMUA SOFTWARE SUDAH TERPASANG DAN UP-TO-DATE! Tidak ada tindakan yang diperlukan."
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

    # Eksekusi Instalasi
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

        if ($raw.type -eq "winget") {
            $success = Invoke-WingetInstall -Package $raw -IsUpgrade:$isUpgrade
        }
        elseif ($raw.type -eq "custom") {
            $handler = $raw.customHandler
            if ($handler -and (Get-Command $handler -ErrorAction SilentlyContinue)) {
                $success = & $handler
            } else {
                Write-LogError "Custom handler '$handler' tidak ditemukan untuk $($raw.name)."
            }
        }

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

    Write-LogStep "PINDAI STATUS SOFTWARE SAAT INI..."
    $manifestPackages = Load-AllManifestPackages -ManifestDir (Join-Path -Path $ScriptRootDirectory -ChildPath "manifests")
    
    $scanResults = @()
    foreach ($pkg in $manifestPackages) {
        Write-Host "Memeriksa: $($pkg.name)..." -ForegroundColor Gray
        $scanResults += Get-PackageStatus -Package $pkg
    }

    Write-Host ""
    Write-Host "======================= HASIL PEMERIKSAAN =======================" -ForegroundColor Cyan
    $table = $scanResults | Select-Object @{Name="Software"; Expression={$_.Name}},
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

    if ($updateInfo.HasUpdate) {
        $confirm = Read-Host "Apakah Anda ingin mengunduh dan menerapkan pembaruan sekarang? (Y/N)"
        if ($confirm -match '^(y|ya|yes)$') {
            $applied = Invoke-SystemUpdate -UpdateInfo $updateInfo -ScriptRootDirectory $ScriptRootDirectory
            if ($applied) {
                Write-Host ""
                Write-Host "Memulai ulang LABInstaller..." -ForegroundColor Green
                Start-Sleep -Seconds 2
                return $true # Meminta restart
            }
        } else {
            Write-LogInfo "Pembaruan ditunda oleh pengguna."
        }
    }

    Write-Host "Tekan Enter untuk kembali ke menu..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
    return $false
}

