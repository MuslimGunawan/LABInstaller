"""Penanganan argumen baris perintah (CLI) untuk Lab Auto Installer.

Mendukung eksekusi tanpa GUI, simulasi --dry-run, verifikasi --check-config,
pengujian mandiri --selftest, dan mode tanpa pengawasan --unattended.
"""

from __future__ import annotations

import argparse

from labinstaller import __version__
from labinstaller.core.config import ConfigManager, check_all_configs
from labinstaller.core.engine import run_dry_run, run_selftest
from labinstaller.core.logger import init_logger


def parse_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    """Menguraikan argumen baris perintah sesuai PRD bagian 10.1."""
    parser = argparse.ArgumentParser(
        prog="LabInstaller",
        description="Lab Auto Installer untuk Komputer Lab Windows",
    )

    parser.add_argument(
        "--cli",
        action="store_true",
        help="Paksa mode baris perintah tanpa membuka jendela antarmuka grafis (GUI)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Tampilkan rencana eksekusi dan simulasi tanpa mengubah sistem",
    )
    parser.add_argument(
        "--apps",
        type=str,
        help="Daftar ID aplikasi yang dipisahkan tanda koma (otomatis mengaktifkan mode CLI)",
    )
    parser.add_argument(
        "--profile",
        type=str,
        help="Nama atau ID profil paket siap pakai (otomatis mengaktifkan mode CLI)",
    )
    parser.add_argument(
        "--unattended",
        action="store_true",
        help="Mode non-interaktif tanpa prompt konfirmasi (backup data tetap berjalan)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Paksa instal ulang meskipun versi software sudah sesuai",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Jalankan verifikasi kondisi instalasi semua aplikasi lalu keluar",
    )
    parser.add_argument(
        "--check-config",
        action="store_true",
        help="Validasi seluruh berkas konfigurasi terhadap skema lalu keluar",
    )
    parser.add_argument(
        "--no-update",
        action="store_true",
        help="Lewati pemeriksaan pembaruan otomatis dari GitHub",
    )
    parser.add_argument(
        "--force-update",
        action="store_true",
        help="Paksa pemeriksaan dan penerapan update program dari GitHub",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="Uji mandiri modul, konfigurasi, runtime, dan utilitas tanpa mengubah sistem",
    )
    parser.add_argument(
        "--selftest-gui",
        action="store_true",
        help="Uji antarmuka grafis: buka jendela, render seluruh komponen, lalu keluar (dipakai CI)",
    )
    parser.add_argument(
        "--version",
        action="store_true",
        help="Cetak nomor versi program lalu keluar",
    )
    parser.add_argument(
        "--publish-to-share",
        action="store_true",
        help="Salin installer terverifikasi ke folder bersama (LAN share)",
    )
    parser.add_argument(
        "--clean-cache",
        action="store_true",
        help="Bersihkan berkas installer versi usang dari folder cache",
    )
    parser.add_argument(
        "--hosting-list",
        action="store_true",
        help="Tampilkan daftar berkas yang perlu di-hosting manual di Google Drive (Menu H)",
    )

    return parser.parse_args(argv)


def run_cli_mode(args: argparse.Namespace) -> int:
    """Mengeksekusi perintah CLI dan mengembalikan kode keluar (exit code)."""
    init_logger(app_version=__version__, is_cli=True)

    if args.version:
        print(f"Lab Auto Installer v{__version__}")
        return 0

    if args.check_config:
        ok, reports = check_all_configs()
        for r in reports:
            print(r)
        return 0 if ok else 4

    if args.selftest:
        return run_selftest()

    config_manager = ConfigManager()
    try:
        config_manager.load_all()
    except Exception as exc:
        print(f"[ERROR] Gagal memuat konfigurasi: {exc}")
        return 4

    if args.hosting_list:
        print("\n=== DAFTAR BERKAS BUTUH HOSTING MANUAL (GOOGLE DRIVE) ===")
        pending = []
        for app in config_manager.apps:
            if app.get("statusSumber") == "menunggu-hosting":
                pending.append(app)
            else:
                for s in app.get("sumber", []):
                    if s.get("tipe") == "gdrive" and "ISI_FILE_ID" in str(s.get("fileId", "")):
                        pending.append(app)
                        break

        if not pending:
            print("Tidak ada berkas yang saat ini menunggu hosting manual di Google Drive.\n")
            return 0

        print(
            f"Ditemukan {len(pending)} aplikasi yang membutuhkan hosting manual di Google Drive:\n"
        )
        for idx, p in enumerate(pending, 1):
            fn = p.get("berkasLokal") or p.get("id")
            print(f"[{idx}] Aplikasi      : {p.get('nama')} (v{p.get('versiTarget')})")
            print(f"    Nama Berkas   : {fn}")
            print(
                f"    Ukuran Resmi  : {p.get('ukuran', 0)} bytes ({int(p.get('ukuran', 0)) / (1024 * 1024):.2f} MB)"
            )
            print(f"    SHA-256 Resmi : {p.get('sha256', '-')}")
            print("-" * 70)
        print(
            "\nInstruksi: Unggah 4 salinan berkas ke Google Drive dan isi ID-nya di config/mirrors.json.\n"
        )
        return 0

    # Identifikasi aplikasi yang dipilih
    selected_apps: list[str] = []
    profile_name: str | None = None

    if args.profile:
        profile_query = args.profile.lower()
        matched = None
        for p in config_manager.profiles:
            if p["id"].lower() == profile_query or p["nama"].lower() == profile_query:
                matched = p
                break
        if not matched:
            print(f"[ERROR] Profil '{args.profile}' tidak ditemukan dalam profiles.json.")
            print("Profil tersedia:", ", ".join(p["id"] for p in config_manager.profiles))
            return 4
        selected_apps = matched.get("apps", [])
        profile_name = matched.get("nama")

    elif args.apps:
        requested_ids = [a.strip() for a in args.apps.split(",") if a.strip()]
        all_app_ids = {a["id"] for a in config_manager.apps}
        for aid in requested_ids:
            if aid not in all_app_ids:
                print(f"[ERROR] Aplikasi '{aid}' tidak ditemukan dalam manifest apps.json.")
                return 4
        selected_apps = requested_ids

    if args.dry_run:
        if not selected_apps:
            # Jika tidak memilih app/profil spesifik, tampilkan seluruh aplikasi dalam dry-run
            selected_apps = [a["id"] for a in config_manager.apps]
            profile_name = "Semua Aplikasi"
        return run_dry_run(selected_apps, config_manager, profile_name=profile_name)

    if args.verify:
        print("Pemeriksaan verifikasi instalasi aplikasi akan dijalankan pada M7.")
        return 0

    # Default fallback bila argumen tidak lengkap
    print(
        "Mode CLI diaktifkan tanpa tindakan instalasi. Gunakan --help untuk melihat panduan argumen."
    )
    return 0
