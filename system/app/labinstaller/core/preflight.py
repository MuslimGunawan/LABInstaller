"""Pemeriksaan awal sistem (Pre-flight checks) sebelum instalasi dimulai.

Memeriksa hak Administrator, kompatibilitas OS, kecukupan ruang disk,
ketersediaan winget, koneksi internet, bentrok port, dan status reboot tertunda.
"""

from __future__ import annotations

import ctypes
import os
import platform
import shutil
import socket
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from labinstaller.core.logger import log_debug


@dataclass
class PreflightIssue:
    """Isu atau temuan saat preflight."""

    kategori: str
    pesan: str
    kritis: bool  # Jika True, instalasi tidak boleh dilanjutkan


@dataclass
class PreflightResult:
    """Hasil akhir pengujian pre-flight."""

    lulus: bool
    issues: list[PreflightIssue] = field(default_factory=list)
    is_admin: bool = False
    has_internet: bool = False
    has_winget: bool = False
    free_disk_bytes: int = 0
    pending_reboot: bool = False


def check_is_admin() -> bool:
    """Memeriksa apakah proses berjalan dengan hak Administrator."""
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin() != 0)
    except Exception:
        # Fallback jika di lingkungan non-Windows / mock
        return os.environ.get("LABINSTALLER_MOCK_ADMIN") == "1"


def check_windows_version() -> tuple[bool, str]:
    """Memeriksa apakah sistem adalah Windows 10/11 64-bit."""
    sys_name = platform.system()
    if sys_name != "Windows":
        # Di Linux / non-Windows saat testing
        if os.environ.get("LABINSTALLER_ALLOW_NON_WINDOWS") == "1":
            return True, f"Non-Windows ({sys_name}) diizinkan untuk pengujian"
        return False, f"Sistem operasi bukan Windows ({sys_name})"

    arch = platform.machine()
    if "64" not in arch:
        return False, f"Arsitektur sistem harus 64-bit (terdeteksi: {arch})"

    version = platform.release()
    try:
        ver_num = float(version)
        if ver_num < 10.0:
            return False, f"Versi Windows minimal Windows 10 (terdeteksi: Windows {version})"
    except ValueError:
        pass

    return True, f"Windows {version} 64-bit ({platform.version()})"


def check_disk_space(
    target_dir: Path, required_bytes: int, margin_percent: float = 30.0
) -> tuple[bool, int, int]:
    """Memeriksa apakah ruang disk mencukupi dengan margin tambahan (default 30%).

    Returns:
        (cukup, ruang_bebas, ruang_dibutuhkan_dengan_margin)
    """
    total_required = int(required_bytes * (1.0 + margin_percent / 100.0))
    try:
        usage = shutil.disk_usage(target_dir.anchor or str(target_dir))
        free_bytes = usage.free
        return free_bytes >= total_required, free_bytes, total_required
    except Exception:
        return True, 0, total_required


def check_internet_connection(timeout_seconds: float = 3.0) -> bool:
    """Memeriksa koneksi internet ke DNS publik atau gateway."""
    for host, port in [("1.1.1.1", 53), ("8.8.8.8", 53), ("google.com", 80)]:
        try:
            with socket.create_connection((host, port), timeout=timeout_seconds):
                return True
        except OSError:
            continue
    return False


def check_winget_available() -> bool:
    """Memeriksa ketersediaan perintah winget di sistem."""
    try:
        proc = subprocess.run(
            ["winget", "--version"],
            capture_output=True,
            text=True,
            timeout=5,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return proc.returncode == 0
    except Exception:
        return False


def check_port_in_use(port: int, host: str = "127.0.0.1") -> bool:
    """Memeriksa apakah suatu port sedang digunakan."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        result = sock.connect_ex((host, port))
        return result == 0


def check_pending_reboot() -> bool:
    """Memeriksa apakah ada reboot tertunda di registry Windows."""
    try:
        import winreg

        reboot_keys = [
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            ),
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            ),
        ]
        for root, subkey in reboot_keys:
            try:
                with winreg.OpenKey(root, subkey):
                    return True
            except OSError:
                pass
    except Exception:
        pass
    return False


def run_preflight_checks(
    target_drive: Path,
    estimated_download_bytes: int = 0,
    check_ports: list[int] | None = None,
) -> PreflightResult:
    """Menjalankan seluruh pemeriksaan pre-flight terintegrasi."""
    issues: list[PreflightIssue] = []

    # 1. Hak Administrator
    is_admin = check_is_admin()
    if not is_admin:
        issues.append(
            PreflightIssue(
                kategori="Hak Akses",
                pesan="Aplikasi wajib dijalankan sebagai Administrator (elevasi gagal).",
                kritis=True,
            )
        )

    # 2. Kompatibilitas OS
    os_ok, os_msg = check_windows_version()
    if not os_ok:
        issues.append(
            PreflightIssue(
                kategori="Sistem Operasi",
                pesan=os_msg,
                kritis=True,
            )
        )
    else:
        log_debug(f"Pemeriksaan OS: {os_msg}")

    # 3. Ruang Disk
    disk_ok, free_bytes, needed_bytes = check_disk_space(
        target_drive, estimated_download_bytes, margin_percent=30.0
    )
    if not disk_ok:
        free_gb = free_bytes / (1024**3)
        needed_gb = needed_bytes / (1024**3)
        issues.append(
            PreflightIssue(
                kategori="Ruang Disk",
                pesan=f"Ruang disk di {target_drive.anchor} tidak mencukupi. Tersedia: {free_gb:.1f} GB, Dibutuhkan: {needed_gb:.1f} GB (termasuk margin 30%).",
                kritis=True,
            )
        )

    # 4. Ketersediaan winget
    has_winget = check_winget_available()
    if not has_winget:
        issues.append(
            PreflightIssue(
                kategori="Package Manager",
                pesan="winget tidak ditemukan di sistem. Program akan menggunakan jalur unduh langsung (fallback).",
                kritis=False,
            )
        )

    # 5. Koneksi Internet
    has_internet = check_internet_connection()
    if not has_internet:
        issues.append(
            PreflightIssue(
                kategori="Jaringan",
                pesan="Koneksi internet tidak terdeteksi. Hanya installer yang tersedia di cache lokal yang dapat dipasang.",
                kritis=False,
            )
        )

    # 6. Bentrok Port
    if check_ports:
        for port in check_ports:
            if check_port_in_use(port):
                issues.append(
                    PreflightIssue(
                        kategori="Port Jaringan",
                        pesan=f"Port {port} sedang digunakan oleh proses lain (kemungkinan IIS, Skype, atau layanan aktif).",
                        kritis=False,
                    )
                )

    # 7. Pending Reboot
    pending_reboot = check_pending_reboot()
    if pending_reboot:
        issues.append(
            PreflightIssue(
                kategori="Sistem",
                pesan="Sistem Windows memiliki pembaruan tertunda (pending reboot). Disarankan restart komputer sebelum instalasi.",
                kritis=False,
            )
        )

    lulus = not any(issue.kritis for issue in issues)
    return PreflightResult(
        lulus=lulus,
        issues=issues,
        is_admin=is_admin,
        has_internet=has_internet,
        has_winget=has_winget,
        free_disk_bytes=free_bytes,
        pending_reboot=pending_reboot,
    )
