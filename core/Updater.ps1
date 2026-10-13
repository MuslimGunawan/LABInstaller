# ==============================================================================
# LABInstaller - Core Self-Updater Engine
# Pengecekan pembaruan GitHub, backup otomatis, staging, atomic overwrite, & rollback
# ==============================================================================

function Get-LocalVersionInfo {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $verFile = Join-Path -Path $scriptRoot -ChildPath "version.json"

    if (Test-Path -Path $verFile) {
        try {
            return (Get-Content -Path $verFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {
            return [PSCustomObject]@{ version = "1.0.0" }
        }
    }
    return [PSCustomObject]@{ version = "1.0.0" }
}

function Check-ForSystemUpdate {
    param (
        [string]$RemoteVersionUrl = "https://raw.githubusercontent.com/MuslimGunawan/LABInstaller/main/version.json",
        [string]$ArchiveUrl = "https://github.com/MuslimGunawan/LABInstaller/archive/refs/heads/main.zip"
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
        $webClient.Headers.Add("Cache-Control", "no-cache")

        $rawJson = $webClient.DownloadString($RemoteVersionUrl)
        $remoteInfo = $rawJson | ConvertFrom-Json

        if ($remoteInfo -and $remoteInfo.version) {
            $remoteVerStr = $remoteInfo.version
            $result.RemoteVersion = $remoteVerStr

            # Bandingkan versi (misal: 1.0.1 > 1.0.0)
            $localVersionObj = [System.Version]$localVerStr
            $remoteVersionObj = [System.Version]$remoteVerStr

            if ($remoteVersionObj -gt $localVersionObj) {
                $result.HasUpdate = $true
                $result.Message = "Pembaruan tersedia! Versi lokal: v$localVerStr -> Versi terbaru di GitHub: v$remoteVerStr"
            } else {
                $result.HasUpdate = $false
                $result.Message = "Sistem LABInstaller Anda sudah versi terbaru (v$localVerStr)."
            }
        }
    }
    catch {
        $result.HasUpdate = $false
        $result.Message = "Tidak dapat memeriksa pembaruan di GitHub (repositori belum memiliki commit version.json atau tidak ada koneksi internet)."
    }

    return $result
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
        # 1. Bersihkan staging lama jika ada
        if (Test-Path -Path $stagingDir) {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

        # 2. Backup berkas saat ini
        Write-LogInfo "Membuat backup sistem lokal ke: $backupDir"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        $itemsToBackup = Get-ChildItem -Path $rootDir | Where-Object { 
            $_.Name -notin @(".git", ".backup", ".update_staging", "logs") 
        }
        foreach ($item in $itemsToBackup) {
            Copy-Item -Path $item.FullName -Destination $backupDir -Recurse -Force
        }
        Write-LogSuccess "Backup berkas lokal berhasil dibuat."

        # 3. Unduh berkas pembaruan (.zip)
        Write-LogInfo "Mengunduh paket pembaruan dari: $($UpdateInfo.ArchiveUrl)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "LABInstaller-Updater")
        $webClient.DownloadFile($UpdateInfo.ArchiveUrl, $zipPath)

        if (-not (Test-Path -Path $zipPath)) {
            throw "Gagal mengunduh berkas zip pembaruan."
        }

        # 4. Ekstrak zip pembaruan
        Write-LogInfo "Mengekstrak paket pembaruan..."
        Expand-Archive -Path $zipPath -DestinationPath $extractedDir -Force

        # Cari folder hasil ekstrak (biasanya bernama LABInstaller-main)
        $subDirs = Get-ChildItem -Path $extractedDir -Directory
        $sourceFilesRoot = if ($subDirs.Count -eq 1) { $subDirs[0].FullName } else { $extractedDir }

        # Verifikasi integritas: pastikan installer.ps1 dan version.json ada di hasil ekstrak
        if (-not (Test-Path -Path (Join-Path -Path $sourceFilesRoot -ChildPath "version.json"))) {
            throw "Validasi integritas gagal: version.json tidak ditemukan di dalam paket unduhan."
        }

        # 5. Menimpa berkas lama dengan berkas baru secara bersih
        Write-LogStep "Menimpa berkas sistem dengan versi terbaru (v$($UpdateInfo.RemoteVersion))..."
        $updateItems = Get-ChildItem -Path $sourceFilesRoot | Where-Object { 
            $_.Name -notin @(".git", ".backup", ".update_staging", "logs") 
        }

        foreach ($uItem in $updateItems) {
            $destPath = Join-Path -Path $rootDir -ChildPath $uItem.Name
            Copy-Item -Path $uItem.FullName -Destination $rootDir -Recurse -Force
            Write-LogInfo "Diperbarui: $($uItem.Name)"
        }

        # 6. Bersihkan staging
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-LogSuccess "SISTEM BERHASIL DIPERBARUI KE VERSI $($UpdateInfo.RemoteVersion)!"
        Write-LogInfo "Semua perubahan telah diterapkan dengan aman tanpa error."
        return $true
    }
    catch {
        Write-LogError "Terjadi kegagalan saat proses update: $_"
        Write-LogWarning "Memulai proses pemulihan (Rollback) dari backup..."

        # Rollback dari backup
        if (Test-Path -Path $backupDir) {
            $backupItems = Get-ChildItem -Path $backupDir
            foreach ($bItem in $backupItems) {
                Copy-Item -Path $bItem.FullName -Destination $rootDir -Recurse -Force
            }
            Write-LogSuccess "Rollback selesai. Sistem dikembalikan ke kondisi sebelumnya."
        }

        if (Test-Path -Path $stagingDir) {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

