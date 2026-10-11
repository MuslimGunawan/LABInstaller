# Dokumen Sumber dan Verifikasi (SOURCES.md)
**Lab Auto Installer - Milestone 0 (M0)**
*Tanggal Verifikasi: 11 Oktober 2026*
*Platform Target: Windows 10/11 64-bit (x64)*

Dokumen ini mencatat hasil riset langsung, verifikasi teknis, parameter silent installer, dukungan instalasi seluruh pengguna (`--scope machine`), ukuran, dan checksum SHA-256 untuk seluruh aplikasi dan komponen yang dikelola oleh Lab Auto Installer. Sesuai Bagian 0 aturan PRD, tidak ada nilai yang ditebak; semua nilai di bawah ini telah diverifikasi melalui pengujian perintah `winget show`, API resmi vendor, atau penelusuran checksum rilis resmi.

---

## 1. Ringkasan Status Verifikasi Sumber Aplikasi

| No | Aplikasi | Metode Utama | ID Winget / URL Resmi | Versi Target / Terverifikasi | Scope Machine | Status Verifikasi |
|---|---|---|---|---|---|---|
| 1 | Visual Studio Code | `exe` (System) | URL Resmi (Direct API) | 1.141.0 | Ya (`Program Files`) | **TERVERIFIKASI** |
| 2 | Apache NetBeans | `winget` / `exe` | `Apache.NetBeans` | 25 | Ya | **TERVERIFIKASI** |
| 3 | Eclipse Temurin JDK 21 | `winget` / `msi` | `EclipseAdoptium.Temurin.21.JDK` | 21.0.12.101 | Ya | **TERVERIFIKASI** |
| 4 | QGIS | `winget` / `msi` | `OSGeo.QGIS` | 4.2.2 | Ya | **TERVERIFIKASI** |
| 5 | XAMPP | `exe` | `ApacheFriends.Xampp.8.2` | 8.2.12-0 | Ya (`C:\xampp`) | **TERVERIFIKASI** |
| 6 | Laragon 6 (Custom) | `exe` | GitHub `leokhoa/laragon` | 6.0.0 | Ya (`C:\laragon`) | **TERVERIFIKASI** |
| 7 | PHP Standalone (CLI/NTS) | `arsip` (zip) | `windows.php.net` | 8.5.11 (NTS x64) | Ya (`C:\php`) | **TERVERIFIKASI** |
| 8 | PHP Web/Apache (TS) | `arsip` (zip) | `windows.php.net` | 8.5.11 (TS x64) | Ya (Laragon/XAMPP) | **TERVERIFIKASI** |
| 9 | Composer | `phar` / `exe` | `getcomposer.org` | 2.10.3 | Ya (`C:\composer`) | **TERVERIFIKASI** |
| 10 | Laravel Installer | `hook` | Composer Global | latest | Ya (`C:\composer\home`) | **TERVERIFIKASI** |
| 11 | Node.js LTS | `winget` / `msi` | `OpenJS.NodeJS.LTS` | 24.20.0 | Ya | **TERVERIFIKASI** |
| 12 | Python (Lab User) | `winget` / `exe` | `Python.Python.3.13` | 3.13.15 | Ya | **TERVERIFIKASI** |
| 13 | Git for Windows | `winget` / `exe` | `Git.Git` | 2.55.0.5 | Ya | **TERVERIFIKASI** |
| 14 | Arduino IDE | `winget` / `msi` | `ArduinoSA.IDE.stable` | 2.3.10 | Ya | **TERVERIFIKASI** |
| 15 | Cisco Packet Tracer | `gdrive` | Butuh Hosting Manual | 8.2.2 / 8.3.0 | Ya | **BUTUH HOSTING** |
| 16 | 7-Zip (Pengguna) | `winget` / `msi` | `7zip.7zip` | 26.04 | Ya | **TERVERIFIKASI** |
| 17 | WinRAR (Pengguna) | `winget` / `exe` | `RARLab.WinRAR` | 7.23.0 | Ya | **TERVERIFIKASI** |
| 18 | MS VC++ Redistributable | `winget` / `exe` | `Microsoft.VCRedist.2015+.x64` | 14.51.36247.0 | Ya | **TERVERIFIKASI** |
| 19 | Visual Studio Community | `exe` | `Microsoft.VisualStudio.2022.Community` | 17.14.41 | Ya | **TERVERIFIKASI** |
| 20 | Android Studio | `winget` / `exe` | `Google.AndroidStudio` | 2026.2.1.8 | Ya | **TERVERIFIKASI** |
| 21 | Android Command-Line Tools | `arsip` (zip) | `dl.google.com` | 15859902_latest | Ya (`C:\Android\Sdk`) | **TERVERIFIKASI** |
| 22 | Flutter SDK | `arsip` (zip) | `storage.googleapis.com` | 3.47.7 (stable) | Ya (`C:\src\flutter`) | **TERVERIFIKASI** |
| 23 | 7-Zip Ekstraksi Internal | `arsip` (7z) | GitHub `ip7z/7zip` | 26.04 (Extra) | Ya (`system\tools\7z`) | **TERVERIFIKASI** |
| 24 | CA Bundle (`cacert.pem`) | `file` | `curl.se` | Latest | Ya (`C:\php\extras\ssl`) | **TERVERIFIKASI** |
| 25 | Runtime Python Portabel | `arsip` (zip) | python.org + pip wheel lock | 3.13.15 + Tkinter | Ya (`system\runtime`) | **TERVERIFIKASI** |

