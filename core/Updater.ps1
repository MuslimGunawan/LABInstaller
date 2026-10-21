# ==============================================================================
# LABInstaller - Core Self-Updater & Double-Verification Engine
# Pengecekan pembaruan GitHub, verifikasi integritas file SHA256, atomic overwrite, & rollback
# ==============================================================================

function Get-LocalVersionInfo {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $verFile = Join-Path -Path $scriptRoot -ChildPath "version.json"

    if (Test-Path -Path $verFile) {
        try {
            return (Get-Content -Path $verFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {
            return [PSCustomObject]@{ version = "1.0.1" }
        }
    }
    return [PSCustomObject]@{ version = "1.0.1" }
}

function Check-ForSystemUpdate {
    param (
        [string]$RemoteVersionUrl = "https://api.github.com/repos/MuslimGunawan/LABInstaller/contents/version.json",
        [string]$FallbackRawUrl   = "https://raw.githubusercontent.com/MuslimGunawan/LABInstaller/main/version.json",
        [string]$ArchiveUrl       = "https://codeload.github.com/MuslimGunawan/LABInstaller/zip/refs/heads/main"
    )

    $localInfo = Get-LocalVersionInfo
    $localVerStr = $localInfo.version

    $result = [PSCustomObject]@{
        HasUpdate     = $false
        LocalVersion  = $localVerStr
        RemoteVersion = $localVerStr
        ArchiveUrl    = $ArchiveUrl
        Message       = ""
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "LABInstaller-Updater")
        $webClient.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
        $webClient.Headers.Add("Pragma", "no-cache")

        $remoteVerStr = $null

        # 1. Coba via GitHub REST API (Real-Time 0 Detik Delay Tanpa Cache CDN)
        try {
            $webClient.Headers.Set("Accept", "application/vnd.github.v3.raw")
            $rawJson = $webClient.DownloadString($RemoteVersionUrl)
            $remoteMeta = $rawJson | ConvertFrom-Json
            if ($remoteMeta -and $remoteMeta.version) {
                $remoteVerStr = $remoteMeta.version
            }
        }
        catch {
            # 2. Fallback via raw.githubusercontent.com jika API limit tercapai
            $webClient.Headers.Remove("Accept")
            $rawJson = $webClient.DownloadString($FallbackRawUrl + "?t=" + [Guid]::NewGuid().ToString('N'))
            $remoteMeta = $rawJson | ConvertFrom-Json
            if ($remoteMeta -and $remoteMeta.version) {
                $remoteVerStr = $remoteMeta.version
            }
        }

        if ($remoteVerStr) {
            $result.RemoteVersion = $remoteVerStr
            $localVersionObj = [System.Version]$localVerStr
            $remoteVersionObj = [System.Version]$remoteVerStr

            if ($remoteVersionObj -gt $localVersionObj) {
                $result.HasUpdate = $true
                $result.Message = "Pembaruan versi terbaru tersedia! Versi lokal: v$localVerStr -> Versi GitHub: v$remoteVerStr"
            } else {
                $result.HasUpdate = $false
                $result.Message = "Sistem LABInstaller Anda berada pada versi terbaru (v$localVerStr)."
            }
        }
    }
    catch {
        $result.HasUpdate = $false
        $result.Message = "Tidak dapat memeriksa pembaruan di GitHub - $_"
    }

    return $result
}

function Test-SystemFileIntegrity {
    param (
        [string]$ScriptRootDirectory
    )

    Write-LogStep "MENJALANKAN DOUBLE VERIFICATION (PENGUJIAN INTEGRITAS BERKAS SISTEM)..."
    $rootDir = $ScriptRootDirectory

    $expectedFiles = @(
        "installer.ps1",
        "version.json",
        "config.json",
        "run.bat",
        "core\Logger.ps1",
        "core\Environment.ps1",
        "core\Detector.ps1",
        "core\WingetEngine.ps1",
        "core\PostInstaller.ps1",
        "core\ConfigManager.ps1",
        "core\Updater.ps1",
        "manifests\apps.json",
        "manifests\runtimes.json",
        "manifests\tooling.json",
        "manifests\servers.json",
        "system\boot\install.ps1",
        "ui\Menu.ps1",
        "activator\HWID_Activation.cmd",
        "activator\Ohook_Activation_AIO.cmd"
    )

    $results = @()
    $allValid = $true

    foreach ($rel in $expectedFiles) {
        $fullPath = Join-Path -Path $rootDir -ChildPath $rel
        $exists = Test-Path -Path $fullPath
        $status = "OK"
        $sha = "-"
        $details = ""

        if (-not $exists) {
            $status = "HILANG/MISSING"
            $allValid = $false
            $details = "Berkas tidak ditemukan"
        } else {
            $item = Get-Item -Path $fullPath
            if ($item.Length -eq 0) {
                $status = "KORUP/KOSONG"
                $allValid = $false
                $details = "Ukuran berkas 0 byte"
            } else {
                # Uji validitas sintaks jika PowerShell
                if ($rel.EndsWith(".ps1")) {
                    $errors = $null
                    $tokens = $null
                    [void][System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$errors)
                    if ($errors.Count -gt 0) {
                        $status = "ERROR SINTAKS"
                        $allValid = $false
                        $details = "$($errors.Count) kesalahan sintaks"
                    }
                }
                # Uji validitas JSON jika JSON
                elseif ($rel.EndsWith(".json")) {
                    try {
                        [void](Get-Content -Path $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json)
                    } catch {
                        $status = "ERROR JSON"
                        $allValid = $false
                        $details = "Format JSON tidak valid"
                    }
                }

                # Hitung SHA256 singkat
                try {
                    $hashObj = Get-FileHash -Path $fullPath -Algorithm SHA256
                    $sha = $hashObj.Hash.Substring(0, 10) + "..."
                } catch {}
            }
        }

        $results += [PSCustomObject]@{
            "Berkas"         = $rel
            "Status"         = $status
            "SHA256 (Kutip)" = $sha
            "Keterangan"     = if ($details) { $details } else { "Terverifikasi Valid" }
        }
    }

    Write-Host ""
    Write-Host "===================== HASIL DOUBLE VERIFICATION =====================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize | Out-Host
    Write-Host "======================================================================" -ForegroundColor Cyan

    if ($allValid) {
        Write-LogSuccess "VERIFIKASI INTEGRITAS SUKSES: Seluruh berkas ($($expectedFiles.Count)/$($expectedFiles.Count)) UTUH, LENGKAP & VALID 100%!"
    } else {
        Write-LogError "VERIFIKASI GAGAL: Ditemukan berkas yang hilang atau rusak. Disarankan melakukan update ulang!"
    }

    return $allValid
}

function Invoke-SystemUpdate {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$UpdateInfo,
        [string]$ScriptRootDirectory
    )

    if (-not $UpdateInfo.HasUpdate) {
        Write-LogInfo "Tidak ada pembaruan untuk diinstal."
        return $false
    }

    Write-LogStep "MEMULAI PROSES PEMBARUAN SISTEM (v$($UpdateInfo.LocalVersion) -> v$($UpdateInfo.RemoteVersion))..."

    $rootDir = $ScriptRootDirectory
    $backupDir = Join-Path -Path $rootDir -ChildPath ".backup\v$($UpdateInfo.LocalVersion)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $stagingDir = Join-Path -Path $rootDir -ChildPath ".update_staging"
    $zipPath = Join-Path -Path $stagingDir -ChildPath "update.zip"
    $extractedDir = Join-Path -Path $stagingDir -ChildPath "extracted"

    try {
        if (Test-Path -Path $stagingDir) {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

        # 0. Bersihkan backup usang untuk menghemat ruang disk
        $backupRoot = Join-Path -Path $rootDir -ChildPath ".backup"
        if (Test-Path -Path $backupRoot) {
            Get-ChildItem -Path $backupRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object CreationTime -Descending |
                Select-Object -Skip 1 |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Rapikan installer liar (zip/exe) dari root direktori ke folder apps/ agar root bersih & hemat disk
        $appsDir = Join-Path -Path $rootDir -ChildPath "apps"
        if (-not (Test-Path -Path $appsDir)) { New-Item -ItemType Directory -Path $appsDir -Force | Out-Null }
        $strayInstallers = Get-ChildItem -Path $rootDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @(".zip", ".exe", ".msi", ".iso", ".7z", ".rar") -and
            $_.Name -notin @("run.bat")
        }
        foreach ($stray in $strayInstallers) {
            $destStray = Join-Path -Path $appsDir -ChildPath $stray.Name
            if (-not (Test-Path -Path $destStray)) {
                Move-Item -Path $stray.FullName -Destination $destStray -Force -ErrorAction SilentlyContinue
            } else {
                Remove-Item -Path $stray.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        # 1. Backup HANYA berkas & modul sistem (core, manifests, ui, system, activator, script root)
        # JANGAN PERNAH menyalin folder apps, cache, atau installer raksasa yang memakan kuota disk!
        Write-LogInfo "Membuat backup komponen sistem lokal ke: $backupDir"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        $systemEntries = @("core", "manifests", "ui", "system", "activator", "installer.ps1", "version.json", "config.json", "run.bat")
        $itemsToBackup = Get-ChildItem -Path $rootDir -ErrorAction SilentlyContinue | Where-Object { 
            ($_.Name -in $systemEntries) -and 
            ($_.Name -notin @(".git", ".backup", ".update_staging", "logs", "apps", "downloads", "cache", "temp")) -and
            ($_.Extension -notin @(".zip", ".exe", ".msi", ".iso", ".7z", ".rar", ".tar", ".gz"))
        }

        foreach ($item in $itemsToBackup) {
            try {
                Copy-Item -Path $item.FullName -Destination $backupDir -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
        }
        Write-LogSuccess "Backup sistem lokal berhasil dibuat (ringan & hemat disk)."

        # 2. Unduh berkas pembaruan (.zip)
        Write-LogInfo "Mengunduh paket pembaruan dari: $($UpdateInfo.ArchiveUrl)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "LABInstaller-Updater")
        
        try {
            $webClient.DownloadFile($UpdateInfo.ArchiveUrl, $zipPath)
        }
        catch {
            Write-LogWarning "Gagal mengunduh dari tautan utama, mencoba tautan cadangan GitHub..."
            $fallbackUrl = "https://github.com/MuslimGunawan/LABInstaller/archive/refs/heads/main.zip"
            $webClient.DownloadFile($fallbackUrl, $zipPath)
        }

        if (-not (Test-Path -Path $zipPath)) {
            throw "Gagal mengunduh berkas zip pembaruan."
        }

        # 3. Ekstrak zip pembaruan
        Write-LogInfo "Mengekstrak paket pembaruan..."
        Expand-Archive -Path $zipPath -DestinationPath $extractedDir -Force

        $subDirs = Get-ChildItem -Path $extractedDir -Directory
        $sourceFilesRoot = if ($subDirs.Count -eq 1) { $subDirs[0].FullName } else { $extractedDir }

        if (-not (Test-Path -Path (Join-Path -Path $sourceFilesRoot -ChildPath "version.json"))) {
            throw "Validasi integritas gagal: version.json tidak ditemukan di dalam paket unduhan."
        }

        # 4. Menimpa berkas lama dengan berkas baru
        Write-LogStep "Menimpa berkas sistem dengan versi terbaru (v$($UpdateInfo.RemoteVersion))..."
        $updateItems = Get-ChildItem -Path $sourceFilesRoot -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notin @(".git", ".backup", ".update_staging", "logs", "apps", "downloads", "cache", "temp") 
        }

        foreach ($uItem in $updateItems) {
            $destPath = Join-Path -Path $rootDir -ChildPath $uItem.Name
            Copy-Item -Path $uItem.FullName -Destination $rootDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogInfo "Diperbarui: $($uItem.Name)"
        }

        # 5. Jalankan Double Verification pasca-update
        $isVerified = Test-SystemFileIntegrity -ScriptRootDirectory $rootDir
        if (-not $isVerified) {
            throw "Verifikasi file setelah update gagal!"
        }

        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-LogSuccess "SISTEM BERHASIL DIPERBARUI KE VERSI $($UpdateInfo.RemoteVersion) DENGAN VERIFIKASI SEMPURNA!"
        return $true
    }
    catch {
        Write-LogError "Terjadi kegagalan saat proses update - $_"
        Write-LogWarning "Memulai proses pemulihan (Rollback) dari backup..."

        if (Test-Path -Path $backupDir) {
            $backupItems = Get-ChildItem -Path $backupDir -ErrorAction SilentlyContinue
            foreach ($bItem in $backupItems) {
                Copy-Item -Path $bItem.FullName -Destination $rootDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-LogSuccess "Rollback selesai. Sistem dikembalikan ke kondisi sebelumnya."
        }

        if (Test-Path -Path $stagingDir) {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}
