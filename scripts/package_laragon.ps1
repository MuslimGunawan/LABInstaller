# ==============================================================================
# Script Pengepakan Laragon Custom untuk LAB Komputer
# Mengumpulkan bin, etc, usr, laragon.exe, memperbaiki phpMyAdmin (tanpa login & tanpa warning),
# membersihkan credential, dan mengompres ke ZIP untuk di-hosting di Google Drive.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$sourceDir = "C:\laragon"
$stagingDir = "D:\KP\Laragon_Custom_LAB"
$zipFile = "D:\KP\Laragon_Custom_LAB.zip"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [1/5] Memeriksa Instalasi Sumber Laragon..." -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

if (-not (Test-Path -Path (Join-Path -Path $sourceDir -ChildPath "laragon.exe"))) {
    Write-Error "Direktori $sourceDir tidak ditemukan atau tidak memiliki laragon.exe!"
    exit 1
}

if (Test-Path -Path $stagingDir) {
    Write-Host "Membersihkan direktori staging lama..." -ForegroundColor DarkGray
    Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [2/5] Menyalin Berkas Inti (bin, etc, usr, laragon.exe)..." -ForegroundColor Cyan
Write-Host " (Mengabaikan www/project pribadi dan data/database pribadi)" -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Salin laragon.exe
Copy-Item -Path (Join-Path -Path $sourceDir -ChildPath "laragon.exe") -Destination $stagingDir -Force
Write-Host " - laragon.exe disalin." -ForegroundColor Green

# 2. Salin usr (konfigurasi & template)
Copy-Item -Path (Join-Path -Path $sourceDir -ChildPath "usr") -Destination $stagingDir -Recurse -Force
Write-Host " - Folder usr disalin." -ForegroundColor Green

# 3. Salin etc (virtualhost, ssl, apps termasuk phpMyAdmin)
Copy-Item -Path (Join-Path -Path $sourceDir -ChildPath "etc") -Destination $stagingDir -Recurse -Force
Write-Host " - Folder etc disalin." -ForegroundColor Green

# 4. Buat folder kosong data, www, tmp
New-Item -ItemType Directory -Path (Join-Path -Path $stagingDir -ChildPath "data") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path -Path $stagingDir -ChildPath "www") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path -Path $stagingDir -ChildPath "tmp") -Force | Out-Null
Write-Host " - Folder kosong data/, www/, tmp/ dibuat." -ForegroundColor Green

# 5. Salin bin dengan robocopy agar cepat dan andal
Write-Host " - Menyalin folder bin (proses ini mungkin memakan waktu beberapa menit)..." -ForegroundColor Cyan
$targetBin = Join-Path -Path $stagingDir -ChildPath "bin"
$sourceBin = Join-Path -Path $sourceDir -ChildPath "bin"

# Gunakan robocopy multi-threaded (/MT:8)
robocopy $sourceBin $targetBin /E /NFL /NDL /NJH /NJS /nc /ns /np /MT:8

Write-Host " - Folder bin berhasil disalin." -ForegroundColor Green

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [3/5] Memperbaiki Konfigurasi phpMyAdmin & Membersihkan Credential..." -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# A. Perbaiki phpMyAdmin config.inc.php
$pmaConfigPath = Join-Path -Path $stagingDir -ChildPath "etc\apps\phpMyAdmin\config.inc.php"
if (Test-Path -Path $pmaConfigPath) {
    Write-Host " - Mengonfigurasi phpMyAdmin agar TIDAK PERLU LOGIN (auth_type config) & BEBAS WARNING..." -ForegroundColor Cyan
    
    $pmaContent = Get-Content -Path $pmaConfigPath -Raw -Encoding UTF8
    
    # 1. Ubah auth_type ke config
    $pmaContent = $pmaContent -replace "\`$cfg\['Servers'\]\[\`$i\]\['auth_type'\]\s*=\s*'cookie';", @"
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
"@

    # 2. Perbaiki blowfish_secret ke 32-byte valid
    $pmaContent = $pmaContent -replace "\`$cfg\['blowfish_secret'\]\s*=\s*'.*?';", "`$cfg['blowfish_secret'] = 'vK8mQ2xL9pZ4wR7tY1uI3oE5aA6sD8fG';"

    # 3. Matikan warning storage, warning reports, dan version check
    $suppressFlags = @"

// Penonaktifan Peringatan & Optimasi Lingkungan Lab
`$cfg['PmaNoRelation_DisableWarning'] = true;
`$cfg['SendErrorReports'] = 'never';
`$cfg['VersionCheck'] = false;
"@
    if ($pmaContent -notmatch "PmaNoRelation_DisableWarning") {
        $pmaContent += $suppressFlags
    }

    Set-Content -Path $pmaConfigPath -Value $pmaContent -Encoding UTF8
    Write-Host " - phpMyAdmin berhasil dikonfigurasi: Auto-login root tanpa password & bebas semua warning!" -ForegroundColor Green
} else {
    Write-Host " - [Perhatian] File config.inc.php phpMyAdmin tidak ditemukan di $pmaConfigPath" -ForegroundColor Yellow
}

# B. Bersihkan Credential Pribadi User di usr\laragon.ini
$laragonIniPath = Join-Path -Path $stagingDir -ChildPath "usr\laragon.ini"
if (Test-Path -Path $laragonIniPath) {
    Write-Host " - Membersihkan token otentikasi pribadi (NgrokAuthToken) dari laragon.ini..." -ForegroundColor Cyan
    $iniText = Get-Content -Path $laragonIniPath -Raw -Encoding UTF8
    $iniText = $iniText -replace 'NgrokAuthToken=.*', 'NgrokAuthToken='
    Set-Content -Path $laragonIniPath -Value $iniText -Encoding UTF8
    Write-Host " - laragon.ini dibersihkan dari token privat." -ForegroundColor Green
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [4/5] Mengompresi Paket ke $zipFile..." -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

if (Test-Path -Path $zipFile) {
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
}

# Gunakan tar.exe bawaan Windows (cepat, multi-core, hemat memori)
$tarExe = "C:\Windows\System32\tar.exe"
if (Test-Path -Path $tarExe) {
    Write-Host " Menjalankan tar kompresi ZIP..." -ForegroundColor Cyan
    $prevPwd = (Get-Location).Path
    Set-Location -LiteralPath "D:\KP"
    & $tarExe -a -c -f "Laragon_Custom_LAB.zip" -C "$stagingDir" .
    Set-Location -LiteralPath $prevPwd
} else {
    Write-Host " Menjalankan Compress-Archive..." -ForegroundColor Cyan
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipFile -CompressionLevel Optimal
}

if (Test-Path -Path $zipFile) {
    $zipSizeMB = [math]::Round((Get-Item -Path $zipFile).Length / 1MB, 2)
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host " [5/5] SUKSES! Paket Laragon Custom Berhasil Dibuat!" -ForegroundColor Green
    Write-Host " Berkas ZIP : $zipFile" -ForegroundColor White
    Write-Host " Ukuran     : $zipSizeMB MB" -ForegroundColor Yellow
    Write-Host " Lokasi Folder Ekstrak : $stagingDir" -ForegroundColor DarkGray
    Write-Host "==================================================================" -ForegroundColor Green
} else {
    Write-Error "Gagal membuat berkas ZIP!"
}
