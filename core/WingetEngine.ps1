# ==============================================================================
# LABInstaller - Core Hybrid Package Engine
# Mesin Instalasi Cerdas Berlapis: Winget Utama + Fallback Vendor Langsung (Anti-Gagal)
# ==============================================================================

$global:IsWingetHealthy = $null

function Test-WingetHealth {
    if ($null -ne $global:IsWingetHealthy) {
        return $global:IsWingetHealthy
    }

    $wingetCmd = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        $global:IsWingetHealthy = $false
        return $false
    }

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget.exe"
        $pinfo.Arguments = "--version"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $finished = $p.WaitForExit(3000)

        if ($finished -and $p.ExitCode -eq 0) {
            $global:IsWingetHealthy = $true
            return $true
        } else {
            if (-not $finished) { $p.Kill() }
            $global:IsWingetHealthy = $false
            return $false
        }
    }
    catch {
        $global:IsWingetHealthy = $false
        return $false
    }
}

function Install-WingetAutoBootstrap {
    Write-LogStep "Mendeteksi WinGet tidak terpasang/bermasalah. Memulai perbaikan otomatis..."

    $tempDir = [System.IO.Path]::GetTempPath()
    $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $xamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
    $bundleUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "LABInstaller")

        $vclibsPath = Join-Path -Path $tempDir -ChildPath "vclibs.appx"
        $xamlPath = Join-Path -Path $tempDir -ChildPath "xaml.appx"
        $bundlePath = Join-Path -Path $tempDir -ChildPath "winget.msixbundle"

        Write-LogInfo "Mengunduh dependensi VCLibs & UI.Xaml..."
        $wc.DownloadFile($vclibsUrl, $vclibsPath)
        $wc.DownloadFile($xamlUrl, $xamlPath)

        Write-LogInfo "Mengunduh paket instalasi resmi WinGet DesktopAppInstaller..."
        $wc.DownloadFile($bundleUrl, $bundlePath)

        Write-LogInfo "Mendaftarkan paket ke sistem Windows..."
        Add-AppxPackage -Path $vclibsPath -ErrorAction SilentlyContinue
        Add-AppxPackage -Path $xamlPath -ErrorAction SilentlyContinue
        Add-AppxPackage -Path $bundlePath -DependencyPath @($vclibsPath, $xamlPath) -ErrorAction SilentlyContinue

        # Cek ulang
        $global:IsWingetHealthy = $null
        if (Test-WingetHealth) {
            Write-LogSuccess "WinGet berhasil diperbaiki dan siap digunakan!"
            return $true
        }
    }
    catch {
        Write-LogWarning "Gagal memasang WinGet via AppX (OS mungkin modifikasi tanpa AppXSvc) - $_"
    }
    finally {
        Remove-Item -Path $vclibsPath, $xamlPath, $bundlePath -Force -ErrorAction SilentlyContinue
    }

    Write-LogInfo "Sistem akan menggunakan mesin unduhan langsung (Direct Vendor Engine) yang tidak memerlukan WinGet."
    return $false
}

function Get-AppStorageDirectory {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $appsDir = Join-Path -Path $scriptRoot -ChildPath "apps"
    if (-not (Test-Path -Path $appsDir)) {
        New-Item -ItemType Directory -Path $appsDir -Force | Out-Null
    }
    return $appsDir
}