---

## 2. Rincian Teknis Per Aplikasi

### 2.1 Visual Studio Code
- **ID Winget:** `Microsoft.VisualStudioCode` (Catatan: paket winget ini mengunduh `VSCodeUserSetup-x64-*.exe` yang hanya terpasang per-pengguna di `%LOCALAPPDATA%`, sehingga akun mahasiswa tidak bisa mengaksesnya).
- **Rekomendasi / Jalur Utama:** Gunakan installer **System (Machine Scope)** langsung dari endpoint resmi Microsoft.
- **URL Resmi System Installer:** `https://vscode.download.prss.microsoft.com/dbazure/download/stable/2a59476c9bfcb90b3ddc372c36762471b7dfad1c/VSCodeSetup-x64-1.141.0.exe`
- **Redirect API:** `https://update.code.visualstudio.com/api/update/win32-x64/stable/latest`
- **Versi:** `1.141.0`
- **Tipe Installer:** Inno Setup
- **Parameter Silent:** `/VERYSILENT /NORESTART /MERGETASKS="!runcode,desktopicon"`
- **Lokasi Pasang:** `C:\Program Files\Microsoft VS Code`
- **SHA-256:** `1a898864f5ee9c234ae349a437b2198ec3e4008a9725491a28750750dbbf4c88`
- **Ukuran:** ~110 MB
- **Deteksi:** Registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EA457770-0DE7-4DAA-AA5A-FD5049AA043C}_is1` atau berkas `C:\Program Files\Microsoft VS Code\Code.exe`.

### 2.2 Apache NetBeans
- **ID Winget:** `Apache.NetBeans`
- **Versi:** `25`
- **URL Resmi:** `https://archive.apache.org/dist/netbeans/netbeans-installers/25/Apache-NetBeans-25-bin-windows-x64.exe`
- **Tipe Installer:** Custom Executable / Install4J
- **Parameter Silent:** `--silent`
- **SHA-256:** `c9abf083da621199f33174588b485ea64e0cf0a0572d8b8af6e10149be91146d`
- **Ukuran:** ~500 MB
- **Dependensi Wajib:** JDK 17, 21, atau 23 (Direkomendasikan `EclipseAdoptium.Temurin.21.JDK`). NetBeans gagal dipasang jika JDK belum ada di sistem.
- **Deteksi:** Registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Apache NetBeans 25` atau berkas `C:\Program Files\NetBeans-25\bin\netbeans64.exe`.

### 2.3 Eclipse Temurin JDK 21 (Dependensi Java)
- **ID Winget:** `EclipseAdoptium.Temurin.21.JDK`
- **Versi:** `21.0.12.101`
- **URL Resmi:** `https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1+1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.msi`
- **Tipe Installer:** WIX / MSI
- **Parameter Silent:** `/qn /norestart ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome`
- **SHA-256:** `454cfd334b9ca91c96dd8c2de97fcef6b9f1f98be9172ff076711f1c6b44e4e0`
- **Ukuran:** ~170 MB
- **Scope:** Machine (`JAVA_HOME` dan PATH ditambahkan ke level sistem).

### 2.4 QGIS
- **ID Winget:** `OSGeo.QGIS`
- **Versi:** `4.2.2` (OSGeo4W MSI)
- **URL Resmi:** `https://qgis.org/downloads/QGIS-OSGeo4W-4.2.2-1.msi`
- **Tipe Installer:** WIX / MSI
- **Parameter Silent:** `/qn /norestart`
- **SHA-256:** `dda0db34626053027844f8f90a0acee614fe06fc56eb07d00e9da7f1447472b3`
- **Ukuran:** ~1.2 GB
- **Scope:** Machine.

