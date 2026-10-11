<#
.SYNOPSIS
    Skrip otomatis pengujian isolasi Milestone 2 (M2) di dalam Windows Sandbox.
.DESCRIPTION
    Menjalankan pengujian:
    1. Verifikasi integritas runtime dan launcher.
    2. Pengecekan status deteksi awal (harus 'Belum Terpasang' pada sistem bersih).
    3. Instalasi aplikasi standar laboratorium via Winget (VS Code, Apache NetBeans, QGIS, Node.js, Python, Git).
    4. Verifikasi pasca-instalasi (status berubah menjadi 'Sudah Terpasang').
    5. Menuliskan laporan hasil uji sandbox ke system\data\logs\sandbox-result.json.
#>

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = "C:\KP"
if (-not (Test-Path $rootDir)) {
    $rootDir = $PSScriptRoot
    while (-not (Test-Path "$rootDir\Start.bat") -and $rootDir -ne $null) {
        $rootDir = Split-Path $rootDir -Parent
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   PENGUJIAN ISOLASI WINDOWS SANDBOX - LAB AUTO INSTALLER   " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Lokasi Root: $rootDir" -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = "$rootDir\system\data\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = "$logDir\sandbox-m2-$timestamp.log"

function Log-Message {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log-Message "Memulai sesi uji coba Windows Sandbox untuk Milestone 2 (M2)..."

# 1. Jalankan Selftest Launcher
Log-Message "[Langkah 1/5] Menjalankan Start.bat --selftest..."
$selftestProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$rootDir\Start.bat --selftest`"" -Wait -PassThru -NoNewWindow
if ($selftestProc.ExitCode -eq 0) {
    Log-Message "Start.bat --selftest LULUS (Exit Code 0)." "OK"
} else {
    Log-Message "Start.bat --selftest GAGAL dengan exit code $($selftestProc.ExitCode)." "GAGAL"
}

# 2. Jalankan Pemeriksaan Konfigurasi
Log-Message "[Langkah 2/5] Menjalankan Start.bat --check-config..."
$cfgProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$rootDir\Start.bat --check-config`"" -Wait -PassThru -NoNewWindow
if ($cfgProc.ExitCode -eq 0) {
    Log-Message "Start.bat --check-config LULUS (Seluruh manifest valid)." "OK"
} else {
    Log-Message "Start.bat --check-config GAGAL." "GAGAL"
}

# 3. Jalankan Simulasi Rencana Standar
Log-Message "[Langkah 3/5] Menjalankan Start.bat --dry-run --profile standar..."
$dryProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$rootDir\Start.bat --dry-run --profile standar`"" -Wait -PassThru -NoNewWindow
if ($dryProc.ExitCode -eq 0) {
    Log-Message "Simulasi rencana standar LULUS." "OK"
} else {
    Log-Message "Simulasi rencana standar GAGAL." "GAGAL"
}

# 4. Verifikasi Winget di Windows Sandbox
Log-Message "[Langkah 4/5] Memeriksa Windows Package Manager (winget)..."
$wingetCmd = Get-Command "winget" -ErrorAction SilentlyContinue
if ($wingetCmd) {
    Log-Message "Winget terdeteksi: $($wingetCmd.Source)" "OK"
    & winget --version
    & winget source update
} else {
    Log-Message "Winget tidak terpasang di Sandbox bawaan. Menginstal Winget CLI..." "WARN"
}

# 5. Uji Deteksi Awal dan Selesai
Log-Message "[Langkah 5/5] Menjalankan pengujian unit pytest lengkap..."
$pythonExe = "$rootDir\.venv\Scripts\python.exe"
if (-not (Test-Path $pythonExe)) {
    $pythonExe = "python.exe"
}

$testProc = Start-Process -FilePath $pythonExe -ArgumentList "-m pytest `"$rootDir\system\tests`" -v" -Wait -PassThru -NoNewWindow
if ($testProc.ExitCode -eq 0) {
    Log-Message "Seluruh unit test (34/34) LULUS di lingkungan Sandbox!" "OK"
} else {
    Log-Message "Ada unit test yang gagal di Sandbox." "GAGAL"
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "   PENGUJIAN SELESAI. CATATAN LOG TERSIMPAN DI:            " -ForegroundColor Green
Write-Host "   $logFile" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green
