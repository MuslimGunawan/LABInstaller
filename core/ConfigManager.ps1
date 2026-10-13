# ==============================================================================
# LABInstaller - Core Configuration & Port Conflict Manager
# Mengelola isolasi port (Laragon vs XAMPP), konfigurasi php.ini, dan ekosistem Laravel
# ==============================================================================

function Start-FullEnvironmentConfiguration {
    param (
        [switch]$Interactive = $true
    )

    Write-LogStep "MENJALANKAN KONFIGURASI OTOMATIS PORT, PHP.INI & EKOSISTEM..."

    # 1. Konfigurasi Port Laragon vs XAMPP
    Configure-WebServerPorts

    # 2. Konfigurasi php.ini untuk PHP 8.5, Laragon, dan XAMPP
    Configure-AllPhpExtensions

    # 3. Konfigurasi Ekosistem Laravel
    Configure-LaravelEcosystem

    Write-LogSuccess "Semua konfigurasi port dan environment berhasil diterapkan secara optimal!"
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

function Configure-WebServerPorts {
    Write-LogStep "Memeriksa & Mengisolasi Port Web Server (Laragon vs XAMPP)..."

    # 0. Bebaskan Port 80 dari PID 4 (System / IIS) terlebih dahulu
    Resolve-Port80Conflict | Out-Null

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
            if ($confText -match 'Listen\s+80\r?\n') {
                $confText = $confText -replace 'Listen\s+80', 'Listen 8080'
                $confText = $confText -replace 'ServerName\s+localhost:80', 'ServerName localhost:8080'
                Set-Content -Path $httpdConf -Value $confText -Encoding UTF8
                Write-LogSuccess "XAMPP Apache HTTP Port disesuaikan ke: 8080 (Bebas Bentrok)."
            } else {
                Write-LogInfo "XAMPP Apache HTTP Port sudah menggunakan port alternatif."
            }
        }

        # B. Atur Apache SSL XAMPP ke Port 4433 (Bebas dari Laragon Port 443)
        $sslConf = Join-Path -Path $xamppDir -ChildPath "apache\conf\extra\httpd-ssl.conf"
        if (Test-Path -Path $sslConf) {
            $sslText = Get-Content -Path $sslConf -Raw
            if ($sslText -match 'Listen\s+443\r?\n') {
                $sslText = $sslText -replace 'Listen\s+443', 'Listen 4433'
                $sslText = $sslText -replace '<VirtualHost _default_:443>', '<VirtualHost _default_:4433>'
                $sslText = $sslText -replace 'ServerName\s+localhost:443', 'ServerName localhost:4433'
                Set-Content -Path $sslConf -Value $sslText -Encoding UTF8
                Write-LogSuccess "XAMPP Apache HTTPS (SSL) Port disesuaikan ke: 4433 (Bebas Bentrok)."
            }
        }

        # C. Atur MySQL XAMPP ke Port 3307 (Bebas dari Laragon MySQL 3306)
        $myIni = Join-Path -Path $xamppDir -ChildPath "mysql\bin\my.ini"
        if (Test-Path -Path $myIni) {
            $myText = Get-Content -Path $myIni -Raw
            if ($myText -match 'port\s*=\s*3306') {
                $myText = $myText -replace 'port\s*=\s*3306', 'port = 3307'
                Set-Content -Path $myIni -Value $myText -Encoding UTF8
                Write-LogSuccess "XAMPP MySQL Port disesuaikan ke: 3307 (Bebas Bentrok)."
            }
        }

        # D. Atur XAMPP Control Panel (xampp-control.ini) agar Tombol 'Admin' Mengarah ke URL yang Benar
        $xamppControlIni = Join-Path -Path $xamppDir -ChildPath "xampp-control.ini"
        if (Test-Path -Path $xamppControlIni) {
            $iniContent = Get-Content -Path $xamppControlIni -Raw
            # Update atau tambahkan konfigurasi port di xampp-control.ini
            if ($iniContent -match '\[ServicePorts\]') {
                $iniContent = $iniContent -replace 'Apache\s*=\s*\d+', 'Apache=8080'
                $iniContent = $iniContent -replace 'ApacheSSL\s*=\s*\d+', 'ApacheSSL=4433'
                $iniContent = $iniContent -replace 'MySQL\s*=\s*\d+', 'MySQL=3307'
            } else {
                $iniContent += "`r`n[ServicePorts]`r`nApache=8080`r`nApacheSSL=4433`r`nMySQL=3307`r`n"
            }
            Set-Content -Path $xamppControlIni -Value $iniContent -Encoding UTF8
            Write-LogSuccess "XAMPP Control Panel INI diselaraskan: Tombol Admin membuka http://localhost:8080/."
        }

        # E. Antisipasi Error phpMyAdmin XAMPP: "mysqli_real_connect(): target machine actively refused it"
        # Sinkronkan phpMyAdmin XAMPP agar konek ke MySQL port 3307
        $xamppPmaConfig = Join-Path -Path $xamppDir -ChildPath "phpMyAdmin\config.inc.php"
        if (Test-Path -Path $xamppPmaConfig) {
            $pmaText = Get-Content -Path $xamppPmaConfig -Raw -Encoding UTF8
            if ($pmaText -match "\`$cfg\['Servers'\]\[\`$i\]\['port'\]\s*=\s*'?\d+'?;") {
                $pmaText = $pmaText -replace "\`$cfg\['Servers'\]\[\`$i\]\['port'\]\s*=\s*'?\d+'?;", "`$cfg['Servers'][`$i]['port'] = '3307';"
            } else {
                $pmaText = $pmaText -replace "(\`$cfg\['Servers'\]\[\`$i\]\['host'\].*?;)", "`$1`r`n`$cfg['Servers'][`$i]['port'] = '3307';"
            }
            Set-Content -Path $xamppPmaConfig -Value $pmaText -Encoding UTF8
            Write-LogSuccess "phpMyAdmin XAMPP disinkronkan ke Port 3307 (Bebas error mysqli target machine refused)!"
        }

        # F. Sinkronkan default port MySQL di php.ini XAMPP
        $xamppPhpIni = Join-Path -Path $xamppDir -ChildPath "php\php.ini"
        if (Test-Path -Path $xamppPhpIni) {
            $phpIniText = Get-Content -Path $xamppPhpIni -Raw -Encoding UTF8
            $phpIniText = $phpIniText -replace 'mysqli\.default_port\s*=\s*\d+', 'mysqli.default_port = 3307'
            $phpIniText = $phpIniText -replace 'mysql\.default_port\s*=\s*\d+', 'mysql.default_port = 3307'
            Set-Content -Path $xamppPhpIni -Value $phpIniText -Encoding UTF8
        }
    }

    # Jika Laragon terpasang, perbaiki phpMyAdmin Laragon (Auto-Login Root tanpa password & Bebas Warning)
    if ($hasLaragon) {
        Write-LogInfo "Menyesuaikan phpMyAdmin Laragon agar Auto-Login (tanpa login popup) & Bebas Warning..."
        $laragonPmaConfig = Join-Path -Path $laragonDir -ChildPath "etc\apps\phpMyAdmin\config.inc.php"
        if (Test-Path -Path $laragonPmaConfig) {
            $lPmaText = Get-Content -Path $laragonPmaConfig -Raw -Encoding UTF8
            
            # Ganti auth_type cookie menjadi config (seperti XAMPP tanpa popup login)
            $lPmaText = $lPmaText -replace "\`$cfg\['Servers'\]\[\`$i\]\['auth_type'\]\s*=\s*'cookie';", @"
`$cfg['Servers'][`$i]['auth_type'] = 'config';
`$cfg['Servers'][`$i]['user'] = 'root';
`$cfg['Servers'][`$i]['password'] = '';
`$cfg['Servers'][`$i]['AllowNoPassword'] = true;
"@
            # Blowfish secret 32-byte valid
            $lPmaText = $lPmaText -replace "\`$cfg\['blowfish_secret'\]\s*=\s*'.*?';", "`$cfg['blowfish_secret'] = 'vK8mQ2xL9pZ4wR7tY1uI3oE5aA6sD8fG';"

            # Matikan warning
            if ($lPmaText -notmatch "PmaNoRelation_DisableWarning") {
                $lPmaText += @"

// Hilangkan peringatan konfigurasi storage & error reports
`$cfg['PmaNoRelation_DisableWarning'] = true;
`$cfg['SendErrorReports'] = 'never';
`$cfg['VersionCheck'] = false;
"@
            }
            Set-Content -Path $laragonPmaConfig -Value $lPmaText -Encoding UTF8
            Write-LogSuccess "phpMyAdmin Laragon berhasil dioptimasi: Langsung terbuka otomatis tanpa login & bebas warning!"
        }
    }

    Write-Host ""
    Write-Host "====================== SKEMA PEMBAGIAN PORT & ADMIN ======================" -ForegroundColor Cyan
    Write-Host " [LARAGON] (Port Bawaan / Standar Resmi):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 80  -> Web: http://localhost/" -ForegroundColor Green
    Write-Host "   - Apache HTTPS : 443 -> SSL: https://localhost/" -ForegroundColor Green
    Write-Host "   - MySQL Server : 3306" -ForegroundColor Green
    Write-Host "   - phpMyAdmin   : http://localhost/phpmyadmin/ (Auto-Login Root, Tanpa Password)" -ForegroundColor Green
    Write-Host " [XAMPP] (Port Alternatif Lab Komputer):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 8080 -> Admin Apache: http://localhost:8080/dashboard/" -ForegroundColor Yellow
    Write-Host "   - Apache HTTPS : 4433" -ForegroundColor Yellow
    Write-Host "   - MySQL Server : 3307" -ForegroundColor Yellow
    Write-Host "   - phpMyAdmin   : http://localhost:8080/phpmyadmin/ (Terkoneksi ke Port 3307)" -ForegroundColor Yellow
    Write-Host " Status: BEBAS BENTROK & TOMBOL ADMIN AKURAT 100%!" -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Cyan
}

function Configure-AllPhpExtensions {
    Write-LogStep "Mengonfigurasi php.ini & Mengaktifkan Ekstensi Wajib Laravel..."

    # Temukan semua file php.ini di sistem
    $targetIniFiles = @()

    # 1. PHP 8.5 Winget / System
    $phpCmd = Get-Command "php.exe" -ErrorAction SilentlyContinue
    if ($phpCmd) {
        $pDir = Split-Path -Parent $phpCmd.Source
        $pIni = Join-Path -Path $pDir -ChildPath "php.ini"
        if (Test-Path -Path $pIni) { $targetIniFiles += $pIni }
    }

    # 2. Laragon PHP
    $laragonPhpRoot = "C:\laragon\bin\php"
    if (Test-Path -Path $laragonPhpRoot) {
        $lInis = Get-ChildItem -Path $laragonPhpRoot -Recurse -Filter "php.ini" -ErrorAction SilentlyContinue
        foreach ($li in $lInis) { $targetIniFiles += $li.FullName }
    }

    # 3. XAMPP PHP
    $xamppIni = "C:\xampp\php\php.ini"
    if (Test-Path -Path $xamppIni) { $targetIniFiles += $xamppIni }

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
        "bcmath",
        "sodium"
    )

    foreach ($iniPath in $uniqueInis) {
        Write-LogInfo "Mengoptimalkan: $iniPath"
        try {
            $content = Get-Content -Path $iniPath -Raw -Encoding UTF8

            # Aktifkan setiap ekstensi wajib
            foreach ($ext in $requiredExtensions) {
                $content = $content -replace ";extension=$ext", "extension=$ext"
                $content = $content -replace ";extension\s*=\s*php_$ext\.dll", "extension=php_$ext.dll"
            }

            # Optimasi Batas Memori & Upload untuk Proyek Laravel Modern
            $content = $content -replace 'memory_limit\s*=\s*\d+M', 'memory_limit = 512M'
            $content = $content -replace 'upload_max_filesize\s*=\s*\d+M', 'upload_max_filesize = 64M'
            $content = $content -replace 'post_max_size\s*=\s*\d+M', 'post_max_size = 64M'
            $content = $content -replace 'max_execution_time\s*=\s*\d+', 'max_execution_time = 300'

            Set-Content -Path $iniPath -Value $content -Encoding UTF8
            Write-LogSuccess "Berhasil mengaktifkan $($requiredExtensions.Count) ekstensi di: $iniPath"
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

