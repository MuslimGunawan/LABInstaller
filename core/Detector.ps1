# ==============================================================================
# LABInstaller - Core Detector (Zero-Hang Hybrid Engine)
# Pendeteksian instan berbasis Windows Registry & CLI (100% Offline, Anti-Freeze, Anti-Shim)
# ==============================================================================

$global:RegistryAppCache = $null

function Initialize-RegistryCache {
    param([switch]$ForceRefresh)

    if ($global:RegistryAppCache -and -not $ForceRefresh) {
        return $global:RegistryAppCache
    }

    $global:RegistryAppCache = @()

    $regTargets = @(
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Registry64 },
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Registry32 },
        @{ Hive = [Microsoft.Win32.RegistryHive]::CurrentUser;  Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Default }
    )

    foreach ($target in $regTargets) {
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($target.Hive, $target.View)
            $subKey = $baseKey.OpenSubKey($target.Path)
            if ($subKey) {
                foreach ($subName in $subKey.GetSubKeyNames()) {
                    try {
                        $appKey = $subKey.OpenSubKey($subName)
                        if ($appKey) {
                            $dispName = $appKey.GetValue("DisplayName")
                            if ($dispName -and -not [string]::IsNullOrWhiteSpace($dispName.ToString())) {
                                $dispVer = $appKey.GetValue("DisplayVersion")
                                $instLoc = $appKey.GetValue("InstallLocation")
                                $global:RegistryAppCache += [PSCustomObject]@{
                                    DisplayName     = $dispName.ToString().Trim()
                                    DisplayVersion  = if ($dispVer) { $dispVer.ToString().Trim() } else { "Terpasang" }
                                    InstallLocation = if ($instLoc) { $instLoc.ToString().Trim() } else { "" }
                                }
                            }
                            $appKey.Close()
                        }
                    } catch {}
                }
                $subKey.Close()
            }
            $baseKey.Close()
        } catch {}
    }

    return $global:RegistryAppCache
}

function Convert-ToVersionObject {
    param ([string]$VersionString)
    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }

    $clean = ($VersionString -replace '^[^\d]*', '')
    $match = [regex]::Match($clean, '^\d+(\.\d+)*')
    if (-not $match.Success) { return $null }

    $parts = $match.Value -split '\.'
    if ($parts.Count -eq 1) {
        $clean = "$($parts[0]).0"
    } elseif ($parts.Count -gt 4) {
        $clean = ($parts[0..3] -join '.')
    } else {
        $clean = $match.Value
    }

    try {
        return [version]$clean
    } catch {
        return $null
    }
}

