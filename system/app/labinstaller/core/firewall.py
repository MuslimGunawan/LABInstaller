"""Manajemen Aturan Windows Firewall untuk Lab Auto Installer.

Mematuhi PRD 8.4:
- Menambahkan aturan Windows Firewall (inbound allow) untuk Apache (httpd.exe)
  dan MySQL/MariaDB (mysqld.exe) milik Laragon dan XAMPP.
- Mencegah munculnya popup izin jaringan Windows Defender Firewall ketika
  mahasiswa membuka Apache/MySQL di komputer lab.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from labinstaller.core.logger import log_error, log_info, log_warn


def add_firewall_rule(
    rule_name: str,
    program_path: Path,
    direction: str = "in",
    action: str = "allow",
    profile: str = "any",
) -> bool:
    """Menambahkan aturan Windows Firewall untuk program tertentu menggunakan netsh advfirewall."""
    if not program_path.is_file():
        log_warn(f"Program biner tidak ditemukan untuk aturan firewall: {program_path}")
        return False

    if sys.platform != "win32":
        # Lingkungan non-Windows (misal CI Linux), simulasikan sukses
        log_info(f"[SIMULASI] Firewall rule '{rule_name}' ditambahkan untuk {program_path}.")
        return True

    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    cflags = subprocess.CREATE_NO_WINDOW

    cmd = [
        "netsh",
        "advfirewall",
        "firewall",
        "add",
        "rule",
        f"name={rule_name}",
        f"dir={direction}",
        f"action={action}",
        f"program={str(program_path)}",
        "enable=yes",
        f"profile={profile}",
    ]

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            startupinfo=startupinfo,
            creationflags=cflags,
        )
        if proc.returncode == 0:
            log_info(
                f"Aturan Windows Firewall berhasil dibuat: '{rule_name}' -> {program_path.name}"
            )
            return True
        else:
            err_msg = proc.stderr.strip() or proc.stdout.strip()
            log_warn(f"Gagal menambahkan aturan firewall '{rule_name}': {err_msg}")
            return False
    except Exception as exc:
        log_error(f"Eksepsi saat mengeksekusi netsh firewall untuk '{rule_name}': {exc}")
        return False


def delete_firewall_rule(rule_name: str) -> bool:
    """Menghapus aturan Windows Firewall berdasarkan nama."""
    if sys.platform != "win32":
        log_info(f"[SIMULASI] Firewall rule '{rule_name}' dihapus.")
        return True

    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    cflags = subprocess.CREATE_NO_WINDOW

    cmd = [
        "netsh",
        "advfirewall",
        "firewall",
        "delete",
        "rule",
        f"name={rule_name}",
    ]

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            startupinfo=startupinfo,
            creationflags=cflags,
        )
        return proc.returncode == 0
    except Exception as exc:
        log_warn(f"Gagal menghapus aturan firewall '{rule_name}': {exc}")
        return False


def ensure_stack_firewall_rules(stack_name: str, base_dir: Path) -> list[str]:
    """Menemukan seluruh biner Apache & MySQL di dalam direktori stack dan menambahkan aturan firewall.

    Args:
        stack_name: Nama stack (misal 'Laragon' atau 'XAMPP').
        base_dir: Direktori root stack (C:\\laragon atau C:\\xampp).

    Returns:
        Daftar nama aturan yang berhasil ditambahkan.
    """
    added_rules: list[str] = []
    if not base_dir.is_dir():
        return added_rules

    # 1. Cari berkas httpd.exe
    httpd_candidates = list(base_dir.glob("**/httpd.exe"))
    for httpd_path in httpd_candidates:
        rule_name = f"LabInstaller - {stack_name} Apache ({httpd_path.parent.name})"
        if add_firewall_rule(rule_name, httpd_path):
            added_rules.append(rule_name)

    # 2. Cari berkas mysqld.exe
    mysql_candidates = list(base_dir.glob("**/mysqld.exe"))
    for mysql_path in mysql_candidates:
        rule_name = f"LabInstaller - {stack_name} MySQL ({mysql_path.parent.name})"
        if add_firewall_rule(rule_name, mysql_path):
            added_rules.append(rule_name)

    return added_rules
