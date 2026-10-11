# Rencana Pengujian Manual Lab Auto Installer (TEST-PLAN.md)
*Panduan Pengujian untuk Administrator & Teknisi Lab di Lingkungan Windows*

Dokumen ini berisi prosedur pengujian langkah-demi-langkah yang dapat dijalankan langsung oleh admin lab pada lingkungan Windows terisolasi (Windows Sandbox, Hyper-V VM, atau PC pengujian lab) untuk memverifikasi keandalan Lab Auto Installer.

---

## 1. Lingkungan Uji yang Disarankan
- **Windows Sandbox** (Windows 10/11 Pro/Enterprise) - sangat disarankan karena selalu bersih dan terisolasi.
- **Virtual Machine (VM)** Windows 10/11 64-bit yang bersih.
- **PENTING:** Jangan menguji eksekusi instalasi penuh software di PC kerja utama Anda, karena program ini memodifikasi variabel PATH sistem, registry, dan port web server.

---

## 2. Skenario Pengujian Milestone 1 (M1: Kerangka, Peluncur, & GUI)

### Skenario 1: Peluncuran Bersih & Hak Administrator
1. **Langkah:** Salin folder `LabInstaller` ke drive `C:\` (misal `C:\LabInstaller`).
2. **Langkah:** Klik dua kali pada `Start.bat` (satu-satunya berkas di root).
3. **Hasil yang Diharapkan:**
   - Prompt UAC Windows muncul meminta izin Administrator (pilih **Yes**).
   - Folder `system\` otomatis tersembunyi (atribut Hidden) sehingga root hanya menampilkan `Start.bat`.
   - Jendela antarmuka grafis (GUI) terbuka dalam 1–3 detik tanpa muncul jendela konsol hitam (`cmd.exe`).
   - Tampilan tajam dan jelas di resolusi dan skala layar apa pun (100%, 125%, 150%, 200%).

### Skenario 2: Navigasi & Pemilihan Profil Aplikasi
1. **Langkah:** Di jendela utama, klik dropdown **Pilih Paket Profil...** di kanan atas.
2. **Langkah:** Pilih **Lab Pemrograman Web**.
3. **Hasil yang Diharapkan:**
   - Aplikasi yang relevan (VS Code, Git, Node.js, Laragon, XAMPP, PHP 8.5, Composer, Laravel) otomatis tercentang `[✓]`.
   - Panel ringkasan di bawah otomatis memperbarui:
     - Jumlah aplikasi terpilih (misal: "Dipilih 9 aplikasi")
     - Estimasi total ukuran unduhan (±588.5 MB)
     - Estimasi waktu unduhan berdasarkan koneksi 20 Mbps (~3.9 menit)
     - Status ruang disk: "Ruang disk mencukupi (... GB)"
   - Tombol **INSTAL TERPILIH** aktif (berwarna biru).

### Skenario 3: Pencarian dan Filter Kategori
1. **Langkah:** Ketik `flutter` pada kotak pencarian di toolbar atas.
2. **Hasil yang Diharapkan:** Tabel menyaring hanya aplikasi yang berhubungan dengan kata kunci tersebut.
3. **Langkah:** Klik kategori **GIS** di sidebar kiri.
4. **Hasil yang Diharapkan:** Hanya QGIS Desktop yang tampil di tabel.

### Skenario 4: Drawer Log Interaktif
1. **Langkah:** Klik tombol **Panel Log** di pojok kanan bawah.
2. **Hasil yang Diharapkan:**
   - Panel log terbuka di bagian bawah jendela, menampilkan catatan sesi yang rapi dengan format waktu, level (`[INFO]`), dan pesan sistem.
   - Mengklik **Tutup Log** melipat kembali panel ke bawah.

### Skenario 5: Mode Baris Perintah & Uji Mandiri (--selftest & --dry-run)
1. **Langkah:** Buka Command Prompt (`cmd.exe`) atau PowerShell di folder program.
2. **Langkah:** Jalankan perintah uji mandiri:
   ```cmd
   Start.bat --selftest
   ```
3. **Hasil yang Diharapkan:** Program mencetak 6 tahap pemeriksaan (struktur direktori, impor modul, batas arsitektur, validasi konfigurasi, Tkinter, dan pre-flight) dan berakhir dengan pesan `HASIL: UJI MANDIRI (SELFTEST) LULUS (Exit Code 0)`.
4. **Langkah:** Jalankan simulasi rencana:
   ```cmd
   Start.bat --dry-run --profile web
   ```
5. **Hasil yang Diharapkan:** Program mencetak tabel urutan instalasi, ukuran unduhan, dan dependensi tanpa mengubah satu pun berkas di komputer (Exit code 0).

---

## 3. Skenario Pengujian Milestone 2 (M2: Deteksi & Instalasi Standar Winget)

### Skenario M2-1: Pengujian Isolasi Penuh di Windows Sandbox
1. **Prasyarat:** Windows 10/11 Pro/Enterprise dengan fitur Windows Sandbox aktif.
2. **Langkah:** Klik dua kali pada `system\tools\sandbox\labinstaller.wsb`.
3. **Hasil yang Diharapkan:**
   - Windows Sandbox terbuka dengan folder proyek ter-mount sebagai `C:\KP`.
   - Skrip `Run-SandboxTest.ps1` berjalan otomatis:
     - Melakukan uji mandiri (`Start.bat --selftest`) -> LULUS.
     - Memvalidasi seluruh skema konfigurasi (`Start.bat --check-config`) -> LULUS.
     - Menjalankan simulasi rencana standar (`Start.bat --dry-run --profile standar`) -> LULUS.
     - Menjalankan seluruh pengujian unit pytest (34 pengujian) -> 100% LULUS.
     - Catatan log otomatis ditulis ke `system\data\logs\sandbox-m2-<timestamp>.log`.

### Skenario M2-2: Pembedaan Akurat 3 Status Deteksi
1. **Langkah:** Jalankan `Start.bat` pada sistem yang belum terpasang software standar.
2. **Hasil yang Diharapkan:**
   - Kolom status menampilkan **Belum Terpasang** untuk aplikasi yang tidak ditemukan di sistem.
   - Aplikasi yang belum terpasang otomatis dicentang `[✓]`.
3. **Langkah:** Jalankan `Start.bat` pada komputer yang memiliki aplikasi versi lama (misal VS Code atau Git versi lama).
4. **Hasil yang Diharapkan:**
   - Kolom status menampilkan **Butuh Update (vA.B -> vX.Y)**.
   - Kolom 'Terpasang' menampilkan versi terpasang di sistem.
5. **Langkah:** Jalankan `Start.bat` pada komputer yang sudah terpasang software sesuai target.
6. **Hasil yang Diharapkan:**
   - Kolom status menampilkan **Sudah Terpasang (vX.Y)** dan centang otomatis dinonaktifkan agar tidak menginstal ulang sia-sia.

### Skenario M2-3: Uji Pemantauan Progres Ganda (Per Aplikasi & Total)
1. **Langkah:** Pilih 2 atau lebih aplikasi, lalu klik **INSTAL TERPILIH**.
2. **Hasil yang Diharapkan:**
   - Tidak ada jendela konsol hitam (`cmd.exe`) yang muncul (flag `CREATE_NO_WINDOW` aktif).
   - Tombol berubah menjadi **Batalkan**.
   - Progress bar bagian atas menampilkan persentase unduh/pasang per aplikasi saat ini (0%–100%).
   - Progress bar bagian bawah menampilkan progres total instalasi (misal: "Progres Total: 1 dari 2 aplikasi").
   - Panel log bawah menampilkan log real-time dengan prefix `[VS Code]`, `[Git]`, dll.

### Skenario M2-4: Uji Sifat Idempoten (Idempotency) & Verifikasi Pasca-Instalasi
1. **Langkah:** Selesaikan instalasi seluruh aplikasi standar sampai muncul dialog "Instalasi Selesai".
2. **Langkah:** Tanpa menutup program, klik kembali **Pindai Sistem** atau **INSTAL TERPILIH**.
3. **Hasil yang Diharapkan:**
   - Seluruh aplikasi yang baru saja terpasang kini berstatus **Sudah Terpasang**.
   - Program melaporkan "Seluruh aplikasi yang dipilih sudah terpasang dan sesuai dengan versi target" dan melewati (SKIP) instalasi tanpa mendownload ulang.

---

## 4. Skenario Pengujian Milestone 3 (M3: Ekstraksi Mandiri & Installer Non-Winget)

### Skenario M3-1: Ekstraksi Mandiri Tanpa Software Archiver di Host
1. **Prasyarat:** Komputer Windows bersih tanpa 7-Zip atau WinRAR terpasang (misal Windows Sandbox).
2. **Langkah:** Tempatkan berkas arsip `.zip`, `.7z`, atau `.rar` di direktori staging/payload.
3. **Hasil yang Diharapkan:**
   - Untuk format `.zip`: Ekstraksi diproses menggunakan modul internal Python `zipfile` per entri dengan verifikasi keamanan.
   - Untuk format `.7z` dan `.rar`: Ekstraksi otomatis menggunakan 7-Zip internal yang ter-bundle di `system\tools\7z\7z.exe` (+ `7z.dll`).
   - Ekstraksi berhasil 100% tanpa meminta pengguna menginstal software unzipper eksternal.

### Skenario M3-2: Pertahanan Terhadap Kerentanan Zip-Slip (Path Traversal)
1. **Langkah:** Buat arsip pengujian dengan entri berbahaya (`../../Windows/System32/malicious.dll` atau path drive root absolut `C:\payload.exe`).
2. **Hasil yang Diharapkan:**
   - Modul `archive.py` (`is_safe_extraction_path`) mendeteksi percobaan path traversal.
   - Operasi ekstraksi dibatalkan seketika dengan melempar `ZipSlipSecurityError`.
   - Tidak ada berkas yang ditulis di luar direktori staging yang ditentukan.

### Skenario M3-3: Idempotensi Ekstraksi (.extracted-ok) & Pembersihan Mark of the Web
1. **Langkah:** Ekstrak arsip aplikasi portabel (misal PHP atau Flutter).
2. **Hasil yang Diharapkan:**
   - Berkas penanda `.extracted-ok` dibuat di direktori target berisi metadata JSON (SHA-256 arsip sumber, jumlah berkas, dan stempel waktu UTC).
   - Seluruh NTFS stream `Zone.Identifier` (Mark of the Web) dibersihkan sehingga binary dapat dijalankan tanpa peringatan keamanan "This file came from another computer".
3. **Langkah:** Jalankan kembali ekstraksi untuk arsip yang sama.
4. **Hasil yang Diharapkan:** Program mendeteksi penanda `.extracted-ok` yang cocok dengan SHA-256 arsip dan langsung melewati (skip) ekstraksi ulang.

### Skenario M3-4: Eksekusi Senyap Installer Non-Winget (.exe & .msi)
1. **Langkah:** Jalankan instalasi berkas biner `.exe` (Inno Setup / NSIS) atau `.msi` (misal Temurin JDK / VC++ Redist).
2. **Hasil yang Diharapkan:**
   - Berkas `.msi` dieksekusi via `msiexec.exe /i "<path>" /qn /norestart`.
   - Berkas `.exe` dieksekusi dengan argumen silent yang sesuai dari konfigurasi.
   - Proses berjalan di latar belakang dengan flag `CREATE_NO_WINDOW` (tanpa pop-up jendela hitam).
   - Exit code `0` dan `3010` (Reboot Required) diperlakukan sebagai status sukses terverifikasi.

### Skenario M3-5: Pengunduh Tangguh & Pencegahan Respons HTML Kuota / Antivirus
1. **Langkah:** Uji unduhan dari tautan Google Drive atau mirror yang menghasilkan halaman HTML konfirmasi/kuota kupon.
2. **Hasil yang Diharapkan:**
   - Modul `downloader.py` mendeteksi respons `Content-Type: text/html` atau tag `<!DOCTYPE html>`.
   - Berkas sementara `.part` langsung dibersihkan dan unduhan ditolak dengan `DownloadHtmlResponseError` alih-alih menyimpan berkas HTML sebagai installer `.exe`.

---

## 5. Skenario Pengujian Milestone 3b (M3b: Sumber Unduhan & Mirror Google Drive)

### Skenario M3b-1: Failover Otomatis Antar Mirror Google Drive
1. **Langkah:** Siapkan aplikasi dengan 4 mirror Google Drive di `config/mirrors.json`.
2. **Langkah:** Simulasikan mirror 1, 2, dan 3 mati/kuota/timeout, sementara mirror 4 aktif dengan hash yang valid.
3. **Hasil yang Diharapkan:**
   - Program mencoba mirror 1-3 secara berurutan, mendeteksi kegagalan tanpa berhenti total.
   - Program otomatis beralih (failover) ke mirror 4.
   - Unduhan berhasil diselesaikan dari mirror 4, diverifikasi integritas SHA-256, dan siap dipasang.

### Skenario M3b-2: Pengacakan Mirror Deterministik Per-PC
1. **Langkah:** Jalankan program pada dua mesin berbeda (atau dengan seed PC yang berbeda di lab).
2. **Hasil yang Diharapkan:**
   - Urutan pengujian mirror Google Drive teracak antar PC lab sehingga beban unduhan dan kuota Google Drive tidak terkonsentrasi pada satu mirror yang sama.
   - Urutan stabil pada PC yang sama sehingga percobaan ulang tidak memicu kekacauan rotasi.

### Skenario M3b-3: Cooldown Otomatis Mirror Terkena Kuota
1. **Langkah:** Akses mirror Google Drive yang mengembalikan respons kuota (HTTP 403/429 atau HTML "kuota terlampaui").
2. **Hasil yang Diharapkan:**
   - Mirror tersebut otomatis ditandai status cooldown (30-60 menit) dan dicatat di `system/data/state/state.json`.
   - Pada unduhan aplikasi lain dalam sesi yang sama, mirror dalam masa cooldown otomatis dilewati (skip) agar tidak membuang waktu tunggu timeout.

### Skenario M3b-4: Pelaporan Berkas "Butuh Hosting Manual" & Generator CSV/TXT
1. **Langkah:** Jalankan instalasi aplikasi yang seluruh sumber resmi dan mirror Drive-nya sengaja diputus/tidak tersedia.
2. **Hasil yang Diharapkan:**
   - Program tidak mengalami crash / unhandled exception.
   - Aplikasi ditandai "menunggu sumber" pada ringkasan, dan program tetap melanjutkan instalasi aplikasi lainnya (PRD 6B.4).
   - Program otomatis menghasilkan berkas laporan di `system/data/logs/butuh-hosting-<timestamp>.txt` dan `.csv` berisi rincian nama aplikasi, versi, nama berkas, ukuran, hash SHA-256, dan kolom kosong untuk 4 File ID Google Drive.

### Skenario M3b-5: Menu H (`Start.bat --hosting-list`) dan Fitur LAN Share (`--publish-to-share`)
1. **Langkah:** Buka konsol dan jalankan perintah:
   ```cmd
   Start.bat --hosting-list
   ```
2. **Hasil yang Diharapkan:**
   - Program mencetak tabel daftar seluruh aplikasi yang membutuhkan hosting manual Google Drive lengkap dengan nama berkas, ukuran, dan SHA-256 resmi.
3. **Langkah:** Jalankan instalasi dengan opsi `--publish-to-share` pada PC pertama yang berhasil mengunduh berkas.
4. **Hasil yang Diharapkan:**
   - Berkas unduhan yang tervalidasi SHA-256 otomatis disalin ke folder bersama LAN (`lokasiCacheBersama` di `data/local.json`) secara atomik sehingga PC lab lainnya dapat mengambil dari LAN tanpa memakai kuota internet 20 Mbps.

---

## 6. Skenario Pengujian Milestone 4 (M4: Laragon 6, Custom Bin, Backup, & Rollback)

### Skenario M4-1: Penghentian Selektif Proses Berjalan (Anti-Bentrok XAMPP)
1. **Langkah:** Jalankan proses dari `C:\laragon` (misal `laragon.exe`, `httpd.exe`, `mysqld.exe`) dan jalankan pula proses serupa dari direktori lain seperti `C:\xampp`.
2. **Langkah:** Jalankan hook pasca-instalasi Laragon atau instalasi Laragon via Lab Auto Installer.
3. **Hasil yang Diharapkan:**
   - Program memeriksa path eksekusi biner dari tiap proses yang berjalan.
   - Hanya proses yang berada di bawah `C:\laragon` yang dihentikan secara tertib.
   - Proses dari direktori lain (seperti Apache/MySQL milik XAMPP di `C:\xampp`) tetap berjalan tanpa terganggu (PRD 7.1 #2).

### Skenario M4-2: Validasi Integritas Payload Custom Bin & Penolakan Payload Rusak
1. **Langkah:** Letakkan payload custom bin di `system/data/payload/laragon-custom-bin/` namun kosongkan isinya (tanpa subfolder `bin/php` atau biner yang valid).
2. **Langkah:** Jalankan instalasi Laragon dengan opsi payload tersebut.
3. **Hasil yang Diharapkan:**
   - Program memvalidasi struktur dan hash SHA-256 payload sebelum memodifikasi folder `C:\laragon\bin`.
   - Program mendeteksi payload tidak valid, mencatat peringatan di log, membatalkan penimpaan, dan membiarkan instalasi Laragon standar tetap utuh apa adanya (PRD 7.1 #3).
   - Exit code dan status instalasi tetap berhasil dengan pesan catatan yang transparan.

### Skenario M4-3: Pencadangan (Backup) Otomatis dan Rollback saat Kegagalan
1. **Langkah:** Siapkan Laragon dengan folder `C:\laragon\bin` yang sudah ada file asli.
2. **Langkah:** Simulasikan kegagalan penimpaan (misal izin tulis disk ditolak di tengah proses transfer biner).
3. **Hasil yang Diharapkan:**
   - Program telah mencadangkan folder `bin` dan `data` ke `system/data/backup/laragon-bin-<timestamp>/` dan `system/data/backup/laragon-data-<timestamp>/`.
   - Kegagalan di tengah penimpaan langsung memicu mekanisme rollback otomatis (`rollback_laragon_bin`).
   - Seluruh berkas lama di `C:\laragon\bin` dipulihkan kembali 100% dari direktori cadangan.
   - Laragon tidak berada dalam kondisi rusak atau setengah-setengah (atomik secara logis per PRD 7.2).

### Skenario M4-4: Penyesuaian Konfigurasi Otomatis (laragon.ini & php.ini)
1. **Langkah:** Terapkan custom bin PHP baru (misal `php-8.5.11`) ke Laragon.
2. **Hasil yang Diharapkan:**
   - File `C:\laragon\usr\laragon.ini` otomatis diperbarui untuk menunjuk versi PHP aktif yang baru (`PHP=php-8.5.11`).
   - File `php.ini` pada build PHP baru dibuat secara aman dari `php.ini-development`, mengatur `extension_dir = "ext"`, dan mengaktifkan ekstensi penting (`mysqli`, `pdo_mysql`, `curl`, `mbstring`, `openssl`, `fileinfo`, `gd`).
   - Eksekusi ulang bersifat idempoten (tidak menggandakan baris konfigurasi).

### Skenario M4-5: Pemasangan Halaman Penanda lab-check.php & Verifikasi Biner
1. **Langkah:** Selesaikan instalasi Laragon 6.
2. **Hasil yang Diharapkan:**
   - Berkas `C:\laragon\www\lab-check.php` terpasang (tanpa menimpa `index.php` pengguna).
   - Halaman penanda berisi `STACK=LARAGON`, pembacaan versi PHP, port Apache (80), dan pengujian koneksi ke MySQL port 3306.
   - Program menjalankan verifikasi biner otomatis (`php -v`, `httpd -t` untuk sintaks Apache, dan `mysqld --version`) dan mencatat status ke log.

---

## 7. Skenario Pengujian Milestone 5 (M5: XAMPP, Penyesuaian Port Anti-Bentrok, Firewall, & Hosts)

### Skenario M5-1: Penyesuaian Port Otomatis & Pembuatan Salinan Cadangan (.bak)
1. **Langkah:** Jalankan penginstalan atau penyesuaian XAMPP di `C:\xampp`.
2. **Hasil yang Diharapkan:**
   - Program membuat salinan cadangan `.bak` sebelum mengubah konfigurasi:
     * `C:\xampp\apache\conf\httpd.conf.bak`
     * `C:\xampp\apache\conf\extra\httpd-ssl.conf.bak`
     * `C:\xampp\mysql\bin\my.ini.bak`
     * `C:\xampp\phpMyAdmin\config.inc.php.bak`
     * `C:\xampp\xampp-control.ini.bak`
   - Berkas `httpd.conf` mendengarkan pada `Listen 8080` dan `ServerName localhost:8080`.
   - Berkas `httpd-ssl.conf` mendengarkan pada `Listen 8443` dan `<VirtualHost _default_:8443>`.
   - Berkas `my.ini` memiliki `port=3307` pada blok `[client]` dan `[mysqld]`.

### Skenario M5-2: Penyesuaian phpMyAdmin & Tombol Admin XAMPP Control Panel
1. **Langkah:** Buka berkas `C:\xampp\phpMyAdmin\config.inc.php` dan `C:\xampp\xampp-control.ini` setelah proses penyesuaian.
2. **Hasil yang Diharapkan:**
   - `config.inc.php` memuat baris `$cfg['Servers'][$i]['port'] = '3307';` dan mengarah ke host `'127.0.0.1'` secara deterministik.
   - `xampp-control.ini` mencatat port `Apache=8080`, `ApacheSSL=8443`, dan `MySQL=3307`.
   - Mengklik tombol **Admin** pada modul Apache di XAMPP Control Panel membuka `http://localhost:8080/` (bukan port 80).
   - Mengklik tombol **Admin** pada modul MySQL membuka `http://localhost:8080/phpmyadmin` dan berhasil login ke database port 3307 tanpa error koneksi.

