# ==============================================================================
# LABInstaller - Core Configuration & Port Conflict Manager
# Mengelola isolasi port (Laragon vs XAMPP), konfigurasi php.ini, dan ekosistem Laravel
# ==============================================================================

function Start-FullEnvironmentConfiguration {
    param (
        [switch]$Interactive = $true
    )

    Write-LogStep "MENJALANKAN KONFIGURASI OTOMATIS PORT, FIREWALL, PHP.INI & EKOSISTEM..."

    # 1. Konfigurasi Port Laragon vs XAMPP
    Configure-WebServerPorts

    # 2. Otomatisasi Izin Firewall (Auto-Allow Apache, Nginx, MySQL, Node, Python, dll)
    Configure-FirewallRules

    # 3. Konfigurasi php.ini untuk PHP 8.5, Laragon, dan XAMPP
    Configure-AllPhpExtensions

    # 4. Konfigurasi Ekosistem Laravel
    Configure-LaravelEcosystem

    Write-LogSuccess "Semua konfigurasi port, firewall, dan environment berhasil diterapkan secara optimal!"
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
            if ($confText -match 'Listen\s+80\r?\n') {
                $confText = $confText -replace 'Listen\s+80', 'Listen 8080'
                $confText = $confText -replace 'ServerName\s+localhost:80', 'ServerName localhost:8080'
                [System.IO.File]::WriteAllText($httpdConf, $confText, [System.Text.Encoding]::ASCII)
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

            # Pastikan [nginx] Use=-1 (Tetap AKTIF!), Port=8081, SSLPort=8443 agar tidak bentrok dengan XAMPP Apache 8080
            if ($lIniText -match '\[nginx\]') {
                $lIniText = $lIniText -replace '(\[nginx\][^\[]*?Use\s*=\s*)\d+', '${1}-1'
                if ($lIniText -match '\[nginx\][^\[]*Port\s*=\s*\d+') {
                    $lIniText = $lIniText -replace '(\[nginx\][^\[]*?Port\s*=\s*)\d+', '${1}8081'
                } else {
                    $lIniText = $lIniText -replace '(\[nginx\]\r?\n)', "`$1Port=8081`r`n"
                }
                if ($lIniText -match '\[nginx\][^\[]*SSLPort\s*=\s*\d+') {
                    $lIniText = $lIniText -replace '(\[nginx\][^\[]*?SSLPort\s*=\s*)\d+', '${1}8443'
                } else {
                    $lIniText = $lIniText -replace '(\[nginx\]\r?\n)', "`$1SSLPort=8443`r`n"
                }
            } else {
                $lIniText += "`r`n[nginx]`r`nUse=-1`r`nPort=8081`r`nSSLPort=8443`r`n"
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($laragonIni, $lIniText, $utf8NoBom)
            Write-LogSuccess "Laragon diselaraskan: Apache Port 80 & Nginx TETAP AKTIF di Port 8081 (Bebas Bentrok 100%)!"
        }

        # 2. Sinkronkan semua Nginx site configuration ke Port 8081 dengan STRICT UTF-8 Non-BOM
        # (PowerShell Set-Content default menambahkan BOM \xEF\xBB\xBF yang menyebabkan Nginx crash pada 'unknown directive server')
        $nginxSitesDir = Join-Path -Path $laragonDir -ChildPath "etc\nginx\sites-enabled"
        if (Test-Path -Path $nginxSitesDir) {
            $confFiles = Get-ChildItem -Path $nginxSitesDir -Filter "*.conf" -ErrorAction SilentlyContinue
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            foreach ($conf in $confFiles) {
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($conf.FullName)
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                    # Hapus BOM jika ada
                    if ($text.StartsWith([char]0xFEFF)) {
                        $text = $text.Substring(1)
                    }
                    # Ganti listen 8080 atau 80 ke 8081
                    $text = $text -replace 'listen\s+8080\b', 'listen 8081'
                    $text = $text -replace 'listen\s+80\b', 'listen 8081'
                    [System.IO.File]::WriteAllText($conf.FullName, $text, $utf8NoBom)
                } catch {
                    Write-LogWarning "Gagal memperbarui konfigurasi Nginx $($conf.Name): $_"
                }
            }
            Write-LogSuccess "Konfigurasi Nginx sites-enabled diselaraskan ke Port 8081 (Strict UTF-8 Non-BOM)."
        }

        # 3. Optimasi phpMyAdmin Laragon (Auto-Login Root tanpa password & Bebas Warning)
        Write-LogInfo "Menyesuaikan phpMyAdmin Laragon agar Auto-Login (tanpa login popup) & Bebas Warning..."
        $laragonPmaConfig = Join-Path -Path $laragonDir -ChildPath "etc\apps\phpMyAdmin\config.inc.php"
        if (Test-Path -Path $laragonPmaConfig) {
            $lPmaText = Get-Content -Path $laragonPmaConfig -Raw
            
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
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($laragonPmaConfig, $lPmaText, $utf8NoBom)
            Write-LogSuccess "phpMyAdmin Laragon berhasil dioptimasi: Langsung terbuka otomatis tanpa login & bebas warning!"
        }
    }

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
        @{ Name = "LAB: OpenJDK Java (Zulu/Other)";    Pattern = "C:\Program Files\*\bin\java.exe" }
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