function Test-ValidInstallerFile {
    param (
        [string]$FilePath,
        [string]$ExpectedType = "exe",
        [long]$MinSizeBytes = 1000000 # Minimal 1 MB
    )

    if (-not (Test-Path -Path $FilePath)) { return $false }
    $fileItem = Get-Item -Path $FilePath -ErrorAction SilentlyContinue
    if (-not $fileItem -or $fileItem.Length -lt $MinSizeBytes) { return $false }

    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        $buf = New-Object byte[] 64
        $read = $fs.Read($buf, 0, 64)
        $fs.Close()

        if ($read -lt 4) { return $false }

        # Tolak jika berkas diawali tag HTML / XML (halaman web error / SourceForge landing page)
        $headerAscii = [System.Text.Encoding]::ASCII.GetString($buf[0..([math]::Min(31, $read - 1))])
        if ($headerAscii -match '^\s*<(!DOCTYPE|html|\?xml)') {
            return $false
        }

        switch ($ExpectedType.ToLower()) {
            "exe" {
                # Validasi Magic Header PE Windows: MZ (0x4D 0x5A)
                return ($buf[0] -eq 77 -and $buf[1] -eq 90)
            }
            "zip" {
                # Validasi Magic Header ZIP: PK (0x50 0x4B)
                return ($buf[0] -eq 80 -and $buf[1] -eq 75)
            }
            "msi" {
                # Validasi Magic Header OLE Compound: 0xD0 0xCF 0x11 0xE0
                return ($buf[0] -eq 208 -and $buf[1] -eq 207 -and $buf[2] -eq 17 -and $buf[3] -eq 224)
            }
            Default {
                return $true
            }
        }
    }
    catch {
        return $false
    }
}

function Invoke-GoogleDriveFileDownload {
    param (
        [string]$FileId,
        [string]$OutPath
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $cookieContainer = New-Object System.Net.CookieContainer

        $url = "https://drive.google.com/uc?export=download&id=$FileId"
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.CookieContainer = $cookieContainer
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LABInstaller"
        $req.AllowAutoRedirect = $true
        
        $resp = $req.GetResponse()
        $ct = $resp.ContentType

        if ($ct -notmatch "text/html") {
            $stream = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($OutPath)
            $stream.CopyTo($fs)
            $fs.Close(); $stream.Close(); $resp.Close()
            return (Test-ValidInstallerFile -FilePath $OutPath -ExpectedType "zip" -MinSizeBytes 10000000)
        }

        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $html = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()

        $confirm = if ($html -match 'name="confirm"\s+value="([^"]+)"') { $matches[1] } else { "t" }
        $uuid = if ($html -match 'name="uuid"\s+value="([^"]+)"') { $matches[1] } else { "" }

        # Unduh melalui endpoint konten resmi
        $dlUrl = "https://drive.usercontent.google.com/download?id=$FileId&export=download&confirm=$confirm"
        if ($uuid) {
            $dlUrl += "&uuid=$uuid"
        }

        $req2 = [System.Net.HttpWebRequest]::Create($dlUrl)
        $req2.CookieContainer = $cookieContainer
        $req2.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LABInstaller"
        $req2.AllowAutoRedirect = $true

        $resp2 = $req2.GetResponse()
        if ($resp2.ContentType -match "text/html") {
            $sr2 = New-Object System.IO.StreamReader($resp2.GetResponseStream())
            $html2 = $sr2.ReadToEnd()
            $sr2.Close(); $resp2.Close()
            if ($html2 -match 'Quota exceeded|Too many users') {
                Write-LogWarning "Kuota unduhan Google Drive untuk berkas ini tercapai."
            }
            return $false
        }

        $stream2 = $resp2.GetResponseStream()
        $fs = [System.IO.File]::Create($OutPath)
        $stream2.CopyTo($fs)
        $fs.Close(); $stream2.Close(); $resp2.Close()

        $isValid = (Test-ValidInstallerFile -FilePath $OutPath -ExpectedType "zip" -MinSizeBytes 10000000)
        if (-not $isValid -and (Test-Path -Path $OutPath)) {
            Remove-Item -Path $OutPath -Force -ErrorAction SilentlyContinue
        }
        return $isValid
    }
    catch {
        return $false
    }
}

