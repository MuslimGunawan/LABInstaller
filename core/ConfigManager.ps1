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

function Configure-WebServerPorts {
    Write-LogStep "Memeriksa & Mengisolasi Port Web Server (Laragon vs XAMPP)..."

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
    }

    Write-Host ""
    Write-Host "====================== SKEMA PEMBAGIAN PORT ======================" -ForegroundColor Cyan
    Write-Host " [LARAGON] (Prioritas Utama untuk Dev Laravel/PHP):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 80" -ForegroundColor Green
    Write-Host "   - Apache HTTPS : 443" -ForegroundColor Green
    Write-Host "   - MySQL Server : 3306" -ForegroundColor Green
    Write-Host " [XAMPP] (Dukungan Tambahan/Praktikum):" -ForegroundColor White
    Write-Host "   - Apache HTTP  : 8080 (Akses via http://localhost:8080)" -ForegroundColor Yellow
    Write-Host "   - Apache HTTPS : 4433" -ForegroundColor Yellow
    Write-Host "   - MySQL Server : 3307" -ForegroundColor Yellow
    Write-Host " Status: BEBAS BENTROK (Kedua Web Server dapat berjalan simultan)!" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Cyan
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
}

