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

# ==============================================================================
# LAB KEEPALIVE GUARD (ANTI-SLEEP & ANTI-IDLE SHUTDOWN)
# Mengantisipasi komputer Lab yang mati/tidur otomatis jika idle selama 10 menit
# ==============================================================================
$global:LabKeepAliveActive = $false

function Initialize-LabKeepAliveAPI {
    $csharpCode = @"
using System;
using System.Threading;
using System.Runtime.InteropServices;

public class LabKeepAliveAPI {
    [Flags]
    public enum EXECUTION_STATE : uint {
        ES_AWAYMODE_REQUIRED = 0x00000040,
        ES_CONTINUOUS        = 0x80000000,
        ES_DISPLAY_REQUIRED  = 0x00000002,
        ES_SYSTEM_REQUIRED   = 0x00000001
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private static Timer _timer;

    public static void StartHeartbeat(int intervalMs = 45000) {
        if (_timer == null) {
            _timer = new Timer(OnTick, null, 0, intervalMs);
        }
    }

    public static void StopHeartbeat() {
        if (_timer != null) {
            _timer.Dispose();
            _timer = null;
        }
        try {
            SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
        } catch {}
    }

    private static void OnTick(object state) {
        try {
            // Jaga sistem dan layar tetap aktif (mencegah sleep/hibernasi Windows)
            SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS | EXECUTION_STATE.ES_SYSTEM_REQUIRED | EXECUTION_STATE.ES_DISPLAY_REQUIRED);
            // Simulasikan pergerakan mouse 1 piksel dan kembalikan seketika (mereset GetLastInputInfo idle timer ke 0)
            mouse_event(MOUSEEVENTF_MOVE, 1, 1, 0, UIntPtr.Zero);
            mouse_event(MOUSEEVENTF_MOVE, -1, -1, 0, UIntPtr.Zero);
        } catch {}
    }
}
"@
    if (-not ([System.Management.Automation.PSTypeName]'LabKeepAliveAPI').Type) {
        Add-Type -TypeDefinition $csharpCode -ErrorAction SilentlyContinue
    }
}

function Start-LabKeepAliveGuard {
    if ($global:LabKeepAliveActive) {
        return
    }

    try {
        Initialize-LabKeepAliveAPI

        # 1. Mulai Heartbeat timer C# (setiap 45 detik pulsa mouse & SetThreadExecutionState)
        if (([System.Management.Automation.PSTypeName]'LabKeepAliveAPI').Type) {
            [LabKeepAliveAPI]::StartHeartbeat(45000)
        }

        # 2. Nonaktifkan standby, hibernate, dan monitor timeout via powercfg
        Start-Process -FilePath "powercfg" -ArgumentList "/change standby-timeout-ac 0" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
        Start-Process -FilePath "powercfg" -ArgumentList "/change hibernate-timeout-ac 0" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
        Start-Process -FilePath "powercfg" -ArgumentList "/change monitor-timeout-ac 0" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null

        $global:LabKeepAliveActive = $true
        if (Get-Command Write-LogSuccess -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Lab Keep-Alive Guard AKTIF: Komputer Lab dilindungi dari shutdown/sleep otomatis akibat idle 10 menit!"
        }
    } catch {
        if (Get-Command Write-LogWarning -ErrorAction SilentlyContinue) {
            Write-LogWarning "Gagal menginisialisasi penuh Lab Keep-Alive Guard: $_"
        }
    }
}

function Stop-LabKeepAliveGuard {
    if (-not $global:LabKeepAliveActive) {
        return
    }

    try {
        if (([System.Management.Automation.PSTypeName]'LabKeepAliveAPI').Type) {
            [LabKeepAliveAPI]::StopHeartbeat()
        }
        $global:LabKeepAliveActive = $false
        if (Get-Command Write-LogInfo -ErrorAction SilentlyContinue) {
            Write-LogInfo "Lab Keep-Alive Guard dinonaktifkan."
        }
    } catch {}
}