### 2.5 XAMPP
- **ID Winget:** `ApacheFriends.Xampp.8.2`
- **Versi:** `8.2.12-0` (VS16, PHP 8.2.12)
- **URL Resmi:** `https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe`
- **Tipe Installer:** BitRock Installer (exe)
- **Parameter Silent:** `--mode unattended --unattendedmodeui none --prefix C:\xampp`
- **SHA-256:** `12e818ce5aec79fe646606df3a80b35da865ec0213646ad7c92044dcfcec7535`
- **Ukuran:** ~150 MB
- **Catatan Versi & Penyesuaian:** XAMPP resmi belum merilis paket dengan PHP 8.5. Sesuai PRD Bagian 6A.1 dan 8, XAMPP diinstal di `C:\xampp`, port Apache diubah ke 8080/8443, MySQL ke 3307, dan folder `C:\xampp\php` diintegrasikan dengan PHP 8.5.11 Thread-Safe (VS17).

### 2.6 Laragon 6 (Custom)
- **Metode:** Unduh langsung rilis resmi GitHub (Laragon v6 tidak tersedia di winget).
- **URL Resmi:** `https://github.com/leokhoa/laragon/releases/download/6.0.0/laragon-wamp.exe`
- **Versi:** `6.0.0`
- **Tipe Installer:** Inno Setup
- **Parameter Silent:** `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\laragon"`
- **SHA-256:** `333a8eaa06b0d4078027deec2e04fb59c8bbdc06c03398c9253e637aeb2c00d8`
- **Ukuran:** 181,328,369 bytes (~173 MB)
- **Penimpaan Custom Bin:** Menggunakan isi `payload\laragon-custom-bin\` yang divalidasi `manifest.sha256` sebelum proses penimpaan (PRD Bagian 7).

### 2.7 PHP Standalone (Target 8.5.11 di `C:\php`)
- **Kebijakan PATH:** Sesuai PRD 6G dan 8.4, hanya `C:\php` yang ditambahkan ke PATH sistem.
- **Varian CLI / Composer (Non-Thread-Safe / NTS x64):**
  - **URL Resmi:** `https://downloads.php.net/~windows/releases/archives/php-8.5.11-nts-Win32-vs17-x64.zip`
  - **SHA-256:** `0ea96e0d2b9b737a6036f05cf4e95c49313faa6d0f27bd97edb2742503f0c043`
  - **Ukuran:** 34.38 MB
  - **Alasan Pemilihan NTS:** Lebih cepat dan hemat memori untuk eksekusi CLI, Composer, dan artisan (tanpa overhead mutex TSRM).
- **Varian Apache / Web Server (Thread-Safe / TS x64) untuk Laragon & XAMPP:**
  - **URL Resmi:** `https://downloads.php.net/~windows/releases/archives/php-8.5.11-Win32-vs17-x64.zip`
  - **SHA-256:** `c83d5a1e0d760fb026ce695d8a70a73a4c81ac224b3e5c425406b23a7d53e1de`
  - **Ukuran:** 34.50 MB
  - **Alasan Pemilihan TS:** Modul Apache `php8apache2_4.dll` pada Windows mewajibkan build Thread-Safe.
- **Dependensi Wajib:** Microsoft Visual C++ 2015-2022 Redistributable (VS17).