function Invoke-GoogleDriveMultiMirrorDownload {
    param (
        [string[]]$MirrorIds,
        [string]$DestinationPath,
        [string]$AppName = "Aplikasi"
    )

    if (Test-Path -Path $DestinationPath) {
        $existingSize = (Get-Item -Path $DestinationPath).Length
        if ($existingSize -gt 100000) { # Lebih dari 100 KB
            Write-LogSuccess "Berkas installer $AppName sudah tersedia di penyimpanan lokal (Cache): $DestinationPath ($([math]::Round($existingSize/1MB, 2)) MB)."
            return $true
        }
    }

    $mirrorNum = 1
    foreach ($mId in $MirrorIds) {
        if ([string]::IsNullOrWhiteSpace($mId)) { continue }
        Write-LogInfo "Mencoba mengunduh $AppName dari Google Drive [Mirror #$mirrorNum (ID: $mId)]..."

        $dlSuccess = Invoke-GoogleDriveFileDownload -FileId $mId -OutPath $DestinationPath
        if ($dlSuccess -and (Test-Path -Path $DestinationPath) -and (Get-Item -Path $DestinationPath).Length -gt 100000) {
            $mb = [math]::Round((Get-Item -Path $DestinationPath).Length / 1MB, 2)
            Write-LogSuccess "Berhasil mengunduh $AppName dari Google Drive Mirror #$mirrorNum ($mb MB)!"
            return $true
        } else {
            Write-LogWarning "Mirror #$mirrorNum gagal atau kuota unduh Google Drive tercapai. Mencoba mirror cadangan berikutnya..."
            if (Test-Path -Path $DestinationPath) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            }
        }
        $mirrorNum++
    }

    Write-LogWarning "Seluruh mirror Google Drive untuk $AppName tidak dapat diakses atau limit. Mengalihkan ke server tercepat vendor..."
    return $false
}

