# ==============================================================================
# LABInstaller - Core Detector
# Mendeteksi status paket secara cerdas: Belum Terpasang / Butuh Update / Up-to-date
# ==============================================================================

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
        Status           = "UNKNOWN" # NOT_INSTALLED, UPDATE_AVAILABLE, UP_TO_DATE
        InstalledVersion = "-"
        TargetVersion    = "-"
        Details          = ""
        RawPackage       = $Package
    }

    if ($Package.type -eq "winget") {
        # Deteksi via Winget
        $wingetId = $Package.wingetId
        $listOutput = winget list --exact --id $wingetId 2>&1

        $isInstalled = $true
        foreach ($line in $listOutput) {
            if ($line -match "No installed package found" -or $line -match "Tidak ada paket yang terinstal") {
                $isInstalled = $false
                break
            }
        }

        if (-not $isInstalled) {
            $result.Status = "NOT_INSTALLED"
            # Coba cari versi target di repo winget
            $searchOutput = winget search --exact --id $wingetId 2>&1
            $parsedTarget = Parse-WingetSearchVersion -OutputLines $searchOutput -PackageId $wingetId
            if ($parsedTarget) {
                $result.TargetVersion = $parsedTarget
            }
            $result.Details = "Belum terpasang di sistem operasi."
        }
        else {
            # Terpasang, ekstrak versi dan cek apakah ada pembaruan
            $parsedInfo = Parse-WingetListInfo -OutputLines $listOutput -PackageId $wingetId
            if ($parsedInfo.InstalledVersion) {
                $result.InstalledVersion = $parsedInfo.InstalledVersion
            }

            if ($parsedInfo.AvailableVersion -and $parsedInfo.AvailableVersion -ne $parsedInfo.InstalledVersion) {
                $result.Status = "UPDATE_AVAILABLE"
                $result.TargetVersion = $parsedInfo.AvailableVersion
                $result.Details = "Versi lama terpasang ($($result.InstalledVersion)), tersedia versi baru ($($result.TargetVersion))."
            }
            else {
                $result.Status = "UP_TO_DATE"
                $result.TargetVersion = $result.InstalledVersion
                $result.Details = "Sudah terpasang dan berada pada versi terbaru."
            }
        }
    }
    elseif ($Package.type -eq "custom") {
        # Deteksi untuk paket khusus seperti Flutter, Composer, Laravel
        $cmdName = $Package.verifyCommand
        $foundCmd = Get-Command $cmdName -ErrorAction SilentlyContinue

        if (-not $foundCmd) {
            # Coba cek path khusus jika belum masuk di PATH sesi
            $fallbackPath = Get-CustomCommandFallbackPath -CommandName $cmdName
            if ($fallbackPath -and (Test-Path -Path $fallbackPath)) {
                $foundCmd = [PSCustomObject]@{ Source = $fallbackPath }
            }
        }

        if (-not $foundCmd) {
            $result.Status = "NOT_INSTALLED"
            $result.Details = "CLI/Tools '$cmdName' belum terdeteksi di sistem."
        }
        else {
            $versionString = Get-CommandVersionOutput -CommandPath $foundCmd.Source -VerifyArgs $Package.verifyArgs
            $result.InstalledVersion = if ($versionString) { $versionString } else { "Terpasang" }
            $result.TargetVersion = $result.InstalledVersion
            $result.Status = "UP_TO_DATE"
            $result.Details = "Sudah terpasang di $($foundCmd.Source)."
        }
    }

    return $result
}

function Parse-WingetListInfo {
    param (
        [string[]]$OutputLines,
        [string]$PackageId
    )

    $installedVer = $null
    $availableVer = $null

    $headerIndex = -1
    for ($i = 0; $i -lt $OutputLines.Count; $i++) {
        if ($OutputLines[$i] -match "---") {
            $headerIndex = $i
            break
        }
    }

    if ($headerIndex -ge 0 -and ($headerIndex + 1) -lt $OutputLines.Count) {
        $header = $OutputLines[$headerIndex - 1]
        $hasAvailableCol = $header -match "Available"

        for ($j = $headerIndex + 1; $j -lt $OutputLines.Count; $j++) {
            $line = $OutputLines[$j].Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            if ($line -match [regex]::Escape($PackageId)) {
                $tokens = $line -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                # Pola umum: [Name...], Id, Version, [Available]
                $idIndex = -1
                for ($k = 0; $k -lt $tokens.Count; $k++) {
                    if ($tokens[$k] -eq $PackageId) {
                        $idIndex = $k
                        break
                    }
                }

                if ($idIndex -ge 0 -and ($idIndex + 1) -lt $tokens.Count) {
                    $installedVer = $tokens[$idIndex + 1]
                    if ($hasAvailableCol -and ($idIndex + 2) -lt $tokens.Count) {
                        $availableVer = $tokens[$idIndex + 2]
                    }
                }
                break
            }
        }
    }

    return [PSCustomObject]@{
        InstalledVersion = $installedVer
        AvailableVersion = $availableVer
    }
}

function Parse-WingetSearchVersion {
    param (
        [string[]]$OutputLines,
        [string]$PackageId
    )

    $headerIndex = -1
    for ($i = 0; $i -lt $OutputLines.Count; $i++) {
        if ($OutputLines[$i] -match "---") {
            $headerIndex = $i
            break
        }
    }

    if ($headerIndex -ge 0 -and ($headerIndex + 1) -lt $OutputLines.Count) {
        for ($j = $headerIndex + 1; $j -lt $OutputLines.Count; $j++) {
            $line = $OutputLines[$j].Trim()
            if ($line -match [regex]::Escape($PackageId)) {
                $tokens = $line -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                for ($k = 0; $k -lt $tokens.Count; $k++) {
                    if ($tokens[$k] -eq $PackageId -and ($k + 1) -lt $tokens.Count) {
                        return $tokens[$k + 1]
                    }
                }
            }
        }
    }

    return $null
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
        $p.WaitForExit(4000)

        $output = if (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout } else { $stderr }
        $firstLine = ($output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)

        if ($firstLine) {
            # Ambil pola angka versi jika memungkinkan (misal: "1.2.3")
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
            Write-LogError "Gagal membaca manifest file '$($file.Name)': $_"
        }
    }

    return $allPackages
}