### Skenario M5-3: Pemasangan Halaman Penanda lab-check.php di htdocs
1. **Langkah:** Buka browser dan akses alamat `http://localhost:8080/lab-check.php`.
2. **Hasil yang Diharapkan:**
   - Halaman menampilkan respons plain text yang diawali dengan `STACK=XAMPP`.
   - `SERVER_PORT=8080` dan `DB_PORT=3307`.
   - `DB_STATUS=OK` (berhasil mengeksekusi `SELECT 1` ke MySQL port 3307).
   - Akses dari luar (bukan 127.0.0.1 / ::1) otomatis ditolak dengan kode status HTTP 403 Forbidden demi keamanan lab.

### Skenario M5-4: Otomasi Aturan Windows Firewall (Inbound Allow)
1. **Langkah:** Buka Windows Defender Firewall with Advanced Security (`wf.msc`) -> Inbound Rules.
2. **Hasil yang Diharapkan:**
   - Terdapat aturan inbound yang dibuat otomatis oleh Lab Auto Installer:
     * `LabInstaller - XAMPP Apache (...)` mengarah ke `C:\xampp\apache\bin\httpd.exe`.
     * `LabInstaller - XAMPP MySQL (...)` mengarah ke `C:\xampp\mysql\bin\mysqld.exe`.
   - Saat mahasiswa menjalankan Apache atau MySQL melalui XAMPP Control Panel, tidak muncul jendela popup konfirmasi firewall Windows.

