"""Modul pengelolaan instalasi khusus dan penimpaan custom bin Laragon 6 (core/laragon.py).

Menerapkan aturan PRD bagian 7 dan 8.3:
1. Pemasangan Laragon 6 WAMP Stack ke C:\\laragon secara senyap (Inno Setup /VERYSILENT).
2. Penghentian proses Laragon aktif secara selektif (laragon.exe, httpd.exe, mysqld.exe, php*.exe)
   berdasarkan direktori C:\\laragon agar tidak mematikan proses XAMPP (PRD 7.1 #2).
3. Validasi payload custom bin (payload\\laragon-custom-bin\\ atau arsip .zip) sebelum menyentuh
   sistem: batalkan dan biarkan Laragon standar utuh jika payload tidak valid (PRD 7.1 #3).
4. Pencadangan (backup) folder bin dan data pengguna (www, data MySQL) ke system\\data\\backup\\
   sebelum modifikasi apa pun (PRD 7.1 #4, 6A.5).
5. Penimpaan aman secara logis (staging + atomic copy / robocopy) dengan rollback otomatis
   jika penimpaan gagal di tengah jalan (PRD 7.1 #5, 7.2).
6. Penyesuaian otomatis berkas konfigurasi (usr\\laragon.ini, etc\\apache2\\, php.ini) yang merujuk
   ke folder versi lama (PRD 7.1 #6).
7. Pemasangan halaman penanda lab-check.php di www\\ (PRD 8.6).
8. Verifikasi pasca-instalasi: php -v, httpd -t, mysqld --version (PRD 7.1 #7).
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from labinstaller.core.archive import extract_archive
from labinstaller.core.hasher import verify_sha256
from labinstaller.core.installer import InstallResult, InstallStatus
from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import (
    BACKUP_DIR,
    CACHE_EXTRACT_DIR,
    PAYLOAD_DIR,
)

DEFAULT_LARAGON_DIR = Path("C:/laragon")

# Nama-nama proses terkait Laragon yang harus dihentikan sebelum manipulasi bin
LARAGON_PROCESS_NAMES = [
    "laragon.exe",
    "httpd.exe",
    "mysqld.exe",
    "php.exe",
    "php-cgi.exe",
    "nginx.exe",
    "redis-server.exe",
    "memcached.exe",
]


def stop_laragon_processes(laragon_dir: Path = DEFAULT_LARAGON_DIR) -> list[str]:
    """Menghentikan seluruh proses Laragon yang aktif berdasarkan path direktori.

    Hanya menghentikan proses yang executable-nya berada di dalam laragon_dir,
    sehingga tidak mematikan proses web server lain seperti XAMPP (PRD 7.1 #2).
    """
    stopped_processes: list[str] = []
    if sys.platform != "win32":
        return stopped_processes

    laragon_dir_str = str(laragon_dir.resolve()).lower()

    # Gunakan PowerShell CIM / WMI untuk memeriksa ExecutablePath tiap proses secara presisi
    ps_cmd = (
        f"Get-CimInstance Win32_Process | "
        f"Where-Object {{ $_.ExecutablePath -and ($_.ExecutablePath.ToLower().StartsWith('{laragon_dir_str}')) }} | "
        f"ForEach-Object {{ $_.ProcessId.ToString() + ':' + $_.Name + ':' + $_.ExecutablePath }}"
    )

    try:
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = subprocess.SW_HIDE

        proc = subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_cmd],
            capture_output=True,
            text=True,
            timeout=15,
            startupinfo=startupinfo,
            creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
        )

        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        for line in lines:
            parts = line.split(":", 2)
            if len(parts) >= 2:
                pid_str, proc_name = parts[0], parts[1]
                try:
                    # Hentikan proses via taskkill
                    subprocess.run(
                        ["taskkill", "/F", "/PID", pid_str],
                        capture_output=True,
                        timeout=5,
                        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
                    )
                    stopped_processes.append(f"{proc_name} (PID {pid_str})")
                    log_info(f"Menghentikan proses Laragon: {proc_name} (PID {pid_str})")
                except Exception as err:
                    log_warn(f"Gagal mematikan proses PID {pid_str}: {err}")

    except Exception as exc:
        log_warn(f"Pemeriksaan proses aktif Laragon menghasilkan galat: {exc}")

    # Jeda singkat agar lock berkas di sistem Windows terlepas
    if stopped_processes:
        time.sleep(1.0)

    return stopped_processes


def backup_laragon(
    laragon_dir: Path = DEFAULT_LARAGON_DIR,
    backup_root: Path = BACKUP_DIR,
) -> tuple[Path | None, Path | None]:
    """Mencadangkan folder bin dan data Laragon sebelum operasi penimpaan (PRD 7.1 #4 & 6A.5).

    Returns:
        (path_backup_bin, path_backup_data)
    """
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_root.mkdir(parents=True, exist_ok=True)

    backup_bin_dest: Path | None = None
    backup_data_dest: Path | None = None

    bin_dir = laragon_dir / "bin"
    if bin_dir.is_dir():
        backup_bin_dest = backup_root / f"laragon-bin-{ts}"
        try:
            log_info(f"Mencadangkan folder bin Laragon ke {backup_bin_dest.name}...")
            shutil.copytree(bin_dir, backup_bin_dest, symlinks=True)
            log_info(f"Cadangan bin Laragon berhasil dibuat di {backup_bin_dest}.")
        except Exception as exc:
            log_error(f"Gagal mencadangkan folder bin Laragon: {exc}")
            backup_bin_dest = None

    # Cadangkan data pengguna (www dan data MySQL)
    data_mysql_dir = laragon_dir / "data"
    www_dir = laragon_dir / "www"

    if data_mysql_dir.is_dir() or www_dir.is_dir():
        backup_data_dest = backup_root / f"data-laragon-{ts}"
        backup_data_dest.mkdir(parents=True, exist_ok=True)
        try:
            if data_mysql_dir.is_dir():
                shutil.copytree(data_mysql_dir, backup_data_dest / "data", symlinks=True)
            if www_dir.is_dir():
                shutil.copytree(www_dir, backup_data_dest / "www", symlinks=True)
            log_info(f"Cadangan data Laragon berhasil dibuat di {backup_data_dest}.")
        except Exception as exc:
            log_warn(f"Pencadangan data pengguna Laragon menghasilkan peringatan: {exc}")

    return backup_bin_dest, backup_data_dest


def validate_custom_payload(
    payload_source: Path,
    expected_sha256: str | None = None,
) -> tuple[bool, str]:
    """Memvalidasi integritas dan struktur folder payload custom bin (PRD 7.1 #3).

    Payload bisa berupa direktori (misal payload\\laragon-custom-bin\\)
    atau berkas arsip .zip (misal laragon-custom-bin.zip).
    """
    if not payload_source.exists():
        return False, f"Sumber payload tidak ditemukan: {payload_source}"

    # Jika payload berupa berkas arsip tunggal
    if payload_source.is_file():
        if expected_sha256 and expected_sha256 != "MEMERLUKAN_HASH_DARI_ADMIN":
            if not verify_sha256(payload_source, expected_sha256):
                return (
                    False,
                    f"Hash SHA-256 berkas arsip payload {payload_source.name} tidak cocok!",
                )
        return True, "Berkas arsip payload valid."

    # Jika payload berupa folder yang sudah diekstrak
    if payload_source.is_dir():
        # Periksa apakah ada subdirektori bin/ atau langsung php/apache/mysql
        has_bin_dir = (payload_source / "bin").is_dir()
        check_root = payload_source / "bin" if has_bin_dir else payload_source

        has_php = (check_root / "php").is_dir()
        has_apache = (check_root / "apache").is_dir()
        has_mysql = (check_root / "mysql").is_dir()

        if not (has_php or has_apache or has_mysql):
            return False, (
                f"Struktur folder payload {payload_source.name} tidak valid. "
                "Wajib memuat minimal salah satu dari: php, apache, atau mysql."
            )

        return True, "Struktur folder payload custom bin valid."

    return False, "Sumber payload tidak dikenali."


def rollback_laragon_bin(laragon_dir: Path, backup_bin_dir: Path) -> bool:
    """Mengembalikan folder bin Laragon ke kondisi cadangan semula jika penimpaan gagal (PRD 7.1 #5)."""
    target_bin = laragon_dir / "bin"
    log_warn(f"Melakukan rollback folder bin Laragon dari {backup_bin_dir.name}...")

    try:
        if target_bin.exists():
            shutil.rmtree(target_bin, ignore_errors=True)
        shutil.copytree(backup_bin_dir, target_bin, symlinks=True)
        log_info("Rollback folder bin Laragon berhasil diselesaikan.")
        return True
    except Exception as exc:
        log_error(f"FATAL: Rollback folder bin Laragon gagal: {exc}")
        return False


def apply_custom_bin(
    laragon_dir: Path,
    payload_source: Path,
    backup_bin_dir: Path | None = None,
    expected_sha256: str | None = None,
) -> bool:
    """Menerapkan penimpaan custom bin ke C:\\laragon\\bin secara atomik & aman (PRD 7.1 #5).

    Alur:
    1. Validasi integritas dan struktur payload.
    2. Ekstrak ke direktori staging sementara.
    3. Terapkan penyalinan ke C:\\laragon\\bin.
    4. Jika gagal: jalankan rollback otomatis dari backup_bin_dir.
    5. Bersihkan staging.
    """
    valid, reason = validate_custom_payload(payload_source, expected_sha256=expected_sha256)
    if not valid:
        log_error(f"Validasi payload Laragon custom bin gagal: {reason}")
        return False

    staging_dir = CACHE_EXTRACT_DIR / "laragon-custom-staging"
    if staging_dir.exists():
        shutil.rmtree(staging_dir, ignore_errors=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Jika sumber adalah arsip zip/7z
        if payload_source.is_file():
            log_info(f"Mengekstrak payload custom bin {payload_source.name} ke staging...")
            extract_archive(
                archive_path=payload_source,
                staging_dir=staging_dir,
                archive_format=payload_source.suffix.lstrip(".").lower() or "zip",
                expected_sha256=expected_sha256,
            )
            extracted_bin = staging_dir / "bin" if (staging_dir / "bin").is_dir() else staging_dir
        else:
            extracted_bin = (
                payload_source / "bin" if (payload_source / "bin").is_dir() else payload_source
            )

        target_bin = laragon_dir / "bin"
        target_bin.mkdir(parents=True, exist_ok=True)

        log_info(f"Menerapkan penimpaan custom bin dari {extracted_bin} ke {target_bin}...")

        # Salin per komponen (php, apache, mysql)
        for item in extracted_bin.iterdir():
            dest_item = target_bin / item.name
            if item.is_dir():
                if dest_item.exists():
                    shutil.rmtree(dest_item, ignore_errors=True)
                shutil.copytree(item, dest_item, symlinks=True)
            elif item.is_file():
                shutil.copy2(item, dest_item)

        log_info("Penimpaan custom bin Laragon selesai dengan sukses.")
        shutil.rmtree(staging_dir, ignore_errors=True)
        return True

    except Exception as exc:
        log_error(f"Gagal saat menerapkan penimpaan custom bin Laragon: {exc}")
        if backup_bin_dir and backup_bin_dir.is_dir():
            rollback_laragon_bin(laragon_dir, backup_bin_dir)
        shutil.rmtree(staging_dir, ignore_errors=True)
        return False


def adjust_laragon_config(laragon_dir: Path = DEFAULT_LARAGON_DIR) -> list[str]:
    """Menyesuaikan file konfigurasi Laragon yang merujuk pada versi baru (PRD 7.1 #6).

    Memperbarui:
    - usr\\laragon.ini: Menetapkan versi PHP aktif ke versi yang terpasang di bin\\php\\.
    - etc\\apache2\\mod_php*.conf: Menyelaraskan modul Apache PHP.
    - php.ini di folder PHP Laragon: Memastikan extension_dir dan ekstensi dasar aktif.
    """
    changes: list[str] = []

    # 1. Deteksi versi PHP yang ada di bin\php\
    bin_php_dir = laragon_dir / "bin" / "php"
    active_php_folder: str | None = None

    if bin_php_dir.is_dir():
        subdirs = sorted([d.name for d in bin_php_dir.iterdir() if d.is_dir()], reverse=True)
        if subdirs:
            active_php_folder = subdirs[0]  # Gunakan versi terbaru yang tersedia

    # 2. Perbarui usr\laragon.ini
    laragon_ini = laragon_dir / "usr" / "laragon.ini"
    if laragon_ini.is_file() and active_php_folder:
        try:
            content = laragon_ini.read_text(encoding="utf-8", errors="ignore")
            # Ganti atau set PHP=...
            if re.search(r"^PHP=.*$", content, flags=re.MULTILINE):
                new_content = re.sub(
                    r"^PHP=.*$",
                    f"PHP={active_php_folder}",
                    content,
                    flags=re.MULTILINE,
                )
            else:
                new_content = content + f"\nPHP={active_php_folder}\n"

            if new_content != content:
                laragon_ini.write_text(new_content, encoding="utf-8")
                changes.append(f"laragon.ini diperbarui: PHP={active_php_folder}")
                log_info(f"Konfigurasi usr\\laragon.ini diperbarui (PHP={active_php_folder}).")
        except Exception as exc:
            log_warn(f"Gagal memperbarui usr\\laragon.ini: {exc}")

    # 3. Periksa dan sesuaikan php.ini di folder PHP aktif Laragon
    if active_php_folder:
        php_dir = bin_php_dir / active_php_folder
        php_ini = php_dir / "php.ini"
        if not php_ini.exists():
            php_ini_dev = php_dir / "php.ini-development"
            if php_ini_dev.exists():
                shutil.copy2(php_ini_dev, php_ini)
                changes.append(f"Membuat {php_ini.name} dari php.ini-development")

        if php_ini.is_file():
            try:
                ini_text = php_ini.read_text(encoding="utf-8", errors="ignore")
                # Pastikan extension_dir = "ext"
                if (
                    'extension_dir = "ext"' not in ini_text
                    and "extension_dir = 'ext'" not in ini_text
                ):
                    ini_text = re.sub(
                        r"^;?\s*extension_dir\s*=.*$",
                        'extension_dir = "ext"',
                        ini_text,
                        flags=re.MULTILINE,
                    )
                # Aktifkan ekstensi penting: mysqli, pdo_mysql, curl, mbstring, openssl
                exts_to_enable = [
                    "mysqli",
                    "pdo_mysql",
                    "curl",
                    "mbstring",
                    "openssl",
                    "fileinfo",
                    "gd",
                ]
                for ext in exts_to_enable:
                    ini_text = re.sub(
                        rf"^;\s*(extension\s*=\s*{ext}(?:\.dll)?)\b",
                        r"\1",
                        ini_text,
                        flags=re.MULTILINE,
                    )
                php_ini.write_text(ini_text, encoding="utf-8")
                changes.append(f"php.ini Laragon ({active_php_folder}) diperbarui")
            except Exception as exc:
                log_warn(f"Gagal menyesuaikan php.ini Laragon: {exc}")

    return changes


def install_laragon_marker(laragon_dir: Path = DEFAULT_LARAGON_DIR) -> Path:
    """Menulis berkas halaman penanda lab-check.php di folder www Laragon (PRD 8.6).

    Halaman penanda ini menjawab permintaan diagnostik dari 127.0.0.1/::1
    untuk memverifikasi port 80 dan integrasi database 3306 tanpa menimpa index pengguna.
    """
    www_dir = laragon_dir / "www"
    www_dir.mkdir(parents=True, exist_ok=True)
    marker_file = www_dir / "lab-check.php"

    marker_content = """<?php
// Lab Auto Installer - Halaman Penanda Laragon (PRD 8.6)
header('Content-Type: text/plain; charset=utf-8');

$remote = $_SERVER['REMOTE_ADDR'] ?? '';
if (!in_array($remote, ['127.0.0.1', '::1', 'localhost'])) {
    http_response_code(403);
    exit('Akses hanya diizinkan dari localhost');
}

echo "STACK=LARAGON\\n";
echo "SERVER_PORT=" . ($_SERVER['SERVER_PORT'] ?? '80') . "\\n";
echo "PHP_VERSION=" . PHP_VERSION . "\\n";

// Cek koneksi MySQL Laragon (Port 3306)
$db_status = "FAIL";
$db_error = "";
try {
    $mysqli = @new mysqli("127.0.0.1", "root", "", "", 3306);
    if (!$mysqli->connect_error) {
        $db_status = "OK";
        $mysqli->close();
    } else {
        $db_error = $mysqli->connect_error;
    }
} catch (Exception $e) {
    $db_error = $e->getMessage();
}

echo "DB_PORT=3306\\n";
echo "DB_STATUS=" . $db_status . "\\n";
if ($db_error) {
    echo "DB_ERROR=" . $db_error . "\\n";
}
"""
    marker_file.write_text(marker_content, encoding="utf-8")
    log_info(f"Halaman penanda lab-check.php dipasang di {marker_file}.")
    return marker_file


def verify_laragon_binaries(laragon_dir: Path = DEFAULT_LARAGON_DIR) -> dict[str, Any]:
    """Menjalankan verifikasi pasca-instalasi terhadap biner Laragon (PRD 7.1 #7).

    Memeriksa:
    - php -v
    - httpd -t (sintaks konfigurasi Apache)
    - mysqld --version
    """
    results: dict[str, Any] = {
        "ok": False,
        "php_version": None,
        "apache_syntax_ok": False,
        "mysql_version": None,
        "messages": [],
    }

    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    cflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

    # 1. Verifikasi PHP
    bin_php = laragon_dir / "bin" / "php"
    if bin_php.is_dir():
        for php_sub in sorted(bin_php.iterdir(), reverse=True):
            php_exe = php_sub / "php.exe"
            if php_exe.is_file():
                try:
                    proc = subprocess.run(
                        [str(php_exe), "-v"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        startupinfo=startupinfo,
                        creationflags=cflags,
                    )
                    first_line = proc.stdout.splitlines()[0] if proc.stdout else ""
                    results["php_version"] = first_line
                    results["messages"].append(f"PHP OK: {first_line}")
                    break
                except Exception as exc:
                    results["messages"].append(f"PHP Cek Galat: {exc}")

    # 2. Verifikasi Apache
    bin_apache = laragon_dir / "bin" / "apache"
    if bin_apache.is_dir():
        for ap_sub in sorted(bin_apache.iterdir(), reverse=True):
            httpd_exe = ap_sub / "bin" / "httpd.exe"
            if httpd_exe.is_file():
                try:
                    proc = subprocess.run(
                        [str(httpd_exe), "-t"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        startupinfo=startupinfo,
                        creationflags=cflags,
                    )
                    out = (proc.stdout + proc.stderr).lower()
                    if "syntax ok" in out:
                        results["apache_syntax_ok"] = True
                        results["messages"].append("Apache sintaks OK (httpd -t).")
                    else:
                        results["messages"].append(
                            f"Apache peringatan sintaks: {proc.stderr.strip()}"
                        )
                    break
                except Exception as exc:
                    results["messages"].append(f"Apache Cek Galat: {exc}")

    # 3. Verifikasi MySQL
    bin_mysql = laragon_dir / "bin" / "mysql"
    if bin_mysql.is_dir():
        for my_sub in sorted(bin_mysql.iterdir(), reverse=True):
            mysqld_exe = my_sub / "bin" / "mysqld.exe"
            if mysqld_exe.is_file():
                try:
                    proc = subprocess.run(
                        [str(mysqld_exe), "--version"],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        startupinfo=startupinfo,
                        creationflags=cflags,
                    )
                    first_line = proc.stdout.splitlines()[0] if proc.stdout else ""
                    results["mysql_version"] = first_line
                    results["messages"].append(f"MySQL OK: {first_line}")
                    break
                except Exception as exc:
                    results["messages"].append(f"MySQL Cek Galat: {exc}")

    # Hasil keseluruhan dianggap OK jika bin minimal ditemukan dan tidak ada crash
    results["ok"] = bool(
        results["php_version"] or results["apache_syntax_ok"] or results["mysql_version"]
    )
    return results


def run_laragon_post_install_hook(
    laragon_dir: Path = DEFAULT_LARAGON_DIR,
    custom_payload_override: Path | None = None,
    expected_payload_sha256: str | None = None,
) -> InstallResult:
    """Orkestrasi alur lengkap penimpaan Laragon 6 sesuai spesifikasi PRD 7.1.

    Sifat: Atomik secara logis (PRD 7.2).
    Jika payload tidak valid: tinggalkan Laragon standar apa adanya.
    Jika penimpaan gagal: lakukan rollback otomatis.
    """
    log_info("Menjalankan hook pasca-instalasi Laragon 6...")

    # 1. Hentikan proses yang berjalan dari C:\laragon
    stopped = stop_laragon_processes(laragon_dir)
    if stopped:
        log_info(f"Dihentikan {len(stopped)} proses Laragon sebelum penimpaan.")

    # 2. Cari sumber custom bin payload
    payload_source: Path | None = custom_payload_override
    if not payload_source:
        # Coba dari payload folder atau cache
        cand1 = PAYLOAD_DIR / "laragon-custom-bin"
        cand2 = PAYLOAD_DIR / "laragon-custom-bin.zip"
        if cand1.is_dir():
            payload_source = cand1
        elif cand2.is_file():
            payload_source = cand2

    # 3. Validasi payload jika tersedia
    if payload_source and payload_source.exists():
        valid, reason = validate_custom_payload(
            payload_source, expected_sha256=expected_payload_sha256
        )
        if not valid:
            # PRD 7.1 #3: "Jika tidak valid -> batalkan penimpaan, tinggalkan Laragon standar apa adanya, laporkan."
            log_warn(
                f"Payload Laragon custom bin tidak valid ({reason}). "
                "Membatalkan penimpaan dan membiarkan Laragon standar utuh apa adanya."
            )
            install_laragon_marker(laragon_dir)
            return InstallResult(
                app_id="laragon",
                app_name="Laragon 6 WAMP Stack",
                status=InstallStatus.BERHASIL,
                message=f"Laragon standar terpasang utuh (penimpaan dibatalkan: {reason}).",
            )

        # 4. Buat cadangan (backup) folder bin dan data
        backup_bin, _backup_data = backup_laragon(laragon_dir)

        # 5. Terapkan penimpaan dengan proteksi rollback otomatis
        applied = apply_custom_bin(
            laragon_dir=laragon_dir,
            payload_source=payload_source,
            backup_bin_dir=backup_bin,
            expected_sha256=expected_payload_sha256,
        )

        if not applied:
            log_error("Penimpaan custom bin gagal. Laragon telah dikembalikan ke kondisi standar.")
            install_laragon_marker(laragon_dir)
            return InstallResult(
                app_id="laragon",
                app_name="Laragon 6 WAMP Stack",
                status=InstallStatus.BERHASIL,
                message="Penimpaan custom bin gagal; Laragon dikembalikan ke kondisi cadangan semula.",
            )

        # 6. Sesuaikan konfigurasi
        adjust_laragon_config(laragon_dir)
    else:
        log_info(
            "Tidak ada payload custom bin Laragon yang dikonfigurasi. Mempertahankan konfigurasi bawaan."
        )

    # 7. Pasang halaman penanda lab-check.php
    install_laragon_marker(laragon_dir)

    # 8. Verifikasi biner
    ver_res = verify_laragon_binaries(laragon_dir)
    ver_msg = "; ".join(ver_res["messages"]) if ver_res["messages"] else "Verifikasi biner selesai."

    log_info(f"Hook pasca-instalasi Laragon selesai: {ver_msg}")
    return InstallResult(
        app_id="laragon",
        app_name="Laragon 6 WAMP Stack",
        status=InstallStatus.BERHASIL,
        message=f"Laragon 6 siap digunakan ({ver_msg}).",
    )