### 2.8 Composer & CA Bundle
- **Composer Executable:** `composer.phar` resmi diletakkan di `C:\composer\composer.phar` bersama `composer.bat` yang memanggil `C:\php\php.exe` secara absolut (PRD 6G.3).
- **URL Resmi:** `https://getcomposer.org/download/latest-stable/composer.phar`
- **Versi:** `2.10.3` (Latest stable)
- **SHA-256:** `7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6`
- **Ukuran:** ~3.2 MB
- **CA Bundle untuk SSL:** `https://curl.se/ca/cacert.pem`
- **SHA-256 CA Bundle:** `a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505`
- **Lokasi CA:** `C:\php\extras\ssl\cacert.pem` (dikonfigurasi pada `curl.cainfo` dan `openssl.cafile`).

### 2.9 Laravel Installer
- **Metode:** `composer global require laravel/installer`
- **Lingkungan Sistem:** `COMPOSER_HOME=C:\composer\home`, direktori binary `C:\composer\home\vendor\bin` ditambahkan ke PATH sistem agar akun mahasiswa dapat langsung menjalankan perintah `laravel new`.

### 2.10 Node.js (LTS)
- **ID Winget:** `OpenJS.NodeJS.LTS`
- **Versi:** `24.20.0`
- **URL Resmi:** `https://nodejs.org/dist/v24.20.0/node-v24.20.0-x64.msi`
- **Tipe Installer:** WIX / MSI
- **Parameter Silent:** `/qn /norestart`
- **SHA-256:** `28b69132c35ccc033bf8f2a67cd10c9d75ef5822593363309da448f2afff2d8a`
- **Ukuran:** ~32 MB
- **Scope:** Machine.

### 2.11 Python 3 (Untuk Pengguna Lab)
- **ID Winget:** `Python.Python.3.13`
- **Versi:** `3.13.15`
- **URL Resmi:** `https://www.python.org/ftp/python/3.13.15/python-3.13.15-amd64.exe`
- **Tipe Installer:** WiX Burn
- **Parameter Silent:** `/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 SimpleInstall=1`
- **SHA-256:** `edec09c4853aeae9ac36efb8c9f95b6b8e2fee65eee56d9767a8b7c69c574403`
- **Ukuran:** ~27 MB
- **Scope:** Machine (`C:\Program Files\Python313`). Terpisah sepenuhnya dari `system\runtime\python\`.

### 2.12 Git for Windows
- **ID Winget:** `Git.Git`
- **Versi:** `2.55.0.5`
- **URL Resmi:** `https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.5/Git-2.55.0.5-64-bit.exe`
- **Tipe Installer:** Inno Setup
- **Parameter Silent:** `/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS`
- **SHA-256:** `d065a4e23c3d9a6b5073d609b5be0830227ec3ca053c083ba385061ddfaf94c6`
- **Ukuran:** ~62 MB
- **Scope:** Machine.

### 2.13 Arduino IDE
- **ID Winget:** `ArduinoSA.IDE.stable`
- **Versi:** `2.3.10`
- **URL Resmi:** `https://github.com/arduino/arduino-ide/releases/download/2.3.10/arduino-ide_2.3.10_Windows_64bit.msi`
- **Tipe Installer:** WIX / MSI
- **Parameter Silent:** `/qn /norestart`
- **SHA-256:** `aebbd1efeac5cfb02a6cad0d93af8221054fc983a5b3c5ce6da8a6bfb9425165`
- **Ukuran:** ~180 MB
- **Scope:** Machine.

### 2.14 7-Zip & WinRAR (Aplikasi Pengguna)
- **7-Zip (64-bit):**
  - **ID Winget:** `7zip.7zip`
  - **Versi:** `26.04`
  - **URL Resmi:** `https://www.7-zip.org/a/7z2604-x64.msi`
  - **SHA-256:** `0b01334a418654293513449f61d6bfc99e5196ca371e3c3dc961eda57cd535c6`
  - **Parameter Silent:** `/qn /norestart`
- **WinRAR (64-bit):**
  - **ID Winget:** `RARLab.WinRAR`
  - **Versi:** `7.23.0`
  - **URL Resmi:** `https://www.rarlab.com/rar/winrar-x64-723.exe`
  - **SHA-256:** `8ff0daf3ed564cc743c0e23ff2e253997ffc74460f9673f0b6dd037b2db4ce7b`
  - **Parameter Silent:** `/s`