function Invoke-PackageInstall {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package,
        [switch]$IsUpgrade
    )

    $pkgName = $Package.name
    Write-LogStep "MEMPROSES INSTALASI: $pkgName [Prioritas: P$($Package.priority)]..."

    # 1. Jalur Custom Handler
    if ($Package.type -eq "custom") {
        $handler = $Package.customHandler
        if ($handler -and (Get-Command $handler -ErrorAction SilentlyContinue)) {
            $ok = & $handler -Package $Package
            return $ok
        } else {
            Write-LogError "Handler kustom '$handler' tidak ditemukan untuk $pkgName."
            return $false
        }
    }

    # 1b. Jalur Local Cache Folder apps (Jika file installer fisik sudah ada di apps/ atau direktori proyek)
    $appsDir = Get-AppStorageDirectory
    $targetFileName = if ($Package.fileName) { $Package.fileName } else { "" }
    $pkgType = if ($Package.installType) { $Package.installType.ToLower() } else { "exe" }
    $minExpectedSize = if ($Package.id -in @("ApacheFriends.Xampp.8.2", "Custom.Laragon")) { 50000000 } else { 1000000 }
    $localCacheFile = $null

    if ($targetFileName) {
        $exactPath = Join-Path -Path $appsDir -ChildPath $targetFileName
        if (Test-Path -Path $exactPath) {
            if (Test-ValidInstallerFile -FilePath $exactPath -ExpectedType $pkgType -MinSizeBytes $minExpectedSize) {
                $localCacheFile = $exactPath
            } else {
                Write-LogWarning "Berkas di cache ($exactPath) tidak valid atau korup (halaman HTML/ukuran tidak sesuai). Menghapus cache..."
                Remove-Item -Path $exactPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $localCacheFile) {
        # Cari file alternatif di folder apps yang cocok dengan nama paket / pattern installer (misal hasil unduhan WinGet)
        $matchedFile = Get-ChildItem -Path $appsDir -Filter "*.$pkgType" -ErrorAction SilentlyContinue | Where-Object {
            (Test-ValidInstallerFile -FilePath $_.FullName -ExpectedType $pkgType -MinSizeBytes $minExpectedSize) -and (
                ($targetFileName -and $_.Name -like "*$($targetFileName -replace '\.[^.]+$','')*") -or
                ($Package.id -and $_.Name -like "*$($Package.id.Split('.')[-1])*") -or
                ($Package.name -and $_.Name -like "*$($Package.name.Split(' ')[0])*")
            )
        } | Select-Object -First 1

        if ($matchedFile) {
            $localCacheFile = $matchedFile.FullName
        }
    }

    if ($localCacheFile -and (Test-Path -Path $localCacheFile)) {
        $mb = [math]::Round((Get-Item -Path $localCacheFile).Length / 1MB, 2)
        Write-LogSuccess "Berkas installer $pkgName ditemukan di folder apps (Cache Lokal): $localCacheFile ($mb MB)."
        Write-LogInfo "Menjalankan instalasi offline dari folder apps tanpa mengunduh ulang..."
        $installed = Install-LocalFilePackage -Package $Package -FilePath $localCacheFile
        if ($installed) {
            return $true
        }
        Write-LogWarning "Instalasi dari berkas lokal di folder apps gagal. Beralih ke metode pengunduhan berikutnya..."
    }

    # 2. Jalur Google Drive Mirror (Prioritas Utama Pengguna: Cepat & Hemat Kuota)
    if ($Package.gdriveMirrors -and $Package.gdriveMirrors.Count -gt 0) {
        $targetFileName = if ($Package.fileName) { $Package.fileName } else { "installer_$($Package.id).exe" }
        $gdriveLocalFile = Join-Path -Path $appsDir -ChildPath $targetFileName

        Write-LogInfo "Memprioritaskan pengunduhan dari Google Drive Mirror resmi..."
        $gdriveDownloaded = Invoke-GoogleDriveMultiMirrorDownload -MirrorIds $Package.gdriveMirrors -DestinationPath $gdriveLocalFile -AppName $pkgName

        if ($gdriveDownloaded -and (Test-Path -Path $gdriveLocalFile)) {
            Write-LogInfo "Menjalankan instalasi dari paket Google Drive ($targetFileName)..."
            $installed = Install-LocalFilePackage -Package $Package -FilePath $gdriveLocalFile
            if ($installed) {
                return $true
            }
            Write-LogWarning "Gagal memasang dari paket Google Drive lokal. Mencoba metode alternatif..."
        }
    }

    # 2b. Jalur Direct Vendor Prioritas (Jika paket di-flag preferDirect untuk server cepat seperti GitHub Releases)
    if ($Package.preferDirect -and -not [string]::IsNullOrWhiteSpace($Package.directUrl)) {
        Write-LogInfo "Memprioritaskan unduhan langsung berkecepatan tinggi dari server vendor resmi/GitHub..."
        $directSuccess = Invoke-DirectInstaller -Package $Package
        if ($directSuccess) {
            return $true
        }
        Write-LogWarning "Unduhan langsung vendor gagal. Mencoba metode alternatif..."
    }

    # 3. Jalur Winget (Jika Winget sehat dan paket memiliki wingetId)
    $wingetHealthy = Test-WingetHealth
    if ($wingetHealthy -and -not [string]::IsNullOrWhiteSpace($Package.wingetId)) {
        Write-LogInfo "Mencoba instalasi via Microsoft WinGet..."
        $wingetSuccess = Invoke-WingetInstall -Package $Package -IsUpgrade:$IsUpgrade
        if ($wingetSuccess) {
            return $true
        }
        Write-LogWarning "Instalasi via WinGet gagal atau bermasalah. Mengaktifkan mesin cadangan (Fallback Langsung Vendor)..."
    }
    elseif (-not $wingetHealthy) {
        Write-LogInfo "WinGet tidak aktif pada OS ini. Menggunakan mesin unduhan langsung vendor..."
    }

    # 4. Jalur Fallback Unduhan Langsung Vendor (Bulletproof Direct Fallback)
    if (-not [string]::IsNullOrWhiteSpace($Package.directUrl)) {
        $directSuccess = Invoke-DirectInstaller -Package $Package
        return $directSuccess
    }

    Write-LogError "Tidak ada metode instalasi yang tersedia untuk $pkgName."
    return $false
}

function Invoke-WingetInstall {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package,
        [switch]$IsUpgrade
    )

    $wingetId = $Package.wingetId
    $action = if ($IsUpgrade) { "upgrade" } else { "install" }

    $wingetArgs = @(
        $action,
        "--exact",
        "--id", $wingetId,
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity",
        "--silent"
    )

    if (-not [string]::IsNullOrWhiteSpace($Package.installOverride)) {
        $wingetArgs += @("--override", $Package.installOverride)
    }

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "winget.exe"
        $pinfo.Arguments = ($wingetArgs -join " ")
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($pinfo)
        $timeoutMs = if ($Package.id -match "VisualStudio") { 1800000 } else { 900000 }
        $completed = $process.WaitForExit($timeoutMs)

        if ($completed -and ($process.ExitCode -eq 0 -or $process.ExitCode -eq 2316632107)) {
            Write-LogSuccess "$($Package.name) berhasil dipasang via WinGet (ExitCode: 0)."
            Refresh-CurrentSessionEnvironment
            return $true
        } else {
            if (-not $completed) { $process.Kill() }
            Write-LogWarning "WinGet selesai dengan kode keluar: $($process.ExitCode)."
            return $false
        }
    }
    catch {
        Write-LogWarning "Terjadi error saat mengeksekusi WinGet: $_"
        return $false
    }
}

