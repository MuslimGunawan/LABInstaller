# ==============================================================================
# LABInstaller - Core Environment Manager
# Pengelolaan PATH sistem, JAVA_HOME, dan refresh environment tanpa restart PC
# ==============================================================================

function Add-DirectoryToPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PathToAdd,
        [ValidateSet("Machine", "User")]
        [string]$Scope = "Machine"
    )

    if (-not (Test-Path -Path $PathToAdd)) {
        Write-LogWarning "Direktori '$PathToAdd' tidak ditemukan pada disk, namun tetap diperiksa."
    }

    try {
        $targetScope = if ($Scope -eq "Machine") { [System.EnvironmentVariableTarget]::Machine } else { [System.EnvironmentVariableTarget]::User }
        $currentPath = [System.Environment]::GetEnvironmentVariable("Path", $targetScope)

        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $pathList = @()
        } else {
            $pathList = $currentPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }

        # Periksa apakah path sudah ada (case-insensitive)
        $normalizedNew = $PathToAdd.TrimEnd('\', '/')
        $alreadyExists = $false

        foreach ($p in $pathList) {
            if ($p.TrimEnd('\', '/').Equals($normalizedNew, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyExists = $true
                break
            }
        }

        if (-not $alreadyExists) {
            $newPathString = ($pathList + $PathToAdd) -join ';'
            [System.Environment]::SetEnvironmentVariable("Path", $newPathString, $targetScope)
            Write-LogSuccess "Menambahkan ke PATH ($Scope): $PathToAdd"

            # Perbarui variabel sesi saat ini juga
            if ($env:Path -split ';' -notcontains $PathToAdd) {
                $env:Path = "$env:Path;$PathToAdd"
            }

            Broadcast-EnvironmentChange
            return $true
        } else {
            Write-LogInfo "Path sudah terdaftar di PATH ($Scope): $PathToAdd"
            
            # Pastikan sesi aktif juga memiliki path ini
            if ($env:Path -split ';' -notcontains $PathToAdd) {
                $env:Path = "$env:Path;$PathToAdd"
            }
            return $false
        }
    }
    catch {
        Write-LogError "Gagal menambahkan '$PathToAdd' ke PATH ($Scope) - $_"
        return $false
    }
}

function Set-SystemEnvironmentVariable {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [ValidateSet("Machine", "User")]
        [string]$Scope = "Machine"
    )

    try {
        $targetScope = if ($Scope -eq "Machine") { [System.EnvironmentVariableTarget]::Machine } else { [System.EnvironmentVariableTarget]::User }
        $currentVal = [System.Environment]::GetEnvironmentVariable($Name, $targetScope)

        if ($currentVal -ne $Value) {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, $targetScope)
            [System.Environment]::SetEnvironmentVariable($Name, $Value, [System.EnvironmentVariableTarget]::Process)
            Write-LogSuccess "Environment Variable $Name ($Scope) diatur ke: $Value"
            Broadcast-EnvironmentChange
            return $true
        } else {
            Write-LogInfo "Environment Variable $Name ($Scope) sudah sesuai: $Value"
            return $false
        }
    }
    catch {
        Write-LogError "Gagal mengatur Environment Variable $Name - $_"
        return $false
    }
}

function Refresh-CurrentSessionEnvironment {
    # Muat ulang PATH dari Machine dan User ke sesi saat ini
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    $combinedPath = "$machinePath;$userPath"

    $env:Path = $combinedPath

    # Muat ulang JAVA_HOME jika ada
    $javaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::Machine)
    if ($javaHome) {
        $env:JAVA_HOME = $javaHome
    }
}

function Broadcast-EnvironmentChange {
    try {
        # Kirim sinyal WM_SETTINGCHANGE ke semua window Windows agar mereka reload environment
        $code = @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
"@
        if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) {
            Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
        }

        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $SMTO_ABORTIFHUNG = 0x0002
        $result = [UIntPtr]::Zero

        [WinAPI]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", $SMTO_ABORTIFHUNG, 3000, [ref]$result) | Out-Null
    }
    catch {
        # Fallback senyap jika API user32 tidak terjangkau (misal session non-GUI)
    }
}
