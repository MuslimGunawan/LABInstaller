# ==============================================================================
# LABInstaller - Core Logger
# Mendukung output berwarna konsol & pencatatan berkas log terperinci
# ==============================================================================

$global:LabLogFile = $null

function Initialize-Logger {
    param (
        [string]$LogDir = "logs"
    )

    if (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $global:LabLogFile = Join-Path -Path $LogDir -ChildPath "labinstaller_$timestamp.log"
    
    # Inisialisasi header file log
    $header = @"
================================================================================
LABInstaller - Log Aktivitas Sistem
Waktu Mulai : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Windows OS  : $((Get-CimInstance Win32_OperatingSystem).Caption) ($((Get-CimInstance Win32_OperatingSystem).Version))
PowerShell  : $($PSVersionTable.PSVersion.ToString())
================================================================================
"@
    Set-Content -Path $global:LabLogFile -Value $header -Encoding UTF8
}

function Write-LogMessage {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $timeStr = Get-Date -Format "HH:mm:ss"
    $tag = "[$Level]"

    # Tampilkan ke layar dengan warna
    Write-Host "[$timeStr] " -NoNewline -ForegroundColor DarkGray
    Write-Host "$tag " -NoNewline -ForegroundColor $Color
    Write-Host $Message

    # Tulis ke file log jika file log sudah diinisialisasi
    if ($global:LabLogFile -and (Test-Path -Path (Split-Path -Parent $global:LabLogFile))) {
        $logLine = "[$timeStr] $tag $Message"
        Add-Content -Path $global:LabLogFile -Value $logLine -Encoding UTF8
    }
}

function Write-LogInfo {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "INFO" -Color Cyan
}

function Write-LogSuccess {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "OK" -Color Green
}

function Write-LogWarning {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "WARN" -Color Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "ERROR" -Color Red
}

function Write-LogStep {
    param([string]$Message)
    Write-LogMessage -Message ">>> $Message" -Level "STEP" -Color Magenta
}

function Write-LogSkip {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "SKIP" -Color DarkYellow
}

function Show-LabBanner {
    param (
        [string]$Version = "1.0.0"
    )

    Clear-Host
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "   _        _    ____  ___           _        _ _             " -ForegroundColor Cyan
    Write-Host "  | |      / \  | __ )|_ _|_ __  ___| |_ __ _| | | ___ _ __   " -ForegroundColor Cyan
    Write-Host "  | |     / _ \ |  _ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|  " -ForegroundColor Cyan
    Write-Host "  | |___ / ___ \| |_) || || | | \__ \ || (_| | | |  __/ |     " -ForegroundColor Cyan
    Write-Host "  |_____/_/   \_\____/|___|_| |_|___/\__\__,_|_|_|\___|_|     " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "  Sistem Instalasi & Manajemen Environment Otomatis Windows" -ForegroundColor White
    Write-Host "  Versi: $Version | Repositori: MuslimGunawan/LABInstaller" -ForegroundColor DarkGray
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

