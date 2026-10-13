# LABInstaller - Sistem Instalasi & Environtment Pintar Windows

Sistem otomasi berbasis PowerShell dan Windows Package Manager (`winget`) untuk menginstal, memperbarui, dan mengonfigurasi perangkat lunak dan environment development secara resmi, terdaftar di sistem operasi Windows, serta dilengkapi fitur **Self-Update Otomatis via GitHub**.

---

## 🚀 Fitur Utama

1. **Instalasi Resmi & Terdaftar di Windows:**
   - Menggunakan `winget` resmi Microsoft dan installer vendor resmi (Oracle, Google, Microsoft, Eclipse Temurin, dll).
   - Terdaftar langsung di *Apps & Features / Control Panel Windows*.
2. **Logika Instalasi Pintar (Smart Scan & Replace):**
   - **Belum Terpasang:** Otomatis diunduh dan dipasang secara silent/resmi.
   - **Versi Lama:** Otomatis ditukar/diperbarui (*upgrade*) ke versi stabil terbaru.
   - **Sudah Terpasang & Pas:** Otomatis dilewati (*skip*), menghemat waktu dan kuota.
3. **Konfigurasi Environment Otomatis:**
   - Penambahan direktori ke **System/User PATH** tanpa restart komputer.
   - Konfigurasi otomatis `JAVA_HOME` untuk JDK.
   - Konfigurasi otomatis `php.ini` dan ekstensi backend (`curl`, `mbstring`, `openssl`, `pdo_mysql`, `fileinfo`).
   - Integrasi global Composer dan Laravel Installer CLI.
4. **Sistem Self-Update Anti-Gagal (Atomic Safe Update):**
   - Pengecekan otomatis saat script pertama kali dibuka (startup).
   - Menu manual *[3] Periksa Pembaruan LABInstaller dari GitHub*.
   - Otomatis mencadangkan versi sebelumnya ke `.backup/`.
   - Mengunduh versi baru dari GitHub (`MuslimGunawan/LABInstaller`), menimpa perubahan berkas, dan memuat ulang sistem.
   - Mekanisme *auto-rollback* jika terjadi kegagalan saat proses pembaruan.
5. **Modular & Sangat Mudah Dikelola:**
   - Menambahkan software baru cukup menambahkan entri di `manifests/*.json` tanpa menyentuh kode inti.

---

## 📦 Daftar Software & Environment Bawaan (Urutan Prioritas Dependensi)

| Prioritas | Kategori | Nama Software | Pengenal / Metode |
| :---: | :--- | :--- | :--- |
| **P1** | **Version Control** | Git for Windows | `Git.Git` (Winget) |
| **P2** | **SDK & Runtime** | Java Temurin OpenJDK 21 LTS | `EclipseAdoptium.Temurin.21.JDK` + `JAVA_HOME` |
| **P3** | **Runtime** | Python 3.12 | `Python.Python.3.12` + Auto PATH |
| **P4** | **Runtime** | Node.js (LTS) | `OpenJS.NodeJS.LTS` (Vite, NPM) |
| **P5** | **Backend Runtime** | PHP 8.5 | `PHP.PHP.8.5` (Resmi Thread-Safe) |
| **P6** | **Tooling** | Composer | `Composer-Setup.exe` Resmi + Auto PATH |
| **P7** | **Framework Tool** | Laravel Installer CLI | `composer global require laravel/installer` |
| **P8** | **SDK** | Flutter SDK (Stable) | Git Official Repo + Auto PATH |
| **P9** | **Web Server** | Laragon WAMP 6.0.0 | Release Resmi GitHub (Apache: 80, MySQL: 3306) |
| **P10** | **Web Server** | XAMPP 8.2 | `ApacheFriends.Xampp.8.2` (Auto Port 8080 & 3307) |
| **P11** | **IDE & Editor** | Visual Studio Code | `Microsoft.VisualStudioCode` (Winget) |
| **P12** | **IDE & Editor** | Apache NetBeans IDE | `Apache.NetBeans` (Winget) |
| **P13** | **Embedded IDE** | Arduino IDE | `ArduinoSA.IDE.stable` (Winget) |
| **P14** | **Browser** | Google Chrome | `Google.Chrome` (Winget) |
| **P15** | **Virtualization** | Oracle VirtualBox | `Oracle.VirtualBox` (Winget) |

---

## ⚡ Cara Menjalankan di Komputer LAB (Sangat Praktis!)

Di komputer lab mana pun (PC baru/lama), cukup buka **PowerShell** dan tempelkan (*paste*) satu baris perintah ini:

```powershell
irm "https://raw.githubusercontent.com/MuslimGunawan/LABInstaller/main/system/boot/install.ps1?$([Guid]::NewGuid())" | iex
```

> **Apa yang terjadi secara otomatis?**
> 1. Meminta hak akses Administrator jika belum aktif.
> 2. Mengunduh paket LABInstaller terbaru langsung dari GitHub.
> 3. Memasang sistem secara dinamis di lokasi terminal yang sedang aktif (misal di Desktop, drive D:\, dll) dan membuat shortcut di Desktop Publik.
> 4. Langsung membuka menu **Instalasi Pintar**.

---

## 🛠️ Cara Menjalankan Lokal (Jika Berkas Sudah Diunduh)

1. **Via File Explorer:**
   - Cukup **klik dua kali berkas `run.bat`**.
   - Script akan otomatis meminta izin Administrator (UAC).

2. **Via PowerShell Console:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\installer.ps1
   ```

---

## 📂 Struktur Berkas

```text
d:\KP\v2\
├── run.bat                     # Launcher sekali klik
├── installer.ps1               # Entrypoint utama & menu loop
├── config.json                 # Konfigurasi repositori GitHub & direktori
├── version.json                # Metadata versi saat ini (1.0.0)
├── README.md                   # Dokumentasi
│
├── core/
│   ├── Logger.ps1              # Sistem pencatatan konsol berwarna & logfile
│   ├── Environment.ps1         # Manipulasi PATH dan variabel Windows
│   ├── Detector.ps1            # Pendeteksi cerdas status software
│   ├── WingetEngine.ps1        # Eksekutor perintah winget
│   ├── PostInstaller.ps1       # Logika konfigurasi Python, Java, PHP, Flutter, Composer
│   └── Updater.ps1             # Mesin self-update GitHub
│
├── manifests/                  # Tempat menambah software baru (Format JSON)
│   ├── apps.json               # Chrome, VSCode, VirtualBox, Git
│   ├── runtimes.json           # Python, JDK, PHP
│   └── tooling.json            # Composer, Laravel, Flutter
│
└── ui/
    └── Menu.ps1                # Antarmuka menu interaktif
```

---

## 🔄 Cara Menerbitkan Pembaruan ke GitHub

Ketika Anda ingin memperbarui sistem (misalnya ke versi `1.0.1`):
1. Ubah nilai `"version": "1.0.1"` pada file `version.json`.
2. Lakukan perubahan pada kode atau tambah software baru di `manifests/`.
3. Commit dan push ke repository Anda:
   ```bash
   git add .
   git commit -m "Rilis versi 1.0.1"
   git push origin main
   ```
4. Saat pengguna lain (atau Anda di PC lain) menjalankan `run.bat`, sistem akan langsung mendeteksi bahwa v1.0.1 tersedia di GitHub dan menawarkan untuk memperbarui secara otomatis!