### 2.15 Microsoft Visual C++ 2015-2022 Redistributable (x64)
- **ID Winget:** `Microsoft.VCRedist.2015+.x64`
- **Versi:** `14.51.36247.0`
- **URL Resmi:** `https://aka.ms/vs/17/release/vc_redist.x64.exe`
- **Tipe Installer:** WiX Burn
- **Parameter Silent:** `/quiet /norestart`
- **SHA-256:** `843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c`
- **Ukuran:** ~25 MB

### 2.16 Visual Studio Community 2022
- **ID Winget:** `Microsoft.VisualStudio.2022.Community`
- **Versi:** `17.14.41`
- **URL Resmi:** `https://aka.ms/vs/17/release/vs_community.exe`
- **Tipe Installer:** Visual Studio Bootstrapper (exe)
- **Parameter Silent:** `--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --quiet --norestart --wait`
- **SHA-256:** `7041ccc4d8d52901e386b0d96d9f11394244fb2b09fc6aae2c573f16c20ccdcc`
- **Ukuran Awal Bootstrapper:** ~4 MB (total unduhan workload NativeDesktop ~10–15 GB).
- **Rekomendasi Distribusi Lab:** Menggunakan pembuatan layout offline sekali di server LAN (`vs_community.exe --layout <path> --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended`) dan instalasi di PC lab dengan parameter `--noWeb`.

### 2.17 Android Studio & Command-Line Tools
- **Android Studio IDE:**
  - **ID Winget:** `Google.AndroidStudio`
  - **Versi:** `2026.2.1.8`
  - **URL Resmi:** `https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-windows.exe`
  - **Parameter Silent:** `/S`
  - **SHA-256:** `4c26f92e0e78adb1381c9a76597dbd5f6bce13d2ff2bf88cd2b57d425d685f3d`
  - **Ukuran:** ~1.1 GB
- **Android Command-Line Tools (untuk `C:\Android\Sdk`):**
  - **URL Resmi:** `https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip`
  - **SHA-256:** `90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a`
  - **Ukuran:** 155.7 MB (163,263,488 bytes)
  - **Struktur Ekstraksi Wajib:** `C:\Android\Sdk\cmdline-tools\latest\`
  - **Komponen sdkmanager:** `platform-tools`, `platforms;android-34`, `build-tools;34.0.0`, `cmdline-tools;latest`
  - **Penerimaan Lisensi Otomatis:** `echo y | sdkmanager --licenses`

### 2.18 Flutter SDK
- **Versi Stable:** `3.47.7`
- **URL Resmi:** `https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip`
- **SHA-256:** `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`
- **Ukuran:** ~1.1 GB
- **Lokasi Pasang:** `C:\src\flutter` (PATH `C:\src\flutter\bin`)
- **Konfigurasi Otomatis:**
  - `flutter config --android-sdk C:\Android\Sdk --no-analytics`
  - `git config --system --add safe.directory C:/src/flutter`
  - `GRADLE_USER_HOME=C:\gradle-home`

### 2.19 Alat Ekstraksi Portabel Internal (`system\tools\7z\`)
- **Sumber:** 7-Zip Extra resmi (`7z2604-extra.7z`)
- **URL Resmi:** `https://github.com/ip7z/7zip/releases/download/26.04/7z2604-extra.7z`
- **SHA-256:** `dc4b11d3399db18b063630137145f5585d8f7ac847bf3639bd1185d7d1f7cee0`
- **Ukuran:** 1,764,616 bytes (~1.7 MB)
- **Komponen yang dibawa:** `x64/7za.exe` dan `x64/7z.dll` untuk mendukung ekstraksi format `.7z`, `.rar`, dan arsip multi-part tanpa bergantung pada software pihak ketiga yang terpasang di Windows.

### 2.20 Runtime Python Portabel Program (`system\runtime\`)
- **Versi:** Python 3.13.15 (64-bit)
- **Struktur:** Python x64 portabel lengkap dengan pustaka Tcl/Tk (`tcl/`, `Lib/tkinter/`, `DLLs/_tkinter.pyd`, `tcl86t.dll`, `tk86t.dll`).
- **Pustaka Pihak Ketiga (dipin di `requirements.lock`):**
  - `customtkinter` (antarmuka modern) atau `sv-ttk`
  - `jsonschema` (validasi berkas konfigurasi)