### Skenario M5-5: Pengeditan Berkas hosts Aman & Idempoten (core/hosts.py)
1. **Langkah:** Panggil penambahan entri domain virtual host (misal `127.0.0.1 myapp.test`).
2. **Hasil yang Diharapkan:**
   - Berkas `C:\Windows\System32\drivers\etc\hosts` memiliki cadangan `hosts.bak`.
   - Entri baru ditambahkan dengan komentar penanda: `127.0.0.1 myapp.test # LabInstaller`.
   - Pemanggilan berulang dengan data yang sama tidak menghasilkan baris duplikat (idempoten).
   - Fungsi penghapusan (`remove_hosts_entry`) hanya menghapus baris yang memiliki tag `# LabInstaller` dan membiarkan konfigurasi sistem lainnya utuh.

### Skenario M5-6: Uji Koeksistensi Bersamaan (Laragon Port 80 vs XAMPP Port 8080)
1. **Langkah:** Jalankan Apache dan MySQL pada Laragon (Start All di Laragon).
2. **Langkah:** Jalankan Apache dan MySQL pada XAMPP (Start Apache & MySQL di XAMPP Control Panel).
3. **Hasil yang Diharapkan:**
   - Keempat layanan (Apache Laragon, MySQL Laragon, Apache XAMPP, MySQL XAMPP) menyala hijau bersamaan tanpa bentrok port.
   - Mengakses `http://localhost` membuka halaman Laragon port 80.
   - Mengakses `http://localhost:8080` membuka halaman dashboard XAMPP port 8080.
   - Menghentikan atau merestart salah satu tumpukan tidak mengganggu tumpukan lainnya.

---

## 8. Skenario Pengujian Lanjutan (Milestone Selanjutnya)
- **M6:** PHP 8.5.11 Standalone (`C:\php`), aktivasi ekstensi `php.ini` bersih, CA bundle SSL, dan Composer.
- **M6b:** Kebijakan versi + uninstall bersih + backup data pengguna (`htdocs`/MySQL).
- **M6c:** Paket Flutter Lab (`flutter doctor -v` hijau, lisensi Android diterima, Windows dev mode).
- **M7:** Menu Verifikasi mandiri (V) dan ekspor laporan CSV/TXT.



