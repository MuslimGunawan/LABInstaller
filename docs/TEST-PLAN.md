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

## 5. Skenario Pengujian Lanjutan (Milestone Selanjutnya)
- **M3b:** Download Manager mandiri multi-koneksi dengan mirror Google Drive cadangan.
- **M4 & M5:** Uji koeksistensi Laragon (port 80/3306) dan XAMPP (port 8080/3307) dengan halaman verifikasi `lab-check.php`.
- **M6:** Pengujian PHP 8.5.11 NTS di `C:\php`, aktivasi ekstensi `php.ini`, dan eksekusi Composer sebagai akun mahasiswa standar.
- **M6c:** Verifikasi `flutter doctor -v` dan build Android / Windows desktop.
- **M7:** Menu Verifikasi mandiri (V) dan ekspor laporan CSV/TXT.