function Test-PackagePhysicalPresence {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package,
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$RegistryMatch
    )

    # ATURAN MUTLAK 0: Web Server Stack (Laragon & XAMPP)
    # Wajib memiliki file eksekutif utama di root C:\ (C:\laragon\laragon.exe & C:\xampp\xampp-control.exe).
    # Jangan pernah percaya residu pintasan desktop/Start Menu/Registry jika berkas fisik root tidak ada!
    if ($Package.id -eq "Custom.Laragon") {
        return (Test-Path -Path "C:\laragon\laragon.exe")
    }
    if ($Package.id -eq "ApacheFriends.Xampp.8.2") {
        return (Test-Path -Path "C:\xampp\xampp-control.exe")
    }

    # 1. Cek pathCheck langsung jika ada
    if (-not [string]::IsNullOrWhiteSpace($Package.pathCheck)) {
        if ($Package.pathCheck -match '\*') {
            $foundItem = Get-Item -Path $Package.pathCheck -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundItem) { return $true }
        } elseif (Test-Path -Path $Package.pathCheck) {
            return $true
        }

        # Cek variasi Program Files (x86) jika pathCheck berada di Program Files
        if ($Package.pathCheck -match 'Program Files' -and $Package.pathCheck -notmatch 'Program Files \(x86\)') {
            $x86Path = $Package.pathCheck -replace 'Program Files', 'Program Files (x86)'
            if ($x86Path -match '\*') {
                $foundItem = Get-Item -Path $x86Path -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundItem) { return $true }
            } elseif (Test-Path -Path $x86Path) {
                return $true
            }
        }
    }

    # 2. Cek InstallLocation dari Registry (Wajib memuat biner .exe aplikasi, bukan folder kosong atau file log)
    if (-not [string]::IsNullOrWhiteSpace($RegistryMatch.InstallLocation)) {
        $instLoc = $RegistryMatch.InstallLocation.Trim('"').Trim()
        if (Test-Path -Path $instLoc) {
            $items = Get-ChildItem -Path $instLoc -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)(unins|setup|install|update)' } | Select-Object -First 1
            if ($items) { return $true }
        }
    }

    # 3. Cek DisplayIcon dari Registry (Hanya jika mengarah ke berkas executable .exe yang benar-benar ada di disk)
    if (-not [string]::IsNullOrWhiteSpace($RegistryMatch.DisplayIcon)) {
        $rawIcon = ($RegistryMatch.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"').Trim()
        if ($rawIcon -and (Test-Path -Path $rawIcon) -and ($rawIcon -match '\.exe$') -and ($rawIcon -notmatch '(?i)(unins|setup|install|update)')) {
            return $true
        }
    }

    # 4. Cek Pintasan Desktop & Start Menu
    # ATURAN KRITIS: Pintasan (.lnk) WAJIB diverifikasi target filenya (TargetPath).
    # Jika target file tidak ada di disk (dead/ghost link), pintasan dianggap sampah dan TIDAK membuktikan software terpasang!
    $wscript = $null
    try { $wscript = New-Object -ComObject WScript.Shell } catch {}

    $shortcutDirs = @(
        "C:\Users\Public\Desktop",
        [Environment]::GetFolderPath('Desktop'),
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    $searchTerms = @($Package.name, $RegistryMatch.DisplayName)
    if ($Package.registryPattern) { $searchTerms += $Package.registryPattern }

    if ($wscript) {
        foreach ($sDir in $shortcutDirs) {
            if (-not (Test-Path -Path $sDir)) { continue }
            $shortcuts = Get-ChildItem -Path $sDir -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue | Select-Object -First 150
            foreach ($sc in $shortcuts) {
                $matchedTerm = $false
                foreach ($term in $searchTerms) {
                    if ($sc.BaseName -like "*$term*" -or $term -like "*$($sc.BaseName)*") {
                        $matchedTerm = $true
                        break
                    }
                }
                if ($matchedTerm) {
                    try {
                        $targetPath = $wscript.CreateShortcut($sc.FullName).TargetPath
                        if ($targetPath -and (Test-Path -Path $targetPath) -and ($targetPath -match '\.exe$') -and ($targetPath -notmatch '(?i)(unins|setup|install|update)')) {
                            return $true
                        }
                    } catch {}
                }
            }
        }
    }

    # 5. Fallback Khusus Berdasarkan ID Aplikasi
    switch ($Package.id) {
        "Apache.NetBeans" {
            $nbCandidates = @(
                "C:\Program Files\Apache NetBeans*\bin\*.exe",
                "C:\Program Files\NetBeans*\bin\*.exe",
                "C:\Program Files (x86)\Apache NetBeans*\bin\*.exe",
                "C:\Program Files (x86)\NetBeans*\bin\*.exe",
                "C:\Program Files*\NetBeans*\netbeans\bin\*.exe",
                "C:\Program Files*\Apache NetBeans*\netbeans\bin\*.exe",
                "C:\NetBeans*\bin\*.exe"
            )
            foreach ($c in $nbCandidates) {
                $item = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($item) { return $true }
            }
            return $false
        }
        "ArduinoSA.IDE.stable" {
            $ardCandidates = @(
                "C:\Program Files\Arduino*\*.exe",
                "C:\Program Files (x86)\Arduino*\*.exe",
                "C:\Program Files\Arduino IDE*\*.exe",
                "C:\Program Files (x86)\Arduino IDE*\*.exe",
                "$env:LOCALAPPDATA\Programs\arduino-ide\*.exe",
                "$env:LOCALAPPDATA\Programs\Arduino IDE\*.exe"
            )
            foreach ($c in $ardCandidates) {
                $item = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($item) { return $true }
            }
            return $false
        }
    }

    # 6. Jika paket mendefinisikan pathCheck namun tidak ada satupun bukti biner fisik yang ditemukan di disk:
    # Wajib return $false agar residu registry/pintasan tidak membohongi detektor instalasi!
    if (-not [string]::IsNullOrWhiteSpace($Package.pathCheck)) {
        return $false
    }

    # Default untuk paket non-pathCheck yang terdaftar di registry Windows
    return $true
}

function Get-PackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package
    )

    if (-not $global:RegistryAppCache) {
        Initialize-RegistryCache | Out-Null
    }

    $priorityVal = if ($null -ne $Package.priority) { [int]$Package.priority } else { 99 }

    $result = [PSCustomObject]@{
        Id               = $Package.id
        Name             = $Package.name
        Category         = $Package.category
        Type             = $Package.type
        Priority         = $priorityVal
        Status           = "NOT_INSTALLED"
        InstalledVersion = "-"
        TargetVersion    = "Terbaru"
        Details          = "Belum terpasang di sistem operasi."
        RawPackage       = $Package
    }

    # Pengecekan Khusus Dependensi: Composer & Laravel Installer wajib memiliki PHP aktif yang berfungsi
    if ($Package.id -in @("Custom.Composer", "Custom.LaravelInstaller")) {
        $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
        if (-not $phpCmd) {
            $fallbackPhp = @(
                "C:\tools\php85\php.exe",
                "C:\laragon\bin\php\*\php.exe",
                "C:\xampp\php\php.exe",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\PHP.PHP.8.5*\php.exe"
            )
            foreach ($cand in $fallbackPhp) {
                $f = Resolve-Path -Path $cand -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($f -and (Test-Path -Path $f.Path)) {
                    $phpCmd = [PSCustomObject]@{ Source = $f.Path }
                    break
                }
            }
        }
        if (-not $phpCmd) {
            $result.Status = "NOT_INSTALLED"
            $result.Details = "Memerlukan runtime PHP aktif (PHP 8.5) yang belum terpasang."
            return $result
        }
    }

    # 1. Jalur Pemeriksaan 1: Path Spesifik Disk (pathCheck)
    if (-not [string]::IsNullOrWhiteSpace($Package.pathCheck)) {
        # Abaikan pathCheck untuk batch/script tool jika harus divalidasi lewat verifyCommand
        $isScriptOnly = ($Package.pathCheck -match '\.(bat|cmd|ps1)$') -and (-not [string]::IsNullOrWhiteSpace($Package.verifyCommand))
        if (-not $isScriptOnly) {
            $resolvedPaths = @()
            if ($Package.pathCheck -match '\*') {
                $resolvedPaths = Get-Item -Path $Package.pathCheck -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            } elseif (Test-Path -Path $Package.pathCheck) {
                $resolvedPaths = @($Package.pathCheck)
            }

            # Cek variasi Program Files (x86) jika pathCheck berada di Program Files
            if ($resolvedPaths.Count -eq 0 -and $Package.pathCheck -match 'Program Files' -and $Package.pathCheck -notmatch 'Program Files \(x86\)') {
                $x86Path = $Package.pathCheck -replace 'Program Files', 'Program Files (x86)'
                if ($x86Path -match '\*') {
                    $resolvedPaths = Get-Item -Path $x86Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
                } elseif (Test-Path -Path $x86Path) {
                    $resolvedPaths = @($x86Path)
                }
            }

            if ($resolvedPaths.Count -gt 0) {
                $targetPath = $resolvedPaths[0]
                $fileVer = (Get-Item $targetPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
                $result.InstalledVersion = if ($fileVer) { $fileVer } else { "Terpasang" }
                $result.TargetVersion = $result.InstalledVersion

                # Validasi batas minimal versi (minVersion)
                if ($Package.minVersion -and $fileVer) {
                    $vInst = Convert-ToVersionObject -VersionString $fileVer
                    $vReq  = Convert-ToVersionObject -VersionString $Package.minVersion
                    if ($vInst -and $vReq -and ($vInst -lt $vReq)) {
                        $result.TargetVersion = $Package.minVersion
                        $result.Status = "UPDATE_AVAILABLE"
                        $result.Details = "Versi berkas ($fileVer) lebih lama dari target lab ($($Package.minVersion)). Perlu upgrade."
                        return $result
                    }
                }

                $result.Status = "UP_TO_DATE"
                $result.Details = "Terdeteksi pada berkas: $targetPath"
                return $result
            }
        }
    }

    # 2. Jalur Pemeriksaan 2: CLI Command di PATH (verifyCommand)
    if (-not [string]::IsNullOrWhiteSpace($Package.verifyCommand)) {
        $cmdName = $Package.verifyCommand
        $foundCmd = Get-Command $cmdName -ErrorAction SilentlyContinue

        # Abaikan WindowsApps dummy shims (seperti python.exe redirector ke Microsoft Store)
        if ($foundCmd -and $foundCmd.Source -like "*\Microsoft\WindowsApps\*") {
            $allCmds = Get-Command $cmdName -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike "*\Microsoft\WindowsApps\*" }
            $foundCmd = if ($allCmds) { $allCmds[0] } else { $null }
        }

        if (-not $foundCmd) {
            $fallbackPath = Get-CustomCommandFallbackPath -CommandName $cmdName
            if ($fallbackPath -and (Test-Path -Path $fallbackPath)) {
                $foundCmd = [PSCustomObject]@{ Source = $fallbackPath }
            }
        }

        if ($foundCmd) {
            $vOutput = Get-CommandVersionOutput -CommandPath $foundCmd.Source -VerifyArgs $Package.verifyArgs
            if ($vOutput) {
                $result.InstalledVersion = $vOutput
                $result.TargetVersion = $result.InstalledVersion

                # Validasi batas minimal versi (minVersion)
                if ($Package.minVersion) {
                    $vInst = Convert-ToVersionObject -VersionString $vOutput
                    $vReq  = Convert-ToVersionObject -VersionString $Package.minVersion
                    if ($vInst -and $vReq -and ($vInst -lt $vReq)) {
                        $result.TargetVersion = $Package.minVersion
                        $result.Status = "UPDATE_AVAILABLE"
                        $result.Details = "Versi CLI aktif ($vOutput di $($foundCmd.Source)) lebih lama dari target lab ($($Package.minVersion)). Perlu upgrade."
                        return $result
                    }
                }

                $result.Status = "UP_TO_DATE"
                $result.Details = "Terdeteksi via perintah CLI ($($foundCmd.Source))."
                return $result
            }
        }
    }

    # 3. Jalur Pemeriksaan 3: Windows Registry Uninstall Keys (registryPattern)
    $pattern = if ($Package.registryPattern) { $Package.registryPattern } else { [regex]::Escape($Package.name) }
    
    $match = $global:RegistryAppCache | Where-Object { $_.DisplayName -match $pattern } | Select-Object -First 1
    if ($match) {
        # Validasi Integritas Fisik Disk (Anti-Residu Registry / Ghost Uninstaller)
        # Jika paket mendefinisikan pathCheck (contoh: Laragon di C:\laragon\laragon.exe, XAMPP di C:\xampp\xampp-control.exe),
        # pastikan berkas fisiknya BENAR-BENAR ada di disk sebelum menyatakan UP_TO_DATE.
        if (-not [string]::IsNullOrWhiteSpace($Package.pathCheck)) {
            $hasPhysical = Test-PackagePhysicalPresence -Package $Package -RegistryMatch $match
            if (-not $hasPhysical) {
                $result.Status = "NOT_INSTALLED"
                $result.InstalledVersion = "-"
                $result.TargetVersion = "Terbaru"
                $result.Details = "Residu Registry terdeteksi ($($match.DisplayName)), namun berkas fisik ($($Package.pathCheck)) tidak ditemukan di disk. Diperlukan instalasi bersih."
                return $result
            }
        }

        # Validasi jika paket memiliki verifyCommand namun binary CLI tidak ada di sistem
        if (-not [string]::IsNullOrWhiteSpace($Package.verifyCommand)) {
            $cliCheck = Get-Command $Package.verifyCommand -ErrorAction SilentlyContinue
            if (-not $cliCheck) {
                $fallbackCli = Get-CustomCommandFallbackPath -CommandName $Package.verifyCommand
                if (-not ($fallbackCli -and (Test-Path -Path $fallbackCli))) {
                    $result.Status = "NOT_INSTALLED"
                    $result.InstalledVersion = "-"
                    $result.TargetVersion = "Terbaru"
                    $result.Details = "Residu Registry terdeteksi ($($match.DisplayName)), namun CLI ($($Package.verifyCommand)) tidak ditemukan di PATH. Diperlukan instalasi bersih."
                    return $result
                }
            }
        }

        $result.InstalledVersion = if ($match.DisplayVersion) { $match.DisplayVersion } else { "Terpasang" }
        $result.TargetVersion = $result.InstalledVersion

        # Validasi batas minimal versi (minVersion)
        if ($Package.minVersion -and $match.DisplayVersion) {
            $vInst = Convert-ToVersionObject -VersionString $match.DisplayVersion
            $vReq  = Convert-ToVersionObject -VersionString $Package.minVersion
            if ($vInst -and $vReq -and ($vInst -lt $vReq)) {
                $result.TargetVersion = $Package.minVersion
                $result.Status = "UPDATE_AVAILABLE"
                $result.Details = "Versi di Registry ($($match.DisplayVersion)) lebih lama dari target lab ($($Package.minVersion)). Perlu upgrade."
                return $result
            }
        }

        $result.Status = "UP_TO_DATE"
        $result.Details = "Terdaftar di Registry Windows: $($match.DisplayName)"
        return $result
    }

    # Jika tidak terdeteksi pada ketiga jalur di atas, maka paket belum terpasang
    $result.Status = "NOT_INSTALLED"
    $result.InstalledVersion = "-"
    $result.TargetVersion = "Terbaru"
    $result.Details = "Software belum ditemukan di Registry atau sistem PATH."

    return $result
}

