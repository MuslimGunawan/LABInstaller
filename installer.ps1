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
    $targetDir = Split-Path -Parent $PSCommandPath
    try {
        Start-Process -FilePath "powershell.exe" -WorkingDirectory "$targetDir" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
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

# Simpan warna asli konsol untuk pemulihan seragam setelah eksekusi alat eksternal (cmd.exe)
try {
    $global:LabOriginalBgColor = $Host.UI.RawUI.BackgroundColor
    $global:LabOriginalFgColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.WindowTitle = "LABInstaller - Automated Lab Deployment"
} catch {}

# Nonaktifkan QuickEdit Mode agar klik mouse pada konsol tidak membekukan (pause) script
try {
    $codeQE = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleQuickEdit {
    const uint ENABLE_QUICK_EDIT = 0x0040;
    const uint ENABLE_EXTENDED = 0x0080;
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void Disable() {
        try {
            IntPtr h = GetStdHandle(-10);
            uint m;
            if (GetConsoleMode(h, out m)) {
                m &= ~ENABLE_QUICK_EDIT;
                m |= ENABLE_EXTENDED;
                SetConsoleMode(h, m);
            }
        } catch {}
    }
}
"@
    if (-not ([System.Management.Automation.PSTypeName]'ConsoleQuickEdit').Type) {
        Add-Type -TypeDefinition $codeQE -ErrorAction SilentlyContinue
    }
    [ConsoleQuickEdit]::Disable()
} catch {}

$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ($ScriptRoot -and (Test-Path -Path $ScriptRoot)) {
    Set-Location -LiteralPath $ScriptRoot
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

# Aktifkan Lab Keep-Alive Guard (Anti-Sleep & Anti-Idle Shutdown 10 menit)
Start-LabKeepAliveGuard

# Pastikan Keep-Alive Guard dilepas bersih saat sesi PowerShell ditutup
try {
    Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action { Stop-LabKeepAliveGuard } -SupportEvent | Out-Null
} catch {}


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
                Stop-LabKeepAliveGuard
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
    try {
        $Host.UI.RawUI.WindowTitle = "LABInstaller v$currentVersion - Automated Lab Deployment"
    } catch {}

    Show-LabBanner -Version $currentVersion

    Write-Host "  PILIHAN MENU UTAMA:" -ForegroundColor Yellow
    Write-Host "  [1] Mulai Instalasi Pintar (Auto Scan, Install, & Isolasi Port)" -ForegroundColor Green
    Write-Host "  [2] Pindai Cepat Status Software Saja (Fast Scan)" -ForegroundColor Cyan
    Write-Host "  [3] Konfigurasi Port, Firewall & Ekosistem Lab (Flutter, Android, Delphi)" -ForegroundColor Yellow
    Write-Host "  [4] Periksa Pembaruan Sistem & Double Verification (GitHub)" -ForegroundColor Magenta
    Write-Host "  [5] Aktivasi Microsoft Windows & Office Khusus (HWID & Ohook)" -ForegroundColor Green
    Write-Host "  [6] Buka Folder Log Aktivitas" -ForegroundColor White
    Write-Host "  [7] Clean Reset & Fresh Purge (Hapus Total Residu PHP, Laragon, XAMPP & Service)" -ForegroundColor Red
    Write-Host "  [8] Khusus Web Server: Fresh Install & Port Isolation (Laragon + XAMPP + phpMyAdmin)" -ForegroundColor Cyan
    Write-Host "  [0] Keluar" -ForegroundColor DarkGray
    Write-Host ""

    $pilihan = Read-Host "Masukkan pilihan Anda (0-8)"

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
                Stop-LabKeepAliveGuard
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
                exit
            }
        }
        "5" {
            Invoke-WindowsAndOfficeActivation -Force
            Write-Host ""
            Write-Host "Tekan Enter untuk kembali ke menu..." -ForegroundColor Gray
            [void][System.Console]::ReadLine()
        }
        "6" {
            $logDir = Join-Path -Path $ScriptRoot -ChildPath "logs"
            if (Test-Path -Path $logDir) {
                Start-Process -FilePath "explorer.exe" -ArgumentList "`"$logDir`""
            } else {
                Write-LogWarning "Folder log belum ada."
            }
        }
        "7" {
            $purged = Invoke-CleanPurgeLegacyLabStack
            if ($purged) {
                Write-Host ""
                $runSmartAfter = Read-Host "Apakah ingin langsung menjalankan Instalasi Pintar (Menu 1)? (Y/N)"
                if ($runSmartAfter -match '^(y|ya|yes)$') {
                    Start-SmartInstallation -ScriptRootDirectory $ScriptRoot
                }
            }
            Write-Host ""
            Write-Host "Tekan Enter untuk kembali ke menu..." -ForegroundColor Gray
            [void][System.Console]::ReadLine()
        }
        "8" {
            Start-WebServerOnlyFreshInstall -ScriptRootDirectory $ScriptRoot
        }
        "0" {
            Stop-LabKeepAliveGuard
            Write-LogInfo "Keluar dari LABInstaller. Terima kasih!"
            Start-Sleep -Seconds 1
            exit
        }
        Default {
            Write-LogWarning "Pilihan '$pilihan' tidak valid. Silakan pilih 0 - 8."
            Start-Sleep -Seconds 1
        }
    }
}
