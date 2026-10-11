"""Manajemen berkas hosts Windows (C:\\Windows\\System32\\drivers\\etc\\hosts).

Mematuhi PRD 8.3:
- Seluruh pengeditan berkas hosts WAJIB melalui modul ini.
- Dilakukan pencadangan (.bak) sebelum modifikasi.
- Setiap entri yang ditambahkan atau dikelola diberi penanda komentar '# LabInstaller'.
- Idempoten dan tidak menduplikasi entri.
"""

from __future__ import annotations

import os
import re
import shutil
from datetime import datetime
from pathlib import Path

from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import BACKUP_DIR

COMMENT_TAG = "# LabInstaller"


def get_default_hosts_path() -> Path:
    """Mendapatkan path default berkas hosts sistem Windows."""
    windir = os.environ.get("WINDIR", "C:\\Windows")
    return Path(windir) / "System32" / "drivers" / "etc" / "hosts"


def backup_hosts_file(
    hosts_path: Path | None = None,
    backup_root: Path = BACKUP_DIR,
) -> Path | None:
    """Membuat salinan cadangan berkas hosts sebelum dilakukan modifikasi (PRD 8.3)."""
    target = hosts_path or get_default_hosts_path()
    if not target.is_file():
        log_warn(f"Berkas hosts tidak ditemukan untuk dicadangkan: {target}")
        return None

    try:
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest_dir = backup_root / f"hosts-{ts}"
        dest_dir.mkdir(parents=True, exist_ok=True)
        backup_file = dest_dir / "hosts.bak"

        shutil.copy2(target, backup_file)
        # Juga buat salinan lokal .bak langsung di samping berkas hosts bila memungkinkan
        local_bak = target.with_suffix(".bak")
        try:
            shutil.copy2(target, local_bak)
        except Exception:
            pass

        log_info(f"Berkas hosts berhasil dicadangkan ke: {backup_file}")
        return backup_file
    except Exception as exc:
        log_error(f"Gagal mencadangkan berkas hosts: {exc}")
        return None


def add_hosts_entry(
    ip: str,
    hostname: str,
    hosts_path: Path | None = None,
) -> bool:
    """Menambahkan atau memperbarui entri pemetaan host secara aman dan idempoten.

    Setiap entri ditandai dengan komentar '# LabInstaller'.
    """
    target = hosts_path or get_default_hosts_path()
    clean_ip = ip.strip()
    clean_host = hostname.strip().lower()

    if not clean_ip or not clean_host:
        log_warn("Alamat IP dan hostname tidak boleh kosong saat memodifikasi hosts.")
        return False

    # Jika file belum ada (misal di mock lingkungan pengujian), buat baru
    if not target.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("# Berkas hosts Windows\n", encoding="utf-8")

    # Lakukan backup dulu
    backup_hosts_file(target)

    try:
        content = target.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()

        new_lines: list[str] = []
        entry_handled = False

        for line in lines:
            stripped = line.strip()
            # Periksa apakah baris ini memuat hostname yang sama dan aktif
            parts = re.split(r"\s+", stripped)
            if len(parts) >= 2 and not stripped.startswith("#"):
                existing_ip = parts[0]
                existing_hosts = [h.lower() for h in parts[1:] if not h.startswith("#")]
                if clean_host in existing_hosts:
                    if existing_ip == clean_ip:
                        # Entri sudah ada dan identik, pertahankan
                        entry_handled = True
                        new_lines.append(line)
                        continue
                    elif COMMENT_TAG in line:
                        # Entri lama buatan LabInstaller dengan IP berbeda, ganti ke IP baru
                        new_lines.append(f"{clean_ip}\t{clean_host}\t{COMMENT_TAG}")
                        entry_handled = True
                        continue

            new_lines.append(line)

        if not entry_handled:
            # Tambahkan baris baru di akhir
            new_lines.append(f"{clean_ip}\t{clean_host}\t{COMMENT_TAG}")

        final_content = "\n".join(new_lines).rstrip() + "\n"
        target.write_text(final_content, encoding="utf-8")
        log_info(f"Entri hosts berhasil ditambahkan: {clean_ip} -> {clean_host} ({COMMENT_TAG})")
        return True

    except Exception as exc:
        log_error(f"Gagal menulis ke berkas hosts ({target}): {exc}")
        return False


def remove_hosts_entry(
    hostname: str,
    hosts_path: Path | None = None,
) -> bool:
    """Menghapus entri berkas hosts yang memiliki penanda '# LabInstaller'."""
    target = hosts_path or get_default_hosts_path()
    if not target.is_file():
        return False

    clean_host = hostname.strip().lower()
    backup_hosts_file(target)

    try:
        content = target.read_text(encoding="utf-8", errors="replace")
        lines = content.splitlines()

        new_lines: list[str] = []
        removed_any = False

        for line in lines:
            stripped = line.strip()
            if COMMENT_TAG in line and clean_host in stripped.lower():
                removed_any = True
                continue
            new_lines.append(line)

        if removed_any:
            final_content = "\n".join(new_lines).rstrip() + "\n"
            target.write_text(final_content, encoding="utf-8")
            log_info(f"Entri hosts {clean_host} ({COMMENT_TAG}) berhasil dihapus.")

        return True
    except Exception as exc:
        log_error(f"Gagal menghapus entri dari berkas hosts ({target}): {exc}")
        return False


def list_hosts_entries(hosts_path: Path | None = None) -> list[tuple[str, str, bool]]:
    """Mendaftar entri hosts yang aktif.

    Returns:
        List of (ip, hostname, is_labinstaller)
    """
    target = hosts_path or get_default_hosts_path()
    if not target.is_file():
        return []

    entries: list[tuple[str, str, bool]] = []
    try:
        content = target.read_text(encoding="utf-8", errors="replace")
        for line in content.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            is_lab = COMMENT_TAG in line
            parts = re.split(r"\s+", stripped)
            if len(parts) >= 2:
                ip = parts[0]
                for h in parts[1:]:
                    if h.startswith("#"):
                        break
                    entries.append((ip, h.lower(), is_lab))
    except Exception as exc:
        log_warn(f"Gagal membaca entri berkas hosts: {exc}")

    return entries
