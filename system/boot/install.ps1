# ==============================================================================
# LABInstaller - One-Line Remote Bootstrapper
# Dijalankan via: irm "https://raw.githubusercontent.com/MuslimGunawan/LABInstaller/main/system/boot/install.ps1?$([Guid]::NewGuid())" | iex
# ==============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Nonaktifkan QuickEdit Mode agar klik mouse pada konsol tidak membekukan script
try {
    $codeQE = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleQuickEditBoot {
    const uint ENABLE_QUICK_EDIT = 0x0040;
    const uint ENABLE_EXTENDED = 0x0080;
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void Disable() {
        try {
            IntPtr h = GetStdHandle(-10);
            uint m;
            if (GetConsoleMode(h, out m)) {
                m &= ~ENABLE_QUICK_EDIT;
                m |= ENABLE_EXTENDED;
                SetConsoleMode(h, m);
            }
        } catch {}
    }
}
"@
    if (-not ([System.Management.Automation.PSTypeName]'ConsoleQuickEditBoot').Type) {
        Add-Type -TypeDefinition $codeQE -ErrorAction SilentlyContinue
    }
    [ConsoleQuickEditBoot]::Disable()
} catch {}

# 1. Tangkap Lokasi Aktif Terminal Pemanggil
$currentLocation = (Get-Location).ProviderPath
if ([string]::IsNullOrWhiteSpace($currentLocation)) {
    $currentLocation = (Get-Location).Path
}

# Jika diteruskan dari proses elevasi sebelumnya via variabel environment
if ($env:LAB_TARGET_DIR -and (Test-Path -Path $env:LAB_TARGET_DIR)) {
    $currentLocation = $env:LAB_TARGET_DIR
}

# 2. Pengecekan Hak Akses Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host " [PERHATIAN] LABInstaller Memerlukan Hak Administrator!" -ForegroundColor Yellow
    Write-Host " Membuka jendela PowerShell Administrator baru..." -ForegroundColor Cyan
    Write-Host " Lokasi Target: $currentLocation" -ForegroundColor DarkGray
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host ""
    
    $elevateCommand = "`$env:LAB_TARGET_DIR = '$currentLocation'; Set-Location -LiteralPath '$currentLocation'; irm 'https://api.github.com/repos/MuslimGunawan/LABInstaller/contents/system/boot/install.ps1' -H @{Accept='application/vnd.github.v3.raw'; 'User-Agent'='LABInstaller'} | iex"
    Start-Process powershell.exe -WorkingDirectory "$currentLocation" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevateCommand`"" -Verb RunAs
    exit
}

# 3. Tentukan Lokasi Instalasi Berdasarkan Direktori Terminal Aktif
if ($currentLocation -like "*system32*" -or $currentLocation -like "*SysWOW64*") {
    # Jangan pernah instal ke folder sistem Windows (system32)!
    if (Test-Path "D:\") {
        $installDir = "D:\LABInstaller"
    } else {
        $installDir = Join-Path -Path $env:SystemDrive -ChildPath "LABInstaller"
    }
} elseif ((Split-Path -Leaf $currentLocation) -ieq "LABInstaller" -or (Test-Path -Path (Join-Path -Path $currentLocation -ChildPath "installer.ps1"))) {
    $installDir = $currentLocation
} else {
    $installDir = Join-Path -Path $currentLocation -ChildPath "LABInstaller"
}

Clear-Host
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   _        _    ____  ___           _        _ _             " -ForegroundColor Cyan
Write-Host "  | |      / \  | __ )|_ _|_ __  ___| |_ __ _| | | ___ _ __   " -ForegroundColor Cyan
Write-Host "  | |     / _ \ |  _ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|  " -ForegroundColor Cyan
Write-Host "  | |___ / ___ \| |_) || || | | \__ \ || (_| | | |  __/ |     " -ForegroundColor Cyan
Write-Host "  |_____/_/   \_\____/|___|_| |_|___/\__\__,_|_|_|\___|_|     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  LABInstaller One-Line Bootstrapper untuk PC Lab Komputer" -ForegroundColor White
Write-Host "  Lokasi Terminal  : $currentLocation" -ForegroundColor DarkGray
Write-Host "  Target Direktori : $installDir" -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

$zipUrl = "https://codeload.github.com/MuslimGunawan/LABInstaller/zip/refs/heads/main"
$tempZip = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "labinstaller_boot_$([Guid]::NewGuid().ToString('N')).zip"
$tempExtract = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "labinstaller_ext_$([Guid]::NewGuid().ToString('N'))"

try {
    Write-Host "[1/4] Mengunduh paket sistem LABInstaller terbaru dari GitHub..." -ForegroundColor Cyan
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "LABInstaller-Bootstrapper")
    $webClient.Headers.Add("Cache-Control", "no-cache")
    $webClient.DownloadFile($zipUrl, $tempZip)

    if (-not (Test-Path -Path $tempZip)) {
        throw "Gagal mengunduh berkas arsip dari GitHub."
    }

    Write-Host "[2/4] Mengekstrak berkas sistem..." -ForegroundColor Cyan
    if (Test-Path -Path $tempExtract) {
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

    $subFolders = Get-ChildItem -Path $tempExtract -Directory
    $extractedRoot = if ($subFolders.Count -eq 1) { $subFolders[0].FullName } else { $tempExtract }

    Write-Host "[3/4] Menyiapkan direktori $installDir..." -ForegroundColor Cyan
    if (-not (Test-Path -Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    # Salin berkas ke direktori target yang dipilih
    $items = Get-ChildItem -Path $extractedRoot
    foreach ($item in $items) {
        Copy-Item -Path $item.FullName -Destination $installDir -Recurse -Force
    }

    # Buat Shortcut di Desktop Publik agar semua pengguna Lab bisa mengakses
    try {
        $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
        if (-not $publicDesktop -or -not (Test-Path -Path $publicDesktop)) {
            $publicDesktop = "C:\Users\Public\Desktop"
        }
        $shortcutPath = Join-Path -Path $publicDesktop -ChildPath "LABInstaller.lnk"
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "C:\Windows\System32\cmd.exe"
        $shortcut.Arguments = "/c `"$installDir\run.bat`""
        $shortcut.WorkingDirectory = $installDir
        $shortcut.Description = "Sistem Instalasi Pintar & Software Lab Komputer"
        $shortcut.Save()
        Write-Host "      Shortcut berhasil dibuat di Desktop: $shortcutPath" -ForegroundColor Green
    }
    catch {
        # Lewati jika gagal membuat shortcut desktop
    }

    Write-Host "[4/4] Memulai LABInstaller..." -ForegroundColor Green
    Write-Host ""
    Start-Sleep -Seconds 1

    # Jalankan installer.ps1 langsung di direktori yang baru diinstall
    $entryScript = Join-Path -Path $installDir -ChildPath "installer.ps1"
    Set-Location -Path $installDir
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entryScript
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Terjadi kegagalan saat menjalankan bootstrapper: $_" -ForegroundColor Red
    Write-Host "Tekan tombol apa saja untuk keluar..."
    [void][System.Console]::ReadKey()
}
finally {
    # Bersihkan file temporer
    if (Test-Path -Path $tempZip) {
        Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path $tempExtract) {
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
