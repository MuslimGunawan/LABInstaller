# Catatan Perubahan (Changelog)

Semua perubahan penting pada proyek Lab Auto Installer dicatat dalam berkas ini. Format mengikuti [Keep a Changelog](https://keepachangelog.com/) dan versi mengikuti [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-11
### Ditambahkan
- Struktur direktori portabel sesuai PRD bagian 3 (`Start.bat` di root, sistem tersembunyi di `system/`).
- Engine inti (`core/paths.py`, `core/config.py`, `core/logger.py`, `core/preflight.py`, `core/engine.py`).
- Antarmuka grafis (GUI) modern dengan CustomTkinter/Tkinter fallback, DPI-aware, tema gelap/terang, dan antrean pesan pekerja (`worker.py`).
- Semua teks antarmuka Bahasa Indonesia di `ui/strings_id.py`.
- Manifest aplikasi lengkap (`apps.json`) dengan 20+ aplikasi terverifikasi dari M0.
- Berkas profil paket (`profiles.json`), pemetaan port Laragon vs XAMPP (`ports.json`), dan Google Drive mirrors (`mirrors.json`).
- Skema validasi JSON untuk seluruh berkas konfigurasi dengan pelaporan kesalahan mendalam dan pemulihan `last-good`.
- CLI dengan dukungan penuh argumen `--dry-run`, `--selftest`, `--selftest-gui`, `--check-config`, `--unattended`, dll.
- Pipeline GitHub Actions CI untuk verifikasi gerbang kualitas penuh di `windows-latest`.
