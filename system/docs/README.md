# Panduan Lengkap: Lab Auto Installer

## 1. Tentang Aplikasi
**Lab Auto Installer** adalah aplikasi otomatisasi instalasi dan penyiapan software untuk komputer laboratorium komputer berbasis Windows 10/11 64-bit. Didesain khusus untuk teknisi dan administrator laboratorium, program ini memungkinkan instalasi puluhan software dengan satu klik secara seragam, hening (silent), tanpa jendela konsol hitam yang mengganggu, serta dilengkapi mekanisme anti-bentrok port (Laragon vs XAMPP) dan kebijakan PATH terpusat.

## 2. Struktur Folder & Penggunaan
Struktur folder program dirancang bersih:
- **`Start.bat`**: Satu-satunya berkas yang terlihat di root folder. Klik dua kali untuk memulai.
- **`system\`**: Berisi seluruh mesin, antarmuka, runtime Python portabel mandiri, dan berkas konfigurasi (memiliki atribut `Hidden` secara default agar tidak membingungkan pengguna).
  - `system\app\`: Kode program utama dan manifest konfigurasi.
  - `system\runtime\`: Python portabel mandiri (tidak mengubah atau bergantung pada Python milik pengguna lab).
  - `system\tools\7z\`: Utilitas ekstraksi mandiri (7-Zip Portable).
  - `system\data\`: Data lokal PC lab (log, cache unduhan, payload kustom, berkas cadangan/backup). Folder ini tidak pernah ditimpa oleh pembaruan otomatis (auto-update).

## 3. Cara Penggunaan

### 3.1 Mode Antarmuka Grafis (GUI)
1. Salin folder `LabInstaller` ke drive lokal PC lab (disarankan `C:\LabInstaller`).
2. Klik dua kali berkas `Start.bat`. Jika diminta izin Administrator (UAC), pilih **Yes**.
3. Pilih profil paket di kanan atas (misal: "Lab Pemrograman Web" atau "Lab GIS") atau centang software yang diinginkan secara manual.
4. Periksa ringkasan di panel bawah (jumlah software, estimasi ukuran unduhan, ruang disk).
5. Klik tombol **Instal Terpilih**.
6. Pantau progres instalasi dan log di panel bawah.

### 3.2 Mode Baris Perintah (CLI) & Otomasi
Program dapat dijalankan tanpa antarmuka untuk otomasi skrip atau remote session:
- Menjalankan uji mandiri:
  ```cmd
  Start.bat --selftest
  ```
- Menjalankan simulasi rencana tanpa mengubah sistem (Dry Run):
  ```cmd
  Start.bat --dry-run --profile "Lab Pemrograman Web"
  ```
- Instalasi tanpa interaksi pengguna (Unattended):
  ```cmd
  Start.bat --unattended --profile "Lab Semua"
  ```
- Validasi seluruh berkas konfigurasi JSON:
  ```cmd
  Start.bat --check-config
  ```

## 4. Kebijakan Anti-Bentrok & Kebijakan PATH
1. **Laragon vs XAMPP:**
   - Laragon Apache: Port `80` (HTTP) dan `443` (HTTPS) | MySQL: Port `3306`
   - XAMPP Apache: Port `8080` (HTTP) dan `8443` (HTTPS) | MySQL: Port `3307`
   - Pengaturan ini diterapkan otomatis pasca-instalasi sehingga kedua web server dapat berjalan bersamaan.
2. **Kebijakan PATH PHP Tunggal:**
   - Hanya **satu** binary PHP yang aktif di PATH lingkungan sistem Windows, yaitu PHP standalone di `C:\php` (versi 8.5.11).
   - PHP internal Laragon (`C:\laragon\bin\php\...`) dan PHP XAMPP (`C:\xampp\php\...`) dikhususkan untuk web server masing-masing dan tidak ditambahkan ke PATH sistem.

## 5. Mengatasi Masalah (Troubleshooting)
- **Runtime rusak:** Jalankan `powershell -ExecutionPolicy Bypass -File system\boot\recover.ps1 -Repair` untuk memulihkan runtime Python portabel.
- **Log sesi:** Berkas log per sesi tersimpan di folder `system\data\logs\install-YYYYMMDD-HHmmss.log`.
- **Unduhan offline:** Simpan installer di folder `system\data\cache\download\` agar program mendeteksi cache lokal tanpa mengunduh ulang via internet.
