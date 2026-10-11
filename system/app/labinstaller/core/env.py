"""Manajemen variabel lingkungan sistem Windows (Registry & WM_SETTINGCHANGE).

Mematuhi PRD 6G.1 & 8.4:
- Menambahkan C:\\php di urutan terdepan entri PATH sistem Windows.
- Menambahkan C:\\composer dan C:\\composer\\home\\vendor\\bin ke PATH sistem.
- Mengatur variabel lingkungan sistem COMPOSER_HOME dan COMPOSER_CACHE_DIR.
- Menyiarkan pesan WM_SETTINGCHANGE agar proses baru langsung mengenali perubahan
  tanpa harus me-restart komputer.
- Memperbarui os.environ pada proses aktif sehingga eksekusi bertahap langsung dapat menggunakannya.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from labinstaller.core.logger import log_error, log_info, log_warn

# Konstanta Windows API
HWND_BROADCAST = 0xFFFF
WM_SETTINGCHANGE = 0x001A
SMTO_ABORTIFHUNG = 0x0002


def broadcast_setting_change(section: str = "Environment", timeout_ms: int = 5000) -> bool:
    """Menyiarkan pesan WM_SETTINGCHANGE ke seluruh jendela sistem Windows."""
    if sys.platform != "win32":
        return True

    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        send_msg_timeout = user32.SendMessageTimeoutW
        send_msg_timeout.argtypes = [
            wintypes.HWND,
            wintypes.UINT,
            wintypes.WPARAM,
            wintypes.LPCWSTR,
            wintypes.UINT,
            wintypes.UINT,
            ctypes.POINTER(wintypes.DWORD),
        ]
        send_msg_timeout.restype = wintypes.LPARAM

        result = wintypes.DWORD()
        res = send_msg_timeout(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            0,
            section,
            SMTO_ABORTIFHUNG,
            timeout_ms,
            ctypes.byref(result),
        )
        log_info(f"Pesan WM_SETTINGCHANGE ({section}) berhasil disiarkan.")
        return bool(res != 0)
    except Exception as exc:
        log_warn(f"Gagal menyiarkan WM_SETTINGCHANGE: {exc}")
        return False


def get_system_environment_variable(name: str) -> str | None:
    """Membaca nilai variabel lingkungan sistem langsung dari Windows Registry HKLM."""
    if sys.platform != "win32":
        return os.environ.get(name)

    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            0,
            winreg.KEY_READ,
        )
        try:
            val, _ = winreg.QueryValueEx(key, name)
            return str(val)
        finally:
            winreg.CloseKey(key)
    except FileNotFoundError:
        return None
    except Exception as exc:
        log_warn(f"Gagal membaca variabel sistem {name} dari Registry: {exc}")
        return os.environ.get(name)


def set_system_environment_variable(name: str, value: str, broadcast: bool = True) -> bool:
    """Menyimpan variabel lingkungan sistem ke Windows Registry HKLM."""
    # Perbarui proses aktif
    os.environ[name] = value

    if sys.platform != "win32":
        log_info(f"[SIMULASI] Variabel sistem {name} diatur ke {value}.")
        return True

    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            0,
            winreg.KEY_SET_VALUE,
        )
        try:
            # Gunakan REG_EXPAND_SZ jika ada referensi %VARIABLE%
            val_type = winreg.REG_EXPAND_SZ if "%" in value else winreg.REG_SZ
            winreg.SetValueEx(key, name, 0, val_type, value)
            log_info(f"Variabel sistem {name} disimpan ke Registry: {value}")
        finally:
            winreg.CloseKey(key)

        if broadcast:
            broadcast_setting_change()
        return True
    except Exception as exc:
        log_error(f"Gagal menulis variabel sistem {name} ke Registry: {exc}")
        return False


def prepend_system_path(target_path: Path | str, broadcast: bool = True) -> bool:
    """Menambahkan target_path ke posisi paling depan PATH sistem Windows (PRD 6G.1).

    Idempoten: jika path sudah ada di depan, tidak diubah.
    Jika sudah ada di posisi lain, dipindahkan ke posisi paling depan.
    """
    clean_target = str(Path(target_path).resolve())
    current_path_str = get_system_environment_variable("Path") or os.environ.get("PATH", "")

    # Pecah path berdasarkan titik koma
    entries = [p.strip() for p in current_path_str.split(";") if p.strip()]

    # Bandingkan secara case-insensitive
    target_lower = clean_target.lower()
    filtered_entries = [p for p in entries if p.lower() != target_lower]

    new_entries = [clean_target] + filtered_entries
    new_path_str = ";".join(new_entries)

    # Perbarui proses saat ini
    os.environ["PATH"] = new_path_str

    if sys.platform != "win32":
        log_info(f"[SIMULASI] Path {clean_target} ditambahkan ke depan PATH.")
        return True

    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            0,
            winreg.KEY_SET_VALUE,
        )
        try:
            winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new_path_str)
            log_info(
                f"PATH sistem berhasil diperbarui. {clean_target} ditempatkan di paling depan."
            )
        finally:
            winreg.CloseKey(key)

        if broadcast:
            broadcast_setting_change()
        return True
    except Exception as exc:
        log_error(f"Gagal memperbarui PATH sistem di Registry: {exc}")
        return False


def append_system_path(target_path: Path | str, broadcast: bool = True) -> bool:
    """Menambahkan target_path ke akhir PATH sistem Windows jika belum ada."""
    clean_target = str(Path(target_path).resolve())
    current_path_str = get_system_environment_variable("Path") or os.environ.get("PATH", "")

    entries = [p.strip() for p in current_path_str.split(";") if p.strip()]
    target_lower = clean_target.lower()

    if any(p.lower() == target_lower for p in entries):
        log_info(f"Path {clean_target} sudah terdaftar di PATH sistem (dilewati).")
        return True

    entries.append(clean_target)
    new_path_str = ";".join(entries)

    os.environ["PATH"] = new_path_str

    if sys.platform != "win32":
        return True

    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            0,
            winreg.KEY_SET_VALUE,
        )
        try:
            winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new_path_str)
            log_info(f"Path {clean_target} ditambahkan ke PATH sistem.")
        finally:
            winreg.CloseKey(key)

        if broadcast:
            broadcast_setting_change()
        return True
    except Exception as exc:
        log_error(f"Gagal menambahkan {clean_target} ke PATH sistem: {exc}")
        return False
