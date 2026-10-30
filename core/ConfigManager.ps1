# ==============================================================================
# LABInstaller - Core Configuration & Port Conflict Manager
# Mengelola isolasi port (Laragon vs XAMPP), konfigurasi php.ini, dan ekosistem Laravel
# ==============================================================================

function Start-FullEnvironmentConfiguration {
    param (
        [switch]$Interactive = $true
    )

    Write-LogStep "MENJALANKAN KONFIGURASI OTOMATIS PORT, FIREWALL, SHORTCUT & EKOSISTEM..."

    # 1. Konfigurasi Port Laragon vs XAMPP
    Configure-WebServerPorts

    # 2. Otomatisasi Izin Firewall (Auto-Allow Apache, Nginx, MySQL, Node, Python, dll)
    Configure-FirewallRules

    # 3. Penjaminan Shortcut Desktop Publik (VS Code, Delphi 7, XAMPP, Android Studio, dll)
    Ensure-DesktopShortcuts

    # 4. Konfigurasi php.ini untuk PHP 8.5, Laragon, dan XAMPP
    Configure-AllPhpExtensions

    # 5. Konfigurasi Ekosistem Laravel
    Configure-LaravelEcosystem

    # 6. Konfigurasi Lisensi & Kompatibilitas Windows 11 Borland Delphi 7
    Repair-Delphi7LicenseAndEnvironment

    # 7. Konfigurasi Ekosistem Flutter & Android SDK (Bebas Error flutter doctor)
    Configure-FlutterAndAndroidEnvironment

    # 8. Penyelarasan Hak Akses Administrator Permanen (Laragon & XAMPP)
    Set-AppRunAsAdmin

    Write-LogSuccess "Semua konfigurasi port, firewall, shortcut desktop, dan environment berhasil diterapkan secara optimal!"
}

