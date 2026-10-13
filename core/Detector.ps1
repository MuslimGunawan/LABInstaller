# ==============================================================================
# LABInstaller - Core Detector (High-Performance Engine)
# Mendeteksi status paket secara instan dengan caching Winget in-memory
# ==============================================================================

$global:WingetCache = $null

function Initialize-WingetCache {
    param([switch]$ForceRefresh)

    if ($global:WingetCache -and -not $ForceRefresh) {
        return $global:WingetCache
    }

    $global:WingetCache = @{}
    Write-LogInfo "Memuat basis data paket terpasang Windows (Caching)..."

    try {
        $rawList = winget list 2>&1
        $headerIndex = -1

        for ($i = 0; $i -lt $rawList.Count; $i++) {
            if ($rawList[$i] -match "---") {
                $headerIndex = $i
                break
            }
        }

        if ($headerIndex -ge 0) {
            for ($j = $headerIndex + 1; $j -lt $rawList.Count; $j++) {
                $line = $rawList[$j].Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                # Split berdasarkan multiple whitespace
                $tokens = $line -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                if ($tokens.Count -ge 3) {
                    $pkgName = $tokens[0].Trim()
                    $pkgId   = $tokens[1].Trim()
                    $pkgVer  = $tokens[2].Trim()
                    $pkgAvail = if ($tokens.Count -ge 4) { $tokens[3].Trim() } else { $null }

                    $item = @{
                        Name      = $pkgName
                        Installed = $pkgVer
                        Available = $pkgAvail
                    }

                    $global:WingetCache[$pkgId] = $item
                    # Simpan juga dengan key lowercase untuk pencarian toleran
                    $global:WingetCache[$pkgId.ToLower()] = $item
                }
            }
        }
    }
    catch {
        Write-LogWarning "Gagal memuat cache Winget: $_"
    }

    return $global:WingetCache
}

function Get-PackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package
    )

    $result = [PSCustomObject]@{
        Id               = $Package.id
        Name             = $Package.name
        Category         = $Package.category
        Type             = $Package.type
        Priority         = if ($Package.priority) { [int]$Package.priority } else { 99 }
        Status           = "UNKNOWN" # NOT_INSTALLED, UPDATE_AVAILABLE, UP_TO_DATE
        InstalledVersion = "-"
        TargetVersion    = "Terbaru"
        Details          = ""
        RawPackage       = $Package
    }

    if ($Package.type -eq "winget") {
        # Pastikan cache winget sudah aktif
        if (-not $global:WingetCache) {
            Initialize-WingetCache | Out-Null
        }

        $wId = $Package.wingetId
        $cached = $null

        if ($global:WingetCache.ContainsKey($wId)) {
            $cached = $global:WingetCache[$wId]
        } elseif ($global:WingetCache.ContainsKey($wId.ToLower())) {
            $cached = $global:WingetCache[$wId.ToLower()]
        }

        if ($cached) {
            $result.InstalledVersion = $cached.Installed
            if (-not [string]::IsNullOrWhiteSpace($cached.Available) -and $cached.Available -ne $cached.Installed) {
                $result.Status = "UPDATE_AVAILABLE"
                $result.TargetVersion = $cached.Available
                $result.Details = "Versi lama terpasang ($($cached.Installed)), tersedia pembaruan ($($cached.Available))."
            } else {
                $result.Status = "UP_TO_DATE"
                $result.TargetVersion = $cached.Installed
                $result.Details = "Sudah terpasang dan sesuai dengan versi rilis stabil."
            }
        } else {
            $result.Status = "NOT_INSTALLED"
            $result.Details = "Belum terpasang di sistem operasi."
        }
    }
    elseif ($Package.type -eq "custom") {
        # Deteksi khusus untuk tool khusus
        switch ($Package.id) {
            "Custom.Laragon" {
                $laragonExe = "C:\laragon\laragon.exe"
                if (Test-Path -Path $laragonExe) {
                    $ver = (Get-Item $laragonExe).VersionInfo.ProductVersion
                    $result.InstalledVersion = if ($ver) { $ver } else { "6.0.0" }
                    $result.TargetVersion = "6.0.0"
                    $result.Status = "UP_TO_DATE"
                    $result.Details = "Laragon terpasang di C:\laragon (v$($result.InstalledVersion))."
                } else {
                    $result.Status = "NOT_INSTALLED"
                    $result.TargetVersion = "6.0.0"
                    $result.Details = "Laragon belum terpasang di C:\laragon."
                }
            }
            Default {
                $cmdName = $Package.verifyCommand
                $foundCmd = Get-Command $cmdName -ErrorAction SilentlyContinue

                if (-not $foundCmd) {
                    $fallbackPath = Get-CustomCommandFallbackPath -CommandName $cmdName
                    if ($fallbackPath -and (Test-Path -Path $fallbackPath)) {
                        $foundCmd = [PSCustomObject]@{ Source = $fallbackPath }
                    }
                }

                if (-not $foundCmd) {
                    $result.Status = "NOT_INSTALLED"
                    $result.Details = "Tool '$cmdName' belum terdeteksi di PATH sistem."
                } else {
                    $versionString = Get-CommandVersionOutput -CommandPath $foundCmd.Source -VerifyArgs $Package.verifyArgs
                    $result.InstalledVersion = if ($versionString) { $versionString } else { "Terpasang" }
                    $result.TargetVersion = $result.InstalledVersion
                    $result.Status = "UP_TO_DATE"
                    $result.Details = "Sudah terpasang di $($foundCmd.Source)."
                }
            }
        }
    }

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
        $p.WaitForExit(3000)

        $output = if (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout } else { $stderr }
        $firstLine = ($output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)

        if ($firstLine) {
            if ($firstLine -match '(\d+\.\d+(\.\d+)?)') {
                return $matches[1]
            }
            return $firstLine.Trim()
        }
        return "Terdeteksi"
    }
    catch {
        return "Terdeteksi"
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

    # Urutkan berdasarkan prioritas instalasi (Dependency ordering)
    $sortedPackages = $allPackages | Sort-Object @{Expression={if ($_.priority) { [int]$_.priority } else { 99 }}}
    return $sortedPackages
}
