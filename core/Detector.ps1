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

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($key in $uninstallKeys) {
        Get-ItemProperty $key -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.DisplayName) {
                $global:RegistryAppCache += [PSCustomObject]@{
                    DisplayName     = $_.DisplayName.Trim()
                    DisplayVersion  = if ($_.DisplayVersion) { $_.DisplayVersion.Trim() } else { "Terpasang" }
                    InstallLocation = if ($_.InstallLocation) { $_.InstallLocation.Trim() } else { "" }
                }
            }
        }
    }

    return $global:RegistryAppCache
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

    # 1. Jalur Pemeriksaan 1: Path Spesifik Disk (pathCheck)
    if (-not [string]::IsNullOrWhiteSpace($Package.pathCheck)) {
        $resolvedPaths = @()
        if ($Package.pathCheck -match '\*') {
            $resolvedPaths = Get-Item -Path $Package.pathCheck -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        } elseif (Test-Path -Path $Package.pathCheck) {
            $resolvedPaths = @($Package.pathCheck)
        }

        if ($resolvedPaths.Count -gt 0) {
            $targetPath = $resolvedPaths[0]
            $fileVer = (Get-Item $targetPath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
            $result.InstalledVersion = if ($fileVer) { $fileVer } else { "Terpasang" }
            $result.TargetVersion = $result.InstalledVersion
            $result.Status = "UP_TO_DATE"
            $result.Details = "Terdeteksi pada berkas: $targetPath"
            return $result
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
            if ($vOutput -and $vOutput -notmatch "Python was not found" -and $vOutput -notmatch "Microsoft Store") {
                $result.InstalledVersion = $vOutput
                $result.TargetVersion = $result.InstalledVersion
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
        $result.InstalledVersion = $match.DisplayVersion
        $result.TargetVersion = $match.DisplayVersion
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
        [void]$p.WaitForExit(2000)

        $output = if (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout } else { $stderr }

        # Filter out WindowsApps stub redirect message
        if ($output -match "Python was not found" -or $output -match "Microsoft Store") {
            return $null
        }

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

    # Urutkan berdasarkan prioritas instalasi (Dependency ordering, P0 s/d P15)
    $sortedPackages = $allPackages | Sort-Object @{Expression={if ($null -ne $_.priority) { [int]$_.priority } else { 99 }}}
    return $sortedPackages
}