function Install-LocalFilePackage {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package,
        [string]$FilePath
    )

    $pkgName = $Package.name
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $appsDir = Get-AppStorageDirectory

    try {
        if ($ext -eq ".msi") {
            Write-LogInfo "Memasang paket MSI: $FilePath..."
            $msiArgs = "/i `"$FilePath`" $($Package.directArgs) /norestart"
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                Write-LogSuccess "$pkgName berhasil dipasang via MSI."
                Refresh-CurrentSessionEnvironment
                return $true
            } else {
                Write-LogError "Pemasangan MSI gagal dengan kode keluar: $($p.ExitCode)"
                return $false
            }
        }
        elseif ($ext -eq ".exe") {
            Write-LogInfo "Memasang paket EXE: $FilePath..."
            $p = Start-Process -FilePath $FilePath -ArgumentList $Package.directArgs -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                Write-LogSuccess "$pkgName berhasil dipasang via EXE."
                Refresh-CurrentSessionEnvironment
                return $true
            } else {
                if ($Package.id -eq "Google.Chrome" -and (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe")) {
                    Write-LogSuccess "$pkgName berhasil dipasang."
                    return $true
                }
                if ($p.ExitCode -eq -2147024784 -or $p.ExitCode -eq 2147942512) {
                    Write-LogError "Pemasangan $pkgName GAGAL KARENA RUANG DISK PENUH (ERROR_DISK_FULL - 0x80070070)!"
                    Write-LogWarning "Mohon perbesar kapasitas disk Virtual Machine atau kosongkan minimal 8-12 GB di Drive C:."
                } else {
                    Write-LogError "Pemasangan EXE gagal dengan kode keluar: $($p.ExitCode)"
                }
                return $false
            }
        }
        elseif ($ext -eq ".rar") {
            Write-LogInfo "Mengekstrak paket RAR: $FilePath menggunakan 7-Zip..."
            $extractDir = Join-Path -Path $appsDir -ChildPath "$($Package.id)_extracted"
            if (-not (Test-Path $extractDir)) { New-Item -ItemType Directory -Path $extractDir -Force | Out-Null }
            
            $sevenZipExe = "C:\Program Files\7-Zip\7z.exe"
            if (-not (Test-Path $sevenZipExe)) {
                $sevenZipCmd = Get-Command "7z.exe" -ErrorAction SilentlyContinue
                if ($sevenZipCmd) { $sevenZipExe = $sevenZipCmd.Source }
            }

            if (Test-Path $sevenZipExe) {
                Start-Process -FilePath $sevenZipExe -ArgumentList "x `"$FilePath`" -o`"$extractDir`" -y" -NoNewWindow -Wait
                $setupExe = Get-ChildItem -Path $extractDir -Recurse -Filter "*.exe" | Select-Object -First 1
                if ($setupExe) {
                    Write-LogInfo "Menjalankan installer yang diekstrak: $($setupExe.FullName)..."
                    $p = Start-Process -FilePath $setupExe.FullName -ArgumentList $Package.directArgs -NoNewWindow -Wait -PassThru
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                        Write-LogSuccess "$pkgName berhasil dipasang!"
                        Refresh-CurrentSessionEnvironment
                        return $true
                    }
                }
            } else {
                Write-LogError "7-Zip diperlukan untuk mengekstrak berkas .rar. Pastikan 7-Zip terpasang terlebih dahulu."
            }
            return $false
        }
        elseif ($ext -eq ".zip") {
            $destDir = if ($Package.extractDir) { $Package.extractDir } else { "C:\tools\$($Package.id)" }
            Write-LogInfo "Mengekstrak paket ZIP ke $destDir..."
            Expand-Archive -Path $FilePath -DestinationPath $destDir -Force
            Add-DirectoryToPath -PathToAdd $destDir -Scope "Machine" | Out-Null
            Write-LogSuccess "$pkgName berhasil diekstrak dan didaftarkan ke sistem PATH."
            Refresh-CurrentSessionEnvironment
            return $true
        }
        return $false
    }
    catch {
        Write-LogError "Gagal memasang paket $pkgName dari berkas lokal: $_"
        return $false
    }
}

