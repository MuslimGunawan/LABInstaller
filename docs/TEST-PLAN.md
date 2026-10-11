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

## 3. Skenario Pengujian Lanjutan (Milestone Selanjutnya)
- **M2:** Pengujian instalasi silent via winget di Windows Sandbox (idempotent, jalankan 2x).
- **M3:** Ekstraksi arsip ZIP, 7Z, dan RAR di PC tanpa software archiver terpasang.
- **M4 & M5:** Uji koeksistensi Laragon (port 80/3306) dan XAMPP (port 8080/3307) dengan halaman verifikasi `lab-check.php`.
- **M6:** Pengujian PHP 8.5.11 NTS di `C:\php`, aktivasi ekstensi `php.ini`, dan eksekusi Composer sebagai akun mahasiswa standar.
- **M6c:** Verifikasi `flutter doctor -v` dan build Android / Windows desktop.