function Get-CustomCommandFallbackPath {
    param([string]$CommandName)

    switch ($CommandName.ToLower()) {
        "flutter" {
            $candidates = @("C:\tools\flutter\bin\flutter.bat", "C:\src\flutter\bin\flutter.bat", "$env:LOCALAPPDATA\flutter\bin\flutter.bat")
            foreach ($c in $candidates) {
                if (Test-Path -Path $c) { return $c }
            }
        }
        "composer" {
            $candidates = @("C:\ProgramData\ComposerSetup\bin\composer.bat", "$env:APPDATA\Composer\vendor\bin\composer.bat")
            foreach ($c in $candidates) {
                if (Test-Path -Path $c) { return $c }
            }
        }
        "laravel" {
            $candidates = @("$env:APPDATA\Composer\vendor\bin\laravel.bat")
            foreach ($c in $candidates) {
                if (Test-Path -Path $c) { return $c }
            }
        }
        "pip" {
            $candidates = @(
                "$env:LOCALAPPDATA\Programs\Python\Python3*\Scripts\pip.exe",
                "C:\Program Files\Python3*\Scripts\pip.exe",
                "C:\Python3*\Scripts\pip.exe"
            )
            foreach ($c in $candidates) {
                $matched = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($matched) { return $matched.FullName }
            }
        }
    }
    return $null
}