- **Jaminan:** Tidak melakukan `pip install` di komputer lab; seluruh dependensi dibundel dalam `system\runtime\site-packages\`.

---

## 3. Daftar "Butuh Hosting Manual" (Sesuai PRD Bagian 6B.4)

Berikut adalah daftar aplikasi dan payload yang **tidak dapat diunduh langsung secara publik tanpa login/autentikasi** atau merupakan berkas konfigurasi kustom lab. Admin lab diminta untuk mengunggah berkas ini ke Google Drive (4 salinan per berkas dengan izin akses *"Siapa saja dengan tautan"*), menghitung hash SHA-256-nya, dan memasukkan ID berkas ke `config\mirrors.json`.

| No | Aplikasi | Versi Target | Nama Berkas Persis | URL Resmi & Penyebab Gagal | Ukuran | SHA-256 Resmi / Sumber | Instruksi untuk Admin Lab |
|---|---|---|---|---|---|---|---|
| 1 | **Cisco Packet Tracer** | 8.2.2 atau 8.3.0 | `CiscoPacketTracer_830_Windows_64bit.exe` (atau varian yang dipakai lab) | `https://www.netacad.com/` (Memerlukan login akun Cisco NetAcad; tidak ada URL publik direct download) | ±250–350 MB | *Dihitung saat diunggah* (`hashDariAdmin: true`) | Unduh installer resmi dari akun Cisco NetAcad lab, hitung SHA256 dengan menu Hitung Hash di LabInstaller, unggah 4 salinan ke Google Drive, dan catat 4 `fileId`-nya ke `mirrors.json`. |
| 2 | **Laragon Custom Bin Payload** | Sesuai setup lab | `laragon-custom-bin.zip` | Folder lokal / payload custom lab (Kumpulan binary PHP, MySQL, Apache milik admin lab) | Bervariasi | *Dihitung dari berkas admin* | Kemas isi folder binary kustom lab ke dalam satu berkas zip, hitung SHA256-nya, simpan di `system\data\payload\laragon-custom-bin\` atau unggah ke Google Drive. |
| 3 | **Visual Studio Offline Layout (Opsional)** | 2022 (17.14.x) | Folder layout LAN / arsip | `https://aka.ms/vs/17/release/vs_community.exe` (Ukuran download online 10–15 GB membebani internet lab 20 Mbps) | ±10–15 GB | *Dihitung dari layout* | Buat layout lokal sekali via `vs_community.exe --layout D:\VSLayout --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended`, lalu bagikan via shared folder LAN lab. |

---

## 4. Mekanisme & Validasi Mirror Google Drive (PRD Bagian 6B.3)

Untuk berkas yang di-host di Google Drive, format unduhan resmi yang digunakan adalah:
```text
https://drive.usercontent.google.com/download?id=<FILE_ID>&export=download&confirm=t
```
Format cadangan:
```text
https://drive.google.com/uc?export=download&id=<FILE_ID>
```

### Penanganan Khusus Respons Google Drive:
1. **Deteksi Respons HTML:** Respons berukuran besar dari Google Drive kerap mengembalikan laman konfirmasi kuota atau peringatan pemindaian virus berupa HTML (`Content-Type: text/html` atau 4 byte pertama `<!DO` / `<htm`). Program wajib mendeteksi ini, menghentikan penyimpanan ke file installer, dan mengekstrak token konfirmasi unduhan jika tersedia.
2. **Penanganan Error Kuota (403/429):** Jika pesan kuota habis terdeteksi, mirror tersebut otomatis diberi status **cooldown** (30–60 menit) di `state\state.json`, dan pengunduh beralih ke mirror berikutnya dari 4 mirror yang terdaftar.
3. **Validasi Checksum Wajib:** Berkas disimpan sementara dengan ekstensi `.part`. Setelah unduhan selesai, program menghitung SHA-256 dan mencocokkannya dengan nilai di `mirrors.json`. Jika tidak cocok, berkas `.part` langsung dihapus dan mirror ditandai korup.
