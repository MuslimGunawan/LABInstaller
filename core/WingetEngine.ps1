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

    # 2. Jalur Winget (Jika Winget sehat dan paket memiliki wingetId)
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

    # 3. Jalur Fallback Unduhan Langsung Vendor (Bulletproof Direct Fallback)
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

function Invoke-DirectInstaller {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package
    )

    $pkgName = $Package.name
    $url = $Package.directUrl
    $type = if ($Package.installType) { $Package.installType.ToLower() } else { "exe" }
    $tempDir = [System.IO.Path]::GetTempPath()
    $localFile = Join-Path -Path $tempDir -ChildPath "labinst_$($Package.id -replace '[^a-zA-Z0-9]','_').$type"

    Write-LogStep "Mengunduh langsung installer resmi $pkgName..."
    Write-LogInfo "Sumber Vendor: $url"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) LABInstaller/1.0.3")

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

        # Eksekusi Instalasi Berdasarkan Tipe Berkas
        if ($type -eq "zip") {
            $destDir = if ($Package.extractDir) { $Package.extractDir } else { "C:\tools\$($Package.id)" }
            Write-LogInfo "Mengekstrak paket zip ke: $destDir..."
            if (-not (Test-Path -Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Expand-Archive -Path $localFile -DestinationPath $destDir -Force
            Add-DirectoryToPath -PathToAdd $destDir -Scope "Machine" | Out-Null
            Write-LogSuccess "$pkgName berhasil diekstrak dan didaftarkan ke sistem PATH."
            Refresh-CurrentSessionEnvironment
            return $true
        }
        elseif ($type -eq "msi") {
            Write-LogInfo "Menjalankan msiexec secara silent..."
            $msiArgs = "/i `"$localFile`" $($Package.directArgs) /norestart"
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                Write-LogSuccess "$pkgName berhasil dipasang via MSI installer resmi."
                Refresh-CurrentSessionEnvironment
                return $true
            } else {
                Write-LogError "Pemasangan MSI gagal dengan kode keluar: $($p.ExitCode)"
                return $false
            }
        }
        else { # EXE
            Write-LogInfo "Menjalankan installer EXE secara silent..."
            $p = Start-Process -FilePath $localFile -ArgumentList $Package.directArgs -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                Write-LogSuccess "$pkgName berhasil dipasang via EXE installer resmi."
                Refresh-CurrentSessionEnvironment
                return $true
            } else {
                # Beberapa installer seperti Chrome mengembalikan kode keluar tertentu saat sukses
                if ($Package.id -eq "Google.Chrome" -and (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe")) {
                    Write-LogSuccess "$pkgName berhasil dipasang (Chrome terdeteksi)."
                    return $true
                }
                Write-LogError "Installer EXE selesai dengan kode keluar: $($p.ExitCode)"
                return $false
            }
        }
    }
    catch {
        Write-LogError "Gagal memasang $pkgName via Direct Installer - $_"
        return $false
    }
    finally {
        if (Test-Path -Path $localFile) {
            Remove-Item -Path $localFile -Force -ErrorAction SilentlyContinue
        }
    }
}
