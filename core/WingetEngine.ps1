# ==============================================================================
# LABInstaller - Core Winget Engine
# Wrapper resmi instalasi, upgrade, dan penghapusan aplikasi via Windows Package Manager
# ==============================================================================

function Invoke-WingetInstall {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Package,
        [switch]$IsUpgrade
    )

    $wingetId = $Package.wingetId
    $actionName = if ($IsUpgrade) { "Memperbarui (Upgrade)" } else { "Menginstal" }
    Write-LogStep "$actionName $($Package.name) [$wingetId]..."

    $wingetArgs = @()
    if ($IsUpgrade) {
        $wingetArgs += "upgrade"
    } else {
        $wingetArgs += "install"
    }

    $wingetArgs += @(
        "--exact",
        "--id", $wingetId,
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent"
    )

    if (-not [string]::IsNullOrWhiteSpace($Package.installOverride)) {
        $wingetArgs += @("--override", $Package.installOverride)
    }

    Write-LogInfo "Menjalankan perintah: winget $($wingetArgs -join ' ')"

    try {
        $process = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode

        # Kode keluar winget: 0 = Sukses, 0x8A15002B = Sudah up to date
        if ($exitCode -eq 0 -or $exitCode -eq 2316632107) {
            Write-LogSuccess "$($Package.name) berhasil diproses (ExitCode: 0)."
            Refresh-CurrentSessionEnvironment
            return $true
        } else {
            Write-LogError "Instalasi $($Package.name) gagal dengan kode keluar: $exitCode (0x$($exitCode.ToString('X')))."
            return $false
        }
    }
    catch {
        Write-LogError "Terjadi kesalahan saat memanggil winget untuk $($Package.name) - $_"
        return $false
    }
}

function Invoke-WingetUninstall {
    param (
        [Parameter(Mandatory=$true)]
        [string]$WingetId,
        [string]$PackageName = ""
    )

    $displayName = if ($PackageName) { $PackageName } else { $WingetId }
    Write-LogStep "Menghapus versi lama: $displayName..."

    $wingetArgs = @(
        "uninstall",
        "--exact",
        "--id", $WingetId,
        "--silent",
        "--accept-source-agreements"
    )

    try {
        $process = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-LogSuccess "Berhasil menghapus versi lama $displayName."
            return $true
        } else {
            Write-LogWarning "Proses penghapusan $displayName selesai dengan kode: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-LogError "Gagal menjalankan uninstall untuk $displayName - $_"
        return $false
    }
}
