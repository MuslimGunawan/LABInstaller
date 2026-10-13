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
            return ((Test-Path $OutPath) -and ((Get-Item $OutPath).Length -gt 1000))
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
        $stream2 = $resp2.GetResponseStream()
        $fs = [System.IO.File]::Create($OutPath)
        $stream2.CopyTo($fs)
        $fs.Close(); $stream2.Close(); $resp2.Close()

        return ((Test-Path $OutPath) -and ((Get-Item $OutPath).Length -gt 1000))
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
            $ok = & $handler
            return $ok
        } else {
            Write-LogError "Handler kustom '$handler' tidak ditemukan untuk $pkgName."
            return $false
        }
    }

    # 2. Jalur Google Drive Mirror (Prioritas Utama Pengguna: Cepat & Hemat Kuota)
    $appsDir = Get-AppStorageDirectory
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
        # Timeout 10 menit untuk download besar
        $completed = $process.WaitForExit(600000)

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
                Write-LogError "Pemasangan EXE gagal dengan kode keluar: $($p.ExitCode)"
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

    # Gunakan cache lokal jika file sudah ada dan ukurannya valid
    if (Test-Path -Path $localFile) {
        $existLen = (Get-Item -Path $localFile).Length
        if ($existLen -gt 100000) {
            Write-LogSuccess "Berkas installer $pkgName sudah tersedia di folder apps (Cache): $localFile"
            return (Install-LocalFilePackage -Package $Package -FilePath $localFile)
        }
    }

    Write-LogStep "Mengunduh langsung installer resmi $pkgName..."
    Write-LogInfo "Sumber Vendor: $url"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LABInstaller/1.0.6")

        # Unduh dengan retry hingga 2 kali
        $downloadSuccess = $false
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                if ($attempt -gt 1) { Write-LogInfo "Mencoba mengunduh ulang (Percobaan $attempt)..." }
                $wc.DownloadFile($url, $localFile)
                if (Test-Path -Path $localFile) {
                    $downloadSuccess = $true
                    break
                }
            }
            catch {
                Start-Sleep -Seconds 2
            }
        }

        if (-not $downloadSuccess) {
            throw "Gagal mengunduh berkas installer dari tautan vendor."
        }

        return (Install-LocalFilePackage -Package $Package -FilePath $localFile)
    }
    catch {
        Write-LogError "Gagal memasang $pkgName via Direct Installer - $_"
        return $false
    }
}