function Get-CommandVersionOutput {
    param (
        [string]$CommandPath,
        [string[]]$VerifyArgs
    )

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $CommandPath
        $pinfo.Arguments = ($VerifyArgs -join " ")
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $exited = $p.WaitForExit(3000)
        if (-not $exited) {
            try { $p.Kill() } catch {}
            return $null
        }

        # Jika kode keluar non-zero, perintah gagal dieksekusi secara normal
        if ($p.ExitCode -ne 0) {
            return $null
        }

        $combined = ($stdout + "`n" + $stderr)

        # Tolak pesan error sistem Windows / CLI
        $errorPhrases = @(
            "is not recognized",
            "not recognized",
            "tidak dikenal",
            "cannot find",
            "tidak dapat menemukan",
            "python was not found",
            "microsoft store",
            "the specified module could not be found",
            "fatal error",
            "uncaught exception",
            "syntax error"
        )
        foreach ($ep in $errorPhrases) {
            if ($combined -match [regex]::Escape($ep)) {
                return $null
            }
        }

        # Ekstrak nomor versi dari baris-baris output
        $allLines = ($stdout -split '\r?\n') + ($stderr -split '\r?\n') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach ($line in $allLines) {
            if ($line -match 'v?(\d+\.\d+(\.\d+)?)') {
                return $matches[1]
            }
        }

        # Jika bersih tanpa error tapi tidak memiliki format versi standar
        $firstClean = $allLines | Select-Object -First 1
        if ($firstClean -and $firstClean.Length -lt 40) {
            return $firstClean.Trim()
        }

        return $null
    }
    catch {
        return $null
    }
}

function Load-AllManifestPackages {
    param (
        [string]$ManifestDir = "manifests"
    )

    $allPackages = @()
    if (-not (Test-Path -Path $ManifestDir)) { return $allPackages }

    $jsonFiles = Get-ChildItem -Path $ManifestDir -Filter "*.json" | Sort-Object Name
    foreach ($file in $jsonFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($content) {
                $allPackages += $content
            }
        }
        catch {
            Write-LogError "Gagal membaca manifest file '$($file.Name)' - $_"
        }
    }

    # Urutkan berdasarkan prioritas instalasi (Dependency ordering, P0 s/d P15)
    $sortedPackages = $allPackages | Sort-Object @{Expression={if ($null -ne $_.priority) { [int]$_.priority } else { 99 }}}
    return $sortedPackages
}