function Invoke-DirectInstaller {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package
    )

    $pkgName = $Package.name
    $url = $Package.directUrl
    $type = if ($Package.installType) { $Package.installType.ToLower() } else { "exe" }
    $appsDir = Get-AppStorageDirectory
    $fileName = if ($Package.fileName) { $Package.fileName } else { "labinst_$($Package.id -replace '[^a-zA-Z0-9]','_').$type" }
    $localFile = Join-Path -Path $appsDir -ChildPath $fileName
    $minExpectedSize = if ($Package.id -in @("ApacheFriends.Xampp.8.2", "Custom.Laragon")) { 50000000 } else { 1000000 }

    # Gunakan cache lokal jika file sudah ada dan ukurannya serta integritasnya valid
    if (Test-Path -Path $localFile) {
        if (Test-ValidInstallerFile -FilePath $localFile -ExpectedType $type -MinSizeBytes $minExpectedSize) {
            Write-LogSuccess "Berkas installer $pkgName sudah tersedia di folder apps (Cache Valid): $localFile"
            return (Install-LocalFilePackage -Package $Package -FilePath $localFile)
        } else {
            Write-LogWarning "Berkas di cache ($localFile) terdeteksi korup/tidak valid. Menghapus dan mengunduh ulang..."
            Remove-Item -Path $localFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-LogStep "Mengunduh langsung installer resmi $pkgName..."
    Write-LogInfo "Sumber Vendor: $url"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        # Gunakan User-Agent Wget agar SourceForge & CDN vendor langsung mengirim biner installer tanpa interupsi landing page HTML
        $wc.Headers.Add("User-Agent", "Wget/1.21.3")

        # Unduh dengan retry hingga 2 kali
        $downloadSuccess = $false
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                if ($attempt -gt 1) { Write-LogInfo "Mencoba mengunduh ulang (Percobaan $attempt)..." }
                $wc.DownloadFile($url, $localFile)
                if (Test-ValidInstallerFile -FilePath $localFile -ExpectedType $type -MinSizeBytes $minExpectedSize) {
                    $downloadSuccess = $true
                    break
                } else {
                    Write-LogWarning "Berkas hasil unduhan tidak lolos validasi header/ukuran. Menghapus percobaan..."
                    if (Test-Path -Path $localFile) { Remove-Item -Path $localFile -Force -ErrorAction SilentlyContinue }
                }
            }
            catch {
                Start-Sleep -Seconds 2
            }
        }

        if (-not $downloadSuccess) {
            throw "Gagal mengunduh berkas installer yang valid dari tautan vendor."
        }

        return (Install-LocalFilePackage -Package $Package -FilePath $localFile)
    }
    catch {
        Write-LogError "Gagal memasang $pkgName via Direct Installer - $_"
        return $false
    }
}
