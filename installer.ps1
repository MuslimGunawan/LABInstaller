<#
.SYNOPSIS
    LABInstaller - Sistem Instalasi Pintar & Otomatis untuk Windows (v1.0.1)
.DESCRIPTION
    Menginstal aplikasi resmi (Chrome, VSCode, VirtualBox, Git, Python, Java JDK,
    PHP 8.5, Composer, Laravel, Flutter, Laragon 6.0.0, XAMPP, NetBeans, Arduino IDE)
    serta konfigurasi port & verifikasi integritas file ganda.
.AUTHOR
    MuslimGunawan
#>

[CmdletBinding()]
param ()

# ------------------------------------------------------------------------------
# 1. Pastikan Script Berjalan Sebagai Administrator (Auto-Elevation)
# ------------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "LABInstaller memerlukan hak Administrator untuk mengonfigurasi sistem Windows." -ForegroundColor Yellow
    Write-Host "Meminta elevasi Administrator..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    catch {
        Write-Host "Gagal membuka jendela Administrator: $_" -ForegroundColor Red
    }
    exit
}

# ------------------------------------------------------------------------------
# 2. Pengaturan Konsol & Lingkungan
# ------------------------------------------------------------------------------
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# ------------------------------------------------------------------------------
# 3. Impor Modul Inti
# ------------------------------------------------------------------------------
. (Join-Path -Path $ScriptRoot -ChildPath "core\Logger.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\Environment.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\Detector.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\WingetEngine.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\ConfigManager.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\PostInstaller.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "core\Updater.ps1")
. (Join-Path -Path $ScriptRoot -ChildPath "ui\Menu.ps1")

# Inisialisasi Logger
Initialize-Logger -LogDir (Join-Path -Path $ScriptRoot -ChildPath "logs")

# ------------------------------------------------------------------------------
# 4. Baca Konfigurasi & Versi
# ------------------------------------------------------------------------------
$configPath = Join-Path -Path $ScriptRoot -ChildPath "config.json"
$config = if (Test-Path -Path $configPath) {
    Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $null
}

$versionInfo = Get-LocalVersionInfo
$currentVersion = $versionInfo.version

# ------------------------------------------------------------------------------
# 5. Pengecekan Update Otomatis di Awal Menjalankan (Startup Check)
# ------------------------------------------------------------------------------
if ($config -and $config.system.checkUpdateOnStartup) {
    Write-LogInfo "Memeriksa pembaruan sistem di GitHub saat memulai..."
    $startupUpdate = Check-ForSystemUpdate -RemoteVersionUrl $config.system.rawVersionUrl -ArchiveUrl $config.system.archiveUrl

    if ($startupUpdate.HasUpdate) {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host " PERHATIAN: Pembaruan versi terbaru tersedia di GitHub!" -ForegroundColor Yellow
        Write-Host " Versi Anda    : v$($startupUpdate.LocalVersion)" -ForegroundColor White
        Write-Host " Versi Terbaru : v$($startupUpdate.RemoteVersion)" -ForegroundColor Green
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host ""
        $promptUpdate = Read-Host "Apakah Anda ingin memperbarui sistem LABInstaller sekarang? (Y/N)"
        if ($promptUpdate -match '^(y|ya|yes)$') {
            $applied = Invoke-SystemUpdate -UpdateInfo $startupUpdate -ScriptRootDirectory $ScriptRoot
            if ($applied) {
                Write-Host "Memulai ulang LABInstaller dengan versi baru..." -ForegroundColor Green
                Start-Sleep -Seconds 2
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
                exit
            }
        }
    } else {
        Write-LogSuccess "Sistem LABInstaller aktif pada versi v$currentVersion."
    }
}

# ------------------------------------------------------------------------------
# 6. Loop Menu Interaktif
# ------------------------------------------------------------------------------
while ($true) {
    $versionInfo = Get-LocalVersionInfo
    $currentVersion = $versionInfo.version

    Show-LabBanner -Version $currentVersion

    Write-Host "  PILIHAN MENU UTAMA:" -ForegroundColor Yellow
    Write-Host "  [1] Mulai Instalasi Pintar (Auto Scan, Install & Auto Config)" -ForegroundColor Green
    Write-Host "  [2] Pindai Cepat Status Software Saja (Fast Scan)" -ForegroundColor Cyan
    Write-Host "  [3] Konfigurasi Port & Environment (Laragon vs XAMPP, php.ini, Laravel)" -ForegroundColor Yellow
    Write-Host "  [4] Periksa Pembaruan Sistem & Double Verification (GitHub)" -ForegroundColor Magenta
    Write-Host "  [5] Buka Folder Log Aktivitas" -ForegroundColor White
    Write-Host "  [0] Keluar" -ForegroundColor DarkGray
    Write-Host ""

    $pilihan = Read-Host "Masukkan pilihan Anda (0-5)"

    switch ($pilihan) {
        "1" {
            Start-SmartInstallation -ScriptRootDirectory $ScriptRoot
        }
        "2" {
            Show-SystemScanOnly -ScriptRootDirectory $ScriptRoot
        }
        "3" {
            Start-FullEnvironmentConfiguration
            Write-Host ""
            Write-Host "Tekan Enter untuk kembali ke menu..." -ForegroundColor Gray
            [void][System.Console]::ReadLine()
        }
        "4" {
            $needRestart = Show-UpdateMenuDialog -ScriptRootDirectory $ScriptRoot -Config $config
            if ($needRestart) {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
                exit
            }
        }
        "5" {
            $logDir = Join-Path -Path $ScriptRoot -ChildPath "logs"
            if (Test-Path -Path $logDir) {
                Start-Process -FilePath "explorer.exe" -ArgumentList "`"$logDir`""
            } else {
                Write-LogWarning "Folder log belum ada."
            }
        }
        "0" {
            Write-LogInfo "Keluar dari LABInstaller. Terima kasih!"
            Start-Sleep -Seconds 1
            exit
        }
        Default {
            Write-LogWarning "Pilihan '$pilihan' tidak valid. Silakan pilih 0 - 5."
            Start-Sleep -Seconds 1
        }
    }
}