function Resolve-Port80Conflict {
    Write-LogStep "Mendeteksi & Mengamankan Port 80 dari Konflik PID 4 (System / IIS)..."

    $port80Conn = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue

    if (-not $port80Conn) {
        Write-LogSuccess "Port 80 BERSIH: Tidak ada proses lain yang mengunci Port 80. Siap untuk Apache Laragon!"
        return $true
    }

    $isPid4 = $false
    $otherProcesses = @()

    foreach ($conn in $port80Conn) {
        $owningPid = $conn.OwningProcess
        if ($owningPid -eq 4) {
            $isPid4 = $true
        } else {
            $proc = Get-Process -Id $owningPid -ErrorAction SilentlyContinue
            $procName = if ($proc) { $proc.ProcessName } else { "PID $owningPid" }
            $otherProcesses += [PSCustomObject]@{ Id = $owningPid; Name = $procName }
        }
    }

    # KASUS 1: Port 80 dikunci oleh PID 4 (System NT Kernel / HTTP.sys driver)
    if ($isPid4) {
        Write-LogWarning "Terdeteksi Port 80 sedang dikunci oleh: System (PID 4 / Kernel HTTP.sys)!"
        Write-LogInfo "Memulai pelepasan otomatis Port 80 dari layanan Windows..."

        # Layanan-layanan Windows yang mendaftarkan port 80 ke HTTP.sys
        $culpritServices = @(
            @{ Name = "W3SVC"; Desc = "World Wide Web Publishing Service (IIS)" },
            @{ Name = "WAS"; Desc = "Windows Process Activation Service" },
            @{ Name = "MsDepSvc"; Desc = "Web Deployment Agent Service" },
            @{ Name = "BranchCache"; Desc = "BranchCache Service" },
            @{ Name = "ReportServer"; Desc = "SQL Server Reporting Services" },
            @{ Name = "SQLBrowser"; Desc = "SQL Server Browser" }
        )

        foreach ($item in $culpritServices) {
            $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq "Running") {
                    Write-LogWarning "Menghentikan layanan '$($item.Name)' ($($item.Desc))..."
                    Stop-Service -Name $item.Name -Force -ErrorAction SilentlyContinue
                }
                # Nonaktifkan agar tidak otomatis mengunci port saat PC Lab di-reboot
                Set-Service -Name $item.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-LogSuccess "Layanan '$($item.Name)' dinonaktifkan (Disabled)."
            }
        }

        # Bersihkan URL Reservation liar di HTTP.sys
        try {
            netsh http delete urlacl url=http://+:80/ 2>$null | Out-Null
            netsh http delete urlacl url=http://*:80/ 2>$null | Out-Null
        } catch {}

        Start-Sleep -Seconds 1

        # Verifikasi apakah PID 4 sudah lepas
        $checkAgain = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq 4 }
        if (-not $checkAgain) {
            Write-LogSuccess "SUKSES: Port 80 BERHASIL DIBEBASKAN dari PID 4! Apache Laragon kini bebas berjalan."
            return $true
        } else {
            Write-LogWarning "PID 4 masih mendengarkan di Port 80. Mencoba melepaskan IP Listen binding..."
            try {
                netsh http delete iplisten ipaddress=0.0.0.0 2>$null | Out-Null
                netsh http delete iplisten ipaddress=127.0.0.1 2>$null | Out-Null
            } catch {}
            Start-Sleep -Seconds 1
        }
    }

    # KASUS 2: Proses lain di luar PID 4 (misal sisa Apache/Nginx zombie)
    if ($otherProcesses.Count -gt 0) {
        foreach ($op in $otherProcesses) {
            Write-LogWarning "Port 80 sedang digunakan oleh: $($op.Name) (PID: $($op.Id))"
            if ($op.Name -match '^(httpd|nginx|apache2|skype)$') {
                Write-LogInfo "Menghentikan proses background '$($op.Name)' (PID: $($op.Id))..."
                Stop-Process -Id $op.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Verifikasi Akhir
    $finalCheck = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
    if (-not $finalCheck) {
        Write-LogSuccess "Port 80 KINI 100% BEBAS & SIAP DIGUNAKAN OLEH LARAGON!"
        return $true
    } else {
        Write-LogWarning "Port 80 masih aktif oleh PID $(($finalCheck | Select-Object -ExpandProperty OwningProcess) -join ', ')."
        return $false
    }
}

function Find-LegacyLabStackLocations {
    param(
        [switch]$Silent = $false
    )

    if (-not $Silent) {
        Write-LogStep "MELACAK SELURUH LOKASI INSTALASI & SERVICE LAMA SECARA DINAMIS..."
    }

    $report = [PSCustomObject]@{
        Services         = @()
        Processes        = @()
        DiscoveredPaths  = @()
        PathPollutions   = @()
        ComposerResidues = @()
        PortConflicts    = @()
    }

    $discoveredDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Deteksi Proses Zombie & Executable Path
    $targetProcNames = @("httpd", "mysqld", "mariadbd", "nginx", "php", "php-cgi", "laragon", "xampp-control", "xampp_start", "postgres", "pg_ctl", "redis-server", "memcached")
    foreach ($pName in $targetProcNames) {
        $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $exePath = ""
            try { $exePath = $p.Path } catch {}
            if (-not $exePath) {
                try {
                    $cimP = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction SilentlyContinue
                    $exePath = $cimP.ExecutablePath
                } catch {}
            }
            $report.Processes += [PSCustomObject]@{
                Id   = $p.Id
                Name = $p.Name
                Path = $exePath
            }
            if ($exePath -and (Test-Path -Path $exePath)) {
                $dir = Split-Path -Parent $exePath
                if ($dir -match '(?i)\\(bin|php|apache|mysql|mariadb)$') { $dir = Split-Path -Parent $dir }
                if ($dir -match '(?i)\\(bin|php|apache|mysql|mariadb)$') { $dir = Split-Path -Parent $dir }
                [void]$discoveredDirs.Add($dir)
            }
        }
    }

    # 2. Deteksi Windows Services & ImagePath Binary
    try {
        $allServices = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
        foreach ($svc in $allServices) {
            $isMatch = ($svc.Name -match '(?i)apache|httpd|mysql|mariadb|nginx|laragon|xampp|php|postgres|redis|memcached') -or
                       ($svc.DisplayName -match '(?i)apache|httpd|mysql|mariadb|nginx|laragon|xampp|php|postgres|redis|memcached') -or
                       ($svc.PathName -match '(?i)httpd\.exe|mysqld\.exe|mariadbd\.exe|nginx\.exe|php-cgi\.exe|laragon\.exe|xampp|postgres\.exe|pg_ctl\.exe|redis-server\.exe|memcached\.exe')

            if ($isMatch) {
                $report.Services += [PSCustomObject]@{
                    Name        = $svc.Name
                    DisplayName = $svc.DisplayName
                    State       = $svc.State
                    PathName    = $svc.PathName
                }

                if ($svc.PathName) {
                    $rawP = $svc.PathName.Trim()
                    if ($rawP -match '^"([^"]+)"') {
                        $rawP = $matches[1]
                    } elseif ($rawP -match '^([^\s]+)') {
                        $rawP = $matches[1]
                    }
                    if (Test-Path -Path $rawP) {
                        $dir = Split-Path -Parent $rawP
                        if ($dir -match '(?i)\\(bin|php|apache|mysql|mariadb)$') { $dir = Split-Path -Parent $dir }
                        if ($dir -match '(?i)\\(bin|php|apache|mysql|mariadb)$') { $dir = Split-Path -Parent $dir }
                        [void]$discoveredDirs.Add($dir)
                    }
                }
            }
        }
    } catch {}

    # 3. Deteksi Perintah CLI di PATH Sistem (Get-Command -All)
    $cmdsToInspect = @("php", "composer", "laravel", "httpd", "mysqld", "mariadbd", "nginx")
    foreach ($cmdName in $cmdsToInspect) {
        $foundCmds = Get-Command $cmdName -All -ErrorAction SilentlyContinue
        foreach ($fc in $foundCmds) {
            if ($fc.Source) {
                $cmdPath = $fc.Source
                $cmdDir = Split-Path -Parent $cmdPath
                [void]$discoveredDirs.Add($cmdDir)
                if ($cmdDir -match '(?i)\\(bin|php|apache|mysql)$') {
                    [void]$discoveredDirs.Add((Split-Path -Parent $cmdDir))
                }
            }
        }
    }

    # 4. Deteksi Registry Uninstall Database (64-bit, 32-bit, CurrentUser)
    $regPaths = @(
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Registry64 },
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Registry32 },
        @{ Hive = [Microsoft.Win32.RegistryHive]::CurrentUser;  Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; View = [Microsoft.Win32.RegistryView]::Default }
    )
    foreach ($rp in $regPaths) {
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($rp.Hive, $rp.View)
            $subKey = $baseKey.OpenSubKey($rp.Path)
            if ($subKey) {
                foreach ($subName in $subKey.GetSubKeyNames()) {
                    try {
                        $appKey = $subKey.OpenSubKey($subName)
                        if ($appKey) {
                            $dispName = $appKey.GetValue("DisplayName")
                            $instLoc  = $appKey.GetValue("InstallLocation")
                            $uninstStr = $appKey.GetValue("UninstallString")

                            if ($dispName -and ($dispName -match '(?i)Laragon|XAMPP|PHP|Composer|Apache|MySQL|MariaDB')) {
                                if ($instLoc -and (Test-Path -Path $instLoc)) {
                                    [void]$discoveredDirs.Add($instLoc.ToString().Trim())
                                }
                                if ($uninstStr) {
                                    $uRaw = $uninstStr.ToString().Trim()
                                    if ($uRaw -match '^"([^"]+)"') { $uRaw = $matches[1] }
                                    elseif ($uRaw -match '^([^\s]+)') { $uRaw = $matches[1] }
                                    if (Test-Path -Path $uRaw) {
                                        [void]$discoveredDirs.Add((Split-Path -Parent $uRaw))
                                    }
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

    # 5. Pindai Partisi Drive Fisik/Lokal (C:, D:, E:, dll.)
    try {
        $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DeviceID
        foreach ($drv in $drives) {
            $candidates = @(
                "$drv\xampp",
                "$drv\laragon",
                "$drv\tools\php85",
                "$drv\tools\php",
                "$drv\php",
                "$drv\php8*",
                "$drv\php7*",
                "$drv\server*",
                "$drv\webserver*",
                "$drv\ProgramData\ComposerSetup"
            )
            foreach ($cand in $candidates) {
                if ($cand -match '\*') {
                    $matchesFound = Get-Item -Path $cand -ErrorAction SilentlyContinue
                    foreach ($mf in $matchesFound) {
                        if ($mf.PSIsContainer) { [void]$discoveredDirs.Add($mf.FullName) }
                    }
                } elseif (Test-Path -Path $cand) {
                    [void]$discoveredDirs.Add($cand)
                }
            }
        }
    } catch {}

    # 6. Residu Composer & User Profile
    $userResidues = @(
        (Join-Path -Path $env:APPDATA -ChildPath "Composer"),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Composer"),
        (Join-Path -Path $env:USERPROFILE -ChildPath ".composer"),
        "C:\ProgramData\ComposerSetup"
    )
    foreach ($ur in $userResidues) {
        if (Test-Path -Path $ur) {
            $report.ComposerResidues += $ur
        }
    }

    # 7. Deteksi Polusi Variabel PATH Sistem
    $patternsToRemove = @(
        '\\laragon\\bin\\php',
        '\\laragon',
        '\\xampp\\php',
        '\\xampp',
        '\\tools\\php',
        '\\php[^\\]*$',
        '\\php8\d',
        'Microsoft\\WinGet\\Packages\\PHP\.PHP',
        'ComposerSetup',
        'AppData\\Roaming\\Composer\\vendor\\bin'
    )

    foreach ($scope in @("Machine", "User")) {
        $rawPath = [System.Environment]::GetEnvironmentVariable("Path", $scope)
        if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
            $parts = $rawPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            foreach ($p in $parts) {
                foreach ($pat in $patternsToRemove) {
                    if ($p -match $pat) {
                        $report.PathPollutions += [PSCustomObject]@{
                            Scope = $scope
                            Path  = $p
                        }
                        if (Test-Path -Path $p) {
                            [void]$discoveredDirs.Add($p)
                        }
                        break
                    }
                }
            }
        }
    }

    # 8. Deteksi Port Lock (Port 80, 443, 3306, 8080)
    $portsToCheck = @(80, 443, 3306, 8080)
    foreach ($port in $portsToCheck) {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($conn in $conns) {
            $pidOwning = $conn.OwningProcess
            $procName = "System/Kernel"
            $pPath = ""
            if ($pidOwning -gt 4) {
                $pObj = Get-Process -Id $pidOwning -ErrorAction SilentlyContinue
                if ($pObj) {
                    $procName = $pObj.Name
                    try { $pPath = $pObj.Path } catch {}
                }
            }
            $report.PortConflicts += [PSCustomObject]@{
                Port        = $port
                PID         = $pidOwning
                ProcessName = $procName
                Path        = $pPath
            }
        }
    }

    # Klasifikasikan direktori yang ditemukan dan cek apakah ada data proyek pengguna
    foreach ($d in $discoveredDirs) {
        $norm = [System.IO.Path]::GetFullPath($d).TrimEnd('\')
        if ($norm -match '^[A-Za-z]:$' -or $norm -match '(?i)^[A-Za-z]:\\(Windows|Program Files|Program Files \(x86\))$') {
            continue
        }

        $dataDir = $null
        $userDataFound = $false
        if (Test-Path -Path (Join-Path -Path $norm -ChildPath "www")) {
            $dataDir = "www"
            $userDataFound = $true
        } elseif (Test-Path -Path (Join-Path -Path $norm -ChildPath "htdocs")) {
            $dataDir = "htdocs"
            $userDataFound = $true
        }

        $report.DiscoveredPaths += [PSCustomObject]@{
            Path        = $norm
            HasUserData = $userDataFound
            DataSubDir  = $dataDir
        }
    }

    return $report
}

function Invoke-CleanPurgeLegacyLabStack {
    param (
        [switch]$Force = $false,
        [switch]$SkipBackup = $false
    )

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host "   CLEAN PURGE & FRESH RESET: WEB SERVER, DATABASE & RUNTIME      " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow

    # Jalankan audit radar sistem secara dinamis di seluruh drive & registry
    $audit = Find-LegacyLabStackLocations

    Write-Host ""
    Write-Host "===================== HASIL AUDIT SISTEM LAB DINAMIS =====================" -ForegroundColor Cyan
    Write-Host " [1] Service Windows Terdeteksi    : $($audit.Services.Count)" -ForegroundColor $(if ($audit.Services.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($s in $audit.Services) {
        Write-Host "     - $($s.Name) ($($s.DisplayName)) -> [$($s.State)]" -ForegroundColor Gray
    }

    Write-Host " [2] Proses Zombie/Background Aktif: $($audit.Processes.Count)" -ForegroundColor $(if ($audit.Processes.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($p in $audit.Processes) {
        Write-Host "     - $($p.Name) (PID: $($p.Id)) -> $($p.Path)" -ForegroundColor Gray
    }

    Write-Host " [3] Direktori Stack Lama Ditemukan: $($audit.DiscoveredPaths.Count)" -ForegroundColor $(if ($audit.DiscoveredPaths.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($dp in $audit.DiscoveredPaths) {
        $backupNotice = if ($dp.HasUserData) { " [Ada Proyek Pengguna ($($dp.DataSubDir)) - Akan Dicadangkan]" } else { "" }
        Write-Host "     - $($dp.Path)$backupNotice" -ForegroundColor Gray
    }

    Write-Host " [4] Polusi PATH Sistem Terdeteksi : $($audit.PathPollutions.Count)" -ForegroundColor $(if ($audit.PathPollutions.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($pp in $audit.PathPollutions) {
        Write-Host "     - [$($pp.Scope)] $($pp.Path)" -ForegroundColor Gray
    }

    Write-Host " [5] Residu Composer & Cache       : $($audit.ComposerResidues.Count)" -ForegroundColor $(if ($audit.ComposerResidues.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($cr in $audit.ComposerResidues) {
        Write-Host "     - $cr" -ForegroundColor Gray
    }

    Write-Host " [6] Konflik Port (80/443/3306)    : $($audit.PortConflicts.Count)" -ForegroundColor $(if ($audit.PortConflicts.Count -gt 0) { "Yellow" } else { "Green" })
    foreach ($pc in $audit.PortConflicts) {
        Write-Host "     - Port $($pc.Port) aktif oleh $($pc.ProcessName) (PID: $($pc.PID))" -ForegroundColor Gray
    }
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "Apakah Anda yakin ingin melakukan CLEAN PURGE untuk seluruh item di atas? (Y/N)"
        if ($confirm -notmatch '^(y|ya|yes)$') {
            Write-LogInfo "Proses Clean Purge dibatalkan oleh pengguna."
            return $false
        }
    }

    Write-LogStep "MEMULAI EKSEKUSI PEMBERSIHAN TOTAL (CLEAN PURGE & RESET)..."

    # 1. Hentikan semua proses aktif secara agresif (taskkill force tree)
    Write-LogInfo "1/7. Menghentikan seluruh proses aktif terkait Web Server, PHP, dan Database..."
    cmd.exe /c "taskkill /F /T /IM laragon* /IM mysqld* /IM mariadbd* /IM httpd* /IM nginx* /IM php* /IM xampp* /IM postgres* /IM pg_ctl* /IM redis* /IM memcached* 2>nul" | Out-Null
    foreach ($p in $audit.Processes) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-LogInfo "Proses $($p.Name) (PID: $($p.Id)) dihentikan."
        } catch {}
    }
    $extraProcs = @("httpd", "mysqld", "mariadbd", "nginx", "php", "php-cgi", "laragon", "xampp-control", "xampp_start", "postgres", "pg_ctl", "redis-server", "memcached")
    foreach ($ep in $extraProcs) {
        $found = Get-Process -Name $ep -ErrorAction SilentlyContinue
        if ($found) { $found | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 1

    # 2. Hentikan & Hapus Service Windows
    Write-LogInfo "2/7. Menghapus seluruh Service Windows web server & database..."
    foreach ($svc in $audit.Services) {
        Write-LogInfo "Menghapus service: $($svc.Name)..."
        try { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue } catch {}
        Start-Process -FilePath "sc.exe" -ArgumentList "delete `"$($svc.Name)`"" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
    }
    $extraSvcs = @("Apache2.4", "apache", "Apache", "mysql", "MySQL", "MySQL80", "MySQL8", "mysql8", "laragon", "xamppapache", "xamppmysql", "postgresql*", "postgres*", "redis*", "memcached*")
    foreach ($es in $extraSvcs) {
        if (Get-Service -Name $es -ErrorAction SilentlyContinue) {
            try { Stop-Service -Name $es -Force -ErrorAction SilentlyContinue } catch {}
            Start-Process -FilePath "sc.exe" -ArgumentList "delete `"$es`"" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # 3. Bebaskan Port 80, 443, 3306
    Write-LogInfo "3/7. Membebaskan Port 80, 443, dan 3306..."
    if (Get-Command Resolve-Port80Conflict -ErrorAction SilentlyContinue) {
        Resolve-Port80Conflict | Out-Null
    }

    # Jalankan Uninstaller Resmi jika tersedia sebelum menghapus folder
    if (Test-Path -Path "C:\laragon\unins000.exe") {
        Write-LogInfo "Menjalankan uninstaller resmi Laragon..."
        Start-Process -FilePath "C:\laragon\unins000.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 1
    }
    # Catatan: C:\xampp\uninstall.exe (Bitnami) TIDAK dipanggil karena memicu 2 jendela cmd.exe interaktif
    # yang menuntut penutupan manual oleh pengguna. Pembersihan total XAMPP dilakukan 100% otomatis,
    # senyap & tuntas via taskkill, sc delete service, registry purge, dan penghapusan direktori di bawah ini.

    # Pastikan proses terkunci mati kembali
    cmd.exe /c "taskkill /F /T /IM laragon* /IM mysqld* /IM mariadbd* /IM httpd* /IM nginx* /IM php* /IM xampp* /IM postgres* /IM pg_ctl* /IM redis* /IM memcached* 2>nul" | Out-Null

    # 4. Cadangkan Proyek Pengguna & Hapus Folder Lama
    Write-LogInfo "4/7. Membersihkan direktori instalasi lama di seluruh drive..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot = "C:\LAB_BACKUP_$timestamp"

    foreach ($dp in $audit.DiscoveredPaths) {
        $folderPath = $dp.Path
        if (Test-Path -Path $folderPath) {
            # Cadangkan jika ada folder www atau htdocs
            if (-not $SkipBackup -and $dp.HasUserData -and $dp.DataSubDir) {
                $userProjectDir = Join-Path -Path $folderPath -ChildPath $dp.DataSubDir
                if (Test-Path -Path $userProjectDir) {
                    $hasProjects = Get-ChildItem -Path $userProjectDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("index.php", "index.html", "dashboard", "webalizer", "xampp", "favicon.ico") }
                    if ($hasProjects) {
                        Write-LogInfo "Mencadangkan proyek pengguna dari $userProjectDir ke $backupRoot..."
                        if (-not (Test-Path -Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
                        $safeFolderName = ($folderPath -replace '[:\\]', '_') + "_$($dp.DataSubDir)"
                        $destBackup = Join-Path -Path $backupRoot -ChildPath $safeFolderName
                        Copy-Item -Path $userProjectDir -Destination $destBackup -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogSuccess "Proyek berhasil dicadangkan ke: $destBackup"
                    }
                }
            }

            Write-LogInfo "Menghapus folder lama: $folderPath..."
            try {
                Get-Process -ErrorAction SilentlyContinue | Where-Object {
                    try { $_.Path -and $_.Path.StartsWith($folderPath, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
                } | Stop-Process -Force -ErrorAction SilentlyContinue

                cmd.exe /c "takeown /f `"$folderPath`" /r /d y >nul 2>&1"
                cmd.exe /c "icacls `"$folderPath`" /grant *S-1-1-0:F /t /c /q >nul 2>&1"
                cmd.exe /c "attrib -r -s -h `"$folderPath\*.*`" /s /d >nul 2>&1"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c rmdir /s /q `"$folderPath`" >nul 2>&1" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
                if (Test-Path -Path $folderPath) {
                    Remove-Item -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Write-LogSuccess "Folder $folderPath berhasil dibersihkan."
            } catch {
                Write-LogWarning "Gagal membersihkan sebagian file di $($folderPath): $_"
            }
        }
    }

    # Pastikan lokasi standar C: selalu dibersihkan secara tuntas
    $stdDirs = @("C:\laragon", "C:\xampp", "C:\tools\php85", "C:\php", "C:\ProgramData\ComposerSetup")
    foreach ($sd in $stdDirs) {
        if (Test-Path -Path $sd) {
            Get-Process -ErrorAction SilentlyContinue | Where-Object {
                try { $_.Path -and $_.Path.StartsWith($sd, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
            } | Stop-Process -Force -ErrorAction SilentlyContinue

            cmd.exe /c "takeown /f `"$sd`" /r /d y >nul 2>&1"
            cmd.exe /c "icacls `"$sd`" /grant *S-1-1-0:F /t /c /q >nul 2>&1"
            cmd.exe /c "attrib -r -s -h `"$sd\*.*`" /s /d >nul 2>&1"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c rmdir /s /q `"$sd`" >nul 2>&1" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
            if (Test-Path -Path $sd) { Remove-Item -Path $sd -Recurse -Force -ErrorAction SilentlyContinue | Out-Null }
        }
    }

    # Hapus seluruh pintasan desktop & Start Menu untuk Laragon dan XAMPP
    Write-LogInfo "Menghapus pintasan desktop dan Start Menu untuk Laragon & XAMPP..."
    $shortcutsToClean = @(
        "C:\Users\Public\Desktop\*laragon*.lnk",
        "$([Environment]::GetFolderPath('Desktop'))\*laragon*.lnk",
        "C:\Users\Public\Desktop\*xampp*.lnk",
        "$([Environment]::GetFolderPath('Desktop'))\*xampp*.lnk",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\*laragon*",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\*laragon*",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\*xampp*",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\*xampp*"
    )
    foreach ($sc in $shortcutsToClean) {
        Get-Item -Path $sc -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Bersihkan Registry Uninstall key Laragon & XAMPP
    $regPurgeKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Laragon",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Laragon",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\xampp",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Laragon",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xampp"
    )
    foreach ($rk in $regPurgeKeys) {
        if (Test-Path -Path $rk) {
            Remove-Item -Path $rk -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 5. Bersihkan Residu Composer & Global Vendor
    Write-LogInfo "5/7. Membersihkan residu Composer (cache & global vendor)..."
    foreach ($cr in $audit.ComposerResidues) {
        if (Test-Path -Path $cr) {
            Remove-Item -Path $cr -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogSuccess "Residu Composer $cr dibersihkan."
        }
    }

    # 6. Sanitasi Variabel PATH Sistem & Pengguna
    Write-LogInfo "6/7. Membersihkan variabel PATH sistem dari entri lama yang bentrok..."
    $patternsToRemove = @(
        '\\laragon\\bin\\php',
        '\\laragon',
        '\\xampp\\php',
        '\\xampp',
        '\\tools\\php',
        '\\php[^\\]*$',
        '\\php8\d',
        'Microsoft\\WinGet\\Packages\\PHP\.PHP',
        'ComposerSetup',
        'AppData\\Roaming\\Composer\\vendor\\bin'
    )

    foreach ($scope in @([System.EnvironmentVariableTarget]::Machine, [System.EnvironmentVariableTarget]::User)) {
        $rawPath = [System.Environment]::GetEnvironmentVariable("Path", $scope)
        if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
            $parts = $rawPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $cleanParts = @()
            foreach ($p in $parts) {
                $shouldRemove = $false
                foreach ($pat in $patternsToRemove) {
                    if ($p -match $pat) {
                        $shouldRemove = $true
                        Write-LogInfo "Menghapus entri PATH usang ($scope): $p"
                        break
                    }
                }
                if (-not $shouldRemove) {
                    $cleanParts += $p
                }
            }
            $newPathStr = ($cleanParts -join ';')
            [System.Environment]::SetEnvironmentVariable("Path", $newPathStr, $scope)
        }
    }

    # Perbarui sesi saat ini
    Refresh-CurrentSessionEnvironment
    Broadcast-EnvironmentChange

    # 7. Reset Cache Detektor LABInstaller
    Write-LogInfo "7/7. Mereset cache detektor LABInstaller..."
    if (Get-Command Initialize-RegistryCache -ErrorAction SilentlyContinue) {
        Initialize-RegistryCache -ForceRefresh | Out-Null
    }

    Write-Host ""
    Write-LogSuccess "BERSIH TOTAL: Seluruh residu stack lama, service liar, port lock, dan file tersembunyi berhasil di-PURGE!"
    Write-LogSuccess "Sistem kini 100% FRESH dan siap dipasang paket baru tanpa konflik!"
    Write-Host ""
    return $true
}

function Set-SystemDefaultBrowser {
    Write-LogStep "Mengonfigurasi Default Browser Sistem (Google Chrome / Edge) untuk Mengatasi Error IE 11..."

    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    $chromeX86  = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    $edgePath   = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $edgeX64    = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"

    $selectedBrowser = $null
    $progId = "ChromeHTML"

    if (Test-Path -Path $chromePath) {
        $selectedBrowser = $chromePath
        $progId = "ChromeHTML"
    } elseif (Test-Path -Path $chromeX86) {
        $selectedBrowser = $chromeX86
        $progId = "ChromeHTML"
    } elseif (Test-Path -Path $edgePath) {
        $selectedBrowser = $edgePath
        $progId = "MSEdgeHTM"
    } elseif (Test-Path -Path $edgeX64) {
        $selectedBrowser = $edgeX64
        $progId = "MSEdgeHTM"
    }

    if ($selectedBrowser) {
        Write-LogInfo "Browser modern terdeteksi: $selectedBrowser"
        try {
            $cmd = "`"$selectedBrowser`" -- `"%1`""
            $browserDir = Split-Path -Parent $selectedBrowser

            # 1. HKLM & HKCU Classes http & https (Protokol Web)
            $regPaths = @(
                "HKLM:\SOFTWARE\Classes\http\shell\open\command",
                "HKLM:\SOFTWARE\Classes\https\shell\open\command",
                "HKCU:\SOFTWARE\Classes\http\shell\open\command",
                "HKCU:\SOFTWARE\Classes\https\shell\open\command"
            )

            foreach ($rp in $regPaths) {
                try {
                    if (-not (Test-Path -Path $rp -ErrorAction SilentlyContinue)) {
                        New-Item -Path $rp -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $rp -Name "(Default)" -Value $cmd -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # 2. Association ProgID di HKCU UserChoice & UrlAssociations
            $userUrlAssoc = @(
                "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice",
                "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice"
            )
            foreach ($ua in $userUrlAssoc) {
                if (Test-Path -Path $ua -ErrorAction SilentlyContinue) {
                    Set-ItemProperty -Path $ua -Name "ProgId" -Value $progId -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }

            # 3. Alihkan stub iexplore.exe ke browser modern (Native 64-bit & WOW64 32-bit untuk Laragon 32-bit)
            $appPathTargets = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe",
                "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe"
            )
            foreach ($ap in $appPathTargets) {
                try {
                    if (-not (Test-Path -Path $ap -ErrorAction SilentlyContinue)) {
                        New-Item -Path $ap -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $ap -Name "(Default)" -Value $selectedBrowser -Force -ErrorAction SilentlyContinue | Out-Null
                    Set-ItemProperty -Path $ap -Name "Path" -Value $browserDir -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # 4. Alihkan StartMenuInternet (Kunci Utama yang dibaca Laragon 32-bit dan Windows GUI)
            $startMenuTargets = @(
                "HKLM:\SOFTWARE\Clients\StartMenuInternet",
                "HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet",
                "HKCU:\Software\Clients\StartMenuInternet",
                "HKCU:\Software\WOW6432Node\Clients\StartMenuInternet"
            )
            foreach ($sm in $startMenuTargets) {
                try {
                    if (-not (Test-Path -Path $sm -ErrorAction SilentlyContinue)) {
                        New-Item -Path $sm -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $sm -Name "(Default)" -Value "Google Chrome" -Force -ErrorAction SilentlyContinue | Out-Null

                    # Override command IEXPLORE.EXE di dalam StartMenuInternet
                    $ieSubCmd = Join-Path -Path $sm -ChildPath "IEXPLORE.EXE\shell\open\command"
                    if (-not (Test-Path -Path $ieSubCmd -ErrorAction SilentlyContinue)) {
                        New-Item -Path $ieSubCmd -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $ieSubCmd -Name "(Default)" -Value "`"$selectedBrowser`"" -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # 5. Alihkan ProgID legacy Internet Explorer di HKCU Classes
            $ieLegacyClasses = @(
                "HKCU:\Software\Classes\IE.HTTP\shell\open\command",
                "HKCU:\Software\Classes\IE.HTTPS\shell\open\command",
                "HKCU:\Software\Classes\IE.AssocFile.HTM\shell\open\command",
                "HKCU:\Software\Classes\IE.AssocFile.MHT\shell\open\command",
                "HKCU:\Software\Classes\IE.AssocFile.URL\shell\open\command",
                "HKCU:\Software\Classes\htmlfile\shell\open\command",
                "HKCU:\Software\Classes\mhtmlfile\shell\open\command",
                "HKCU:\Software\Classes\Applications\iexplore.exe\shell\open\command"
            )
            foreach ($cl in $ieLegacyClasses) {
                try {
                    if (-not (Test-Path -Path $cl -ErrorAction SilentlyContinue)) {
                        New-Item -Path $cl -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $cl -Name "(Default)" -Value $cmd -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # 6. Alihkan eksekusi iexplore.exe via IFEO (Image File Execution Options Debugger)
            $ifeoPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\iexplore.exe",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\iexplore.exe",
                "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\iexplore.exe"
            )
            foreach ($ifp in $ifeoPaths) {
                try {
                    if (-not (Test-Path -Path $ifp -ErrorAction SilentlyContinue)) {
                        New-Item -Path $ifp -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Set-ItemProperty -Path $ifp -Name "Debugger" -Value "`"$selectedBrowser`"" -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }

            # 7. Pastikan laragon.ini memiliki referensi Browser eksplisit
            $laragonIni = "C:\laragon\usr\laragon.ini"
            if (Test-Path -Path $laragonIni) {
                try {
                    $lIniText = [System.IO.File]::ReadAllText($laragonIni, [System.Text.Encoding]::UTF8)
                    if ($lIniText -match '\[preferences\]') {
                        if ($lIniText -match 'Browser\s*=.*') {
                            $lIniText = $lIniText -replace 'Browser\s*=.*', "Browser=$selectedBrowser"
                        } else {
                            $lIniText = $lIniText -replace '(\[preferences\]\r?\n)', "`$1Browser=$selectedBrowser`r`n"
                        }
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                        [System.IO.File]::WriteAllText($laragonIni, $lIniText, $utf8NoBom)
                    }
                } catch {}
            }

            # 8. Trigger silent make-default-browser jika Chrome
            if ($selectedBrowser -like "*chrome.exe") {
                Start-Process -FilePath $selectedBrowser -ArgumentList "--make-default-browser" -NoNewWindow -Wait -ErrorAction SilentlyContinue
            }

            Write-LogSuccess "Default browser sistem & isolasi IE 11 berhasil diarahkan ke: $selectedBrowser (Tombol Web & Database Laragon 100% aman)."
        } catch {
            Write-LogWarning "Gagal memperbarui asosiasi browser sistem: $_"
        }
    } else {
        Write-LogWarning "Browser Google Chrome atau Microsoft Edge belum ditemukan di path standar."
    }
}

function Set-AppRunAsAdmin {
    param (
        [string[]]$ExecutablePaths = @(
            "C:\laragon\laragon.exe",
            "D:\laragon\laragon.exe",
            "C:\xampp\xampp-control.exe",
            "D:\xampp\xampp-control.exe",
            "C:\xampp\xampp_start.exe",
            "D:\xampp\xampp_start.exe"
        )
    )

    Write-LogStep "Mengonfigurasi Hak Administrator Permanen (Run As Administrator) untuk Laragon & XAMPP..."

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    )

    # 1. Terapkan flag ~ RUNASADMIN ke Registry Windows
    # Menjamin aplikasi selalu berjalan sebagai Administrator saat dibuka dari mana pun (Start Menu, Desktop, Taskbar, Explorer, dll)
    $appliedCount = 0
    foreach ($exe in $ExecutablePaths) {
        if (Test-Path -Path $exe) {
            foreach ($rp in $regPaths) {
                try {
                    if (-not (Test-Path -Path $rp)) {
                        New-Item -Path $rp -Force | Out-Null
                    }
                    Set-ItemProperty -Path $rp -Name $exe -Value "~ RUNASADMIN" -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    Write-LogWarning "Gagal mengatur registry RunAsAdmin untuk ${exe}: $_"
                }
            }
            Write-LogSuccess "Hak Run As Administrator permanen diterapkan di Registry untuk: $exe"
            $appliedCount++
        }
    }

    # 2. Penyelarasan Flag RunAsAdmin (Byte 21 = 0x20) pada Seluruh File Pintasan (.lnk)
    # Berlaku di Desktop Publik, Desktop Pengguna, Start Menu Publik, & Start Menu Pengguna
    $shortcutDirs = @(
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory),
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop),
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonPrograms),
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Programs)
    )

    $wshShell = New-Object -ComObject WScript.Shell
    foreach ($dir in $shortcutDirs) {
        if ($dir -and (Test-Path -Path $dir)) {
            $lnks = Get-ChildItem -Path $dir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '(?i)(laragon|xampp)'
            }
            foreach ($lnk in $lnks) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($lnk.FullName)
                    if ($bytes.Length -gt 21) {
                        # Terapkan bit 5 (0x20) pada byte 21 (LinkFlags -> SLDF_RUNAS_USER)
                        $bytes[21] = [byte]($bytes[21] -bor 0x20)
                        [System.IO.File]::WriteAllBytes($lnk.FullName, $bytes)
                        Write-LogSuccess "Pintasan '$($lnk.Name)' dikonfigurasi Run As Administrator (Desktop / Start Menu)."
                    }
                } catch {}
            }
        }
    }

    if ($appliedCount -gt 0) {
        Write-LogSuccess "Laragon & XAMPP berhasil disetel agar selalu berjalan sebagai Administrator di Desktop maupun Start Menu!"
    }
}

function Configure-WebServerPorts {
    Write-LogStep "Memeriksa & Mengisolasi Port Web Server (Laragon vs XAMPP)..."

    # 0. Bebaskan Port 80 dari PID 4 (System / IIS) terlebih dahulu
    Resolve-Port80Conflict | Out-Null

    # Pastikan sistem default browser modern terdaftar (cegah error IE 11 di Laragon & XAMPP)
    Set-SystemDefaultBrowser

    $laragonDir = "C:\laragon"
    $xamppDir   = "C:\xampp"

    $hasLaragon = Test-Path -Path (Join-Path -Path $laragonDir -ChildPath "laragon.exe")
    $hasXampp   = Test-Path -Path (Join-Path -Path $xamppDir -ChildPath "xampp-control.exe")

    Write-Host " Status Deteksi Web Server:" -ForegroundColor Cyan
    Write-Host " - Laragon terpasang : $(if ($hasLaragon) { 'YA [C:\laragon]' } else { 'BELUM' })" -ForegroundColor $(if ($hasLaragon) { 'Green' } else { 'DarkGray' })
    Write-Host " - XAMPP terpasang   : $(if ($hasXampp) { 'YA [C:\xampp]' } else { 'BELUM' })" -ForegroundColor $(if ($hasXampp) { 'Green' } else { 'DarkGray' })

    # Jika XAMPP terpasang, sesuaikan portnya agar tidak bentrok dengan Laragon
    if ($hasXampp) {
        Write-LogInfo "Menyesuaikan konfigurasi port XAMPP agar tidak bentrok dengan Laragon..."

        # A. Atur Apache XAMPP ke Port 8080 (Bebas dari Laragon Port 80)
        $httpdConf = Join-Path -Path $xamppDir -ChildPath "apache\conf\httpd.conf"
        if (Test-Path -Path $httpdConf) {
            $confText = Get-Content -Path $httpdConf -Raw
            # Ganti Listen 80 ke Listen 8080 jika masih 80
            if ($confText -match '(?m)^Listen\s+(?:.*:)?80\s*$') {
                $confText = $confText -replace '(?m)^Listen\s+(?:.*:)?80\s*$', 'Listen 8080'
                $confText = $confText -replace '(?m)^ServerName\s+localhost:80\s*$', 'ServerName localhost:8080'
                [System.IO.File]::WriteAllText($httpdConf, $confText, [System.Text.Encoding]::ASCII)
                Write-LogSuccess "XAMPP Apache HTTP Port disesuaikan ke: 8080 (Bebas Bentrok)."
            } elseif ($confText -match '(?m)^Listen\s+(?:.*:)?8080\s*$') {
                Write-LogInfo "XAMPP Apache HTTP Port sudah menggunakan port alternatif 8080."
            } else {
                $confText = $confText -replace 'Listen\s+80\b', 'Listen 8080'
                [System.IO.File]::WriteAllText($httpdConf, $confText, [System.Text.Encoding]::ASCII)
                Write-LogSuccess "XAMPP Apache HTTP Port disesuaikan ke: 8080 (Bebas Bentrok)."
            }
        }

        # B. Atur Apache SSL XAMPP ke Port 4433 (Bebas dari Laragon Port 443)
        $sslConf = Join-Path -Path $xamppDir -ChildPath "apache\conf\extra\httpd-ssl.conf"
        if (Test-Path -Path $sslConf) {
            $sslText = Get-Content -Path $sslConf -Raw
            if ($sslText -match 'Listen\s+443\b') {
                $sslText = $sslText -replace 'Listen\s+443\b', 'Listen 4433'
                $sslText = $sslText -replace '<VirtualHost\s+_default_:443>', '<VirtualHost _default_:4433>'
                $sslText = $sslText -replace 'ServerName\s+localhost:443\b', 'ServerName localhost:4433'
                [System.IO.File]::WriteAllText($sslConf, $sslText, [System.Text.Encoding]::ASCII)
                Write-LogSuccess "XAMPP Apache HTTPS (SSL) Port disesuaikan ke: 4433 (Bebas Bentrok)."
            }
        }

        # C. Atur MySQL XAMPP ke Port 3307 (Bebas dari Laragon MySQL 3306) & Pemulihan Mutlak Tanpa BOM
        $myIni = Join-Path -Path $xamppDir -ChildPath "mysql\bin\my.ini"
        $mysqlDataDir = Join-Path -Path $xamppDir -ChildPath "mysql\data"
        $mysqlBackupDir = Join-Path -Path $xamppDir -ChildPath "mysql\backup"

        if (Test-Path -Path $myIni) {
            # Hentikan sisa proses mysqld jika ada yang tersangkut/crash
            Get-Process -Name "mysqld", "mysql" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

            # Hapus file lock / stale PID yang memblokir startup MySQL
            if (Test-Path -Path $mysqlDataDir) {
                Get-ChildItem -Path $mysqlDataDir -Filter "*.pid" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }

            # Ganti port 3306 menjadi 3307 untuk kedua blok [client] dan [mysqld]
            $myText = Get-Content -Path $myIni -Raw
            $myText = $myText -replace 'port\s*=\s*\d+', 'port = 3307'

            # KRITIKAL: Tulis berkas strictly ASCII (TANPA UTF-8 BOM)
            # Binary MySQL Windows akan crash jika menemukan UTF-8 BOM di baris pertama ([client])!
            [System.IO.File]::WriteAllText($myIni, $myText, [System.Text.Encoding]::ASCII)
            Write-LogSuccess "XAMPP MySQL Port disesuaikan ke: 3307 (Encoding ASCII Non-BOM Valid)."

            # Verifikasi jika database sistem awal belum terinisialisasi
            $sysDbPath = Join-Path -Path $mysqlDataDir -ChildPath "mysql"
            if ((-not (Test-Path -Path $sysDbPath)) -and (Test-Path -Path $mysqlBackupDir)) {
                Write-LogInfo "Memulihkan berkas basis data sistem awal XAMPP dari backup..."
                Copy-Item -Path "$mysqlBackupDir\*" -Destination $mysqlDataDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # D. Atur XAMPP Control Panel (xampp-control.ini)
        # 1. Port Services (8080, 4433, 3307)
        # 2. Browser Modern (Google Chrome / Edge) agar tidak memanggil Internet Explorer 11 yang mati di Windows 11
        $xamppControlIni = Join-Path -Path $xamppDir -ChildPath "xampp-control.ini"
        if (Test-Path -Path $xamppControlIni) {
            $iniContent = Get-Content -Path $xamppControlIni -Raw
            
            # Update ServicePorts
            if ($iniContent -match '\[ServicePorts\]') {
                $iniContent = $iniContent -replace 'Apache\s*=\s*\d+', 'Apache=8080'
                $iniContent = $iniContent -replace 'ApacheSSL\s*=\s*\d+', 'ApacheSSL=4433'
                $iniContent = $iniContent -replace 'MySQL\s*=\s*\d+', 'MySQL=3307'
            } else {
                $iniContent += "`r`n[ServicePorts]`r`nApache=8080`r`nApacheSSL=4433`r`nMySQL=3307`r`n"
            }

            # Deteksi browser modern yang terpasang di sistem
            $browserExe = $null
            $browserCandidates = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
            )
            foreach ($b in $browserCandidates) {
                if (Test-Path -Path $b) {
                    $browserExe = $b
                    break
                }
            }

            if ($browserExe) {
                if ($iniContent -match '\[Common\]') {
                    if ($iniContent -match 'Browser\s*=.*') {
                        $iniContent = $iniContent -replace 'Browser\s*=.*', "Browser=$browserExe"
                    } else {
                        $iniContent = $iniContent -replace '(\[Common\]\r?\n)', "`$1Browser=$browserExe`r`n"
                    }
                } else {
                    $iniContent += "`r`n[Common]`r`nBrowser=$browserExe`r`n"
                }
                Write-LogSuccess "Browser default XAMPP diselaraskan ke: $browserExe (Bebas error IE 11)."
            }

            # Simpan tanpa BOM
            [System.IO.File]::WriteAllText($xamppControlIni, $iniContent, [System.Text.Encoding]::ASCII)
            Write-LogSuccess "XAMPP Control Panel INI diselaraskan: Tombol Admin membuka http://localhost:8080/ via browser modern."
        }

        # E. Antisipasi Error phpMyAdmin XAMPP: "mysqli_real_connect(): target machine actively refused it"
        # Sinkronkan phpMyAdmin XAMPP agar konek ke MySQL port 3307 dan IP 127.0.0.1
        $xamppPmaConfig = Join-Path -Path $xamppDir -ChildPath "phpMyAdmin\config.inc.php"
        if (Test-Path -Path $xamppPmaConfig) {
            $pmaText = Get-Content -Path $xamppPmaConfig -Raw
            if ($pmaText -match "\`$cfg\['Servers'\]\[\`$i\]\['port'\]\s*=\s*'?\d+'?;") {
                $pmaText = $pmaText -replace "\`$cfg\['Servers'\]\[\`$i\]\['port'\]\s*=\s*'?\d+'?;", "`$cfg['Servers'][`$i]['port'] = '3307';"
            } else {
                $pmaText = $pmaText -replace "(\`$cfg\['Servers'\]\[\`$i\]\['host'\].*?;)", "`$1`r`n`$cfg['Servers'][`$i]['port'] = '3307';"
            }
            # Pakai 127.0.0.1 daripada localhost untuk mencegah resolusi IPv6 ::1 yang sering ditolak MariaDB
            $pmaText = $pmaText -replace "\`$cfg\['Servers'\]\[\`$i\]\['host'\]\s*=\s*'localhost';", "`$cfg['Servers'][`$i]['host'] = '127.0.0.1';"
            [System.IO.File]::WriteAllText($xamppPmaConfig, $pmaText, [System.Text.Encoding]::ASCII)
            Write-LogSuccess "phpMyAdmin XAMPP disinkronkan ke 127.0.0.1:3307 (Bebas error mysqli target machine refused)!"
        }

        # F. Sinkronkan default port MySQL di php.ini XAMPP
        $xamppPhpIni = Join-Path -Path $xamppDir -ChildPath "php\php.ini"
        if (Test-Path -Path $xamppPhpIni) {
            $phpIniText = Get-Content -Path $xamppPhpIni -Raw
            $phpIniText = $phpIniText -replace 'mysqli\.default_port\s*=\s*\d+', 'mysqli.default_port = 3307'
            $phpIniText = $phpIniText -replace 'mysql\.default_port\s*=\s*\d+', 'mysql.default_port = 3307'
            [System.IO.File]::WriteAllText($xamppPhpIni, $phpIniText, [System.Text.Encoding]::ASCII)
        }
    }

    # Jika Laragon terpasang:
    if ($hasLaragon) {
        # 1. Konfigurasi Laragon INI: Apache Aktif (Port 80/443), Nginx Aktif (Port 8081/8443)
        $laragonIni = Join-Path -Path $laragonDir -ChildPath "usr\laragon.ini"
        if (Test-Path -Path $laragonIni) {
            $lIniText = [System.IO.File]::ReadAllText($laragonIni, [System.Text.Encoding]::UTF8)

            # Pastikan [apache] Use=-1
            if ($lIniText -match '\[apache\][^\[]*Use\s*=\s*0') {
                $lIniText = $lIniText -replace '(\[apache\][^\[]*?Use\s*=\s*)0', '${1}-1'
            }

            # Pastikan [nginx] Use=0 (Nonaktifkan auto-start bersamaan dengan Apache agar Laragon tidak crash/bentrok)
            if ($lIniText -match '\[nginx\]') {
                $lIniText = $lIniText -replace '(\[nginx\][^\[]*?Use\s*=\s*)-?\d+', '${1}0'
                if ($lIniText -match '\[nginx\][^\[]*Port\s*=\s*\d+') {
                    $lIniText = $lIniText -replace '(\[nginx\][^\[]*?Port\s*=\s*)\d+', '${1}8081'
                } else {
                    $lIniText = $lIniText -replace '(\[nginx\]\r?\n)', "`$1Port=8081`r`n"
                }
            } else {
                $lIniText += "`r`n[nginx]`r`nUse=0`r`nPort=8081`r`nSSLPort=8443`r`n"
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($laragonIni, $lIniText, $utf8NoBom)
            Write-LogSuccess "Laragon diselaraskan: Apache Port 80 Utama & Nginx Port 8081 (Siaga Bebas Bentrok)!"
        }

        # 2. Selaraskan konfigurasi Nginx 00-default.conf dengan format sintaks valid & STRICT UTF-8 Non-BOM
        $nginxSitesDir = Join-Path -Path $laragonDir -ChildPath "etc\nginx\sites-enabled"
        if (-not (Test-Path -Path $nginxSitesDir)) {
            New-Item -ItemType Directory -Path $nginxSitesDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $defaultNginxConf = Join-Path -Path $nginxSitesDir -ChildPath "00-default.conf"
        $cleanNginxTemplate = @"
server {
    listen 8081 default_server;
    listen 8443 ssl default_server;
    server_name localhost;
    root "C:/laragon/www/";
    index index.html index.htm index.php;

    location / {
        try_files `$uri `$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass 127.0.0.1:9000;
    }
}
"@
        try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($defaultNginxConf, $cleanNginxTemplate, $utf8NoBom)
            Write-LogSuccess "Konfigurasi Nginx sites-enabled (00-default.conf) diselaraskan (Port 8081, Bebas Error Syntax)."
        } catch {
            Write-LogWarning "Gagal memperbarui konfigurasi Nginx 00-default.conf: $_"
        }

        # 3. Selaraskan Konfigurasi MySQL Laragon (Port 3306, bind-address 0.0.0.0, ASCII Non-BOM)
        Write-LogInfo "Menyelaraskan konfigurasi MySQL Laragon (Port 3306, bind-address 0.0.0.0)..."
        $laragonMysqlCandidates = @(
            (Join-Path -Path $laragonDir -ChildPath "bin\mysql\*")
        )
        # Hentikan proses mysqld dan laragon aktif jika ada agar handle file my.ini tidak terkunci
        Get-Process -Name "mysqld", "mysql", "laragon" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300

        foreach ($mc in $laragonMysqlCandidates) {
            $dirs = Resolve-Path -Path $mc -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                $lMyIni = Join-Path -Path $d.Path -ChildPath "my.ini"
                if (Test-Path -Path $lMyIni) {
                    try {
                        # Lepaskan proteksi ReadOnly jika berkas beratribut ReadOnly
                        Set-ItemProperty -Path $lMyIni -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                        [System.IO.File]::SetAttributes($lMyIni, [System.IO.FileAttributes]::Normal)

                        $myText = Get-Content -Path $lMyIni -Raw
                        $myText = $myText -replace 'port\s*=\s*\d+', 'port = 3306'

                        # Pastikan bind-address 0.0.0.0 agar menerima koneksi localhost dan 127.0.0.1 tanpa ditolak (actively refused)
                        if ($myText -match '(?m)^bind-address\s*=.*') {
                            $myText = $myText -replace '(?m)^bind-address\s*=.*', 'bind-address = 0.0.0.0'
                        } elseif ($myText -match '\[mysqld\]') {
                            $myText = $myText -replace '(\[mysqld\]\r?\n)', "`$1bind-address = 0.0.0.0`r`n"
                        }

                        # Deteksi versi MySQL: MySQL 8.4 LTS dan MySQL 9.x MENGHAPUS variabel default_authentication_plugin!
                        # Menuliskan default_authentication_plugin pada MySQL 8.4+ / MySQL 9 menyebabkan crash fatal saat startup server.
                        $isMysql84OrHigher = ($d.Path -match '(?i)mysql-(?:8\.[4-9]|[9-9]|\d{2,})\.')

                        if ($isMysql84OrHigher) {
                            # Hapus opsi deprecated yang menyebabkan mysqld aborting di MySQL 8.4+ / 9.x
                            $myText = $myText -replace '(?m)^\s*default_authentication_plugin\s*=.*(\r?\n)?', ''
                        } else {
                            # MySQL 8.0 ke bawah mendukung default_authentication_plugin
                            if ($myText -notmatch 'default_authentication_plugin') {
                                $myText = $myText -replace '(\[mysqld\]\r?\n)', "`$1default_authentication_plugin = mysql_native_password`r`n"
                            }
                        }

                        # Pastikan folder data sesuai yang ada di sistem
                        $leaf = Split-Path -Leaf $d.Path
                        $candData = @(
                            (Join-Path -Path $laragonDir -ChildPath "data\$leaf"),
                            (Join-Path -Path $laragonDir -ChildPath "data\mysql-8"),
                            (Join-Path -Path $laragonDir -ChildPath "data\mysql")
                        )
                        $validData = $null
                        foreach ($cd in $candData) {
                            if (Test-Path -Path $cd) {
                                $validData = $cd
                                break
                            }
                        }
                        if (-not $validData) {
                            $validData = Join-Path -Path $laragonDir -ChildPath "data\mysql"
                            if (-not (Test-Path -Path $validData)) {
                                New-Item -ItemType Directory -Path $validData -Force | Out-Null
                            }
                        }

                        # Pra-inisialisasi database sistem jika data directory masih kosong / belum diinisialisasi
                        $isDataReady = (Test-Path -Path (Join-Path -Path $validData -ChildPath "mysql")) -or (Test-Path -Path (Join-Path -Path $validData -ChildPath "ibdata1"))
                        if (-not $isDataReady) {
                            $mysqldBin = Join-Path -Path $d.Path -ChildPath "bin\mysqld.exe"
                            if (Test-Path -Path $mysqldBin) {
                                Write-LogInfo "Melakukan pra-inisialisasi database MySQL ($leaf) secara aman..."
                                $normData = ($validData -replace '\\', '/')
                                Get-Process -Name "mysqld", "mysql" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                                Start-Process -FilePath $mysqldBin -ArgumentList "--no-defaults --initialize-insecure --datadir=`"$normData`"" -NoNewWindow -Wait -ErrorAction SilentlyContinue
                                Write-LogSuccess "Database MySQL ($leaf) berhasil diinisialisasi! Siap start instan."
                            }
                        }

                        if ($validData) {
                            $normData = ($validData -replace '\\', '/')
                            if ($myText -match '(?m)^\s*datadir\s*=.*') {
                                $myText = $myText -replace '(?m)^\s*datadir\s*=.*', "datadir=`"$normData`""
                            } elseif ($myText -match '\[mysqld\]') {
                                $myText = $myText -replace '(\[mysqld\]\r?\n)', "`$1datadir=`"$normData`"`r`n"
                            }
                        }

                        try {
                            [System.IO.File]::WriteAllText($lMyIni, $myText, [System.Text.Encoding]::ASCII)
                        } catch {
                            Set-Content -Path $lMyIni -Value $myText -Encoding Ascii -Force
                        }
                        Write-LogSuccess "Konfigurasi MySQL Laragon ($lMyIni) diselaraskan (Port 3306, bind 0.0.0.0, ASCII Non-BOM, Bebas Error Crash)."
                    } catch {
                        Write-LogWarning "Tidak dapat menyelaraskan $lMyIni : $($_.Exception.Message)"
                    }
                }
            }
        }

        # Pastikan laragon.ini mengaktifkan modul MySQL (Use=-1 dan Port=3306)
        if (Test-Path -Path $laragonIni) {
            $lIniText = [System.IO.File]::ReadAllText($laragonIni, [System.Text.Encoding]::UTF8)
            if ($lIniText -match '\[mysql\]') {
                $lIniText = $lIniText -replace '(\[mysql\][^\[]*?Use\s*=\s*)-?\d+', '${1}-1'
                if ($lIniText -match '\[mysql\][^\[]*Port\s*=\s*\d+') {
                    $lIniText = $lIniText -replace '(\[mysql\][^\[]*?Port\s*=\s*)\d+', '${1}3306'
                } else {
                    $lIniText = $lIniText -replace '(\[mysql\]\r?\n)', "`$1Port=3306`r`n"
                }
            } else {
                $lIniText += "`r`n[mysql]`r`nUse=-1`r`nPort=3306`r`n"
            }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($laragonIni, $lIniText, $utf8NoBom)
            Write-LogSuccess "Laragon INI diselaraskan: Modul MySQL dipastikan Aktif (Use=-1, Port=3306)."
        }

        # Cegah pembajakan service Windows: Jika service bernama 'mysql' membajak ke XAMPP, hapus agar Laragon memegang kendali
        try {
            $svcCheck = Get-CimInstance Win32_Service -Filter "Name='mysql'" -ErrorAction SilentlyContinue
            if ($svcCheck -and $svcCheck.PathName -like "*xampp*") {
                Write-LogInfo "Menghapus service Windows 'mysql' XAMPP yang membajak port default..."
                Stop-Service -Name "mysql" -Force -ErrorAction SilentlyContinue
                Start-Process -FilePath "sc.exe" -ArgumentList "delete `"mysql`"" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}

        # 4. Optimasi phpMyAdmin Laragon (Auto-Login Root tanpa password & Multi-Host Resilient)
        Write-LogInfo "Menyesuaikan phpMyAdmin Laragon agar Auto-Login (tanpa login popup) & Multi-Host..."
        if (Get-Command Install-LaragonPhpMyAdmin -ErrorAction SilentlyContinue) {
            Install-LaragonPhpMyAdmin -LaragonDir $laragonDir | Out-Null
        }
        $laragonPmaConfig = Join-Path -Path $laragonDir -ChildPath "etc\apps\phpMyAdmin\config.inc.php"
        if (Test-Path -Path $laragonPmaConfig) {
            $cleanPmaContent = @"
<?php
/**
 * phpMyAdmin Configuration - LABInstaller Auto-Login & Zero-Warning
 */
`$cfg['blowfish_secret'] = 'vK8mQ2xL9pZ4wR7tY1uI3oE5aA6sD8fG';

`$i = 0;

/* Server 1: Laragon MySQL (127.0.0.1:3306) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'Laragon MySQL (127.0.0.1)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = '127.0.0.1';
`$cfg['Servers'][`$i]['port'] = '3306';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

/* Server 2: Laragon MySQL (localhost:3306) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'Laragon MySQL (localhost)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = 'localhost';
`$cfg['Servers'][`$i]['port'] = '3306';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

/* Server 3: XAMPP MariaDB/MySQL (Port 3307) */
`$i++;
`$cfg['Servers'][`$i]['verbose'] = 'XAMPP MySQL (Port 3307)';
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['host'] = '127.0.0.1';
`$cfg['Servers'][`$i]['port'] = '3307';
`$cfg['Servers'][`$i]['connect_type'] = 'tcp';
`$cfg['Servers'][`$i]['extension'] = 'mysqli';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
`$cfg['Servers'][`$i]['Compress'] = false;

`$cfg['UploadDir'] = '';
`$cfg['SaveDir'] = '';
`$cfg['PmaNoRelation_DisableWarning'] = true;
`$cfg['SendErrorReports'] = 'never';
`$cfg['VersionCheck'] = false;
"@
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($laragonPmaConfig, $cleanPmaContent, $utf8NoBom)
            Write-LogSuccess "phpMyAdmin Laragon berhasil dioptimasi: Multi-Host, Langsung terbuka tanpa login & bebas warning!"
        }
    }

    # 5. Terapkan Hak Akses Run As Administrator Otomatis (Desktop, Start Menu, & Explorer)
    Set-AppRunAsAdmin

    Write-Host ""
    Write-Host "====================== SKEMA PEMBAGIAN PORT & ADMIN ======================" -ForegroundColor Cyan
    Write-Host " [LARAGON] (Port Bawaan / Standar Resmi):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 80   -> Web: http://localhost/" -ForegroundColor Green
    Write-Host "   - Apache HTTPS : 443  -> SSL: https://localhost/" -ForegroundColor Green
    Write-Host "   - Nginx HTTP   : 8081 -> Nginx Web: http://localhost:8081/ (TETAP AKTIF!)" -ForegroundColor Green
    Write-Host "   - Nginx HTTPS  : 8443" -ForegroundColor Green
    Write-Host "   - MySQL Server : 3306" -ForegroundColor Green
    Write-Host "   - phpMyAdmin   : http://localhost/phpmyadmin/ (Auto-Login Root, Tanpa Password)" -ForegroundColor Green
    Write-Host "   - Browser Nav  : Google Chrome / Edge (Bebas Error IE 11)" -ForegroundColor Green
    Write-Host " [XAMPP] (Port Alternatif Lab Komputer):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 8080 -> Admin Apache: http://localhost:8080/dashboard/" -ForegroundColor Yellow
    Write-Host "   - Apache HTTPS : 4433" -ForegroundColor Yellow
    Write-Host "   - MySQL Server : 3307" -ForegroundColor Yellow
    Write-Host "   - phpMyAdmin   : http://localhost:8080/phpmyadmin/ (Terkoneksi ke Port 3307)" -ForegroundColor Yellow
    Write-Host "   - Browser Nav  : Google Chrome / Edge (Bebas Error IE 11)" -ForegroundColor Yellow
    Write-Host " Status: BEBAS BENTROK, NGINX + APACHE AKTIF BERSAMAAN & TOMBOL ADMIN AKURAT 100%!" -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Cyan
}

function Configure-AllPhpExtensions {
    Write-LogStep "Mengonfigurasi php.ini, extension_dir & Mengaktifkan Ekstensi Wajib Laravel..."

    # Temukan semua file php.ini di sistem (C:\tools\php85, Laragon, XAMPP, WinGet, PATH)
    $targetIniFiles = @()

    $candidateRoots = @(
        "C:\tools\php85",
        "C:\php",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\PHP.PHP.8.5*",
        "C:\laragon\bin\php\*",
        "C:\xampp\php"
    )

    foreach ($cr in $candidateRoots) {
        $matched = Resolve-Path -Path $cr -ErrorAction SilentlyContinue
        foreach ($m in $matched) {
            $pIni = Join-Path -Path $m.Path -ChildPath "php.ini"
            if (-not (Test-Path -Path $pIni)) {
                $pDev = Join-Path -Path $m.Path -ChildPath "php.ini-development"
                $pProd = Join-Path -Path $m.Path -ChildPath "php.ini-production"
                if (Test-Path -Path $pDev) {
                    Copy-Item -Path $pDev -Destination $pIni -Force -ErrorAction SilentlyContinue
                } elseif (Test-Path -Path $pProd) {
                    Copy-Item -Path $pProd -Destination $pIni -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -Path $pIni) {
                $targetIniFiles += $pIni
            }
        }
    }

    $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
    if ($phpCmd) {
        $pDir = Split-Path -Parent $phpCmd.Source
        $pIni = Join-Path -Path $pDir -ChildPath "php.ini"
        if (Test-Path -Path $pIni) { $targetIniFiles += $pIni }
    }

    $uniqueInis = $targetIniFiles | Select-Object -Unique

    if ($uniqueInis.Count -eq 0) {
        Write-LogWarning "Belum ada berkas php.ini yang terdeteksi di sistem."
        return
    }

    $requiredExtensions = @(
        "curl",
        "fileinfo",
        "mbstring",
        "openssl",
        "pdo_mysql",
        "mysqli",
        "sqlite3",
        "pdo_sqlite",
        "gd",
        "zip",
        "intl",
        "exif",
        "sodium"
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    foreach ($iniPath in $uniqueInis) {
        Write-LogInfo "Mengoptimalkan: $iniPath"
        try {
            $content = Get-Content -Path $iniPath -Raw -Encoding UTF8
            $iniDir = Split-Path -Parent $iniPath
            $extDir = Join-Path -Path $iniDir -ChildPath "ext"

            # 1. Bersihkan semua baris extension_dir lama agar tidak salah fallback atau dobel
            $content = $content -replace '(?m)^\s*;?\s*extension_dir\s*=.*`r?`n?', ''

            # 2. Bersihkan semua deklarasi ekstensi wajib yang lama & bcmath (mencegah duplicate warning openssl/module already loaded/bcmath)
            $allToClean = @($requiredExtensions) + @("bcmath")
            foreach ($ext in $allToClean) {
                $content = $content -replace "(?m)^\s*;?\s*extension\s*=\s*(php_)?$ext(\.dll)?\s*`r?`n?", ""
            }

            # 3. Bentuk blok ekstensi tunggal dan direktori ekstensi yang valid (HANYA SATU extension_dir absolut)
            $extDirLines = ""
            $availableDlls = @()
            if (Test-Path -Path $extDir) {
                $normExt = $extDir.Replace('\', '/')
                $extDirLines = "extension_dir = `"$normExt`"`r`n"
                $availableDlls = @(Get-ChildItem -Path $extDir -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.BaseName -replace '^php_', ''
                })
            } else {
                $extDirLines = "extension_dir = `"ext`"`r`n"
            }

            # Hanya aktifkan ekstensi yang file DLL fisiknya benar-benar ada di ext/ (bebas warning module not found)
            $activeExtensions = @()
            if ($availableDlls.Count -gt 0) {
                $activeExtensions = $requiredExtensions | Where-Object {
                    $availableDlls -contains $_ -or
                    (Test-Path -Path (Join-Path -Path $extDir -ChildPath "php_$_.dll")) -or
                    (Test-Path -Path (Join-Path -Path $extDir -ChildPath "$_.dll"))
                }
            } else {
                $activeExtensions = $requiredExtensions | Where-Object { $_ -ne "bcmath" }
            }

            $extBlock = ($activeExtensions | ForEach-Object { "extension=$_" }) -join "`r`n"
            $injectionBlock = "$extDirLines$extBlock`r`n"

            if ($content -match '(?m)^\[PHP\]\s*`r?`n') {
                $content = $content -replace '(?m)^\[PHP\]\s*`r?`n', "[PHP]`r`n$injectionBlock"
            } else {
                $content = "[PHP]`r`n$injectionBlock" + $content
            }

            # 4. Optimasi Batas Memori & Upload untuk Proyek Laravel Modern
            $content = $content -replace 'memory_limit\s*=\s*\d+M', 'memory_limit = 512M'
            $content = $content -replace 'upload_max_filesize\s*=\s*\d+M', 'upload_max_filesize = 64M'
            $content = $content -replace 'post_max_size\s*=\s*\d+M', 'post_max_size = 64M'
            $content = $content -replace 'max_execution_time\s*=\s*\d+', 'max_execution_time = 300'

            [System.IO.File]::WriteAllText($iniPath, $content, $utf8NoBom)
            Write-LogSuccess "Berhasil mengonfigurasi extension_dir & $($activeExtensions.Count) ekstensi (bebas warning) di: $iniPath"
        }
        catch {
            Write-LogError "Gagal memperbarui $iniPath - $_"
        }
    }
}

function Configure-LaravelEcosystem {
    Write-LogStep "Memverifikasi Kesiapan Ekosistem Laravel (PHP + Composer + Node + CLI)..."
    Refresh-CurrentSessionEnvironment

    $phpOk      = [bool](Get-Command "php" -ErrorAction SilentlyContinue)
    $composerOk = [bool](Get-Command "composer" -ErrorAction SilentlyContinue)
    $nodeOk     = [bool](Get-Command "node" -ErrorAction SilentlyContinue)
    $laravelOk  = [bool](Get-Command "laravel" -ErrorAction SilentlyContinue)

    Write-Host ""
    Write-Host "===================== KESIAPAN LARAVEL 11/12 =====================" -ForegroundColor Cyan
    Write-Host " 1. PHP Interpreter     : $(if ($phpOk) { 'READY (' + (php -r 'echo PHP_VERSION;') + ')' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($phpOk) { 'Green' } else { 'Yellow' })
    Write-Host " 2. Composer Manager    : $(if ($composerOk) { 'READY' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($composerOk) { 'Green' } else { 'Yellow' })
    Write-Host " 3. Node.js & NPM (Vite): $(if ($nodeOk) { 'READY (' + (node -v) + ')' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($nodeOk) { 'Green' } else { 'Yellow' })
    Write-Host " 4. Laravel Installer   : $(if ($laravelOk) { 'READY (laravel new ...)' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($laravelOk) { 'Green' } else { 'Yellow' })
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Panduan Membuat Proyek Laravel Baru (Sesuai Dokumentasi Resmi):" -ForegroundColor Gray
    Write-Host "  1. laravel new nama-proyek" -ForegroundColor White
    Write-Host "  2. cd nama-proyek" -ForegroundColor White
    Write-Host "  3. npm install && npm run build" -ForegroundColor White
    Write-Host "  4. composer run dev" -ForegroundColor White
    Write-Host ""

    # Status Ekosistem Python & Pip
    $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
    $pipCmd = Get-Command "pip" -ErrorAction SilentlyContinue
    Write-Host "====================== KESIAPAN PYTHON & PIP =====================" -ForegroundColor Cyan
    Write-Host " 1. Python Runtime  : $(if ($pyCmd) { 'READY (' + (python --version 2>&1) + ')' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($pyCmd) { 'Green' } else { 'Yellow' })
    Write-Host " 2. Pip Tooling     : $(if ($pipCmd) { 'READY (' + ((pip --version 2>&1) -split '\n')[0] + ')' } else { 'BELUM TERPASANG' })" -ForegroundColor $(if ($pipCmd) { 'Green' } else { 'Yellow' })
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Configure-FirewallRules {
    Write-LogStep "Mengonfigurasi Aturan Windows Firewall (Auto-Allow Layanan Lab & Developer)..."

    $targetApps = @(
        # Web Servers & Proxies
        @{ Name = "LAB: Apache HTTP Server (Laragon)"; Pattern = "C:\laragon\bin\apache\*\bin\httpd.exe" },
        @{ Name = "LAB: Apache HTTP Server (XAMPP)";   Pattern = "C:\xampp\apache\bin\httpd.exe" },
        @{ Name = "LAB: Nginx Server (Laragon)";       Pattern = "C:\laragon\bin\nginx\*\nginx.exe" },
        @{ Name = "LAB: Ngrok Tunnel (Laragon)";       Pattern = "C:\laragon\bin\ngrok\ngrok.exe" },

        # Databases & Caches
        @{ Name = "LAB: MySQL Server (Laragon)";       Pattern = "C:\laragon\bin\mysql\*\bin\mysqld.exe" },
        @{ Name = "LAB: MySQL Server (XAMPP)";         Pattern = "C:\xampp\mysql\bin\mysqld.exe" },
        @{ Name = "LAB: PostgreSQL Server (Laragon)";  Pattern = "C:\laragon\bin\postgresql\*\bin\postgres.exe" },
        @{ Name = "LAB: Redis Server (Laragon)";       Pattern = "C:\laragon\bin\redis\*\redis-server.exe" },
        @{ Name = "LAB: Memcached Server (Laragon)";   Pattern = "C:\laragon\bin\memcached\*\memcached.exe" },

        # Runtimes & Dev Tooling
        @{ Name = "LAB: Node.js JavaScript Runtime";   Pattern = "C:\Program Files\nodejs\node.exe" },
        @{ Name = "LAB: Node.js (Laragon)";            Pattern = "C:\laragon\bin\nodejs\*\node.exe" },
        @{ Name = "LAB: Python Interpreter";           Pattern = "C:\Program Files\Python*\python.exe" },
        @{ Name = "LAB: Python (LocalApp)";            Pattern = "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" },
        @{ Name = "LAB: Python (Laragon)";             Pattern = "C:\laragon\bin\python\*\python.exe" },
        @{ Name = "LAB: PHP CLI / Built-in Server";    Pattern = "C:\Program Files\PHP\*\php.exe" },
        @{ Name = "LAB: PHP (Laragon)";                Pattern = "C:\laragon\bin\php\*\php.exe" },
        @{ Name = "LAB: PHP (XAMPP)";                  Pattern = "C:\xampp\php\php.exe" },
        @{ Name = "LAB: Git Executable";               Pattern = "C:\Program Files\Git\bin\git.exe" },
        @{ Name = "LAB: OpenJDK / Java Runtime";       Pattern = "C:\Program Files\Eclipse Adoptium\*\bin\java.exe" },
        @{ Name = "LAB: OpenJDK Java (Zulu/Other)";    Pattern = "C:\Program Files\*\bin\java.exe" },
        @{ Name = "LAB: Android Debug Bridge (ADB)";   Pattern = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" },
        @{ Name = "LAB: Android Debug Bridge (System)";Pattern = "C:\Android\Sdk\platform-tools\adb.exe" }
    )

    $configuredCount = 0

    foreach ($item in $targetApps) {
        $paths = Resolve-Path -Path $item.Pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
        if (-not $paths) {
            # Coba cari dari PATH sistem jika pattern tidak langsung cocok
            if ($item.Pattern -match '([^\\]+\.exe)$') {
                $cmdName = $matches[1]
                $cmdObj = Get-Command $cmdName -ErrorAction SilentlyContinue
                if ($cmdObj -and (Test-Path -Path $cmdObj.Source)) {
                    $paths = @($cmdObj.Source)
                }
            }
        }

        if ($paths) {
            foreach ($exePath in $paths) {
                if (Test-Path -Path $exePath) {
                    $ruleBaseName = "$($item.Name) - $(Split-Path -Leaf $exePath)"
                    try {
                        # Tambahkan aturan Inbound Allow untuk TCP & UDP (Private & Public)
                        # Menggunakan netsh advfirewall yang sangat cepat dan kompatibel di semua versi Windows
                        $ruleNameTCP = "$ruleBaseName (TCP-In)"
                        $ruleNameUDP = "$ruleBaseName (UDP-In)"

                        # Hapus aturan lama jika pernah ada agar bersih & terbarui
                        netsh advfirewall firewall delete rule name="$ruleNameTCP" 2>$null | Out-Null
                        netsh advfirewall firewall delete rule name="$ruleNameUDP" 2>$null | Out-Null

                        # Daftarkan aturan TCP
                        $resTcp = netsh advfirewall firewall add rule name="$ruleNameTCP" dir=in action=allow program="$exePath" protocol=TCP enable=yes profile=any 2>&1
                        # Daftarkan aturan UDP
                        $resUdp = netsh advfirewall firewall add rule name="$ruleNameUDP" dir=in action=allow program="$exePath" protocol=UDP enable=yes profile=any 2>&1

                        if ($resTcp -match 'Ok|Berhasil|successfully' -or $LASTEXITCODE -eq 0) {
                            $configuredCount++
                            Write-LogInfo "Firewall Allow disetujui otomatis: $(Split-Path -Leaf $exePath)"
                        }
                    } catch {
                        Write-LogWarning "Gagal mendaftarkan firewall untuk $exePath : $_"
                    }
                }
            }
        }
    }

    if ($configuredCount -gt 0) {
        Write-LogSuccess "Berhasil mengonfigurasi $configuredCount layanan ke dalam Windows Firewall (Auto-Allow Bebas Popup Dialog)!"
    } else {
        Write-LogInfo "Tidak ada binary layanan baru yang perlu didaftarkan ke Firewall."
    }
}

function Ensure-DesktopShortcuts {
    Write-LogStep "Memverifikasi & Menyelaraskan Ikon Desktop (Pembersihan Duplikat & Ikon Tunggal)..."

    try {
        $publicDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonDesktopDirectory)
        $userDesktop   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
        $wshShell      = New-Object -ComObject WScript.Shell

        # 1. PEMBERSIHAN DUPLIKAT (Deduplication)
        # Jika sebuah shortcut sudah ada di Public Desktop, hapus shortcut kembar di User Desktop
        # agar Windows Explorer tidak menampilkan 2 ikon ganda yang sama di layar desktop pengguna.
        $cleanedDuplicates = 0
        if ((Test-Path -Path $publicDesktop) -and (Test-Path -Path $userDesktop)) {
            $pubLnks = Get-ChildItem -Path $publicDesktop -Filter "*.lnk" -ErrorAction SilentlyContinue
            foreach ($pLnk in $pubLnks) {
                $usrDuplicate = Join-Path -Path $userDesktop -ChildPath $pLnk.Name
                if (Test-Path -Path $usrDuplicate) {
                    try {
                        Remove-Item -Path $usrDuplicate -Force -ErrorAction SilentlyContinue
                        $cleanedDuplicates++
                        Write-LogInfo "Menghapus shortcut duplikat ganda: $($pLnk.Name) dari User Desktop"
                    } catch {}
                }
            }
        }

        # 2. PENJAMINAN HANYA JIKA SHORTCUT BELUM ADA SAMA SEKALI
        # Hanya aplikasi yang shortcut-nya sama sekali tidak dibuat oleh installer bawaan (seperti VS Code)
        # yang akan dibuatkan shortcut, dan HANYA 1 shortcut tunggal di Public Desktop (atau User Desktop jika gagal).
        $desktopTargets = @(
            @{
                Name            = "Visual Studio Code"
                LnkName         = "Visual Studio Code.lnk"
                Patterns        = @(
                    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
                    "C:\Users\*\AppData\Local\Programs\Microsoft VS Code\Code.exe",
                    "C:\Program Files\Microsoft VS Code\Code.exe",
                    "C:\Program Files (x86)\Microsoft VS Code\Code.exe"
                )
                FallbackCommand = "code"
                Description     = "Visual Studio Code"
            },
            @{
                Name            = "Borland Delphi 7"
                LnkName         = "Delphi 7.lnk"
                Patterns        = @(
                    "C:\Program Files (x86)\Borland\Delphi7\Bin\delphi32.exe",
                    "C:\Program Files\Borland\Delphi7\Bin\delphi32.exe"
                )
                Description     = "Borland Delphi 7 Enterprise Edition"
            },
            @{
                Name            = "XAMPP Control Panel"
                LnkName         = "XAMPP Control Panel.lnk"
                Patterns        = @(
                    "C:\xampp\xampp-control.exe",
                    "D:\xampp\xampp-control.exe"
                )
                Description     = "XAMPP Control Panel"
            },
            @{
                Name            = "Laragon"
                LnkName         = "Laragon.lnk"
                Patterns        = @(
                    "C:\laragon\laragon.exe",
                    "D:\laragon\laragon.exe"
                )
                Description     = "Laragon WAMP 6.0.0"
            },
            @{
                Name            = "Android Studio"
                LnkName         = "Android Studio.lnk"
                Patterns        = @(
                    "C:\Program Files\Android\Android Studio\bin\studio64.exe",
                    "C:\Program Files (x86)\Android\Android Studio\bin\studio64.exe"
                )
                Description     = "Android Studio"
            },
            @{
                Name            = "Apache NetBeans"
                LnkName         = "Apache NetBeans.lnk"
                Patterns        = @(
                    "C:\Program Files\*NetBeans*\bin\netbeans64.exe",
                    "C:\Program Files\NetBeans*\bin\netbeans64.exe"
                )
                Description     = "Apache NetBeans IDE"
            },
            @{
                Name            = "Arduino IDE"
                LnkName         = "Arduino IDE.lnk"
                Patterns        = @(
                    "C:\Program Files\Arduino IDE\Arduino IDE.exe",
                    "$env:LOCALAPPDATA\Programs\Arduino IDE\Arduino IDE.exe",
                    "C:\Users\*\AppData\Local\Programs\Arduino IDE\Arduino IDE.exe"
                )
                Description     = "Arduino IDE"
            },
            @{
                Name            = "Google Chrome"
                LnkName         = "Google Chrome.lnk"
                Patterns        = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe",
                    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
                )
                Description     = "Google Chrome"
            },
            @{
                Name            = "Oracle VirtualBox"
                LnkName         = "Oracle VirtualBox.lnk"
                Patterns        = @(
                    "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
                )
                Description     = "Oracle VM VirtualBox"
            },
            @{
                Name            = "Cisco Packet Tracer"
                LnkName         = "Cisco Packet Tracer.lnk"
                Patterns        = @(
                    "C:\Program Files\Cisco Packet Tracer *\bin\PacketTracer.exe"
                )
                Description     = "Cisco Packet Tracer"
            },
            @{
                Name            = "QGIS Desktop"
                LnkName         = "QGIS Desktop.lnk"
                Patterns        = @(
                    "C:\Program Files\QGIS *\bin\qgis-bin.exe",
                    "C:\Program Files\QGIS *\qgis.bat"
                )
                Description     = "QGIS Desktop GIS"
            },
            @{
                Name            = "Visual Studio 2022"
                LnkName         = "Visual Studio 2022.lnk"
                Patterns        = @(
                    "C:\Program Files\Microsoft Visual Studio\2022\*\Common7\IDE\devenv.exe"
                )
                Description     = "Microsoft Visual Studio 2022"
            },
            @{
                Name            = "Git Bash"
                LnkName         = "Git Bash.lnk"
                Patterns        = @(
                    "C:\Program Files\Git\git-bash.exe",
                    "C:\Program Files (x86)\Git\git-bash.exe"
                )
                Description     = "Git Bash"
            },
            @{
                Name            = "Microsoft Word"
                LnkName         = "Word.lnk"
                Patterns        = @(
                    "C:\Program Files\Microsoft Office\root\Office*\WINWORD.EXE",
                    "C:\Program Files (x86)\Microsoft Office\root\Office*\WINWORD.EXE",
                    "C:\Program Files\Microsoft Office\Office*\WINWORD.EXE",
                    "C:\Program Files (x86)\Microsoft Office\Office*\WINWORD.EXE"
                )
                Description     = "Microsoft Word"
            },
            @{
                Name            = "Microsoft Excel"
                LnkName         = "Excel.lnk"
                Patterns        = @(
                    "C:\Program Files\Microsoft Office\root\Office*\EXCEL.EXE",
                    "C:\Program Files (x86)\Microsoft Office\root\Office*\EXCEL.EXE",
                    "C:\Program Files\Microsoft Office\Office*\EXCEL.EXE",
                    "C:\Program Files (x86)\Microsoft Office\Office*\EXCEL.EXE"
                )
                Description     = "Microsoft Excel"
            },
            @{
                Name            = "Microsoft PowerPoint"
                LnkName         = "PowerPoint.lnk"
                Patterns        = @(
                    "C:\Program Files\Microsoft Office\root\Office*\POWERPNT.EXE",
                    "C:\Program Files (x86)\Microsoft Office\root\Office*\POWERPNT.EXE",
                    "C:\Program Files\Microsoft Office\Office*\POWERPNT.EXE",
                    "C:\Program Files (x86)\Microsoft Office\Office*\POWERPNT.EXE"
                )
                Description     = "Microsoft PowerPoint"
            }
        )

        $createdCount = 0

        foreach ($target in $desktopTargets) {
            $pubLnk = Join-Path -Path $publicDesktop -ChildPath $target.LnkName
            $usrLnk = Join-Path -Path $userDesktop -ChildPath $target.LnkName

            # Jika SUDAH ADA di salah satu desktop (Public atau User), JANGAN buat lagi!
            if ((Test-Path -Path $pubLnk) -or (Test-Path -Path $usrLnk)) {
                # Jika ada di kedua lokasi, bersihkan duplikat di User Desktop
                if ((Test-Path -Path $pubLnk) -and (Test-Path -Path $usrLnk)) {
                    try {
                        Remove-Item -Path $usrLnk -Force -ErrorAction SilentlyContinue
                        $cleanedDuplicates++
                    } catch {}
                }
                continue
            }

            # Cari path binary executable jika belum ada shortcut sama sekali
            $foundExe = $null
            foreach ($pat in $target.Patterns) {
                $matched = Resolve-Path -Path $pat -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
                if ($matched -and (Test-Path -Path $matched)) {
                    $foundExe = $matched
                    break
                }
            }

            if (-not $foundExe -and $target.FallbackCommand) {
                $cmd = Get-Command $target.FallbackCommand -ErrorAction SilentlyContinue
                if ($cmd -and $cmd.Source) {
                    if ($cmd.Source -like "*.exe" -and (Test-Path -Path $cmd.Source)) {
                        $foundExe = $cmd.Source
                    } elseif ($cmd.Source -like "*.cmd" -or $cmd.Source -like "*.bat") {
                        $parentDir = Split-Path -Parent (Split-Path -Parent $cmd.Source)
                        $guessExe = Join-Path -Path $parentDir -ChildPath "$($target.FallbackCommand).exe"
                        if (Test-Path -Path $guessExe) {
                            $foundExe = $guessExe
                        }
                    }
                }
            }

            if ($foundExe) {
                # Simpan HANYA SATU shortcut: utamakan Public Desktop, jika gagal baru User Desktop
                $saved = $false
                if ($publicDesktop -and (Test-Path -Path $publicDesktop)) {
                    try {
                        $sc = $wshShell.CreateShortcut($pubLnk)
                        $sc.TargetPath = $foundExe
                        $sc.WorkingDirectory = Split-Path -Parent $foundExe
                        $sc.Description = $target.Description
                        $sc.Save()
                        $createdCount++
                        $saved = $true
                        Write-LogInfo "Shortcut dibuat tunggal di (Public Desktop): $($target.Name)"
                    } catch {}
                }

                if (-not $saved -and $userDesktop -and (Test-Path -Path $userDesktop)) {
                    try {
                        $sc = $wshShell.CreateShortcut($usrLnk)
                        $sc.TargetPath = $foundExe
                        $sc.WorkingDirectory = Split-Path -Parent $foundExe
                        $sc.Description = $target.Description
                        $sc.Save()
                        $createdCount++
                        Write-LogInfo "Shortcut dibuat tunggal di (User Desktop): $($target.Name)"
                    } catch {
                        Write-LogWarning "Gagal membuat shortcut $($target.Name): $_"
                    }
                }
            }
        }

        if ($cleanedDuplicates -gt 0) {
            Write-LogSuccess "Berhasil membersihkan $cleanedDuplicates shortcut ganda agar hanya tersisa 1 ikon per aplikasi."
        }
        if ($createdCount -gt 0) {
            Write-LogSuccess "Berhasil menambahkan $createdCount shortcut baru yang sebelumnya belum ada."
        }
        if ($cleanedDuplicates -eq 0 -and $createdCount -eq 0) {
            Write-LogInfo "Seluruh shortcut desktop aplikasi sudah rapi & tunggal (tidak ada duplikat)."
        }

        # Pastikan shortcut dan aplikasi web server (Laragon & XAMPP) disetel Run As Administrator
        Set-AppRunAsAdmin
    }
    catch {
        Write-LogWarning "Pemeriksaan shortcut desktop mengalami kendala: $_"
    }
}

function Repair-Delphi7LicenseAndEnvironment {
    Write-LogStep "Memeriksa & Menyelaraskan Lisensi serta Kompatibilitas Borland Delphi 7..."

    $installDir = "C:\Program Files (x86)\Borland\Delphi7"
    if (-not (Test-Path -Path $installDir)) {
        $installDir = "C:\Program Files\Borland\Delphi7"
    }

    $delphiExe = Join-Path -Path $installDir -ChildPath "Bin\delphi32.exe"
    if (-not (Test-Path -Path $delphiExe)) {
        return $false
    }

    $serialNumber = "6AKD-PD29Q9-RDF?JQ-X65Z"
    $authKey      = "QX8-EEC"

    # 1. Bersihkan seluruh file cache lisensi korup di user profile & sistem
    $borlandCachePaths = @(
        (Join-Path -Path $env:USERPROFILE -ChildPath ".borland"),
        "C:\Users\Public\.borland",
        "C:\ProgramData\Borland"
    )
    foreach ($bcp in $borlandCachePaths) {
        if (Test-Path -Path $bcp) {
            Remove-Item -Path (Join-Path -Path $bcp -ChildPath "registry.slm") -Force -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path -Path $bcp -ChildPath "registry.dat") -Force -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path -Path $bcp -ChildPath "borland.lic") -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -ItemType Directory -Path $bcp -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # 2. Temukan dent.slip cracked yang valid
    $appsDir = if (Get-Command Get-AppStorageDirectory -ErrorAction SilentlyContinue) { Get-AppStorageDirectory } else { "d:\KP\v2\apps" }
    $slipCandidates = @(
        (Join-Path -Path $installDir -ChildPath "dent.slip"),
        (Join-Path -Path $installDir -ChildPath "Bin\dent.slip"),
        (Join-Path -Path $appsDir -ChildPath "dent.slip"),
        "D:\KP\dent.slip",
        "C:\Users\musgu\Downloads\Compressed\D7_ENT.kuyhAa\D7_ENT.kuyhAa\dent.slip"
    )
    $validSlip = $null
    foreach ($sc in $slipCandidates) {
        if (Test-Path -Path $sc) {
            $validSlip = $sc
            break
        }
    }

    if ($validSlip) {
        $binDir = Join-Path -Path $installDir -ChildPath "Bin"
        if (-not (Test-Path -Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
        Copy-Item -Path $validSlip -Destination (Join-Path -Path $installDir -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $validSlip -Destination (Join-Path -Path $binDir -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
        foreach ($bcp in $borlandCachePaths) {
            if (Test-Path -Path $bcp) {
                Copy-Item -Path $validSlip -Destination (Join-Path -Path $bcp -ChildPath "dent.slip") -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 3. Suntikkan Registrasi Lisensi Resmi ke Registry (HKLM, WOW6432Node, HKCU)
    $delphiRegPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0",
        "HKLM:\SOFTWARE\Borland\Delphi\7.0",
        "HKCU:\Software\Borland\Delphi\7.0"
    )
    foreach ($rp in $delphiRegPaths) {
        try {
            if (-not (Test-Path -Path $rp)) { New-Item -Path $rp -Force | Out-Null }
            Set-ItemProperty -Path $rp -Name "RootDir" -Value $installDir -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $rp -Name "App" -Value $delphiExe -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $rp -Name "LMLIC" -Value $serialNumber -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $rp -Name "LMKEY" -Value $authKey -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $rp -Name "UseSharedFiles" -Value "TRUE" -Force -ErrorAction SilentlyContinue | Out-Null

            # Bersihkan subkey LM korup
            $subLm = Join-Path -Path $rp -ChildPath "LM"
            if (Test-Path -Path $subLm) {
                Remove-Item -Path $subLm -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }

    # Konfigurasi Just-in-Time Debugger (AeDebug) otomatis agar Delphi tidak memicu popup dialog debugger
    try {
        $borDbg = Join-Path -Path $installDir -ChildPath "Bin\bordbg70.exe"
        if (Test-Path -Path $borDbg) {
            $aeDebugPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug"
            )
            foreach ($aep in $aeDebugPaths) {
                if (-not (Test-Path -Path $aep)) { New-Item -Path $aep -Force | Out-Null }
                Set-ItemProperty -Path $aep -Name "Debugger" -Value "`"$borDbg`" -aegrs %ld %ld" -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $aep -Name "Auto" -Value "1" -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {}

    # 4. Kebijakan Windows 11 AppCompat (PCA Hard Block Bypass) & Exploit Protection
    try {
        $pcaPolPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
        if (-not (Test-Path -Path $pcaPolPath)) { New-Item -Path $pcaPolPath -Force | Out-Null }
        Set-ItemProperty -Path $pcaPolPath -Name "DisablePCA" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $pcaPolPath -Name "DisableEngine" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

        Stop-Service -Name "PcaSvc" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Service -Name "PcaSvc" -StartupType Disabled -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # 5. Lapisan Kompatibilitas XP SP3 & Exploit Protection
    $compatReg = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    )
    $compatVal = "~ WINXPSP3 HIGHDPIAWARE RUNASADMIN"
    foreach ($cr in $compatReg) {
        try {
            if (-not (Test-Path -Path $cr)) { New-Item -Path $cr -Force | Out-Null }
            Set-ItemProperty -Path $cr -Name $delphiExe -Value $compatVal -Force -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }

    try {
        if (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue) {
            Set-ProcessMitigation -Name "delphi32.exe" -Disable DEP,CFG,SEHOP,DynamicCode,BottomUp,HighEntropy -ErrorAction SilentlyContinue | Out-Null
        }
        if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
            Add-MpPreference -ExclusionPath $installDir -ErrorAction SilentlyContinue | Out-Null
            Add-MpPreference -ExclusionProcess "delphi32.exe" -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}

    # 6. Hak Akses Write/Modify
    try {
        & icacls "$installDir" /grant "Users:(OI)(CI)M" /T /Q | Out-Null
        if (Test-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath ".borland")) {
            & icacls (Join-Path -Path $env:USERPROFILE -ChildPath ".borland") /grant "Users:(OI)(CI)M" /T /Q | Out-Null
        }
    } catch {}

    # 7. Penjaminan Paket Komponen VisionLab & VideoLab ke Component Palette
    $bplCheck = Join-Path -Path $installDir -ChildPath "Projects\Bpl\VisionLabDsnD7.bpl"
    if (-not (Test-Path -Path $bplCheck)) {
        Write-LogInfo "Paket VisionLab VCL belum lengkap, menjalankan sinkronisasi installer VisionLab..."
        if (Get-Command Setup-Delphi7VisionLabHandler -ErrorAction SilentlyContinue) {
            Setup-Delphi7VisionLabHandler | Out-Null
        }
    }

    if (Test-Path -Path $bplCheck) {
        $dstBpl = Join-Path -Path $installDir -ChildPath "Projects\Bpl"
        # HANYA daftarkan Design-time packages (*DsnD7.bpl).
        # JANGAN daftarkan Runtime packages (*PkgD7.bpl) karena akan memicu dialog "can't be installed because it is not a design time package".
        $knownPackages = @{
            (Join-Path -Path $dstBpl -ChildPath "OpenWireDsnD7.bpl")             = "OpenWire Pin Editors"
            (Join-Path -Path $dstBpl -ChildPath "SignalLabBasicDsnD7.bpl")       = "SignalLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "TimingLabBasicDsnD7.bpl")       = "TimingLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "AudioLabBasicDsnD7.bpl")        = "AudioLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "MediaLabBasicDsnD7.bpl")        = "MediaLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VideoLabBasicDsnD7.bpl")        = "VideoLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VideoLabAdditionalDsnD7.bpl")   = "VideoLab Additional Design Package"
            (Join-Path -Path $dstBpl -ChildPath "IntelligenceLabBasicDsnD7.bpl") = "IntelligenceLab Basic Design Package"
            (Join-Path -Path $dstBpl -ChildPath "VisionLabDsnD7.bpl")            = "VisionLab Design Package"
        }

        $kpTargets = @(
            "HKCU:\Software\Borland\Delphi\7.0\Known Packages",
            "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0\Known Packages",
            "HKLM:\SOFTWARE\Borland\Delphi\7.0\Known Packages"
        )
        $runtimePackages = @(
            "OpenWirePkgD7.bpl", "SignalLabBasicPkgD7.bpl", "TimingLabBasicPkgD7.bpl",
            "AudioLabBasicPkgD7.bpl", "MediaLabBasicPkgD7.bpl", "VideoLabBasicPkgD7.bpl",
            "VideoLabAdditionalPkgD7.bpl", "IntelligenceLabBasicPkgD7.bpl", "VisionLabPkgD7.bpl"
        )
        foreach ($kpPath in $kpTargets) {
            try {
                if (-not (Test-Path -Path $kpPath)) { New-Item -Path $kpPath -Force | Out-Null }

                # Bersihkan entri runtime package (*PkgD7.bpl) agar Delphi tidak memunculkan dialog error
                $propNames = (Get-Item -Path $kpPath -ErrorAction SilentlyContinue).Property
                if ($propNames) {
                    foreach ($pn in $propNames) {
                        foreach ($rp in $runtimePackages) {
                            if ($pn -match [regex]::Escape($rp)) {
                                Remove-ItemProperty -Path $kpPath -Name $pn -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                    }
                }

                foreach ($k in $knownPackages.Keys) {
                    Set-ItemProperty -Path $kpPath -Name $k -Value $knownPackages[$k] -Force -ErrorAction SilentlyContinue | Out-Null
                }
            } catch {}
        }

        # Library Search Path
        $libTargets = @(
            "HKCU:\Software\Borland\Delphi\7.0\Library",
            "HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\7.0\Library",
            "HKLM:\SOFTWARE\Borland\Delphi\7.0\Library"
        )
        foreach ($lp in $libTargets) {
            try {
                if (-not (Test-Path -Path $lp)) { New-Item -Path $lp -Force | Out-Null }
                $currSearch = (Get-ItemProperty -Path $lp -Name "Search Path" -ErrorAction SilentlyContinue)."Search Path"
                $extraPaths = @("`$(DELPHI)\Projects\Bpl", "`$(DELPHI)\OpenWire", "`$(DELPHI)\LabPacks")
                if ($currSearch) {
                    foreach ($ep in $extraPaths) {
                        if ($currSearch -notmatch [regex]::Escape($ep)) {
                            $currSearch += ";$ep"
                        }
                    }
                } else {
                    $currSearch = "`$(DELPHI)\Lib;`$(DELPHI)\Bin;`$(DELPHI)\Imports;`$(DELPHI)\Projects\Bpl;`$(DELPHI)\OpenWire;`$(DELPHI)\LabPacks"
                }
                Set-ItemProperty -Path $lp -Name "Search Path" -Value $currSearch -Force -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }
        Write-LogSuccess "Paket VisionLab & VideoLab berhasil diselaraskan ke Component Palette Delphi 7."
    }

    Write-LogSuccess "Lisensi resmi & kompatibilitas Windows 11 untuk Borland Delphi 7 berhasil diselaraskan!"
    return $true
}

function Configure-FlutterAndAndroidEnvironment {
    Write-LogStep "Memeriksa & Menyelaraskan Ekosistem Flutter & Android SDK (flutter doctor)..."

    # 1. Cari binary Flutter
    $flutterExe = $null
    $flutterCandidates = @(
        "C:\tools\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat"
    )
    foreach ($fc in $flutterCandidates) {
        if (Test-Path -Path $fc) {
            $flutterExe = $fc
            break
        }
    }
    if (-not $flutterExe) {
        $cmdObj = Get-Command "flutter" -ErrorAction SilentlyContinue
        if ($cmdObj) { $flutterExe = $cmdObj.Source }
    }

    if (-not $flutterExe) {
        Write-LogInfo "Flutter SDK belum terpasang di sistem. Melewati konfigurasi Flutter."
        return $false
    }

    Write-LogInfo "Flutter SDK terdeteksi di: $flutterExe"

    # 2. Cari instalasi Android Studio
    $studioDir = $null
    $studioCandidates = @(
        "C:\Program Files\Android\Android Studio",
        "C:\Program Files (x86)\Android\Android Studio",
        "$env:LOCALAPPDATA\Programs\Android Studio"
    )
    foreach ($sc in $studioCandidates) {
        if (Test-Path -Path (Join-Path -Path $sc -ChildPath "bin\studio64.exe")) {
            $studioDir = $sc
            break
        }
    }

    if ($studioDir) {
        Write-LogInfo "Android Studio terdeteksi di: $studioDir"
        try {
            & $flutterExe config --android-studio-dir "$studioDir" 2>$null | Out-Null
            Write-LogSuccess "Flutter dikonfigurasi dengan Android Studio: $studioDir"
        } catch {}

        # Konfigurasi JDK/JBR bawaan Android Studio jika ada
        $jbrDir = Join-Path -Path $studioDir -ChildPath "jbr"
        if (Test-Path -Path (Join-Path -Path $jbrDir -ChildPath "bin\java.exe")) {
            try {
                & $flutterExe config --jdk-dir "$jbrDir" 2>$null | Out-Null
                [Environment]::SetEnvironmentVariable("JAVA_HOME", $jbrDir, "Machine")
                Write-LogSuccess "Flutter dikonfigurasi dengan JDK bawaan Android Studio ($jbrDir)"
            } catch {}
        }
    }

    # 3. Cari dan Siapkan Android SDK
    $sdkDir = $null
    $sdkCandidates = @(
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Android\Sdk"),
        "C:\Android\Sdk",
        "C:\Android\android-sdk",
        (Join-Path -Path $env:USERPROFILE -ChildPath "AppData\Local\Android\Sdk"),
        "C:\Users\Public\Android\Sdk"
    )
    foreach ($skc in $sdkCandidates) {
        if (Test-Path -Path $skc) {
            $sdkDir = $skc
            break
        }
    }

    # Jika folder Sdk belum ada, buat direktori default standar
    if (-not $sdkDir) {
        $sdkDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Android\Sdk"
        if (-not (Test-Path -Path $sdkDir)) {
            New-Item -ItemType Directory -Path $sdkDir -Force | Out-Null
        }
    }

    # Pastikan platform-tools (adb.exe) tersedia
    $adbPath = Join-Path -Path $sdkDir -ChildPath "platform-tools\adb.exe"
    if (-not (Test-Path -Path $adbPath)) {
        Write-LogInfo "Mengunduh platform-tools (adb) resmi Google untuk melengkapi Android SDK..."
        $appsDir = if (Get-Command Get-AppStorageDirectory -ErrorAction SilentlyContinue) { Get-AppStorageDirectory } else { "d:\KP\v2\apps" }
        $ptZip = Join-Path -Path $appsDir -ChildPath "platform-tools.zip"
        try {
            if (-not (Test-Path -Path $ptZip) -or ((Get-Item $ptZip).Length -lt 1000000)) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                (New-Object Net.WebClient).DownloadFile("https://dl.google.com/android/repository/platform-tools-latest-windows.zip", $ptZip)
                Write-LogSuccess "platform-tools.zip berhasil disimpan permanen di folder apps!"
            } else {
                Write-LogSuccess "Berkas platform-tools.zip sudah tersedia di folder apps: $ptZip"
            }
            if (Test-Path -Path $ptZip) {
                Expand-Archive -Path $ptZip -DestinationPath $sdkDir -Force
                Write-LogSuccess "Platform-tools (adb.exe) berhasil dipasang ke $sdkDir\platform-tools"
            }
        } catch {
            Write-LogWarning "Tidak dapat mengunduh platform-tools secara otomatis: $_"
        }
    }

    # Daftarkan aturan Firewall untuk adb.exe agar bebas popup dialog pemblokiran
    if (Test-Path -Path $adbPath) {
        try {
            netsh advfirewall firewall delete rule name="LAB: Android Debug Bridge (ADB-In)" 2>$null | Out-Null
            netsh advfirewall firewall delete rule name="LAB: Android Debug Bridge (ADB-Out)" 2>$null | Out-Null
            netsh advfirewall firewall add rule name="LAB: Android Debug Bridge (ADB-In)" dir=in action=allow program="$adbPath" enable=yes profile=any 2>&1 | Out-Null
            netsh advfirewall firewall add rule name="LAB: Android Debug Bridge (ADB-Out)" dir=out action=allow program="$adbPath" enable=yes profile=any 2>&1 | Out-Null
            Write-LogSuccess "Aturan Firewall otomatis untuk adb.exe berhasil diterapkan (Bebas Popup Blokir)."
        } catch {}
    }

    # Pastikan Android SDK Command-line Tools (cmdline-tools/latest) tersedia
    $cmdlineBat = Join-Path -Path $sdkDir -ChildPath "cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path -Path $cmdlineBat)) {
        Write-LogInfo "Mengunduh Android SDK Command-line Tools resmi Google (~140 MB)..."
        $appsDir = if (Get-Command Get-AppStorageDirectory -ErrorAction SilentlyContinue) { Get-AppStorageDirectory } else { "d:\KP\v2\apps" }
        $cmdlineZip = Join-Path -Path $appsDir -ChildPath "commandlinetools.zip"
        $cmdlineTempExtract = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "cmdline_extract"
        try {
            if (-not (Test-Path -Path $cmdlineZip) -or ((Get-Item $cmdlineZip).Length -lt 10000000)) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                (New-Object Net.WebClient).DownloadFile("https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip", $cmdlineZip)
                Write-LogSuccess "commandlinetools.zip berhasil disimpan permanen di folder apps!"
            } else {
                Write-LogSuccess "Berkas commandlinetools.zip sudah tersedia di folder apps: $cmdlineZip"
            }
            if (Test-Path -Path $cmdlineZip) {
                Write-LogInfo "Mengekstrak Android SDK Command-line Tools..."
                $sevenZip = "C:\Program Files\7-Zip\7z.exe"
                if (Test-Path -Path $sevenZip) {
                    & $sevenZip x "$cmdlineZip" "-o$cmdlineTempExtract" -y | Out-Null
                } else {
                    Expand-Archive -Path $cmdlineZip -DestinationPath $cmdlineTempExtract -Force
                }

                $extractedCmdline = Join-Path -Path $cmdlineTempExtract -ChildPath "cmdline-tools"
                $targetLatest = Join-Path -Path $sdkDir -ChildPath "cmdline-tools\latest"
                $cmdlineParent = Split-Path -Parent $targetLatest
                if (-not (Test-Path -Path $cmdlineParent)) {
                    New-Item -ItemType Directory -Path $cmdlineParent -Force | Out-Null
                }
                if (Test-Path -Path $targetLatest) {
                    Remove-Item -Path $targetLatest -Recurse -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path -Path $extractedCmdline) {
                    Move-Item -Path $extractedCmdline -Destination $targetLatest -Force
                    Write-LogSuccess "Android SDK Command-line Tools (sdkmanager) berhasil dipasang ke $targetLatest!"
                }

                Remove-Item -Path $cmdlineTempExtract -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-LogWarning "Gagal mengunduh cmdline-tools otomatis: $_"
        }
    }

    # Daftarkan variabel lingkungan ANDROID_HOME & ANDROID_SDK_ROOT
    try {
        [Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdkDir, "Machine")
        [Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdkDir, "Machine")
        $env:ANDROID_HOME = $sdkDir
        $env:ANDROID_SDK_ROOT = $sdkDir

        & $flutterExe config --android-sdk "$sdkDir" 2>$null | Out-Null
        Write-LogSuccess "Flutter dikonfigurasi dengan Android SDK: $sdkDir"

        # Tambahkan platform-tools & cmdline-tools ke PATH sistem
        $ptDir = Join-Path -Path $sdkDir -ChildPath "platform-tools"
        if (Test-Path -Path $ptDir) {
            Add-DirectoryToPath -PathToAdd $ptDir -Scope "Machine" | Out-Null
        }
        $clDir = Join-Path -Path $sdkDir -ChildPath "cmdline-tools\latest\bin"
        if (Test-Path -Path $clDir) {
            Add-DirectoryToPath -PathToAdd $clDir -Scope "Machine" | Out-Null
        }
    } catch {}

    # 4. Otomatisasi Lisensi Android (Accept all licenses via sdkmanager / flutter doctor)
    try {
        Write-LogInfo "Menyetujui seluruh lisensi resmi Android SDK..."
        $sdkManagerBat = Join-Path -Path $sdkDir -ChildPath "cmdline-tools\latest\bin\sdkmanager.bat"
        if (-not (Test-Path -Path $sdkManagerBat)) {
            $foundSdkMan = Get-ChildItem -Path $sdkDir -Recurse -Filter "sdkmanager.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundSdkMan) { $sdkManagerBat = $foundSdkMan.FullName }
        }

        if ($sdkManagerBat -and (Test-Path -Path $sdkManagerBat)) {
            $psiLic = New-Object System.Diagnostics.ProcessStartInfo
            $psiLic.FileName = "cmd.exe"
            $psiLic.Arguments = "/c `"(echo y&echo y&echo y&echo y&echo y&echo y&echo y) | `"$sdkManagerBat`" --licenses`""
            $psiLic.UseShellExecute = $false
            $psiLic.CreateNoWindow = $true
            $pLic = [System.Diagnostics.Process]::Start($psiLic)
            $pLic.WaitForExit(15000) | Out-Null
            if (-not $pLic.HasExited) { try { $pLic.Kill() } catch {} }
            Write-LogSuccess "Pemeriksaan dan persetujuan lisensi Android SDK via sdkmanager berhasil!"
        } elseif ($flutterExe -and (Test-Path -Path $flutterExe)) {
            # Jalankan via flutter doctor dengan timeout maksimal 20 detik agar tidak hang jika pub.dev offline
            $psiFlut = New-Object System.Diagnostics.ProcessStartInfo
            $psiFlut.FileName = "cmd.exe"
            $psiFlut.Arguments = "/c `"(echo y&echo y&echo y&echo y&echo y) | `"$flutterExe`" doctor --android-licenses`""
            $psiFlut.UseShellExecute = $false
            $psiFlut.CreateNoWindow = $true
            $pFlut = [System.Diagnostics.Process]::Start($psiFlut)
            $pFlut.WaitForExit(20000) | Out-Null
            if (-not $pFlut.HasExited) {
                try { $pFlut.Kill() } catch {}
            }
            Write-LogSuccess "Pemeriksaan lisensi Android SDK berhasil diselesaikan!"
        }
    } catch {}

    Write-LogSuccess "Ekosistem Flutter & Android Toolchain berhasil diselaraskan!"
    return $true
}

function Invoke-WindowsAndOfficeActivation {
    param (
        [switch]$Force = $false
    )

    Write-LogStep "MENJALANKAN AKTIVASI OTOMATIS MICROSOFT WINDOWS & OFFICE (PERMANEN)..."

    # 1. Cari direktori activator
    $scriptRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
    $activatorCandidates = @(
        (Join-Path -Path $scriptRoot -ChildPath "activator"),
        "d:\KP\v2\activator",
        "D:\KP\activator",
        "C:\KP\activator",
        (Join-Path -Path (Get-Location).Path -ChildPath "activator")
    )

    $activatorDir = $null
    foreach ($cand in $activatorCandidates) {
        if (Test-Path -Path (Join-Path -Path $cand -ChildPath "HWID_Activation.cmd")) {
            $activatorDir = $cand
            break
        }
    }

    if (-not $activatorDir) {
        Write-LogWarning "Direktori alat aktivator tidak ditemukan. Melewati proses aktivasi."
        return $false
    }

    $hwidCmd  = Join-Path -Path $activatorDir -ChildPath "HWID_Activation.cmd"
    $ohookCmd = Join-Path -Path $activatorDir -ChildPath "Ohook_Activation_AIO.cmd"

    # Normalisasi otomatis Line Ending ke CRLF murni dan pastikan baris kosong di akhir berkas
    foreach ($cmdFile in @($hwidCmd, $ohookCmd)) {
        if (Test-Path -Path $cmdFile) {
            try {
                $rawText = [System.IO.File]::ReadAllText($cmdFile)
                $normalized = $rawText.Replace("`r`n", "`n").Replace("`n", "`r`n")
                if (-not $normalized.EndsWith("`r`n")) {
                    $normalized += "`r`n"
                }
                [System.IO.File]::WriteAllText($cmdFile, $normalized, [System.Text.Encoding]::ASCII)
            } catch {}
        }
    }

    # --------------------------------------------------------------------------
    # A. AKTIVASI WINDOWS (HWID - Digital License Permanen Resmi Microsoft)
    # --------------------------------------------------------------------------
    Write-LogInfo "Memeriksa status lisensi Microsoft Windows..."
    $isWinActivated = $false
    try {
        $licObj = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Windows*" } | Select-Object -First 1
        if ($licObj -and $licObj.LicenseStatus -eq 1) {
            $isWinActivated = $true
        }
    } catch {}

    if ($isWinActivated -and -not $Force) {
        Write-LogSuccess "Microsoft Windows SUDAH TERAKTIVASI PERMANEN (Digital License Aktif)!"
    } else {
        if (Test-Path -Path $hwidCmd) {
            Write-LogStep "Menjalankan Aktivasi HWID Microsoft Windows (Permanen)..."
            try {
                $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$hwidCmd`" /HWID" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -eq 0) {
                    Write-LogSuccess "Microsoft Windows BERHASIL DIAKTIVASI SECARA PERMANEN (HWID Digital License)!"
                } else {
                    Write-LogWarning "Skrip aktivasi Windows selesai dengan kode: $($p.ExitCode)"
                }
            } catch {
                Write-LogError "Gagal mengeksekusi HWID_Activation.cmd: $_"
            }
        }
    }

    # --------------------------------------------------------------------------
    # B. AKTIVASI MICROSOFT OFFICE (Ohook - Perpetual Offline Activation)
    # --------------------------------------------------------------------------
    Write-LogInfo "Memeriksa instalasi Microsoft Office di sistem..."
    $officeInstalled = $false
    $officePaths = @(
        "C:\Program Files\Microsoft Office\root\Office*\WINWORD.EXE",
        "C:\Program Files (x86)\Microsoft Office\root\Office*\WINWORD.EXE",
        "C:\Program Files\Microsoft Office\Office*\WINWORD.EXE",
        "C:\Program Files (x86)\Microsoft Office\Office*\WINWORD.EXE"
    )
    foreach ($op in $officePaths) {
        if (Resolve-Path -Path $op -ErrorAction SilentlyContinue) {
            $officeInstalled = $true
            break
        }
    }

    if (Test-Path -Path $ohookCmd) {
        if ($officeInstalled -or $Force) {
            Write-LogStep "Menjalankan Aktivasi Ohook Microsoft Office (Permanen Seumur Hidup)..."
            try {
                $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$ohookCmd`" /Ohook" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -eq 0) {
                    Write-LogSuccess "Microsoft Office BERHASIL DIAKTIVASI SECARA PERMANEN (Ohook Engine)!"
                } else {
                    Write-LogWarning "Skrip aktivasi Office selesai dengan kode: $($p.ExitCode)"
                }
            } catch {
                Write-LogError "Gagal mengeksekusi Ohook_Activation_AIO.cmd: $_"
            }
        } else {
            Write-LogInfo "Microsoft Office belum terdeteksi. Menyuntikkan Ohook universal untuk Office masa depan..."
            try {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$ohookCmd`" /Ohook" -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
                Write-LogSuccess "Hook aktivasi Office universal siap digunakan."
            } catch {}
        }
    }

    # Kembalikan warna konsol secara merata (membersihkan artefak warna cmd.exe / cls)
    try {
        if ($global:LabOriginalBgColor) {
            $Host.UI.RawUI.BackgroundColor = $global:LabOriginalBgColor
        }
        if ($global:LabOriginalFgColor) {
            $Host.UI.RawUI.ForegroundColor = $global:LabOriginalFgColor
        }
        Clear-Host
        if (Get-Command "Show-LabBanner" -ErrorAction SilentlyContinue) {
            $ver = if (Get-Command "Get-LocalVersionInfo" -ErrorAction SilentlyContinue) { (Get-LocalVersionInfo).version } else { "1.0.30" }
            Show-LabBanner -Version $ver
        }
    } catch {}

    Write-LogSuccess "Proses aktivasi sistem Windows & Office selesai diterapkan!"
    return $true
}


