# PRD: Lab Auto Installer

| | |
|---|---|
| Versi | 1.3 FINAL (Python + antarmuka grafis; siap dieksekusi agent) |
| Tanggal | 9 Oktober 2026 |
| Pelaksana | Agent (Antigravity, Gemini 3.8) |
| Bahasa antarmuka program | Bahasa Indonesia |
| Platform target | Windows 10/11 64-bit; aplikasi Python dengan runtime portabel yang dibawa sendiri (tidak ada yang perlu dipasang di PC lab) |

---

## 0. Instruksi Kerja untuk Agent (BACA DULU)

1. **Jangan menebak.** Setiap ID paket winget/Chocolatey, URL unduhan, dan parameter silent installer **harus diverifikasi** (`winget show --id ...`, `winget search ...`, cek halaman rilis resmi) sebelum dimasukkan ke manifest. Daftar di dokumen ini adalah titik awal, bukan fakta final.
2. **Prioritas utama: tidak boleh error di sisi program ini.** Kegagalan Laragon/XAMPP/aplikasi itu sendiri bukan tanggung jawab kita, tetapi program wajib *mendeteksi, mencatat, dan memberi tahu* dengan jelas, tidak berhenti diam-diam, dan tidak meninggalkan instalasi setengah jadi.
3. **Wajib diuji** di lingkungan Windows bersih (Windows Sandbox atau VM) sebelum dinyatakan selesai. Jika lingkungan uji tidak tersedia (mis. agent tidak berjalan di Windows), tandai bagian itu "BELUM TERUJI" di laporan akhir, jangan klaim berhasil, dan **buat `TEST-PLAN.md`** berisi langkah uji manual yang bisa dijalankan admin di PC Windows, lengkap dengan hasil yang diharapkan.
4. **Jika ada informasi yang kurang** (lihat bagian 12), gunakan placeholder yang jelas di config dan daftarkan sebagai pertanyaan terbuka, jangan mengarang nilainya.
5. Kerjakan bertahap sesuai milestone (bagian 11) dan laporkan hasil tiap milestone.
6. **Kebijakan versi (6A), sumber unduhan/mirror (6B), verifikasi (6C), auto-update (6D), kasus tak terduga (6E), alur arsip (6F), PHP/Composer (6G), dan paket Flutter (6H) bersifat wajib**, setara dengan fitur instalasi itu sendiri.
7. **Kode yang di-push ke GitHub akan otomatis terpakai di semua PC lab.** Jangan push ke cabang rilis sebelum lolos pemeriksaan otomatis (lihat 6D.6). Satu push yang rusak bisa merusak seluruh lab.
8. **Jika sumber resmi suatu aplikasi (mis. PHP) tidak dapat dijangkau, laporkan ke admin lewat daftar "Butuh Hosting Manual" (6B.4)**; jangan menebak URL atau memakai sumber tidak resmi.
9. **Format laporan tiap milestone** dan **definisi selesai** mengikuti bagian 14. Jika terblokir, lanjutkan ke milestone yang tidak bergantung padanya; berhenti dan bertanya hanya untuk keputusan yang tidak bisa dibatalkan (mis. menghapus data pengguna).
10. **Kualitas kode adalah syarat rilis (bagian 4.2).** Tidak boleh ada push ke cabang rilis atau rilis yang belum lulus seluruh gerbang kualitas (ruff, mypy, compileall, pytest, uji GUI, dan uji paket rilis nyata di Windows). Laporkan hasil CI yang sebenarnya, bukan klaim. Jika agent tidak memiliki Windows, GitHub Actions (`windows-latest`) adalah tempat pembuktiannya.
11. **Antarmuka grafis (5.1) adalah inti produk**, dibangun sejak M1 dan disempurnakan di tiap milestone. Mesin (`core\`) dan tampilan (`ui\`) dipisah tegas.

---

## 1. Latar Belakang & Tujuan

Komputer di lab perlu diinstal banyak aplikasi (editor, web stack, GIS, bahasa pemrograman) secara berulang dan seragam. Instalasi manual lambat, tidak konsisten, dan rawan salah konfigurasi, terutama untuk setup custom (Laragon + binary PHP dll. milik sendiri) dan koeksistensi Laragon dengan XAMPP.

**Tujuan:** satu aplikasi berantarmuka grafis (GUI) yang rapi. Admin lab mencentang aplikasi atau memilih paket lalu menekan satu tombol; aplikasi terinstal otomatis (silent), konfigurasi custom diterapkan otomatis, hasilnya dapat diverifikasi dan dicatat di log. Tersedia juga mode baris perintah (CLI) untuk otomasi dan sesi remote.

**Bukan tujuan (non-goals):**
- Bukan manajemen perangkat skala enterprise (tanpa agen jaringan, tanpa dashboard web).
- Tidak memperbaiki bug di Laragon/XAMPP itu sendiri.
- Tidak mengelola lisensi aplikasi berbayar.

---

## 2. Pengguna & Konteks

- **Pengguna:** admin/teknisi lab (bukan mahasiswa).
- **Lingkungan:** komputer lab, Windows, jalan sebagai Administrator.
- **Internet:** sekitar **20 Mbps** (praktisnya ±2 MB/s). Konsekuensi desain:
  - Unduhan besar (QGIS ±1 GB+, NetBeans, XAMPP, Laragon) **tidak boleh diunduh ulang di setiap PC**.
  - Program harus punya **cache lokal / repositori offline** (folder di flashdisk atau shared folder server lab) yang dipakai bersama.
  - Unduhan harus **bisa dilanjutkan (resume)**, **diverifikasi hash**, dan **di-retry**.

---

## 3. Struktur Folder Program

```
LabInstaller\                          # folder yang dibuka admin; di root HANYA ada SATU file
├── Start.bat                          # SATU-SATUNYA file di root: klik ini untuk memulai
└── system\                            # semua yang lain ada di sini (atribut Hidden, lihat 6D.8)
    ├── boot\
    │   ├── bootstrap.py               # kecil & stabil: cek update (6D), ganti app\, lalu jalankan aplikasi
    │   └── recover.ps1                # darurat: pulihkan / tukar runtime\ (6D.9); SATU-SATUNYA skrip PowerShell
    ├── runtime\                       # PYTHON PORTABEL + dependensi pihak ketiga (versi sendiri; jarang berubah)
    │   ├── python\                    # python.exe, pythonw.exe, pustaka standar, Tcl/Tk (untuk GUI)
    │   ├── site-packages\             # dependensi yang di-pin (requirements.lock)
    │   └── runtime.json               # versi runtime, versi Python, hash berkas penting
    ├── app\                           # KODE PROGRAM (diganti utuh saat auto-update; kecil, beberapa MB)
    │   ├── VERSION                    # nomor versi program (semver), mis. 1.4.2
    │   ├── version.json               # metadata rilis: versi, hash paket, runtime yang dibutuhkan, versi minimum, catatan
    │   ├── CHANGELOG.md               # catatan perubahan per versi (dipakai untuk pesan update)
    │   ├── labinstaller\              # paket Python utama
    │   │   ├── __main__.py            # pintu masuk: pilih GUI atau CLI + penangan error global
    │   │   ├── cli.py                 # argumen baris perintah (10.1) dan mode tanpa jendela
    │   │   ├── core\                  # MESIN: tanpa kode tampilan; dapat diuji otomatis
    │   │   │   ├── paths.py           # semua path dihitung dari satu root (lokasi Start.bat), pakai pathlib
    │   │   │   ├── config.py          # baca & validasi apps/mirrors/profiles/ports/local.json (+ config terakhir yang valid)
    │   │   │   ├── logger.py          # log ke file + antrean pesan untuk tampilan
    │   │   │   ├── preflight.py       # pengecekan awal (admin, disk, port, internet, winget)
    │   │   │   ├── download.py        # unduh resume + retry + cek SHA256 + cache
    │   │   │   ├── sources.py         # urutan sumber, failover mirror (termasuk Google Drive), cooldown mirror
    │   │   │   ├── extract.py         # ekstraksi arsip zip/rar/7z + validasi + staging (6F)
    │   │   │   ├── installer.py       # eksekusi installer silent (winget/exe/msi/arsip)
    │   │   │   ├── detect.py          # deteksi aplikasi sudah terinstal + versi
    │   │   │   ├── uninstall.py       # uninstall resmi + pembersihan terdaftar + backup data
    │   │   │   ├── verify.py          # verifikasi instalasi + laporan
    │   │   │   ├── updater.py         # auto-update dari GitHub (6D)
    │   │   │   ├── ports.py           # cek & atur port (anti-bentrok)
    │   │   │   ├── hosts.py           # edit file hosts dengan aman
    │   │   │   ├── winenv.py          # registry, PATH sistem, variabel lingkungan, ACL, firewall, shortcut (satu-satunya tempat panggilan Windows tingkat rendah)
    │   │   │   ├── journal.py         # jurnal transaksi + state.json + file lock
    │   │   │   └── engine.py          # orkestrasi: rencana → eksekusi → verifikasi → ringkasan (dipakai GUI dan CLI)
    │   │   ├── hooks\                 # skrip pasca-instal khusus per aplikasi
    │   │   │   ├── laragon.py
    │   │   │   ├── xampp.py
    │   │   │   ├── php.py
    │   │   │   ├── composer.py
    │   │   │   └── flutter.py ...
    │   │   └── ui\                    # TAMPILAN (GUI): hanya memanggil core\engine.py
    │   │       ├── app.py             # jendela utama
    │   │       ├── views\             # daftar aplikasi, paket, verifikasi, update, hosting, log, ringkasan
    │   │       ├── theme.py           # warna, font, ikon, tema terang/gelap
    │   │       ├── worker.py          # pekerjaan di thread latar + antrean pesan ke UI
    │   │       └── strings_id.py      # SEMUA teks antarmuka (Bahasa Indonesia) di satu tempat
    │   ├── config\
    │   │   ├── apps.json              # MANIFEST semua aplikasi (satu-satunya tempat menambah app)
    │   │   ├── mirrors.json           # nama file, 4 fileId Google Drive, ukuran, SHA256 per aplikasi (6B.4)
    │   │   ├── profiles.json          # paket siap pakai (mis. "Lab Web", "Lab GIS")
    │   │   ├── ports.json             # peta port Laragon vs XAMPP
    │   │   └── schema\                # skema JSON untuk validasi tiap berkas config
    │   └── assets\                    # ikon, logo lab, templat (mis. lab-check.php)
    ├── tools\                         # alat portabel yang dibawa rilis (diganti saat update)
    │   └── 7z\                        # 7z.exe + 7z.dll + file hash (6F.2)
    ├── docs\                          # README.md, SOURCES.md (hasil riset M0), TEST-PLAN.md, TEST-REPORT.md
    ├── tests\                         # pytest + skrip uji; hanya ada di repo, tidak ikut paket rilis
    └── data\                          # DATA LOKAL PC INI: TIDAK PERNAH ditimpa update, tidak masuk Git
        ├── local.json                 # override lokal per PC/lab (proxy, password arsip, opsi)
        ├── payload\                   # file custom milik admin (TIDAK diunduh)
        │   └── laragon-custom-bin\    # PHP/Apache/MySQL/dll. versi terbaru milik admin + manifest.sha256
        ├── cache\
        │   ├── download\              # installer/arsip hasil unduhan (+ file .sha256)
        │   └── extract\               # staging hasil ekstraksi arsip (sementara)
        ├── backup\                    # backup otomatis sebelum menimpa file
        ├── logs\                      # install-YYYYMMDD-HHmmss.log (per sesi), verify-*.txt/.csv
        └── state\                     # state.json (waktu cek update, cooldown mirror, jurnal transaksi), last-good\ (config terakhir yang valid), lock file
```

**Konvensi nama di seluruh dokumen ini** (agar tidak perlu menulis path panjang): `cache\`, `payload\`, `backup\`, `logs\`, `state\` = `system\data\<nama>\`; `config\...` = `system\app\config\...` (kecuali `config\local.json` = `system\data\local.json`); `labinstaller\` = `system\app\labinstaller\` (kode Python), `core\` = `labinstaller\core\` (mesin) dan `ui\` = `labinstaller\ui\` (tampilan); `runtime\` = `system\runtime\`; `docs\` = `system\docs\`. Rujukan "menu U/H/F/V/L/P" di bagian lain dokumen ini berarti tombol atau tampilan yang setara di GUI (5.1) dan perintah yang setara di CLI.

**Dilarang hardcode path di kode**: semua path dihitung dari satu root yang diturunkan dari lokasi `Start.bat` (modul `core\paths.py`, memakai `pathlib`), sehingga seluruh folder bisa dipindah tanpa ada yang rusak. **Mesin dan tampilan terpisah:** `core\` tidak boleh mengimpor apa pun dari `ui\` (diperiksa otomatis di CI); GUI dan CLI sama-sama hanya memanggil `core\engine.py`.

---

## 4. Teknologi yang Dipakai

### 4.1 Pilihan teknologi

| Komponen | Pilihan | Alasan |
|---|---|---|
| Bahasa utama | **Python 3, 64-bit**, satu versi minor dipatok (agent memilih versi stabil terbaru yang didukung semua dependensi dan Windows di lab, lalu mencatatnya di `docs\SOURCES.md`) | Kode rapi dan mudah diuji; pustaka standar sudah mencakup registry (`winreg`), HTTP, hash, zip, JSON, dan proses |
| Runtime | **Python portabel yang dibawa sendiri** di `system\runtime\` (6D.9) | Tidak ada yang perlu dipasang di PC lab; versi seragam; tidak mengganggu Python milik pengguna |
| Antarmuka | **GUI Tkinter** bertema modern: default `customtkinter`, cadangan `ttk` + tema `sv-ttk`, cadangan terakhir PySide6. Pilihan final ditentukan lewat prototipe di Windows pada M1 berdasarkan kriteria 5.1 (tajam di DPI tinggi, tidak membeku, tema terang/gelap) | Tkinter ikut Python portabel (ringan); Qt hanya bila Tkinter tidak memenuhi kriteria |
| Launcher | **`Start.bat`** (satu-satunya file di root) | Klik dua kali; meminta hak Administrator; memeriksa runtime; memanggil bootstrap |
| Dependensi pihak ketiga | Seminimal mungkin (kandidat: `customtkinter`, `jsonschema`); di-pin ke versi pasti + hash di `requirements.lock`; **dibundel di runtime**; tidak ada `pip install` di PC lab | Menghindari "jalan di komputer pengembang, rusak di lab" |
| Package manager | **winget** sebagai sumber utama, unduh langsung (URL resmi/mirror) sebagai fallback; dipanggil lewat `subprocess` | winget bawaan Win 10/11; Laragon v6 dan XAMPP butuh unduh langsung |
| Unduh | `urllib`/`http.client` (stdlib) dengan header `Range` untuk resume, `hashlib` untuk SHA256 | Satu mekanisme untuk GitHub, Drive, dan vendor; memakai penyimpanan sertifikat dan proxy sistem Windows |
| Ekstraksi arsip | `zipfile` untuk `.zip`; **7-Zip portabel** (`system\tools\7z\`) untuk `.7z`, `.rar`, dan lainnya | Tidak bergantung pada aplikasi yang belum terpasang (6F) |
| Format config | **JSON** + skema (`config\schema\`) | Mudah diedit admin dan divalidasi |
| Log | Teks UTF-8 | Mudah dibaca dan dikirim |
| Pemeriksaan kualitas | `ruff`, `mypy`, `compileall`, `pytest`, GitHub Actions di `windows-latest` | Mencegah error sebelum sampai ke PC lab (4.2) |
| Skrip PowerShell | **Hanya satu**: `system\boot\recover.ps1` (pemulihan/penukar runtime) | Interpreter tidak dapat menukar dirinya sendiri (6D.9) |

### 4.2 Gerbang Kualitas Kode (WAJIB: mencegah syntax error dan error sejenisnya)

Semua perubahan kode harus lulus gerbang berikut **sebelum** masuk cabang rilis. Gerbang dijalankan oleh satu perintah lokal (mis. `python -m tools.check`) dan diulang otomatis di GitHub Actions (`windows-latest`) dengan **versi Python yang sama persis dengan runtime yang dibundel**.

1. **Gaya dan tipe:** seluruh kode memakai type hints; `ruff check` dan `ruff format --check` tanpa temuan; `mypy --strict` (atau pyright mode strict) tanpa error.
2. **Sintaks:** `python -m compileall -q` atas seluruh paket memakai Python runtime yang dibundel.
3. **Uji unit (`pytest`) pada `core\`**, minimal mencakup: perbandingan versi, parsing dan validasi manifest, failover mirror, deteksi halaman HTML dari Drive, resume unduhan (server uji lokal), penolakan zip-slip, penyuntingan `php.ini`/`httpd.conf`/`my.ini` memakai berkas contoh (idempotent), jurnal transaksi, dan updater dengan paket palsu (sukses, hash salah, kode rusak, rollback). Cakupan minimal 80% pada `core\` (di luar `winenv.py`).
4. **Uji khusus Windows** di `windows-latest`: registry, PATH, ACL, dan `hosts` pada lokasi/kunci uji sementara; tidak menyentuh bagian runner di luar uji.
5. **Uji GUI:** `--selftest-gui` membuka jendela utama, merender semua tampilan, lalu menutup tanpa error; tangkapan layar otomatis disimpan sebagai artefak CI untuk ditinjau.
6. **Uji paket rilis yang sebenarnya (gerbang paling penting):** CI membangun paket lengkap (runtime + app), mengekstraknya ke folder bersih di Windows, lalu menjalankan `Start.bat --selftest` (mengimpor semua modul, memvalidasi semua config, memeriksa runtime, Tkinter, 7-Zip) dan `--dry-run` untuk semua profil. **Rilis hanya terbit bila semuanya berakhir dengan exit code 0.** Ini yang menjamin tidak ada "modul hilang" atau "tkinter tidak ada" saat sampai di PC lab.
7. **Config yang diedit admin (mis. di Notepad) rawan salah sintaks JSON.** Config dibaca dengan `utf-8-sig` (toleran BOM) dan divalidasi skema dengan pesan jelas (nama berkas, baris, kolom, penjelasan). Program tidak crash: memakai **config terakhir yang valid** (`state\last-good\`), menampilkan peringatan di GUI, dan menyediakan tombol/perintah "Periksa konfigurasi" (`--check-config`).
8. **Penangan error global:** tidak ada traceback mentah ke layar. Pengguna melihat dialog ramah berisi ringkasan dan lokasi log; traceback lengkap hanya di log (`faulthandler` aktif); exit code mengikuti 10.1.
9. **Praktik kode yang dilarang/diwajibkan:** path memakai `pathlib`; tidak ada `shell=True` dengan string gabungan (pakai daftar argumen); setiap `subprocess` memakai `timeout` dan `creationflags=CREATE_NO_WINDOW` (agar jendela hitam tidak muncul); keluaran proses Windows didekode dengan penanganan code page (agent memverifikasi); tidak ada `eval`/`exec`; tidak ada manipulasi `sys.path` ad hoc; `PYTHONUTF8=1`.
10. **Pra-komit:** hook pre-commit menjalankan gerbang 1 sampai 3. Dilarang push bila gagal. Pembaruan dependensi hanya lewat PR terjadwal dengan seluruh gerbang lulus.
11. **Pembuktian jujur:** agent melaporkan hasil CI yang nyata (tautan/ringkasan), dan menandai "BELUM TERUJI" bila suatu gerbang tidak bisa dijalankan.

### 4.3 Penting (sumber error umum di Windows)
- **UTF-8 eksplisit:** buka berkas dengan `encoding` yang disebut jelas; JSON dibaca `utf-8-sig`; log ditulis UTF-8.
- **DPI:** tandai proses DPI-aware (`SetProcessDpiAwareness`) **sebelum** membuat jendela agar tidak buram di skala 125% ke atas.
- **Elevasi:** `Start.bat` memeriksa hak Administrator (mis. `fltmc`); bila bukan, meluncurkan ulang dirinya dengan `Start-Process -Verb RunAs` (memakai `powershell.exe` hanya untuk elevasi); setelah elevasi, direktori kerja dan `%~dp0` harus benar; semua path dikutip; **jendela tidak menutup otomatis saat error** (`pause`).
- **Menjalankan Python:** `Start.bat` memanggil `"%~dp0system\runtime\python\pythonw.exe" -X utf8 "%~dp0system\boot\bootstrap.py"` dan menunggu prosesnya selesai (`start /wait`) agar exit code terbaca; karena `pythonw.exe` tidak punya konsol, semua error harus masuk log dan dialog (agent memverifikasi perilakunya). `Start.bat` meneruskan semua argumen (`%*`) ke program; untuk argumen non-interaktif (`--selftest`, `--dry-run`, `--unattended`, `--cli`) ia tidak memakai `pause` dan mengembalikan exit code program apa adanya (dibutuhkan CI dan otomasi).
- **Mark of the Web:** berkas hasil unduhan/ekstraksi dapat bertanda "dari internet" sehingga memicu peringatan SmartScreen. Setelah mengekstrak paket (dari GitHub maupun arsip aplikasi), hapus penanda itu (`Zone.Identifier`).
- **TLS:** `ssl` bawaan Python sudah memakai TLS modern dan penyimpanan sertifikat Windows; tidak perlu pengaturan khusus, tetapi jam sistem yang salah tetap menyebabkan error sertifikat (6E).
- **Satu instance:** gunakan mutex agar aplikasi tidak berjalan ganda.
- Jangan bergantung pada `pip`, internet, atau Python milik sistem untuk menjalankan program.

---

## 5. Fitur Aplikasi (Antarmuka dan Daftar Aplikasi)

### 5.1 Antarmuka Grafis (GUI)

Prinsip: **rapi, jelas, dan tidak pernah membeku**. Seluruh teks berbahasa Indonesia dan berada di satu berkas (`ui\strings_id.py`).

Tata letak jendela utama (ilustrasi, bukan desain final):
```
+--------------------------------------------------------------------------------+
| [logo] LAB AUTO INSTALLER    v1.4.2  (v) Terbaru   Daftar r2026.10.09-1  [Cek update] |
+----------------+---------------------------------------------------------------+
| KATEGORI       | [ Cari aplikasi...        ]   [Pilih paket v]   [Kosongkan]    |
| > Semua        | +-----------------------------------------------------------+ |
|   Editor & IDE | | [x] Laragon 6 + Custom Bin   target 6.x    -     o Belum   | |
|   Web Stack    | | [x] PHP 8.5.11 (C:\php)      target 8.5.11  8.3.4 ^ Versi beda| |
|   Bahasa&Tools | | [ ] Visual Studio Code       target 1.x     1.x   (v) Sesuai | |
|   Flutter      | +-----------------------------------------------------------+ |
|   GIS          |                                                               |
+----------------+---------------------------------------------------------------+
| Dipilih 2 aplikasi | unduhan +-1,8 GB | estimasi +-25 menit | ruang disk OK     |
| [ INSTAL TERPILIH ] [Verifikasi] [Butuh hosting (2)] [Buka folder v] [Log ^]   |
+--------------------------------------------------------------------------------+
```

**Persyaratan tampilan dan perilaku:**
- **Daftar aplikasi:** satu baris per aplikasi berisi kotak centang, nama, versi target, versi terpasang, dan **lencana status** (teks + ikon + warna, tidak hanya warna): Sesuai, Belum terpasang, Versi beda (akan diganti), Rusak, Menunggu sumber, Butuh reboot. Ada pencarian dan filter kategori.
- **Paket (profil):** memilih paket mencentang semua anggotanya; dependensi ikut tercentang otomatis dan diberi keterangan "dibutuhkan oleh ...".
- **Ringkasan bawah:** jumlah terpilih, total unduhan, perkiraan waktu (dasar 20 Mbps, dikalibrasi dari kecepatan terukur), dan ketersediaan ruang disk. Tombol **Instal** nonaktif disertai alasan bila syarat belum terpenuhi.
- **Saat instalasi:** progres keseluruhan dan progres per aplikasi (Mengunduh x% dengan kecepatan dan sisa waktu → Mengekstrak → Memasang → Memverifikasi), panel log yang dapat dibuka (saring Info/Peringatan/Error), dan tombol **Batalkan** yang berhenti rapi di batas langkah (tidak memutus installer di tengah). **Tidak ada jendela hitam (cmd) yang muncul.**
- **Ringkasan akhir:** tabel Berhasil/Dilewati/Gagal/Butuh reboot, dengan tombol "Buka log", "Coba lagi yang gagal", dan "Salin ringkasan".
- **Konfirmasi sebelum tindakan yang merusak:** uninstall/penggantian versi menampilkan daftar apa yang akan diganti dan memberitahu bahwa data di-backup (6A.5).
- **Fungsi yang harus tersedia (disebut "menu" di bagian lain dokumen ini):** Verifikasi (V), Cek update (U), File perlu di-hosting (H, termasuk tombol **Hitung hash** untuk memilih berkas dan menyalin SHA256-nya), Buka folder data/log/payload (F), Lihat log (L), Paket (P), dan Periksa konfigurasi.
- **Visual:** tema terang/gelap mengikuti Windows; **DPI-aware** dan tajam di skala 100%, 125%, 150%, dan 200%; ukuran awal 1100x700, minimum 960x600 (juga nyaman di 1366x768), ukuran dan posisi terakhir diingat; font, jarak, dan ikon konsisten; dapat dipakai dengan keyboard (Tab dan pintasan).
- **Responsif:** semua pekerjaan berat berjalan di thread latar (`ui\worker.py`); UI hanya menerima pesan dari antrean, sehingga jendela tidak pernah "Not Responding". Menutup jendela saat instalasi meminta konfirmasi lalu berhenti rapi (jurnal tersimpan agar bisa dilanjutkan).
- **Satu instance saja:** membuka aplikasi kedua kali memunculkan jendela pertama.
- **CLI:** semua fitur GUI punya padanan CLI karena sama-sama memanggil `core\engine.py` (10.1). Bila GUI gagal dibuat (mis. Tk rusak), program jatuh ke CLI dengan pesan jelas, bukan crash.

### 5.2 Daftar aplikasi awal
VS Code, Apache NetBeans (+ cek JDK yang dibutuhkan; agent verifikasi versi JDK kompatibel dan tambahkan sebagai dependensi), QGIS, XAMPP, Laragon 6 (custom), Composer, PHP (standalone, lihat kebijakan PATH di 8.4), Laravel Installer (via Composer), Node.js LTS, Python 3.x, Git, **Arduino IDE** dan **Cisco Packet Tracer** (keduanya lewat mirror Google Drive, 6B), serta **7-Zip** dan **WinRAR** (dibutuhkan pengguna lab; ekstraksi oleh program ini sendiri **tidak** bergantung pada keduanya, lihat 6F), **Visual Studio Community** (beban kerja dideklarasikan di manifest), **Paket Flutter** (Visual Studio C++, Android Studio + Android SDK + lisensi, Flutter SDK; lihat 6H), serta **PHP standalone di `C:\php` + Composer** (6G). Daftar bisa bertambah hanya dengan mengedit `apps.json`. Python untuk pengguna lab adalah aplikasi biasa yang **terpisah** dari runtime program (`system\runtime\`); memasang atau meng-uninstall-nya tidak boleh mengganggu runtime.

### 5.3 Manifest `apps.json` (skema minimal)
```json
{
  "id": "vscode",
  "nama": "Visual Studio Code",
  "kategori": "Editor & IDE",
  "metode": "winget",
  "wingetId": "Microsoft.VisualStudioCode",
  "versiTarget": "1.x.y | latest-resolved",
  "kebijakanVersi": "exact | exact-minor | minimum",
  "deteksi": { "tipe": "registry|file|command", "nilai": "..." },
  "sumber": [
    { "tipe": "cache|share|resmi|gdrive", "url": "...", "fileId": "...", "prioritas": 1 }
  ],
  "ukuran": 0,
  "sha256": "wajib untuk sumber gdrive/exe/zip",
  "uninstall": { "metode": "quiet-string|winget|msi|custom", "args": "...", "bersihkan": [] },
  "backupData": [],
  "dependensi": [],
  "hook": null
}
```
Metode yang didukung: `winget`, `exe` (URL + argumen silent + sha256), `msi`, `arsip` (unduh → ekstrak → instal; mencakup zip/rar/7z, lihat 6F), `hook-only`. Skema harus divalidasi saat program mulai; entri rusak ditandai dan dilewati dengan pesan jelas, program tidak boleh berhenti.

### 5.4 Profil/paket
`profiles.json` berisi kumpulan id aplikasi, contoh "Lab Pemrograman Web", "Lab GIS", "Lab Semua". Memilih profil menginstal semua anggotanya berurutan sesuai dependensi.

---

## 6. Persyaratan Keandalan (Anti-Error)

### 6.1 Pre-flight (sebelum instalasi apa pun)
Program menolak lanjut dengan pesan jelas bila:
- Tidak berjalan sebagai Administrator.
- Versi Windows tidak didukung (minimal Windows 10; agent menentukan build minimum dari persyaratan Python dan winget yang dipakai), atau runtime Python tidak lolos pemeriksaan integritas.
- Ruang disk di drive tujuan kurang (hitung dari total ukuran terpilih + margin 30%).
- winget tidak ada (tawarkan jalur fallback unduh langsung, jangan crash).
- Internet tidak tersedia **dan** file yang dibutuhkan tidak ada di cache (jika cache lengkap, lanjut offline).
- Ada instalasi lain berjalan (mutex `_MSIExec`/proses installer lain) → tunggu/retry.
- Port yang akan dipakai Laragon/XAMPP sudah dipakai proses lain (lihat bagian 8).
- Pending reboot terdeteksi (registry) → peringatkan.

### 6.2 Setiap langkah instalasi
1. **Idempotent**: jika sudah terinstal pada versi yang diinginkan → lewati (kecuali mode `--force`/Repair). Menjalankan ulang tidak boleh merusak.
2. **Unduh** → resume, retry 3x dengan jeda bertambah, cek SHA256 (jika hash tersedia), simpan di `cache\download\`.
3. **Instal silent** dengan timeout (mis. 30 menit) agar tidak menggantung selamanya.
4. **Tangani exit code** (0 = sukses, 3010 = sukses butuh reboot, kode "sudah terinstal" winget dianggap sukses, selain itu = gagal).
5. **Verifikasi pasca-instal**: panggil deteksi lagi + cek file/versi. Instal dianggap sukses **hanya jika verifikasi lolos**, bukan sekadar exit code 0.
6. **Gagal satu aplikasi tidak menghentikan yang lain**; di akhir tampil **ringkasan**: berhasil / dilewati / gagal / perlu reboot, lengkap dengan lokasi log.
7. Semua `try/catch` mencatat pesan error + stack ke log; layar menampilkan pesan ramah.

### 6.3 Logging
- Satu file log per sesi di `logs\`, format: waktu, level (INFO/WARN/ERROR), id aplikasi, pesan.
- Catat versi, path, exit code, durasi, hash file.
- Mode `--dry-run`: hanya menampilkan apa yang akan dilakukan, tanpa mengubah sistem (wajib ada untuk pengujian).

### 6.4 Aturan instalasi via winget
- Gunakan `--source winget` (hindari sumber `msstore`), `--exact`, `--silent --disable-interactivity --accept-package-agreements --accept-source-agreements`, dan `--version <target>` untuk mengunci versi. Jalankan `winget source update` sebelum mulai.
- **Instal untuk semua pengguna (`--scope machine`) bila paket mendukung.** Beberapa paket (mis. VS Code) default per-pengguna sehingga tidak terlihat oleh akun mahasiswa. Agent memeriksa dukungan scope per paket dan mencatat hasilnya di manifest.
- Kode keluar winget "sudah terinstal / tidak ada pembaruan" dianggap sukses **hanya setelah** verifikasi versi (6A) lolos.
- Jika winget tidak ada atau sumbernya error → fallback ke unduh langsung (6B), bukan gagal.

### 6.5 Penyesuaian Umum untuk Lingkungan Lab (hook, dapat dikonfigurasi di `data\local.json`)
- **Hak tulis:** bila mahasiswa memakai akun standar, beri grup `Users` hak Modify (`icacls`) hanya pada `C:\xampp\htdocs` dan `C:\laragon\www` (bukan seluruh drive).
- **Shortcut** di Public Desktop (semua pengguna) untuk aplikasi utama; hapus shortcut ganda hasil instalasi ulang.
- **Tanpa auto-start:** Laragon/XAMPP tidak dijalankan otomatis saat login dan tidak dipasang sebagai Windows Service.
- **Jangan menonaktifkan antivirus/Defender.** Program hanya memberi petunjuk pengecualian bila admin menginginkannya.

---

## 6A. Kebijakan Versi & Uninstall Otomatis

### 6A.1 Versi target
- Setiap aplikasi punya `versiTarget`: versi pasti (mis. `8.5.11`) atau `latest-resolved` (agent/program menentukan versi terbaru dari sumber resmi saat dijalankan, lalu mencatatnya di log).
- `kebijakanVersi`: `exact` (**default**, versi harus sama persis), `exact-minor` (mayor.minor sama, patch boleh berbeda), `minimum` (versi yang sama atau lebih baru dibiarkan).
- **PHP: target 8.5.11** (atau 8.5.x terbaru yang terverifikasi). Agent wajib memeriksa rilis di sumber resmi (windows.php.net) dan **tidak boleh mengandalkan ID winget per-minor** seperti `PHP.PHP.8.2` atau `PHP.PHP.8.3`, karena itu yang menghasilkan versi lama. Versi PHP lama (8.2/8.3/dst.) tidak boleh ada di manifest.
- **PHP bawaan XAMPP:** XAMPP membawa PHP-nya sendiri, yang bisa saja versi lama. Agent harus memeriksa apakah ada rilis XAMPP dengan PHP 8.5.x. Jika tidak ada, ganti folder `C:\xampp\php` dengan build PHP target yang **kompatibel dengan Apache XAMPP** (arsitektur x64, versi Visual C++ yang sama, varian Thread Safe, serta `php8apache2_4.dll`), lalu perbaiki `httpd-xampp.conf`. Jika tidak kompatibel, **laporkan, jangan dipaksakan**.
- Setelah selesai, **hanya satu PHP** yang boleh aktif di PATH sistem, yaitu `C:\php` (lihat 6G dan 8.4); pemindaian `php.exe` di seluruh PC (PATH, Laragon, XAMPP, Chocolatey, Scoop, winget) dilaporkan oleh menu verifikasi.

### 6A.2 Alur keputusan per aplikasi
| Kondisi terdeteksi | Tindakan |
|---|---|
| Belum terinstal | Instal versi target |
| Terinstal, versi sesuai kebijakan, verifikasi lolos | **SKIP** (dicatat "sudah sesuai") |
| Terinstal, versi **berbeda** (lebih lama **atau** lebih baru) | Uninstall resmi + bersih, lalu instal versi target |
| Terinstal tetapi rusak / verifikasi gagal | Uninstall resmi + bersih, lalu instal ulang |
| Beberapa salinan (mis. VS Code mode user + system, banyak versi Python) | Deteksi semua, hapus yang tidak sesuai, sisakan satu |

Catatan: kebijakan "versi lebih baru pun diganti" artinya downgrade memang bisa terjadi. Ini disengaja, dan bisa dilonggarkan per aplikasi dengan `kebijakanVersi: minimum`.

### 6A.3 Deteksi
Gabungkan beberapa sumber: registry Uninstall (HKLM 64-bit, HKLM 32-bit, HKCU), `winget list`, versi file executable, dan keluaran perintah `--version`. Bandingkan dengan `[System.Version]`, bukan perbandingan string. Waspadai alias Python dari Microsoft Store (`python.exe` palsu) dan dua jenis installer VS Code (User vs System).

### 6A.4 Uninstall resmi dan bersih
1. Hentikan proses terkait (berdasarkan path, bukan nama saja).
2. Gunakan uninstaller **resmi** berurutan: `QuietUninstallString`/`UninstallString` dengan flag senyap, `winget uninstall`, `msiexec /x {GUID} /qn /norestart`, atau uninstaller khusus (XAMPP: `uninstall.exe --mode unattended`; Laragon: `unins000.exe /VERYSILENT`). Parameter harus diverifikasi.
3. Pakai timeout; tangani kode 1618 (installer lain berjalan), 3010 (butuh reboot).
4. **Pembersihan** hanya terhadap daftar `bersihkan` yang dideklarasikan eksplisit di manifest (folder sisa, entri PATH, shortcut, aturan firewall, entri `hosts` milik kita, variabel lingkungan). **Dilarang menghapus dengan wildcard atau path yang tidak ada di whitelist.**
5. Verifikasi bahwa aplikasi benar-benar hilang sebelum memasang yang baru.

### 6A.5 Pengaman data (WAJIB)
Menghapus XAMPP/Laragon/MySQL dapat menghapus `htdocs`, `www`, dan database mahasiswa/dosen. Sebelum uninstall aplikasi seperti itu, program **otomatis backup** folder di `backupData` (mis. `htdocs`, `www`, data MySQL) ke `backup\data-<timestamp>\` setelah cek ruang disk. Mode interaktif menampilkan konfirmasi ("Akan menghapus X versi A, diganti versi B. Lanjut? Y/N"); mode `--unattended` melewati konfirmasi **tetapi tetap backup**. Data pengguna (ekstensi VS Code, paket pip, dll.) tidak dihapus secara default.

---

## 6B. Sumber Unduhan & Mirror Google Drive

### 6B.1 Urutan sumber
1. Cache lokal yang hash-nya sudah terverifikasi.
2. Payload lokal / shared folder LAN.
3. Sumber resmi (winget / URL resmi), dengan batas waktu ketat.
4. Mirror Google Drive 1 sampai 4.

Untuk aplikasi bertanda `lambat` atau `tidakBisaDiunduh` (Cisco Packet Tracer, Arduino IDE, Apache NetBeans, dan sejenisnya), urutan menjadi: cache → LAN → **mirror Google Drive** → sumber resmi sebagai cadangan terakhir (bila ada).

### 6B.2 Failover antar mirror
- Tiap aplikasi punya hingga 4 salinan identik di Drive (`fileId` masing-masing, di manifest). **Urutan mirror diacak per PC** agar beban unduhan dan kuota Drive tersebar.
- Batas waktu koneksi 15 detik; jika tidak ada byte masuk selama 30 detik (stall) → pindah mirror. Tiap mirror dicoba maksimal 2x.
- Jika mirror terkena kuota/timeout/error → tandai gagal dengan **cooldown** (mis. 30–60 menit, disimpan di `state\state.json`) lalu langsung lanjut ke mirror berikutnya.
- Jika semua mirror gagal → tampilkan pesan jelas dan nama file yang bisa ditaruh manual di `cache\`, lalu lanjut ke aplikasi berikutnya (jangan berhenti total).

### 6B.3 Detail teknis Google Drive (sumber error umum)
- Gunakan format `https://drive.usercontent.google.com/download?id=<FILE_ID>&export=download&confirm=t`. Agent harus menguji format ini secara nyata, karena Google dapat mengubahnya.
- File besar dapat mengembalikan **halaman HTML peringatan** (bukan file). Program harus mendeteksi respons HTML (Content-Type `text/html` atau byte awal bukan `MZ`/`PK`/header yang diharapkan), menangani token konfirmasi bila ada, dan **tidak pernah menyimpan HTML sebagai installer**.
- Pesan kuota seperti "terlalu banyak pengguna yang mengunduh" (kode 403/429) diperlakukan sebagai mirror gagal sementara.
- Gunakan `HttpClient`/`Invoke-WebRequest` dengan header `Range` untuk resume (BITS kurang andal untuk Drive). Simpan sebagai `.part`, ganti nama hanya setelah **SHA256 cocok**.
- **SHA256 dan ukuran wajib** ada di manifest untuk setiap file Drive. Hash tidak cocok → hapus file, tandai mirror korup, coba mirror lain.
- Folder/file Drive diatur "siapa saja dengan tautan" (tanpa login). Tidak ada kredensial di repo.
- Untuk mengurangi beban kuota: PC pertama yang berhasil mengunduh menyalin file terverifikasi ke shared folder LAN (opsi `--publish-to-share`), sehingga PC lain mengambil dari LAN.
- Catatan lisensi: Cisco Packet Tracer didistribusikan lewat Cisco Networking Academy dengan syarat penggunaan tertentu. Admin lab bertanggung jawab memastikan distribusi internal sesuai ketentuan.

### 6B.4 Pelaporan Sumber Tidak Terjangkau ("Butuh Hosting Manual")

Jika sebuah aplikasi (contoh: **PHP**) tidak dapat dijangkau dari sumber resminya, program dan agent **tidak boleh menebak URL, memakai sumber tidak resmi, atau diam saja**. Keduanya wajib memberi tahu admin agar file bisa ditaruh di Google Drive.

**A. Saat pengembangan (tugas agent):**
- Jika agent tidak bisa mengakses/mengunduh sumber resmi (timeout, 404, diblokir, versi tidak ditemukan), agent berhenti menebak dan menaruh aplikasi itu di bagian **"Butuh Hosting Manual"** pada laporan akhir tiap milestone.
- Setiap entri wajib berisi: nama aplikasi, **versi target**, **nama file persis dan varian** (mis. untuk PHP: x64, Thread Safe/Non Thread Safe, versi Visual C++ yang dibutuhkan, beserta alasannya), URL resmi yang dicoba dan penyebab kegagalannya, ukuran serta SHA256 resmi bila diketahui, dan instruksi singkat untuk admin.
- Di manifest, aplikasi itu diberi status `menunggu-hosting` dan `fileId` berisi placeholder `ISI_FILE_ID_GDRIVE`, **bukan** URL karangan.

**B. Saat program berjalan (runtime):**
- Jika sumber resmi gagal dan tidak ada mirror Drive yang terisi atau berfungsi, tampilkan pesan jelas di layar, contoh:
  `[PHP 8.5.11] tidak bisa diunduh dari sumber resmi (alasan: timeout). Mohon taruh file "php-8.5.11-Win32-vs17-x64.zip" di Google Drive Anda dan berikan ID filenya.`
- Aplikasi ditandai **"menunggu sumber"** pada ringkasan akhir; aplikasi lain tetap diproses.
- Program menulis `logs\butuh-hosting-<timestamp>.txt` dan `.csv` berisi daftar semua file yang perlu di-hosting (kolom: aplikasi, versi, nama file persis, URL resmi + penyebab gagal, ukuran, SHA256, kolom kosong untuk `fileId` 1 sampai 4). Daftar yang sama dapat dibuka lewat menu **`H. Daftar file yang perlu di-hosting`**.

**C. Cara admin menindaklanjuti:**
1. Unduh file persis seperti yang diminta (dari jaringan/PC lain yang bisa menjangkau sumber resmi).
2. Hitung hash dengan tombol **Hitung hash** di aplikasi (tampilan "Butuh hosting") atau `Get-FileHash -Algorithm SHA256 <file>`, lalu cocokkan dengan hash resmi bila halaman rilis menyediakannya (windows.php.net mencantumkan SHA256 per berkas).
3. Unggah **4 salinan** ke Google Drive dengan akses "siapa saja dengan tautan". ID file adalah bagian `<FILE_ID>` pada tautan `https://drive.google.com/file/d/<FILE_ID>/view`.
4. Isi `config\mirrors.json` (file khusus yang mudah diedit; berisi nama file, 4 `fileId`, ukuran, SHA256) atau serahkan ID-nya kepada agent untuk dimasukkan.
5. Agent mendorong perubahan ke GitHub dan merilis versi baru; semua PC lab mendapat konfigurasi mirror itu otomatis lewat auto-update (6D).

**D. Aturan hash:** bila hash resmi tidak dapat diperoleh, hash dihitung dari file yang diunggah admin lalu dicatat di `mirrors.json` dan diberi tanda `hashDariAdmin: true`, dan agent harus mengingatkan admin untuk mencocokkannya dengan sumber resmi. Hash tidak boleh dikosongkan untuk file dari Drive.

---

## 6C. Verifikasi Instalasi

Tampilan/tombol tingkat atas **Verifikasi instalasi** (V; hanya membaca, tidak mengubah sistem), juga dijalankan otomatis di akhir tiap sesi instalasi sebagai ringkasan.

**Yang diperiksa:**
- Tiap aplikasi: terpasang? versi sesuai target? file kunci ada?
- Custom Laragon: hash file di `bin` cocok dengan `manifest.sha256`; `php -v`, `httpd -t`, `mysqld --version` dari path Laragon sukses.
- `php -v`, `composer -V`, `node -v`, `python --version`, `laravel --version` sesuai dan konsisten (hanya satu PHP di PATH).
- Konfigurasi port: Apache/MySQL XAMPP berada di 8080/8443/3307; Laragon di 80/443/3306 (lihat bagian 8).
- Pengujian layanan (opsional, start sementara lalu stop): `http://localhost` merespons halaman Laragon dan `http://localhost:8080` merespons XAMPP.
- Entri `hosts`, aturan firewall, dan ada tidaknya aplikasi ganda/tersisa.

**Keluaran:** tabel di layar dengan status `OK`, `VERSI BEDA`, `TIDAK ADA/RUSAK`, `DILEWATI`; laporan `logs\verify-<timestamp>.txt` dan `.csv` (berisi nama komputer, tanggal, versi program, versi tiap aplikasi). Menu lanjutan: **"Perbaiki yang gagal"**, yang menjalankan ulang instalasi hanya untuk yang bermasalah. Dalam mode `--unattended`/`--verify` mengembalikan exit code non-nol bila ada yang gagal (lihat 10.1).

---

## 6D. Auto-Update dari GitHub

### 6D.1 Tujuan
Skrip disimpan di GitHub. Setiap kali agent menyempurnakan program dan merilisnya, semua PC lab otomatis mendapat versi terbaru saat program dijalankan, termasuk perubahan `apps.json` (misalnya versi target PHP naik), tanpa admin menyalin file manual.

### 6D.2 Alur
1. `Start.bat` menjalankan **`system\boot\bootstrap.py`** memakai Python portabel (`system\runtime\`). Bootstrap (kecil, jarang berubah) yang memperbarui program lalu memanggil `labinstaller`, supaya kode yang sedang berjalan tidak menimpa dirinya sendiri.
2. Pengecekan berkala: simpan waktu cek terakhir di `state\state.json`; cek setiap kali jalan jika lebih dari 24 jam (atau via menu `U` / parameter `--force-update`). Pengaturan interval ada di config.
3. Ambil `version.json` dari rilis GitHub. **Gunakan URL rilis/raw (`raw.githubusercontent.com`, aset rilis), bukan GitHub API**, karena API tanpa token dibatasi 60 permintaan/jam per IP dan seluruh lab berbagi satu IP publik.
4. Jika versi jarak jauh lebih baru: unduh paket update `app-vX.Y.Z.zip` → **verifikasi SHA256** (dari `version.json`) → ekstrak ke folder staging.
5. **Validasi paket sebelum dipasang:** semua berkas `.py` lolos `compileall` memakai Python runtime yang terpasang, semua modul dapat diimpor, semua JSON valid dan sesuai skema, dan `version.json` konsisten dengan isi paket. Setelah ekstraksi hapus penanda Mark of the Web (`Zone.Identifier`).
6. Backup versi sekarang ke `backup\app-<versi>\`, lalu ganti isi `system\app\`, `system\tools\`, dan `system\docs\` dengan versi baru. `system\runtime\` diganti **hanya** bila `runtimeVersion` di `version.json` berbeda (6D.9). **Jangan sentuh `system\data\`** (cache, payload, backup, logs, state, `local.json`), **jangan ubah `Start.bat`**, dan jangan ganti `system\boot\` (lihat 6D.8).
7. Jalankan **uji mandiri** (`python -m labinstaller --selftest`: mengimpor semua modul, memvalidasi semua config, memeriksa runtime, Tkinter, dan 7-Zip, tanpa mengubah sistem). Jika gagal → **rollback otomatis** ke versi sebelumnya dan catat peringatan.
8. Mulai ulang program dengan versi baru dan tampilkan "Diperbarui dari X ke Y" beserta catatan rilis.

### 6D.3 Aturan ketahanan
- **Update tidak boleh memblokir kerja:** timeout 10 detik; tanpa internet atau GitHub tidak terjangkau → lanjut dengan versi saat ini dan beri peringatan singkat.
- Gunakan file kunci (lock) di `state\` agar dua instance (mis. dua PC di shared folder yang sama) tidak memperbarui bersamaan.
- Rekomendasi penempatan: **salin program ke disk lokal** (mis. `C:\LabInstaller`), sedangkan shared folder hanya untuk `cache\` dan `payload\` (lokasinya diatur di `data\local.json`, mis. `lokasiCacheBersama` dan `lokasiPayload`; bila tidak diisi, dipakai `system\data\` lokal).
- Dukung saluran (channel): `stable` (cabang `main`) dan `beta` (opsional, untuk uji di satu PC).
- Pengaturan `version.json` memuat `minSupportedVersion` dan penanda `disabled` (kill switch: bila rilis ternyata bermasalah, update ke versi itu dibatalkan).

### 6D.4 Repositori
- **Repo resmi: `https://github.com/MuslimGunawan/LABInstaller`.** Nama akun dan repo dipakai oleh updater (URL `raw.githubusercontent.com/MuslimGunawan/LABInstaller/...` dan aset rilis) serta ditulis **di satu tempat** pada konfigurasi updater, bukan tersebar di kode, supaya mudah diganti bila repo berpindah.
- Disarankan **repo publik** tanpa rahasia apa pun (tanpa token/kata sandi). Jika harus privat, gunakan token read-only (fine-grained PAT) yang disimpan di `data\local.json` (lokal, tidak masuk Git) dan jelaskan risikonya. Seluruh `system\data\` (payload, cache, backup, logs, state, `local.json`) **tidak** masuk Git (`.gitignore`).
- Versi mengikuti semver; setiap rilis diberi tag `vX.Y.Z`.

### 6D.5 Alur kerja agent saat mengubah kode
1. Bekerja di cabang `dev`; commit kecil dengan pesan jelas.
2. Naikkan `VERSION`, perbarui `version.json` (hash dihitung otomatis) dan `CHANGELOG.md`.
3. Merge ke `main` hanya jika pemeriksaan otomatis (6D.6) lulus; tag rilis memicu pembuatan paket zip + `version.json`.

### 6D.6 Pemeriksaan Otomatis (GitHub Actions)
Tiap push/PR ke `main` menjalankan **seluruh gerbang kualitas 4.2** di `windows-latest`: pemasangan Python yang dipatok dan dependensi dari `requirements.lock` (dengan hash), `ruff`, `mypy --strict`, `compileall`, `pytest` + cakupan, pemeriksaan batas mesin/tampilan (`core\` tidak mengimpor `ui\`), validasi JSON terhadap skema, uji GUI (`--selftest-gui` + tangkapan layar), pemeriksaan kesinkronan versi (6D.7 poin 6), lalu pembangunan paket rilis (`LabInstaller-full`, `app`, `runtime`) beserta hash dan **uji paket rilis yang sebenarnya** (ekstrak ke folder bersih, `Start.bat --selftest`, `--dry-run` semua profil, uji `recover.ps1`). **Rilis hanya terbit jika semuanya lulus.** Uji `core\` juga dijalankan di Linux untuk umpan balik cepat.

### 6D.7 Nomor Versi: Selalu Terlihat dan Jelas Terbaru atau Tidak

Admin harus bisa langsung tahu apakah PC itu memakai versi terkini.

1. **Header jendela utama (banner)** selalu menampilkan nomor versi program dan status update, contoh:
   - `v1.4.2 [✔ terbaru]` jika sama dengan rilis terbaru di GitHub.
   - `v1.4.1 [⬆ tersedia v1.4.2]` jika ada versi baru yang belum terpasang.
   - `v1.4.2 [offline: terakhir dicek 09 Okt 2026 08:20]` jika GitHub tidak terjangkau.
   - `v1.5.0-dev [versi pengembangan]` jika nomor lokal lebih tinggi dari rilis resmi.
2. **Versi daftar aplikasi** (`manifestVersion` di `apps.json`, mis. `r2026.10.09-1`) ikut ditampilkan di banner, karena versi target aplikasi (misalnya PHP) bisa berubah tanpa kode program berubah.
3. **Pesan saat update berhasil:** `Diperbarui dari v1.4.1 ke v1.4.2` disertai ringkasan catatan rilis (diambil dari `CHANGELOG.md`/`version.json`). Jika rollback: `Update ke v1.4.3 gagal, kembali ke v1.4.2` beserta alasannya.
4. **Menu `U. Cek update program`** menampilkan: versi terpasang, versi terbaru di GitHub, tanggal rilis, saluran (stable/beta), waktu pengecekan terakhir, dan daftar perubahan di antara keduanya. Bila ada versi baru, tersedia pilihan "Perbarui sekarang".
5. **Versi tercatat di mana-mana:** baris pertama setiap file log, setiap laporan verifikasi (`.txt`/`.csv`), `state\state.json`, dan perintah `--version` yang mencetak versi lalu keluar.
6. **Satu sumber kebenaran:** file `VERSION` menjadi acuan; `version.json`, tag Git (`vX.Y.Z`), dan nama paket rilis harus sama. Pemeriksaan otomatis (6D.6) **gagal** jika angkanya tidak sinkron, atau jika kode berubah tetapi `VERSION` tidak dinaikkan.
7. Aturan semver: **PATCH** (perbaikan kecil/bug), **MINOR** (fitur baru yang kompatibel, termasuk menambah aplikasi), **MAJOR** (perubahan yang mengubah struktur/format config). Perbandingan versi memakai `[System.Version]`, bukan perbandingan teks, sehingga `1.10.0` dianggap lebih baru dari `1.9.0`.

### 6D.8 Paket Rilis, Repo, dan Folder Root yang Bersih
- **Yang terlihat admin di root hanya satu file: `Start.bat`.** Semua lainnya ada di `system\`. Saat pertama dijalankan, `bootstrap.py` memberi atribut Hidden pada folder `system\` (opsi `sembunyikanFolderSistem` di `data\local.json`, default `true`) agar root benar-benar hanya menampilkan `Start.bat`. Tombol "Buka folder" (F) membuka folder data/log/payload sehingga admin tidak perlu menampilkan item tersembunyi.
- **Tiga jenis paket rilis** (semuanya tanpa `data\`): (1) `LabInstaller-full-vX.Y.Z.zip` untuk pemasangan pertama = `Start.bat` + `system\boot\`, `runtime\`, `app\`, `tools\`, `docs\` (ekstrak ke `C:\LabInstaller\`); (2) `app-vX.Y.Z.zip` untuk update rutin = `app\`, `tools\`, `docs\` (kecil, beberapa MB); (3) `runtime-rN.zip` hanya bila runtime berubah (6D.9).
- **Yang diganti auto-update:** `system\app\`, `system\tools\`, `system\docs\`; `system\runtime\` hanya bila `runtimeVersion` berubah (6D.9). **Tidak diganti:** `Start.bat`, `system\boot\`, `system\data\`.
- `system\boot\bootstrap.py` dan `recover.ps1` sengaja kecil dan jarang berubah (bootstrap tidak boleh menimpa dirinya sendiri saat berjalan). Jika perlu diubah, itu dilakukan sebagai rilis MAJOR dengan catatan langkah manual di `CHANGELOG.md`; `version.json` memuat `bootVersion`, dan tampilan Update memperingatkan bila bootstrap di PC itu sudah usang.
- **Repo GitHub** memiliki berkas pengembangan di root repo (`.github\`, `.gitignore`, `pyproject.toml`, `requirements.lock`, konfigurasi `ruff`/`mypy`, `README.md` singkat yang menunjuk ke `system\docs\README.md`), tetapi yang sampai ke PC lab hanya isi paket rilis. `system\data\` masuk `.gitignore`.

### 6D.9 Runtime Terpisah dan Pemulihan
- **Mengapa dipisah:** runtime (Python + Tcl/Tk + dependensi) berukuran puluhan hingga ratusan MB, sedangkan kode hanya beberapa MB. Dengan versi sendiri (`runtime.json`, `runtimeVersion` di `version.json`), update kode rutin tidak mengunduh ulang runtime, sehingga hemat kuota di jaringan 20 Mbps.
- **Pembuatan runtime (oleh CI):** dari Python resmi python.org (tanda tangan Authenticode dan hash diverifikasi), ditambah dependensi dari `requirements.lock` dengan `--require-hashes`; mengandung Tcl/Tk; `pip` dan berkas yang tidak perlu dipangkas; hasilnya diuji (impor `tkinter`, `ssl`, `ctypes`, `winreg`, dan seluruh dependensi, plus GUI smoke test). Agent memverifikasi cara resmi yang menghasilkan Python portabel lengkap dengan Tcl/Tk (paket "embeddable" resmi setahu kami tidak menyertakannya).
- **Penukaran runtime:** interpreter tidak dapat menimpa dirinya sendiri. Saat `runtimeVersion` berubah, bootstrap mengunduh `runtime-rN.zip` ke staging, memverifikasi SHA256, lalu keluar dengan exit code khusus (10); `Start.bat` memanggil `recover.ps1 -Apply` yang menukar `runtime\` (dengan backup dan rollback) lalu menjalankan ulang aplikasi.
- **Pemulihan:** sebelum menjalankan Python, `Start.bat` melakukan pemeriksaan ringan (keberadaan `python.exe` dan hash ringkas di `runtime.json`). Bila hilang atau rusak, `recover.ps1 -Repair` mengunduh runtime dari rilis GitHub (hash diverifikasi) dan memasangnya. Bila offline, tampilkan pesan jelas: ekstrak ulang paket lengkap, atau taruh `runtime-rN.zip` di `data\cache\download\`.
- `recover.ps1` kecil, tidak mengandung logika bisnis, dan diuji di CI (termasuk skenario runtime yang sengaja dirusak).

---

## 6E. Antisipasi Kasus Tak Terduga

| Kasus | Penanganan wajib |
|---|---|
| Aplikasi sudah terinstal dan benar | Skip, catat "sudah sesuai" |
| Aplikasi terinstal versi lain (lama/baru) | Uninstall resmi bersih lalu instal target (6A) |
| Instalasi sebelumnya terputus (listrik mati, Ctrl+C) | Jurnal transaksi di `state\`; saat dijalankan ulang, deteksi langkah setengah jadi dan lanjutkan/ulangi dengan aman; bersihkan `.part` |
| File unduhan korup atau HTML dari Drive | Hash gagal → hapus, coba mirror lain |
| Semua mirror dan sumber resmi gagal | Pesan jelas, minta file manual di `cache\`, lanjut ke aplikasi lain |
| Windows Installer sibuk (kode 1618) atau butuh reboot (3010) | Tunggu dan coba ulang; tandai "butuh reboot" di ringkasan |
| Aplikasi sedang berjalan saat di-uninstall/ditimpa | Hentikan proses (berdasarkan path), baru lanjut |
| Port dipakai IIS/layanan lain | Pre-flight laporkan; tawarkan menghentikan dengan konfirmasi |
| Antivirus/SmartScreen memblokir installer | Deteksi kegagalan, catat, beri petunjuk pengecualian folder `cache\` |
| Jam sistem salah (error TLS/sertifikat) | Peringatkan, sarankan sinkronisasi waktu |
| Proxy kampus | Dukung pengaturan proxy di `data\local.json` |
| Disk penuh | Pre-flight tolak lanjut; jangan mulai uninstall bila ruang tidak cukup untuk instalasi baru |
| Path berspasi / karakter khusus | Selalu kutip path, uji di folder berspasi |
| Python alias Store / VS Code ganda | Deteksi dan tangani (6A.3) |
| Deep Freeze / Reboot Restore aktif | Peringatkan harus mode "thawed" |
| Pengguna memilih kombinasi tidak valid / salah input | Validasi di GUI (tombol nonaktif disertai alasan) atau pesan di CLI, tanpa crash |
| Update GitHub membawa kode rusak | Validasi paket, uji mandiri, rollback otomatis (6D) |
| Arsip rusak / ekstraksi gagal sebagian | Cek exit code ekstraktor + `isiDiharapkan`; hapus staging; unduh ulang dari mirror lain (6F) |
| Arsip multi-part kurang satu bagian | Tolak sebelum ekstraksi, tandai "menunggu sumber" (6B.4) |
| Arsip berpassword tanpa password | Ambil dari `data\local.json` atau input tersembunyi; pada `--unattended` gagal dengan pesan jelas |
| Path hasil ekstraksi terlalu panjang (MAX_PATH) | Staging di path pendek; laporkan bila tetap terlampaui |
| Entri arsip berpath berbahaya (`..`, absolut) | Tolak seluruh arsip (cegah zip-slip) |
| Folder `system\` tersembunyi membingungkan admin | Tombol "Buka folder" (F) membuka folder data; opsi `sembunyikanFolderSistem` dapat dimatikan |
| `apps.json`/`mirrors.json` salah sintaks (diedit di Notepad) | Pesan jelas (berkas, baris, kolom), memakai config terakhir yang valid, perintah Periksa konfigurasi (4.2 poin 7) |
| Runtime Python hilang atau rusak | `Start.bat` mendeteksi, `recover.ps1` memulihkan dari rilis (hash diverifikasi) atau memberi panduan manual (6D.9) |
| Jendela ditutup atau komputer mati saat instalasi | Pekerjaan di thread latar + jurnal transaksi; menutup jendela meminta konfirmasi dan berhenti rapi; jalan berikutnya melanjutkan atau mengulang dengan aman |

---

## 6F. Arsip (zip/rar/7z): Unduh → Ekstrak → Instal

Banyak aplikasi atau payload hanya tersedia sebagai arsip. Metode `arsip` menangani seluruh alurnya secara otomatis.

### 6F.1 Alur
1. **Unduh** semua bagian arsip lewat mekanisme sumber/mirror (6B) dan verifikasi SHA256 tiap bagian.
2. **Cek ruang disk** (pakai `ukuranEkstrak` di manifest bila ada; jika tidak, perkirakan 3x ukuran arsip).
3. **Ekstrak** ke staging `cache\extract\<id>-<versi>\` (path pendek).
4. **Validasi hasil:** exit code ekstraktor dan semua berkas di `isiDiharapkan` ada.
5. **Lanjutan** sesuai `lanjutan.tipe`: `installer` (jalankan setup di dalam arsip dengan argumen silent), `msi`, `salin` (aplikasi portabel: salin ke folder tujuan, buat shortcut/PATH bila perlu), atau `hook`.
6. **Verifikasi pasca-instal** (deteksi 6A). Jika sukses, bersihkan staging; arsip asli tetap di `cache\download\`.

### 6F.2 Alat ekstraksi (hindari masalah "ayam dan telur")
- `.zip`: ekstrak dengan modul `zipfile` bawaan Python, per entri (path tiap entri divalidasi sebelum menulis untuk mencegah zip-slip), bertahap agar progres dapat ditampilkan.
- `.7z`, `.rar`, `.iso`, arsip multi-part, dan lainnya: gunakan **7-Zip portabel yang dibawa program** di `system\tools\7z\` (`7z.exe` + `7z.dll` dari 7-Zip resmi, lengkap dengan hash). Agent wajib memeriksa paket/berkas 7-Zip mana yang benar-benar mendukung RAR dan mencatat versi + hash-nya di `docs\SOURCES.md`.
- Cadangan: 7-Zip atau WinRAR yang sudah terpasang di PC (`7z.exe x -y`, `UnRAR.exe`/`WinRAR.exe x -y -ibck`). Alat yang dipakai dicatat di log.
- Tidak ada ekstraktor yang bisa → pesan jelas, aplikasi ditandai gagal, aplikasi lain tetap lanjut.

### 6F.3 Keselamatan & ketahanan
- **Tolak arsip** yang berisi entri dengan path berbahaya (`..`, path absolut, tautan keluar dari staging), untuk mencegah zip-slip.
- **Multi-part** (`.part1.rar`, `.7z.001`, dll.): semua bagian wajib ada dan hash cocok sebelum mulai; kalau kurang → "menunggu sumber" (6B.4).
- **Arsip bersarang** (zip di dalam rar, dll.): didukung maksimal 3 tingkat.
- **Password:** tidak boleh ada di repo atau manifest. Manifest hanya berisi `passwordRef`; nilainya dibaca dari `data\local.json`, atau diminta lewat input tersembunyi; pada `--unattended` tanpa password → gagal dengan pesan jelas.
- **Kode keluar ekstraktor:** 0 sukses, 1 peringatan (periksa `isiDiharapkan` sebelum menganggap sukses), 2 ke atas gagal (agent verifikasi per alat).
- **Idempotent:** staging yang lengkap dan bertanda `.extracted-ok` (berisi hash arsip) dipakai ulang; yang tidak lengkap dihapus lalu diekstrak ulang. Staging sisa dari proses yang terputus dibersihkan lewat jurnal transaksi pada jalan berikutnya.
- Hapus penanda Mark of the Web (`Zone.Identifier`) pada hasil ekstraksi. Jangan menonaktifkan antivirus.
- **Lisensi:** WinRAR berlisensi (shareware). Admin lab bertanggung jawab atas lisensinya; tidak ada kunci lisensi di repo.

### 6F.4 Skema manifest untuk `metode: "arsip"`
```json
{
  "id": "contoh-aplikasi",
  "metode": "arsip",
  "arsip": {
    "format": "zip | rar | 7z",
    "bagian": ["contoh.part1.rar", "contoh.part2.rar"],
    "passwordRef": null,
    "ukuranEkstrak": 0,
    "isiDiharapkan": ["setup\\setup.exe"],
    "lanjutan": {
      "tipe": "installer | msi | salin | hook",
      "berkas": "setup\\setup.exe",
      "args": "/S",
      "tujuan": "C:\\Tools\\Contoh"
    }
  }
}
```
Payload custom Laragon (bagian 7) juga boleh berupa arsip di mirror Drive; ia mengikuti alur ini, lalu hasil ekstraksinya divalidasi seperti biasa.

### 6F.5 7-Zip dan WinRAR sebagai aplikasi untuk pengguna
Keduanya masuk daftar aplikasi menu dan mengikuti kebijakan versi biasa (6A). Memasang atau meng-uninstall keduanya **tidak boleh** mengganggu `system\tools\7z\`.

---

## 6G. PHP Standalone (`C:\php`), php.ini, dan Composer

### 6G.1 Pemasangan PHP
- **Lokasi default: `C:\php`** (tanpa spasi). Sumber: arsip zip PHP target (8.5.11, x64) lewat metode `arsip` (6F). Agent memeriksa varian yang tepat (Non-Thread-Safe untuk CLI/Composer; Thread-Safe dipakai web server Apache) dan mencatat pilihan serta alasannya di `docs\SOURCES.md`. Jika windows.php.net tidak terjangkau → alur "Butuh Hosting Manual" (6B.4).
- **Dependensi wajib: Microsoft Visual C++ Redistributable** yang cocok dengan build PHP (mis. build vs17 membutuhkan paket 2015-2022 x64). Tanpa ini PHP gagal dengan error `VCRUNTIME140.dll` / `MSVCP140.dll tidak ditemukan`. Agent menentukan versi persisnya dari halaman rilis PHP dan memasangnya **sebelum** PHP.
- **PATH sistem:** tambahkan `C:\php` (di depan entri lain yang berisi `php.exe`), lalu umumkan perubahan lingkungan (`WM_SETTINGCHANGE`) agar proses baru langsung mengenalinya. Entri PHP lain di PATH sistem hanya dihapus bila dikelola oleh program ini atau atas konfirmasi admin.

### 6G.2 `php.ini` (otomatis, tanpa error)
1. Buat `C:\php\php.ini` dari `php.ini-development` (default untuk lab; dapat diganti `production` di config).
2. Atur nilai dasar: `extension_dir = "C:\php\ext"` (path absolut), `date.timezone = "Asia/Jakarta"`, `memory_limit` (mis. 512M), `upload_max_filesize` dan `post_max_size` (mis. 64M), `max_execution_time` (mis. 120).
3. **CA bundle untuk HTTPS:** unduh `cacert.pem` (sumber resmi curl.se, atau mirror Drive bila tidak terjangkau; hash dicatat) ke `C:\php\extras\ssl\`, lalu isi `curl.cainfo` dan `openssl.cafile`. Tanpa ini Composer dan cURL sering gagal pada HTTPS.
4. **Aktifkan ekstensi** dengan menghapus tanda `;` **hanya** pada baris `extension=` yang tepat:
   - **Wajib:** `curl`, `fileinfo`, `gd`, `intl`, `mbstring`, `exif`, `mysqli`, `openssl`, `pdo_mysql`, `pdo_sqlite`, `sqlite3`, `zip`, `sodium`, `bcmath`.
   - **Disarankan:** `sockets`, `soap`, `xsl`, `gettext`, `ftp`, `gmp`, dan `zend_extension=opcache`.
   - Agent **memeriksa setiap ekstensi benar-benar ada** di folder `ext\` build yang dipakai (nama DLL dapat berbeda antar versi); ekstensi yang tidak tersedia tidak diaktifkan dan dicatat sebagai peringatan di laporan, bukan dibiarkan menjadi error diam-diam.
5. Edit dengan backup `.bak`, pola regex terjangkar, validasi sesudahnya, dan **idempotent** (dijalankan ulang tidak menggandakan baris).
6. **Kriteria "tanpa error":** `php -v` dan `php -m` tidak mengeluarkan satu pun peringatan di stderr (mis. "Unable to load dynamic library"); `php --ini` menunjukkan `C:\php\php.ini`; semua ekstensi wajib muncul di `php -m`.
7. **php.ini internal Laragon dan XAMPP** (setelah PHP-nya diganti/ditimpa) juga harus lolos kriteria yang sama, dan log error Apache tidak boleh berisi error "PHP Startup" saat start.

### 6G.3 Composer
- Dipasang **setelah** PHP. Pilih salah satu dan catat alasannya: (a) `Composer-Setup.exe` resmi dengan parameter senyap (diverifikasi) yang diarahkan ke `C:\php\php.exe`; atau (b) **`composer.phar` resmi** (verifikasi SHA256 dari situs resmi) + `composer.bat` di `C:\composer\` yang memanggil `C:\php\php.exe` secara eksplisit. **Rekomendasi: (b)**, karena deterministik dan tidak berubah bila PATH berubah.
- **Akses semua pengguna:** `COMPOSER_HOME` sistem = `C:\composer\home` (bukan profil admin), `C:\composer\home\vendor\bin` masuk PATH sistem, `COMPOSER_CACHE_DIR` = `C:\composer\cache` dengan hak tulis untuk `Users`. Dengan begitu `laravel` dan paket global terlihat oleh akun mahasiswa.
- **Laravel Installer:** `composer global require laravel/installer` memakai `COMPOSER_HOME` di atas.
- **Kriteria:** `composer -V` menampilkan Composer dan PHP 8.5.x; `composer diagnose` tanpa error; `composer check-platform-reqs` OK; tidak ada pesan "openssl extension is required", "curl", atau "zip"; `laravel --version` berhasil. Semuanya diuji sebagai **akun standar** (bukan admin), dan satu uji `composer require` paket kecil di folder sementara saat online (folder dihapus sesudahnya).

---

## 6H. Paket Flutter (Visual Studio C++, Android Studio, Android SDK, Flutter SDK)

**Tujuan:** admin memilih satu entri "Flutter Lab", semuanya terpasang, lisensi Android sudah diterima, dan `flutter doctor -v` hijau, **tanpa langkah manual**, termasuk di akun mahasiswa standar.

### 6H.1 Komponen dan urutan
1. **Git for Windows** (dibutuhkan Flutter) + `git config --system --add safe.directory` untuk folder Flutter, agar tidak muncul error kepemilikan folder ("dubious ownership") saat dijalankan akun lain (agent memverifikasi).
2. **VC++ Redistributable** bila belum ada.
3. **Visual Studio Community** (versi yang diterima `flutter doctor`; agent memverifikasi apakah 2022 atau yang terbaru) dengan beban kerja **Desktop development with C++** (`Microsoft.VisualStudio.Workload.NativeDesktop`) beserta komponen yang disyaratkan Flutter (toolchain MSVC, Windows SDK, CMake). Dipasang senyap lewat bootstrapper resmi (`--add ... --includeRecommended --quiet --norestart --wait`) atau berkas `.vsconfig`, dan dideteksi dengan `vswhere` (`-requires Microsoft.VisualStudio.Workload.NativeDesktop`). Ukurannya >10 GB, sehingga dibuat **layout offline** (`--layout`) sekali dan dibagikan lewat LAN; PC lain memasang dengan `--noWeb`. Estimasi unduhan 10 GB di 20 Mbps ±1,5 jam.
4. **Android Studio** (installer resmi, senyap; lewat mirror Drive bila lambat) dengan plugin **Flutter** dan **Dart** bila bisa dipasang untuk semua pengguna (agent meneliti mekanismenya).
5. **Android SDK di `C:\Android\Sdk`** (tanpa spasi): unduh `commandlinetools-win-*_latest.zip` (metode `arsip`), ekstrak ke `C:\Android\Sdk\cmdline-tools\latest\` (struktur ini wajib), lalu `sdkmanager` memasang `platform-tools`, `platforms;android-<API>`, `build-tools;<versi>`, dan `cmdline-tools;latest`. Versi/API dipilih agent sesuai persyaratan Flutter stable saat ini (diverifikasi, bukan ditebak). `emulator` dan system image **default tidak dipasang** (opsi `flutter.emulator` di config).
6. **Terima semua lisensi Android otomatis:** `sdkmanager --licenses` dengan jawaban `y` non-interaktif (dan/atau `flutter doctor --android-licenses`). Verifikasi berkas di `C:\Android\Sdk\licenses\` ada dan `flutter doctor` tidak lagi menyebut "Some Android licenses not accepted". Penerimaan lisensi dicatat di log (siapa dan kapan).
7. **Flutter SDK:** arsip zip stabil dari sumber resmi (besar; siapkan mirror Drive), diekstrak ke `C:\src\flutter` (tanpa spasi, bukan `Program Files`; agent memverifikasi lokasi yang disarankan dokumentasi), `C:\src\flutter\bin` ditambahkan ke PATH sistem.
8. **Konfigurasi:** `flutter config --android-sdk C:\Android\Sdk` (+ `--jdk-dir` bila perlu), variabel sistem `ANDROID_HOME` dan `ANDROID_SDK_ROOT`, `platform-tools` ke PATH, `flutter config --no-analytics`.
9. **Windows Developer Mode** diaktifkan (registri `AllowDevelopmentWithoutDevLicense`, diverifikasi agent) agar plugin Flutter di Windows (butuh symlink) tidak error.
10. **Pre-warm sekali sebagai admin:** `flutter precache` (android, windows), lalu membangun proyek contoh (`flutter create`, `flutter build apk --debug`, `flutter build windows`) dengan `GRADLE_USER_HOME` sistem = `C:\gradle-home`, supaya dependensi Gradle/pub terunduh **sekali**, bukan di tiap akun mahasiswa (hemat kuota 20 Mbps). Proyek contoh dihapus sesudahnya.
11. **Hak akun standar:** grup `Users` diberi Modify pada `C:\src\flutter\bin\cache`, `C:\gradle-home`, dan `C:\Android\Sdk` (agar Gradle/SDK bisa menulis), tidak lebih dari itu.
12. **Android Studio tanpa wizard:** wizard pertama (unduh SDK) tidak boleh muncul di akun mahasiswa; SDK sudah mengarah ke `C:\Android\Sdk`. Agent meneliti mekanisme resminya (mis. `disable.android.first.run` di `idea.properties`) dan membuktikannya dengan profil pengguna standar yang baru.

### 6H.2 Kriteria lulus
- `flutter doctor -v` sebagai **akun standar**: tanda ✓ untuk Flutter, Windows Version, Android toolchain (lisensi diterima), Visual Studio (Desktop development with C++), Android Studio, dan VS Code bila terpasang; "Connected device" menampilkan minimal Windows (+ Chrome/Edge). **Tidak ada `[✗]`**, dan setiap `[!]` yang tersisa dijelaskan di laporan (mis. tidak ada emulator/perangkat fisik).
- `flutter create demo` lalu `flutter run -d windows` (build sukses, jendela terbuka, ditutup otomatis oleh uji) dan `flutter build apk --debug` sukses di akun standar.
- Android Studio terbuka tanpa wizard dan mengenali SDK serta plugin Flutter.
- Seluruh paket dapat dipilih dari satu entri menu "Flutter Lab", dan idempotent (jalankan ulang = lewati yang sudah sesuai).

### 6H.3 Catatan
- **Ukuran sangat besar:** perkiraan VS C++ 10 sampai 20 GB, Android Studio + SDK 5 sampai 10 GB, Flutter 2 sampai 3 GB, ditambah cache Gradle beberapa GB. Pre-flight menolak bila ruang disk kurang (agent menghitung dari manifest; perkirakan ≥ 50 GB bebas) dan menampilkan estimasi waktu unduh di 20 Mbps. Manfaatkan cache LAN, layout offline VS, dan mirror Drive.
- **Emulator Android** membutuhkan virtualisasi (Hyper-V/Windows Hypervisor Platform) sehingga default tidak dipasang; alternatif uji: perangkat fisik (USB debugging), Windows desktop, atau Chrome.
- **Lisensi Visual Studio Community** memiliki syarat penggunaan (penggunaan pendidikan diperbolehkan dalam kondisi tertentu) dan dapat meminta login akun setelah masa awal. Agent memverifikasi perilakunya dan melaporkannya; keputusan lisensi ada pada admin lab. Alternatif bila login bermasalah: Build Tools for Visual Studio, **jika** `flutter doctor` menerimanya (diverifikasi agent).
- Persetujuan lisensi Android SDK dilakukan atas nama admin lab dan dicatat di log.

---

## 7. Kasus Khusus: Laragon 6 + Custom Bin

### 7.1 Alur
1. **Instal Laragon versi 6** dari rilis resmi GitHub (agent verifikasi URL aset rilis dan hash; pilih varian installer yang sesuai, mis. full/wamp). Gunakan argumen silent Inno Setup (umumnya `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\laragon"`; **verifikasi dulu**). Folder tujuan tetap `C:\laragon` (tanpa spasi).
2. Pastikan Laragon **tidak sedang berjalan** (hentikan `laragon.exe`, `httpd.exe`, `nginx.exe`, `mysqld.exe`, `php*.exe` milik Laragon; cek berdasarkan path agar tidak menghentikan proses XAMPP).
3. **Validasi payload** sebelum menyentuh apa pun: `payload\laragon-custom-bin\` ada, hash cocok dengan `manifest.sha256`, struktur folder sesuai yang diharapkan (mis. `bin\php\php-8.x...`, `bin\apache\...`, `bin\mysql\...`). Jika tidak valid → **batalkan penimpaan, tinggalkan Laragon standar apa adanya**, laporkan. Payload boleh berupa arsip yang diunduh dari mirror Drive; ikuti alur 6F lalu validasi hasil ekstraksinya.
4. **Backup** folder `bin` yang akan ditimpa ke `backup\laragon-bin-<timestamp>\`.
5. **Terapkan penimpaan secara aman**: salin ke folder staging dulu (`robocopy` dengan `/E` dan cek exit code robocopy; kode 0-7 = sukses, ≥8 = gagal), lalu pindahkan/timpa. Jika gagal di tengah jalan → **rollback otomatis** dari backup.
6. **Sesuaikan konfigurasi** yang bergantung pada nama folder versi (mis. versi PHP aktif di `laragon.ini`, konfigurasi `etc\apache2\mod_php*.conf`, `my.ini`). Agent wajib menelusuri file mana yang merujuk ke versi lama setelah penimpaan dan memperbaikinya, bukan berasumsi. Termasuk memastikan `php.ini` Laragon memuat ekstensi penting dengan `extension_dir` yang benar dan lolos kriteria bersih di 6G.2.
7. **Verifikasi**: jalankan `php -v`, `httpd -t` (cek sintaks konfigurasi Apache), `mysqld --version` dari path Laragon; semua harus sukses. Catat versi hasil.
8. **Catatan data MySQL/MariaDB**: jika versi database custom berbeda mayor dari bawaan, direktori data lama bisa tidak kompatibel. Lakukan penimpaan **sebelum Laragon pertama kali dijalankan** (data belum terinisialisasi) atau inisialisasi ulang data; agent harus menangani dan mendokumentasikan alurnya.
9. Terapkan pengaturan port dari bagian 8.

### 7.2 Kriteria
Penimpaan bersifat **atomik secara logis**: hasil akhirnya hanya "Laragon custom lengkap dan terverifikasi" atau "Laragon standar utuh seperti semula"; tidak boleh ada kondisi setengah-setengah.

---

## 8. Anti-Bentrok Laragon vs XAMPP

Masalah: keduanya default memakai Apache port 80/443 dan MySQL 3306, sehingga salah satu gagal start dan tombol "Admin"/"Web" membuka localhost yang sama.

### 8.1 Pemetaan port (`ports.json`, dapat diubah admin)

| Layanan | Laragon | XAMPP |
|---|---|---|
| Apache HTTP | **80** | **8080** |
| Apache HTTPS | **443** | **8443** |
| MySQL/MariaDB | **3306** | **3307** |

### 8.2 Perubahan konfigurasi XAMPP (otomatis, setelah instal)
- `C:\xampp\apache\conf\httpd.conf`: `Listen 8080` dan `ServerName localhost:8080`.
- `C:\xampp\apache\conf\extra\httpd-ssl.conf`: `Listen 8443`, `<VirtualHost _default_:8443>`, `ServerName localhost:8443`.
- `C:\xampp\mysql\bin\my.ini`: `port=3307` di blok `[client]` **dan** `[mysqld]`.
- `C:\xampp\phpMyAdmin\config.inc.php`: set port server ke `3307` (`$cfg['Servers'][$i]['port']`) dan host `127.0.0.1`.
- `C:\xampp\xampp-control.ini`: pastikan port yang tercatat sama agar tombol **Admin** di XAMPP Control Panel membuka `http://localhost:8080/...` (phpMyAdmin) dan bukan port 80. **Agent wajib menguji perilaku tombol ini secara nyata**; jika Control Panel tidak mengikuti config, sediakan solusi cadangan (mis. shortcut desktop "XAMPP Admin" → `http://localhost:8080/phpmyadmin` dan penjelasan di log).
- Lakukan edit dengan **backup `.bak` dulu**, ganti nilai dengan pola yang spesifik (regex terjangkar), dan **validasi hasil** (`httpd -t` pada Apache XAMPP).

### 8.3 Laragon
- Tetap di port 80/443/3306 (default). Tombol **Web** membuka `http://localhost` → situs Laragon.
- Pastikan Laragon Auto Virtual Host (`*.test`) tidak bentrok: XAMPP tidak memakai nama host itu.
- Edit file `hosts` hanya lewat `core\hosts.py`: backup dulu, tambah entri bertanda komentar `# LabInstaller`, tidak menduplikasi entri.

### 8.4 Hal lain agar tidak bentrok
- **Jangan install Apache/MySQL sebagai Windows Service** untuk keduanya (jalankan lewat panel masing-masing).
- Cek dan laporkan jika port 80/443 dipakai IIS, World Wide Web Publishing Service, Skype, VMware, dll. Tawarkan menghentikan layanan IIS/W3SVC hanya dengan konfirmasi admin.
- **Aturan Windows Firewall** (`netsh advfirewall`/`New-NetFirewallRule`) untuk `httpd.exe` dan `mysqld.exe` masing-masing path agar tidak muncul popup saat mahasiswa menjalankan.
- **Kebijakan PATH PHP/Composer** (WAJIB diputuskan dan didokumentasikan): hanya **satu** PHP yang ada di PATH sistem, yaitu **PHP standalone di `C:\php`** (6G), yang dipakai CLI, Composer, dan Laravel. PHP milik Laragon (custom bin) dan PHP milik XAMPP adalah komponen internal web server masing-masing dan **tidak** ditambahkan ke PATH sistem. Ketiganya sebaiknya satu versi (target 8.5.11); selisih versi dilaporkan sebagai peringatan oleh menu verifikasi. Jika kebijakan ini tidak dipenuhi, `php -v` bisa menampilkan versi yang berbeda dari yang dipakai web server. Karena Laragon dapat menambah/mengubah PATH sendiri dan nama folder PHP memuat nomor versi, agent harus **menguji nyata** bagaimana PATH terbentuk setelah Laragon dijalankan dan setelah PHP diganti, lalu menetapkan satu mekanisme yang konsisten (mis. PATH mesin menunjuk ke folder PHP target, atau pengaturan PATH bawaan Laragon dinonaktifkan bila bentrok) dan menuliskannya di `README.md`.
- XAMPP dipasang di `C:\xampp`, Laragon di `C:\laragon` (hindari `Program Files` karena masalah izin).

### 8.5 Uji penerimaan khusus bagian ini
1. Start Apache + MySQL Laragon **dan** Apache + MySQL XAMPP bersamaan → keempatnya hijau tanpa error.
2. Tombol **Web** Laragon → `http://localhost` menampilkan halaman Laragon.
3. Tombol **Admin** XAMPP → `http://localhost:8080/phpmyadmin` (atau dashboard XAMPP di 8080), **bukan** halaman Laragon.
4. phpMyAdmin XAMPP berhasil login ke MySQL port 3307; aplikasi Laragon terhubung ke 3306.
5. Setelah reboot, semuanya tetap berfungsi.
6. **Uji tombol, dalam tiga kondisi:** (a) hanya Laragon dijalankan, (b) hanya XAMPP dijalankan, (c) keduanya dijalankan. Pada ketiga kondisi, **setiap tombol di tabel 8.6 membuka halaman yang benar dan tidak pernah menampilkan "Unable to reach" / "This site can't be reached"**.
7. Menghentikan satu tumpukan (Laragon atau XAMPP) tidak mengganggu yang lain; menjalankannya kembali tidak menimbulkan error port.
8. Alamat diuji dengan `localhost`, `127.0.0.1`, dan `[::1]`; bila `localhost` hanya terpetakan ke IPv6 sedangkan Apache hanya mendengarkan IPv4 (atau sebaliknya), samakan agar tidak ada alamat yang gagal.
9. Uji klik tombol sungguhan di Windows (otomatisasi UI bila memungkinkan; jika tidak, langkah manual di `TEST-PLAN.md` beserta tangkapan layar sebagai bukti). Uji HTTP otomatis saja **tidak cukup**.

### 8.6 Tombol, Alamat, dan Halaman Penanda

| Tombol | Alamat yang harus terbuka | Bukti yang harus tampil |
|---|---|---|
| Laragon: **Web** | `http://localhost` | Halaman penanda Laragon (port 80) |
| Laragon: **Database** | Alat database bawaan tombol itu terbuka (agent memverifikasi alat apa yang dipakai Laragon 6, mis. HeidiSQL) dengan sesi sudah mengarah ke `127.0.0.1:3306` | Koneksi berhasil, tanpa error "can't connect" |
| XAMPP: **Admin** (Apache) | `http://localhost:8080/` | Dashboard XAMPP / halaman penanda XAMPP (port 8080) |
| XAMPP: **Admin** (MySQL) | `http://localhost:8080/phpmyadmin` | phpMyAdmin tampil dan berhasil terhubung ke `127.0.0.1:3307` |

Aturan pendukung:
- **Halaman penanda `lab-check.php`** dipasang di `C:\laragon\www\` dan `C:\xampp\htdocs\` (tidak menimpa `index` milik pengguna). Isinya: nama tumpukan (LARAGON/XAMPP), versi PHP, port server (`$_SERVER['SERVER_PORT']`), hasil `SELECT 1` ke MySQL pada port masing-masing (3306 atau 3307), dan daftar ekstensi penting. Halaman hanya menjawab permintaan dari `127.0.0.1`/`::1`, dan kredensial uji dibaca dari `data\local.json` (default `root` tanpa password pada instalasi baru).
- **Uji otomatis** (`core\verify.py`): menjalankan Apache + MySQL tiap tumpukan secara senyap (`httpd.exe`/`mysqld.exe` dengan konfigurasi masing-masing), meminta `lab-check.php` dengan batas waktu, lalu menghentikan **hanya proses yang dimulai oleh uji**. Lulus bila: Laragon menjawab di port 80 dengan penanda LARAGON dan DB 3306 OK; XAMPP menjawab di 8080 dengan penanda XAMPP dan DB 3307 OK; dan alamat `http://localhost` **tidak** pernah dijawab oleh XAMPP.
- Penyebab "Unable to reach" yang harus dicegah: port tidak sesuai konfigurasi, Apache gagal start karena port bentrok, Windows Firewall memblokir, `localhost` terpetakan ke alamat yang tidak didengarkan, dan konfigurasi Apache yang salah sintaks (`httpd -t` wajib lulus).
- Perilaku nyata tombol XAMPP Control Panel dan Laragon (alamat yang dibuka) wajib dikonfirmasi agent di Windows; bila tombol tidak mengikuti konfigurasi port, sediakan penyesuaian atau shortcut pengganti dan dokumentasikan di `README.md`.

---

## 9. Persyaratan Instalasi XAMPP

- Gunakan installer resmi (BitRock). Mode senyap umumnya `--mode unattended --unattendedmodeui none --prefix C:\xampp` (**verifikasi parameter**; jika versi tidak mendukung, laporkan dan cari alternatif).
- Pilih hanya komponen yang dibutuhkan (Apache, MySQL, PHP, phpMyAdmin) bila opsi tersedia, dan ceritakan pilihan itu di manifest.
- Hook pasca-instal menjalankan penyesuaian bagian 8.2, memasang halaman penanda (8.6), dan menyesuaikan `php.ini` XAMPP sesuai 6G.2 bila PHP-nya diganti.

---

## 10. Persyaratan Non-Fungsional

- **Kecepatan:** repositori offline/cache dipakai bersama; ukuran unduhan ditampilkan sebelum mulai; estimasi waktu berdasarkan 20 Mbps.
- **Keamanan:** hanya HTTPS dan hanya dua jenis sumber: sumber resmi vendor atau mirror Google Drive milik admin yang **wajib diverifikasi SHA256**; tidak ada kredensial di repo (kredensial opsional seperti proxy, password arsip, atau token hanya di `data\local.json` yang lokal dan tidak masuk Git); tidak menjalankan skrip dari sumber tak dikenal. Karena hash di GitHub menentukan kepercayaan, akun GitHub pemilik repo wajib memakai 2FA dan cabang `main` dilindungi (merge hanya lewat PR + CI lulus).
- **Keterbacaan kode:** fungsi kecil, type hints penuh, komentar singkat berbahasa Indonesia, nama fungsi/variabel konsisten, gaya diseragamkan oleh `ruff format`.
- **Portabilitas:** bisa dijalankan dari lokasi mana pun (path diturunkan dari lokasi `Start.bat`, bukan hardcode), tetapi **disarankan disalin ke disk lokal** (`C:\LabInstaller`) karena auto-update menulis ke folder program; shared folder dipakai hanya untuk cache/payload bersama (6D.3).
- **Pembaruan:** menambah aplikasi atau menaikkan versi target cukup mengubah `apps.json`; program sendiri ikut diperbarui otomatis dari GitHub (6D).
- **Antarmuka:** GUI (5.1) adalah antarmuka utama dan inti produk; mode CLI tersedia untuk otomasi dan sesi remote. Mesin (`core\`) tidak berisi kode tampilan sehingga keduanya memakai logika yang sama.

### 10.1 Parameter & Exit Code
Argumen baris perintah (GUI memakai fungsi mesin yang sama):

| Parameter | Fungsi |
|---|---|
| `--cli` | Paksa mode tanpa jendela (GUI tidak dibuka) |
| `--dry-run` | Tampilkan rencana tanpa mengubah sistem |
| `--apps <id,id>` / `--profile <nama>` | Pilih aplikasi/paket tanpa memilih di GUI (otomatis mode CLI) |
| `--unattended` | Non-interaktif: tanpa prompt (konfirmasi uninstall dilewati, **backup data tetap jalan**) |
| `--force` | Instal ulang walau sudah sesuai |
| `--verify` | Jalankan verifikasi (6C) lalu keluar |
| `--check-config` | Validasi semua config dengan pesan jelas lalu keluar |
| `--no-update` / `--force-update` | Lewati / paksa cek update (6D) |
| `--selftest` | Uji mandiri: impor semua modul, validasi config, cek runtime/Tk/7-Zip, tanpa mengubah sistem |
| `--selftest-gui` | Uji tampilan (dipakai CI): buka jendela, render semua tampilan, tutup |
| `--version` | Cetak versi program lalu keluar |
| `--publish-to-share` | Salin file unduhan terverifikasi ke shared folder LAN |
| `--clean-cache` | Bersihkan installer versi usang dari `cache\` |

Exit code: `0` semua sukses/sesuai · `1` sebagian gagal · `2` pre-flight gagal · `3` sukses tetapi butuh reboot · `4` config/manifest tidak valid · `5` dibatalkan pengguna · `6` kesalahan internal tak terduga (sudah dicatat di log) · `10` internal: runtime perlu ditukar (ditangani `Start.bat`, bukan kesalahan).

### 10.2 Retensi
Simpan 5 backup terakhir atau maksimal 30 hari (mana yang lebih sedikit; backup data pengguna tidak dihapus otomatis tanpa konfirmasi), log 60 hari. `cache\` tidak dihapus otomatis kecuali lewat opsi `--clean-cache` (installer versi usang). Penulisan ke shared folder memakai file lock dan rename atomik agar dua PC tidak merusak file yang sama.

---

## 11. Milestone & Deliverables

| M | Isi | Bukti selesai |
|---|---|---|
| M0 | **Riset & verifikasi sumber**: tiap aplikasi, ID winget, URL resmi, versi terbaru, parameter silent, kemampuan `--scope machine`, ukuran/hash; catat di `docs\SOURCES.md`; tentukan daftar "Butuh Hosting Manual" | `SOURCES.md` lengkap, tiap parameter diberi status "terverifikasi" atau "belum terverifikasi + alasan"; daftar hosting manual diserahkan ke admin **di awal** |
| M1 | **Kerangka & pengaman**: runtime Python portabel (Tkinter berfungsi), `Start.bat`, bootstrap, **GUI shell** (daftar aplikasi, progres, log; prototipe memilih pustaka GUI), CLI, config + validasi skema (+ config terakhir yang valid), logger, pre-flight, mode `--dry-run`, dan **CI gerbang kualitas penuh (4.2) sudah hijau sejak awal** | GUI tampil benar (tangkapan layar di 100/125/150%), `--dry-run` menampilkan rencana, log terbentuk, CI hijau termasuk uji paket rilis di Windows bersih; struktur folder sesuai bagian 3 (root hanya `Start.bat`, path dihitung dari lokasi `Start.bat`) |
| M2 | Instal aplikasi biasa via winget (VS Code, NetBeans, QGIS, Node, Python, Git) + deteksi + verifikasi | Semua terinstal di lingkungan bersih; jalankan ulang = dilewati |
| M3 | Modul unduh (resume, retry, hash, cache) + metode `exe` + **metode `arsip` (6F)**: zip dan rar/7z, multi-part, password, staging | Simulasi putus koneksi lalu lanjut berhasil; arsip rar berhasil diekstrak di PC tanpa 7-Zip/WinRAR; arsip rusak atau multi-part kurang ditolak dengan pesan jelas; entri `..` ditolak |
| M4 | Laragon 6 + penimpaan custom bin + backup/rollback | Uji sukses dan uji gagal-sengaja (payload rusak) berakhir aman |
| M5 | XAMPP + penyesuaian port + hook + halaman penanda | Semua uji 8.5 dan 8.6 lulus, termasuk uji klik tombol pada tiga kondisi (hanya Laragon, hanya XAMPP, keduanya) tanpa "Unable to reach" |
| M6 | PHP standalone `C:\php` + VC++ Redistributable + php.ini otomatis + Composer + Laravel installer + kebijakan PATH (6G) | `php -v` dan `php -m` tanpa peringatan, semua ekstensi wajib aktif, `composer -V`, `composer diagnose`, dan `laravel --version` berhasil sebagai akun standar |
| M3b | Sumber & mirror (6B): failover Google Drive 4 mirror, deteksi HTML/kuota, cooldown, resume | Uji: matikan mirror 1-3 secara sengaja, unduhan tetap berhasil dari mirror 4; hash salah ditolak; sumber resmi yang sengaja diputus menghasilkan pesan jelas + `butuh-hosting-*.txt/.csv` dan menu `H`, tanpa menghentikan aplikasi lain |
| M6b | Kebijakan versi + uninstall bersih + backup data (6A) | Uji: pasang versi lain lalu program menggantinya; data `htdocs`/MySQL ter-backup; PHP 8.5.11 jadi satu-satunya PHP aktif |
| M6c | Visual Studio Community + Paket Flutter (6H): Android Studio, Android SDK, lisensi otomatis, Flutter SDK, pre-warm, ACL | `flutter doctor -v` tanpa `[✗]` sebagai akun standar; build Windows dan APK debug sukses; Android Studio tanpa wizard |
| M7 | Tampilan verifikasi (6C) + profil/paket + ringkasan akhir (GUI dan CLI) | Tabel status benar untuk kondisi OK, versi beda, dan rusak; laporan `.txt/.csv` terbentuk |
| M8 | Auto-update GitHub (6D): bootstrap, validasi, rollback, kill switch, pemisahan runtime + pemulihan (6D.9), GitHub Actions | Uji: rilis dummy v+1 terpasang otomatis; rilis rusak ditolak/di-rollback; offline tidak memblokir; nomor versi dan status (terbaru / tersedia / offline) tampil benar di banner, log, dan laporan verifikasi; CI gagal bila `VERSION` tidak sinkron dengan `version.json`/tag; update kode tidak mengunduh ulang runtime; runtime yang sengaja dirusak dipulihkan otomatis oleh `recover.ps1` |
| M9 | Pengujian kasus tak terduga (6E), dokumentasi `README.md` untuk admin, laporan pengujian | Laporan uji + panduan pemakaian |
| M10 | **Poles dan uji kegunaan antarmuka**: Windows 10 dan 11, skala 100/125/150/200%, tema terang/gelap, layar kecil (1366x768), daftar periksa uji oleh admin, tangkapan layar di `docs\` | Tidak ada teks terpotong atau buram, jendela tidak pernah membeku, semua teks Indonesia konsisten, tidak ada traceback mentah |

**Urutan pengerjaan:** M0 → M1 → M2 → M3 → M3b → M4 → M5 → M6 → M6b → M6c → M7 → M8 → M9 → M10. Kode M3b, M6b, dan M6c sengaja disisipkan agar nomor milestone lain tidak berubah.

Deliverable akhir: folder `LabInstaller\` lengkap di repo GitHub (CI hijau, rilis pertama `v1.0.0` berisi paket `LabInstaller-full`, `app`, dan `runtime`), `README.md` (cara pakai, cara menambah aplikasi, cara memperbarui payload, kebijakan PATH, cara mengatasi masalah umum), `docs\SOURCES.md`, `docs\TEST-REPORT.md` (apa yang diuji, di OS apa, hasil, yang belum teruji), dan `docs\TEST-PLAN.md` bila ada bagian yang belum bisa diuji agent.

---

## 12. Informasi yang Dibutuhkan dari Admin (belum diketahui)

Agent **jangan lanjut menebak**; minta atau beri placeholder untuk:
1. Versi Windows di lab (10/11, edisi) dan apakah winget tersedia di semua PC.
2. Isi payload custom: folder `bin` mana saja yang ditimpa (php, apache, mysql/mariadb, nginx, dll.) dan versi persisnya.
3. Apakah database custom berbeda mayor dari bawaan Laragon 6.
4. Daftar akhir aplikasi dan versi yang diinginkan (mis. versi PHP XAMPP, versi Python).
5. Lokasi distribusi: flashdisk, shared folder, atau server lokal; apakah PC lab punya akses ke sana.
6. Apakah ada Deep Freeze/Reboot Restore yang aktif (instalasi harus dilakukan dalam mode "thawed").
7. Apakah komputer dibersihkan/di-clone dari satu PC master (jika ya, pertimbangkan membuat image setelah satu PC sukses).
8. **Mirror Google Drive:** daftar aplikasi yang memakainya, 4 `fileId` per aplikasi, nama file, ukuran, dan SHA256 masing-masing (hash bisa dihitung dengan tombol **Hitung hash** di aplikasi atau `Get-FileHash`).
9. **GitHub:** repo sudah ditetapkan, yaitu `https://github.com/MuslimGunawan/LABInstaller` (akun `MuslimGunawan`, repo `LABInstaller`, kosong saat PRD ini ditulis). Yang masih perlu dikonfirmasi admin: publik atau privat (disarankan publik, lihat 6D.4) dan siapa yang berwenang merge ke `main`.
10. **Versi target tiap aplikasi** (PHP 8.5.11 sudah ditetapkan; yang lain pinned atau `latest-resolved`?).
11. Apakah data di `htdocs`/`www`/database lab boleh di-backup otomatis ke disk lokal sebelum uninstall, dan berapa lama backup disimpan.
12. Apakah proxy kampus dipakai di jaringan lab.
13. Apakah mahasiswa memakai akun **Administrator atau akun standar** (menentukan hak tulis di 6.5 dan scope instalasi).
14. Di mana agent bisa menguji: apakah ada Windows (VM/Sandbox/PC) yang dapat dipakai, atau pengujian harus dilakukan manual oleh admin lewat `TEST-PLAN.md`.
15. Lokasi folder `payload\` dan shared folder LAN (path/UNC) bila ada.
16. Apakah ada arsip berpassword atau multi-part, dan format apa saja yang akan dipakai (zip/rar/7z). Password **tidak boleh** ditaruh di repo; berikan lewat `data\local.json`.
17. **Visual Studio:** versi yang diinginkan (2022 atau yang terbaru yang diterima Flutter), dan bagaimana urusan login/lisensi Community di lab (akun Microsoft, akun sekolah, atau lainnya).
18. **Flutter/Android:** apakah emulator Android diperlukan (butuh virtualisasi di BIOS dan Hyper-V) atau cukup perangkat fisik, Windows desktop, dan Chrome; API level Android yang diinginkan (atau ikuti persyaratan Flutter stable).
19. **Ruang disk** yang tersedia di PC lab (paket Flutter + Visual Studio butuh ±50 GB atau lebih), dan apakah ada PC yang disk-nya kecil.
20. Apakah ekstensi PHP tambahan di luar daftar 6G.2 dibutuhkan, dan apakah `php.ini` lab memakai profil `development` atau `production`.
21. Apakah VS Code perlu ekstensi tertentu (mis. Dart/Flutter, PHP) terpasang untuk semua pengguna.
22. Nama lab, logo, dan warna untuk header aplikasi (opsional; default netral).
23. Resolusi dan skala layar terkecil di PC lab (mis. 1366x768 @125%) serta build Windows 10 yang dipakai (menentukan tata letak GUI dan versi Python yang dipatok).

> Pertanyaan yang belum terjawab **tidak boleh menghentikan pekerjaan**: pakai placeholder atau asumsi paling aman, catat di laporan milestone (bagian 14) sebagai "asumsi yang diambil", lalu lanjut.

---

## 13. Risiko & Mitigasi

| Risiko | Mitigasi |
|---|---|
| Internet 20 Mbps lambat/putus | Cache bersama, BITS resume, retry, hash |
| Installer mengubah parameter silent antar versi | Parameter di manifest + verifikasi pasca-instal + DryRun |
| Penimpaan bin gagal di tengah | Backup + staging + rollback otomatis |
| Port bentrok / IIS memakai port 80 | Pre-flight cek port + konfirmasi admin |
| ID winget berubah/hilang | Verifikasi di milestone; fallback unduh langsung |
| Kode Python salah sintaks/tipe atau modul hilang di PC lab | Gerbang kualitas 4.2 (ruff, mypy, compileall, pytest, GUI smoke) + uji paket rilis nyata di Windows bersih sebelum rilis; uji mandiri + rollback di PC |
| PC lab punya Deep Freeze | Wajib dicek di pre-flight/README |
| Push GitHub yang rusak menyebar ke seluruh lab | CI wajib lulus, uji mandiri, rollback otomatis, kill switch di `version.json` |
| Kuota Google Drive habis saat banyak PC mengunduh | 4 mirror, urutan acak, cooldown, cache LAN bersama |
| Uninstall menghapus data mahasiswa/dosen | Backup otomatis `backupData` + konfirmasi + whitelist pembersihan |
| Rate limit GitHub API (satu IP publik untuk seluruh lab) | Pakai URL rilis/raw, bukan API; cek berkala 24 jam |
| Downgrade tak sengaja karena kebijakan `exact` | Dicatat jelas di konfirmasi/log; `minimum` per aplikasi bila perlu |
| Agent tidak dapat menguji di Windows nyata | `TEST-PLAN.md` untuk pengujian manual admin; bagian terkait ditandai "BELUM TERUJI", jangan dirilis ke seluruh lab sebelum diuji di satu PC (saluran `beta`) |
| Runtime Python hilang/rusak atau terlalu besar diunduh | Runtime berversi terpisah, `recover.ps1` memulihkan dengan hash terverifikasi (6D.9) |
| GUI membeku atau buram di layar DPI tinggi | Thread latar, DPI-aware, uji 100 sampai 200% (5.1, M10) |
| Config JSON diedit admin dan salah sintaks | Validasi skema, config terakhir yang valid, perintah Periksa konfigurasi (4.2 poin 7) |
| Dependensi pihak ketiga berubah atau rusak | Pin versi + hash, dibundel di runtime, tanpa `pip install` di PC lab (4.1) |
| Antivirus/SmartScreen menandai `Start.bat` atau berkas hasil unduhan | Interpreter resmi bertanda tangan, penanda Mark of the Web dihapus, petunjuk pengecualian folder (4.3, 6E) |
| Paket winget terpasang per-pengguna sehingga tidak terlihat akun mahasiswa | `--scope machine` bila didukung (6.4), diverifikasi di menu verifikasi |
| Unduhan sangat besar (Visual Studio, Android, Flutter) di 20 Mbps | Layout offline Visual Studio, mirror Drive, cache LAN, estimasi waktu, pre-flight ruang disk (6H) |
| Akun mahasiswa tidak bisa menjalankan Flutter/Composer/Gradle (izin, profil per-pengguna) | Variabel dan PATH sistem, `COMPOSER_HOME` dan `GRADLE_USER_HOME` bersama, ACL terbatas, uji sebagai akun standar (6G, 6H) |
| `php.ini` salah sehingga muncul peringatan/error saat PHP dimulai | Aktifkan hanya ekstensi yang ada di `ext\`, kriteria `php -v` bersih, berlaku untuk ketiga PHP (6G.2) |
| Visual Studio Community meminta login/lisensi | Agent memverifikasi perilaku, admin memutuskan; fallback Build Tools bila diterima Flutter (6H.3) |
| Tombol XAMPP/Laragon menuju alamat salah atau "Unable to reach" | Halaman penanda `lab-check.php`, uji HTTP otomatis tiga kondisi, uji klik nyata (8.5, 8.6) |

---

## 14. Definisi Selesai & Format Laporan Agent

### 14.1 Definisi Selesai (semua harus terpenuhi)
1. Semua fitur pada bagian 5 sampai 9 (termasuk 6A sampai 6F) berfungsi, dan semua uji penerimaan di 8.5 serta kolom "Bukti selesai" milestone **lulus** di Windows bersih.
2. Skenario 6E diuji satu per satu; tidak ada error tak tertangani (tidak ada stack trace mentah ke layar).
3. Menjalankan program dua kali berturut-turut tidak mengubah apa pun pada kedua kalinya (idempotent).
4. Pengujian di PC yang **sebelumnya** sudah memiliki XAMPP/Laragon/PHP versi lain terpasang: program mengganti dengan benar dan data ter-backup.
5. Seluruh gerbang kualitas 4.2 lulus di CI (ruff, mypy, compileall, pytest, uji GUI, uji paket rilis di Windows bersih); JSON valid sesuai skema; tidak ada rahasia di repo.
6. Repo GitHub: CI hijau, rilis `v1.0.0` terbit, auto-update teruji end-to-end (rilis dummy diterima, rilis rusak ditolak).
7. `README.md`, `docs\SOURCES.md`, `docs\TEST-REPORT.md` selesai; bagian yang belum teruji ditulis jujur sebagai "BELUM TERUJI".
8. Daftar "Butuh Hosting Manual" sudah diserahkan ke admin dan ditindaklanjuti (atau tercatat sebagai tertunda).
9. **Struktur folder sesuai bagian 3:** di root `LabInstaller\` hanya ada `Start.bat` (folder `system\` tersembunyi), auto-update tidak pernah menyentuh `system\data\`, `system\boot\`, maupun `Start.bat`, dan seluruh folder tetap berfungsi setelah dipindah ke lokasi lain.
10. Alur arsip (6F) lulus untuk zip, rar, dan 7z di PC tanpa 7-Zip/WinRAR terpasang.
11. **Tombol Laragon dan XAMPP** (8.6) membuka alamat yang benar pada tiga kondisi (hanya Laragon, hanya XAMPP, keduanya), tanpa "Unable to reach", dibuktikan dengan uji klik nyata.
12. **PHP dan Composer** (6G): `php -v`/`php -m` bersih dari peringatan, ekstensi wajib aktif, `composer diagnose` tanpa error, dan semuanya berfungsi di akun standar; php.ini Laragon dan XAMPP juga bersih.
13. **Paket Flutter** (6H): `flutter doctor -v` tanpa `[✗]` di akun standar, lisensi Android sudah diterima, build Windows dan APK debug sukses, Android Studio tanpa wizard.
14. **GUI (5.1)**: tampil rapi dan tajam di skala 100/125/150/200%, tema terang dan gelap, tidak pernah membeku, semua teks Bahasa Indonesia konsisten, tidak ada jendela hitam atau traceback mentah ke pengguna.
15. **Runtime dan pemulihan (6D.9)**: update kode tidak mengunduh ulang runtime; runtime yang sengaja dirusak dipulihkan otomatis; program berjalan tanpa Python/pip/internet tambahan di PC bersih.
16. **Config salah sintaks** (mis. `apps.json` diedit di Notepad) tidak membuat program crash: pesan jelas dan memakai config terakhir yang valid.

### 14.2 Format laporan tiap milestone (singkat)
1. **Selesai:** apa yang dikerjakan.
2. **Hasil uji:** lulus / gagal / BELUM TERUJI, dengan bukti (cuplikan log pendek).
3. **Butuh Hosting Manual:** daftar sesuai 6B.4 (kosong bila tidak ada).
4. **Asumsi & keputusan** yang diambil beserta alasan singkat.
5. **Temuan/risiko** dan pertanyaan terbuka bagian 12 yang masih relevan.
6. **Langkah berikutnya.**
