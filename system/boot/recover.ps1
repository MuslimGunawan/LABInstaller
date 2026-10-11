# ============================================================================
# Lab Auto Installer - Skrip Pemulihan & Penukar Runtime Portabel (recover.ps1)
# SATU-SATUNYA skrip PowerShell di proyek.
# Digunakan untuk:
#   -Apply   : Mengganti runtime\ saat pembaruan runtimeVersion (exit code 10).
#   -Repair  : Memulihkan runtime\ bila rusak atau hilang.
# ============================================================================

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [switch]$Repair
)

$ErrorActionPreference = "Stop"

$BootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SystemDir = Split-Path -Parent $BootDir
$RuntimeDir = Join-Path $SystemDir "runtime"
$DataDir = Join-Path $SystemDir "data"
$BackupDir = Join-Path $DataDir "backup"
$CacheDownloadDir = Join-Path $DataDir "cache\download"
$StagingRuntime = Join-Path $DataDir "cache\runtime-staging"

Write-Host "=== Lab Auto Installer: Utilitas Pemulihan Runtime ===" -ForegroundColor Cyan

if ($Apply) {
    Write-Host "[INFO] Memeriksa paket runtime baru di staging..." -ForegroundColor Yellow
    if (-not (Test-Path $StagingRuntime)) {
        Write-Host "[ERROR] Folder staging runtime tidak ditemukan: $StagingRuntime" -ForegroundColor Red
        exit 1
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupRuntimePath = Join-Path $BackupDir "runtime-$Timestamp"
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    try {
        Write-Host "[INFO] Mencadangkan runtime lama ke $BackupRuntimePath..."
        if (Test-Path $RuntimeDir) {
            Move-Item -Path $RuntimeDir -Destination $BackupRuntimePath -Force
        }

        Write-Host "[INFO] Menerapkan runtime baru..."
        Move-Item -Path $StagingRuntime -Destination $RuntimeDir -Force
        Write-Host "[SUKSES] Runtime berhasil diperbarui." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Host "[ERROR] Gagal mengganti runtime: $_" -ForegroundColor Red
        if (Test-Path $BackupRuntimePath) {
            Write-Host "[INFO] Melakukan rollback ke runtime sebelumnya..."
            Move-Item -Path $BackupRuntimePath -Destination $RuntimeDir -Force
        }
        exit 1
    }
}

if ($Repair) {
    Write-Host "[INFO] Memulai perbaikan runtime portabel..." -ForegroundColor Yellow
    # Periksa apakah berkas paket runtime lokal ada di cache
    $LocalRuntimeZip = Get-ChildItem -Path $CacheDownloadDir -Filter "runtime-*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($LocalRuntimeZip) {
        Write-Host "[INFO] Menemukan arsip runtime lokal: $($LocalRuntimeZip.FullName)"
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        Expand-Archive -Path $LocalRuntimeZip.FullName -DestinationPath $RuntimeDir -Force
        Write-Host "[SUKSES] Runtime berhasil dipulihkan dari arsip lokal." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[INFO] Arsip runtime lokal tidak ditemukan. Silakan unduh paket rilis lengkap" -ForegroundColor Yellow
        Write-Host "       atau tempatkan 'runtime-r1.zip' di folder system\data\cache\download\" -ForegroundColor Yellow
        exit 2
    }
}

Write-Host "Gunakan parameter -Apply atau -Repair." -ForegroundColor Yellow
exit 0
