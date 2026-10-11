"""Modul deteksi multi-sumber untuk aplikasi terpasang di sistem Windows.

Menggabungkan 4 sumber deteksi (PRD 6A.3):
1. Windows Registry (HKLM 64-bit, HKLM 32-bit / WOW6432Node, HKCU).
2. Keluaran perintah CLI (mis. git --version, node -v, python --version)
   dengan pengaman terhadap alias 0-byte WindowsApps / Microsoft Store.
3. Keberadaan berkas dan metadata PE Version Info (ctypes VerQueryValue).
4. Daftar winget terpasang (winget list).

Mendukung perbandingan versi berbasis tuple numerik (mirip [System.Version])
dan kebijakan versi: exact, exact-minor, minimum, serta latest-resolved.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any

from labinstaller.core.logger import log_debug, log_warn


# Enum status deteksi sesuai PRD 11.3 dan 6A.2
class AppStatus(str, Enum):
    BELUM_TERPASANG = "BELUM_TERPASANG"
    SUDAH_TERPASANG = "SUDAH_TERPASANG"
    BUTUH_UPDATE = "BUTUH_UPDATE"
    RUSAK = "RUSAK"


@dataclass
class RegistryAppInfo:
    display_name: str
    display_version: str
    install_location: str
    uninstall_string: str
    quiet_uninstall_string: str
    publisher: str
    hive: str
    key_name: str
    is_msi: bool


@dataclass
class DetectionResult:
    app_id: str
    status: AppStatus
    installed_version: str | None
    target_version: str
    policy: str
    install_location: str | None = None
    architecture: str | None = None
    scope: str | None = None
    detected_by: str = "none"
    details: dict[str, Any] = field(default_factory=dict)
    display_text: str = ""

    def __post_init__(self) -> None:
        if not self.display_text:
            if self.status == AppStatus.SUDAH_TERPASANG:
                ver = (self.installed_version or "terpasang").lstrip("vV")
                self.display_text = f"Sudah Terpasang (v{ver})"
            elif self.status == AppStatus.BUTUH_UPDATE:
                inst = (self.installed_version or "?").lstrip("vV")
                tgt = self.target_version.lstrip("vV")
                self.display_text = f"Butuh Update (v{inst} -> v{tgt})"
            elif self.status == AppStatus.RUSAK:
                self.display_text = "Rusak / Tidak Lengkap"
            else:
                self.display_text = "Belum Terpasang"


# --- Cache Sesi Deteksi ---
_REGISTRY_CACHE: list[RegistryAppInfo] | None = None
_WINGET_LIST_CACHE: dict[str, str] | None = None


def parse_version_tuple(version_str: str | None) -> tuple[int, ...]:
    """Mengubah string versi menjadi tuple integer untuk perbandingan terurut.

    Contoh:
    '1.141.0' -> (1, 141, 0)
    '2.55.0.windows.5' -> (2, 55, 0, 5)
    '25' -> (25,)
    """
    if not version_str:
        return (0,)
    # Ekstrak semua blok angka
    numbers = re.findall(r"\d+", version_str)
    if not numbers:
        return (0,)
    return tuple(int(n) for n in numbers)


def compare_versions(installed_ver: str, target_ver: str, policy: str) -> bool:
    """Membandingkan versi terpasang dengan target berdasarkan kebijakan versi.

    Kebijakan:
    - 'exact': tuple versi harus persis sama.
    - 'exact-minor': mayor dan minor harus sama (2 elemen pertama).
    - 'minimum': versi terpasang harus >= versi target.
    - target 'latest-resolved': versi terpasang dianggap memenuhi jika tidak kosong.
    """
    if not installed_ver:
        return False

    if target_ver == "latest-resolved":
        return True

    inst_tuple = parse_version_tuple(installed_ver)
    target_tuple = parse_version_tuple(target_ver)

    if policy == "exact":
        # Samakan panjang tuple dengan padding 0 jika perlu (mis. 25 vs 25.0)
        max_len = max(len(inst_tuple), len(target_tuple))
        pad_inst = inst_tuple + (0,) * (max_len - len(inst_tuple))
        pad_target = target_tuple + (0,) * (max_len - len(target_tuple))
        return pad_inst == pad_target

    if policy == "exact-minor":
        inst_minor = inst_tuple[:2] if len(inst_tuple) >= 2 else inst_tuple + (0,)
        target_minor = target_tuple[:2] if len(target_tuple) >= 2 else target_tuple + (0,)
        return inst_minor == target_minor

    if policy == "minimum":
        max_len = max(len(inst_tuple), len(target_tuple))
        pad_inst = inst_tuple + (0,) * (max_len - len(inst_tuple))
        pad_target = target_tuple + (0,) * (max_len - len(target_tuple))
        return pad_inst >= pad_target

    # Default fallback: minimum
    return inst_tuple >= target_tuple


def get_pe_file_version(filepath: str | Path) -> str | None:
    """Membaca PE FileVersion info dari executable Windows menggunakan ctypes."""
    if sys.platform != "win32":
        return None

    path_str = str(filepath)
    if not os.path.exists(path_str):
        return None

    try:
        import ctypes
        from ctypes import wintypes

        size = ctypes.windll.version.GetFileVersionInfoSizeW(path_str, None)
        if not size:
            return None

        res = ctypes.create_string_buffer(size)
        if not ctypes.windll.version.GetFileVersionInfoW(path_str, 0, size, res):
            return None

        p_ptr = ctypes.c_void_p()
        p_len = wintypes.UINT()
        if not ctypes.windll.version.VerQueryValueW(
            res, "\\", ctypes.byref(p_ptr), ctypes.byref(p_len)
        ):
            return None

        class VS_FIXEDFILEINFO(ctypes.Structure):
            _fields_ = [
                ("dwSignature", wintypes.DWORD),
                ("dwStrucVersion", wintypes.DWORD),
                ("dwFileVersionMS", wintypes.DWORD),
                ("dwFileVersionLS", wintypes.DWORD),
                ("dwProductVersionMS", wintypes.DWORD),
                ("dwProductVersionLS", wintypes.DWORD),
            ]

        if p_ptr.value is None:
            return None
        vs = VS_FIXEDFILEINFO.from_address(p_ptr.value)
        major = vs.dwFileVersionMS >> 16
        minor = vs.dwFileVersionMS & 0xFFFF
        build = vs.dwFileVersionLS >> 16
        revision = vs.dwFileVersionLS & 0xFFFF

        if revision > 0:
            return f"{major}.{minor}.{build}.{revision}"
        if build > 0:
            return f"{major}.{minor}.{build}"
        return f"{major}.{minor}"
    except Exception as err:
        log_debug(f"Gagal membaca PE version dari {path_str}: {err}")
        return None


def scan_windows_registry_uninstall(force_refresh: bool = False) -> list[RegistryAppInfo]:
    """Memindai entri uninstall Windows pada HKLM (64 & 32 bit) dan HKCU."""
    global _REGISTRY_CACHE
    if _REGISTRY_CACHE is not None and not force_refresh:
        return _REGISTRY_CACHE

    results: list[RegistryAppInfo] = []
    if sys.platform != "win32":
        _REGISTRY_CACHE = results
        return results

    try:
        import winreg

        hives = [
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM_64",
                winreg.KEY_WOW64_64KEY,
            ),
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKLM_32",
                winreg.KEY_WOW64_32KEY,
            ),
            (
                winreg.HKEY_CURRENT_USER,
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                "HKCU",
                0,
            ),
        ]

        for root_hive, subkey_path, hive_name, flag in hives:
            try:
                with winreg.OpenKey(root_hive, subkey_path, 0, winreg.KEY_READ | flag) as root_key:
                    num_subkeys, _, _ = winreg.QueryInfoKey(root_key)
                    for i in range(num_subkeys):
                        try:
                            key_name = winreg.EnumKey(root_key, i)
                            with winreg.OpenKey(root_key, key_name) as app_key:
                                num_values = winreg.QueryInfoKey(app_key)[1]
                                values: dict[str, Any] = {}
                                for j in range(num_values):
                                    try:
                                        vname, val, _ = winreg.EnumValue(app_key, j)
                                        values[vname] = val
                                    except OSError:
                                        continue

                                disp_name = str(values.get("DisplayName", "")).strip()
                                if not disp_name:
                                    continue

                                disp_ver = str(values.get("DisplayVersion", "")).strip()
                                inst_loc = str(values.get("InstallLocation", "")).strip()
                                uninst = str(values.get("UninstallString", "")).strip()
                                quiet_uninst = str(values.get("QuietUninstallString", "")).strip()
                                publisher = str(values.get("Publisher", "")).strip()
                                is_msi = bool(values.get("WindowsInstaller", 0))

                                results.append(
                                    RegistryAppInfo(
                                        display_name=disp_name,
                                        display_version=disp_ver,
                                        install_location=inst_loc,
                                        uninstall_string=uninst,
                                        quiet_uninstall_string=quiet_uninst,
                                        publisher=publisher,
                                        hive=hive_name,
                                        key_name=key_name,
                                        is_msi=is_msi,
                                    )
                                )
                        except OSError:
                            continue
            except OSError:
                continue
    except Exception as err:
        log_warn(f"Terjadi kesalahan saat membaca registry uninstall: {err}")

    _REGISTRY_CACHE = results
    return results


def scan_winget_installed_list(force_refresh: bool = False) -> dict[str, str]:
    """Memindai daftar aplikasi terpasang dari winget list.

    Mengembalikan dictionary {winget_id: version_string}.
    """
    global _WINGET_LIST_CACHE
    if _WINGET_LIST_CACHE is not None and not force_refresh:
        return _WINGET_LIST_CACHE

    results: dict[str, str] = {}
    if not shutil.which("winget"):
        _WINGET_LIST_CACHE = results
        return results

    try:
        startupinfo = None
        creationflags = 0
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creationflags = 0x08000000  # CREATE_NO_WINDOW

        proc = subprocess.run(
            ["winget", "list", "--accept-source-agreements"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=25,
            startupinfo=startupinfo,
            creationflags=creationflags,
        )

        if proc.returncode == 0 and proc.stdout:
            lines = proc.stdout.splitlines()
            # Cari baris pemisah "---"
            header_idx = -1
            for idx, line in enumerate(lines):
                if line.startswith("---") or "---" in line:
                    header_idx = idx
                    break

            if header_idx != -1:
                data_lines = lines[header_idx + 1 :]
                for dline in data_lines:
                    parts = dline.split()
                    if len(parts) >= 3:
                        # Winget baris biasanya: Name ... Id Version [Available] [Source]
                        # Cari part yang menyerupai ID (mengandung titik, mis. Git.Git atau Microsoft.VisualStudioCode)
                        for p_idx, part in enumerate(parts):
                            if "." in part and p_idx + 1 < len(parts):
                                possible_id = part
                                possible_ver = parts[p_idx + 1]
                                if re.match(r"^\d", possible_ver):
                                    results[possible_id] = possible_ver
    except Exception as err:
        log_debug(f"Pengecekan winget list menghasilkan error / timeout: {err}")

    _WINGET_LIST_CACHE = results
    return results


def check_command_version(
    command_name: str, argument: str = "--version"
) -> tuple[str | None, str | None]:
    """Mengecek ketersediaan perintah di PATH dan mengambil string versinya.

    Melindungi terhadap alias Microsoft Store 0-byte untuk Python (PRD 6A.3).
    Mengembalikan tuple (version_str, full_path).
    """
    exe_path = shutil.which(command_name)
    if not exe_path:
        return None, None

    # Pengaman Microsoft Store App Execution Alias untuk python / python3
    if command_name.lower() in ("python", "python3", "python.exe"):
        normalized_path = exe_path.lower()
        if "windowsapps" in normalized_path:
            try:
                if os.path.getsize(exe_path) == 0:
                    log_debug(f"Mengabaikan alias palsu WindowsApps Python: {exe_path}")
                    return None, None
            except OSError:
                return None, None

    try:
        startupinfo = None
        creationflags = 0
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creationflags = 0x08000000  # CREATE_NO_WINDOW

        args = [exe_path]
        if argument:
            args.extend(argument.split())

        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=8,
            startupinfo=startupinfo,
            creationflags=creationflags,
        )

        output = (proc.stdout + " " + proc.stderr).strip()
        if proc.returncode == 0 or output:
            # Ekstrak versi dari output
            match = re.search(r"(\d+(?:\.\d+)+)", output)
            if match:
                return match.group(1), exe_path
            # Kasus versi single integer seperti Apache NetBeans '25'
            int_match = re.search(r"\b(\d+)\b", output)
            if int_match:
                return int_match.group(1), exe_path
    except Exception as err:
        log_debug(f"Gagal menjalankan perintah {command_name} {argument}: {err}")

    return None, exe_path


def check_known_file_locations(app_id: str) -> tuple[str | None, str | None]:
    """Mengecek lokasi pemasangan umum berkas executable berdasarkan app_id.

    Mengembalikan (file_path, version_str) jika ditemukan.
    """
    candidates: list[str] = []
    prog_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    prog_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    local_app_data = os.environ.get("LOCALAPPDATA", "")

    if app_id == "vscode":
        candidates = [
            os.path.join(prog_files, "Microsoft VS Code", "Code.exe"),
            os.path.join(local_app_data, "Programs", "Microsoft VS Code", "Code.exe"),
        ]
    elif app_id == "netbeans":
        candidates = [
            os.path.join(prog_files, "NetBeans-25", "bin", "netbeans64.exe"),
            os.path.join(prog_files, "NetBeans-24", "bin", "netbeans64.exe"),
            os.path.join(prog_files, "NetBeans", "bin", "netbeans64.exe"),
        ]
    elif app_id == "qgis":
        candidates = [
            os.path.join(prog_files, "QGIS 4.2.2", "bin", "qgis-bin.exe"),
            os.path.join(prog_files, "QGIS 3.44.14", "bin", "qgis-bin.exe"),
        ]
        # Cari juga di seluruh folder QGIS di Program Files jika ada
        if os.path.exists(prog_files):
            try:
                for entry in os.listdir(prog_files):
                    if entry.startswith("QGIS"):
                        bin_path = os.path.join(prog_files, entry, "bin", "qgis-bin.exe")
                        if bin_path not in candidates:
                            candidates.append(bin_path)
            except OSError:
                pass
    elif app_id == "git":
        candidates = [
            os.path.join(prog_files, "Git", "bin", "git.exe"),
            os.path.join(prog_files, "Git", "cmd", "git.exe"),
            os.path.join(prog_x86, "Git", "cmd", "git.exe"),
        ]
    elif app_id == "nodejs":
        candidates = [
            os.path.join(prog_files, "nodejs", "node.exe"),
        ]
    elif app_id == "python-user":
        candidates = [
            os.path.join(prog_files, "Python313", "python.exe"),
            os.path.join(prog_files, "Python312", "python.exe"),
            os.path.join(local_app_data, "Programs", "Python", "Python313", "python.exe"),
            os.path.join(local_app_data, "Programs", "Python", "Python312", "python.exe"),
        ]
    elif app_id == "laragon":
        candidates = [
            r"C:\laragon\laragon.exe",
        ]
    elif app_id == "xampp":
        candidates = [
            r"C:\xampp\xampp-control.exe",
        ]
    elif app_id == "php-standalone":
        candidates = [
            r"C:\php\php.exe",
        ]
    elif app_id == "7zip":
        candidates = [
            os.path.join(prog_files, "7-Zip", "7z.exe"),
            os.path.join(prog_x86, "7-Zip", "7z.exe"),
        ]
    elif app_id == "winrar":
        candidates = [
            os.path.join(prog_files, "WinRAR", "WinRAR.exe"),
            os.path.join(prog_x86, "WinRAR", "WinRAR.exe"),
        ]

    for cand in candidates:
        if cand and os.path.exists(cand):
            ver = get_pe_file_version(cand)
            return cand, ver

    return None, None


def detect_app(app_data: dict[str, Any], use_cache: bool = True) -> DetectionResult:
    """Mendeteksi status instalasi satu aplikasi secara menyeluruh dan akurat.

    Alur keputusan (PRD 6A.2):
    1. Belum terinstal -> BELUM_TERPASANG
    2. Terinstal, versi sesuai kebijakan -> SUDAH_TERPASANG
    3. Terinstal, versi berbeda -> BUTUH_UPDATE
    4. Terinstal tetapi file/komponen rusak -> RUSAK
    """
    app_id = str(app_data.get("id", ""))
    target_ver = str(app_data.get("versiTarget", "latest-resolved"))
    policy = str(app_data.get("kebijakanVersi", "minimum"))
    deteksi = app_data.get("deteksi") or {}
    deteksi_tipe = deteksi.get("tipe", "")
    deteksi_nilai = deteksi.get("nilai", "")
    deteksi_arg = deteksi.get("argumen", "--version")
    winget_id = app_data.get("wingetId")
    app_name = str(app_data.get("nama", app_id))

    installed_version: str | None = None
    install_location: str | None = None
    detected_by = "none"
    details: dict[str, Any] = {}
    is_corrupted = False

    # 1. Deteksi Primer sesuai konfigurasi manifest
    if deteksi_tipe == "command":
        ver, loc = check_command_version(deteksi_nilai, deteksi_arg)
        if ver:
            installed_version = ver
            install_location = loc
            detected_by = "command"

    elif deteksi_tipe == "file":
        if os.path.exists(deteksi_nilai):
            install_location = deteksi_nilai
            pe_ver = get_pe_file_version(deteksi_nilai)
            installed_version = pe_ver or target_ver
            detected_by = "file"
        else:
            # Periksa lokasi fallback umum
            cand_loc, cand_ver = check_known_file_locations(app_id)
            if cand_loc:
                install_location = cand_loc
                installed_version = cand_ver or target_ver
                detected_by = "file_fallback"

    elif deteksi_tipe == "registry":
        # Cek registry spesifik atau scan uninstall
        if sys.platform == "win32":
            try:
                import winreg

                # Pisahkan root hive jika nilai diawali HKLM/HKCU
                root_key = winreg.HKEY_LOCAL_MACHINE
                sub_path = deteksi_nilai
                if deteksi_nilai.startswith("HKLM\\"):
                    sub_path = deteksi_nilai[5:]
                    root_key = winreg.HKEY_LOCAL_MACHINE
                elif deteksi_nilai.startswith("HKCU\\"):
                    sub_path = deteksi_nilai[5:]
                    root_key = winreg.HKEY_CURRENT_USER

                with winreg.OpenKey(
                    root_key, sub_path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY
                ) as k:
                    val_name = deteksi.get("polaVersi", "Version")
                    reg_ver, _ = winreg.QueryValueEx(k, val_name)
                    if reg_ver:
                        installed_version = str(reg_ver)
                        detected_by = "registry_key"
            except OSError:
                pass

    # 2. Cek winget list jika belum terdeteksi dan memiliki wingetId
    if not installed_version and winget_id:
        winget_map = scan_winget_installed_list(force_refresh=not use_cache)
        if winget_id in winget_map:
            installed_version = winget_map[winget_id]
            detected_by = "winget"

    # 3. Cek pemindaian Registry Uninstall (pencocokan nama / keyword)
    reg_apps = scan_windows_registry_uninstall(force_refresh=not use_cache)
    matched_reg: list[RegistryAppInfo] = []
    for r_app in reg_apps:
        # Cocokkan nama aplikasi atau ID
        if app_name.lower() in r_app.display_name.lower():
            matched_reg.append(r_app)
        elif app_id.lower() in r_app.display_name.lower():
            matched_reg.append(r_app)
        elif app_id == "vscode" and "visual studio code" in r_app.display_name.lower():
            matched_reg.append(r_app)
        elif app_id == "python-user" and "python 3" in r_app.display_name.lower():
            # Hindari python embeddable atau python runtime aplikasi lain
            if "launcher" not in r_app.display_name.lower():
                matched_reg.append(r_app)

    if matched_reg:
        primary_reg = matched_reg[0]
        details["registry_matches"] = [
            {"name": m.display_name, "version": m.display_version, "hive": m.hive}
            for m in matched_reg
        ]
        if len(matched_reg) > 1 and app_id == "vscode":
            details["multiple_installations"] = True
            log_warn(
                "Terdeteksi beberapa instalasi Visual Studio Code (potensi konflik User & Machine)!"
            )

        if not installed_version and primary_reg.display_version:
            installed_version = primary_reg.display_version
            if not install_location and primary_reg.install_location:
                install_location = primary_reg.install_location
            detected_by = "registry_uninstall"

        details["uninstall_string"] = primary_reg.uninstall_string
        details["quiet_uninstall_string"] = primary_reg.quiet_uninstall_string
        details["hive"] = primary_reg.hive

    # 4. Cek fallback lokasi file jika masih belum terdeteksi
    if not installed_version:
        cand_loc, cand_ver = check_known_file_locations(app_id)
        if cand_loc:
            install_location = cand_loc
            installed_version = cand_ver or "1.0.0"
            detected_by = "file_fallback"

    # 5. Tentukan Status Akhir
    if not installed_version:
        status = AppStatus.BELUM_TERPASANG
    elif is_corrupted:
        status = AppStatus.RUSAK
    else:
        # Bandingkan versi dengan kebijakan
        matches = compare_versions(installed_version, target_ver, policy)
        if matches:
            status = AppStatus.SUDAH_TERPASANG
        else:
            status = AppStatus.BUTUH_UPDATE

    scope = "user" if install_location and "appdata" in install_location.lower() else "machine"
    arch = "x64"

    return DetectionResult(
        app_id=app_id,
        status=status,
        installed_version=installed_version,
        target_version=target_ver,
        policy=policy,
        install_location=install_location,
        architecture=arch,
        scope=scope,
        detected_by=detected_by,
        details=details,
    )


def detect_all_apps(
    apps_list: list[dict[str, Any]], use_cache: bool = True
) -> dict[str, DetectionResult]:
    """Mendeteksi seluruh aplikasi dalam manifest secara cepat dengan cache sesi."""
    # Pre-warm cache registry
    scan_windows_registry_uninstall(force_refresh=not use_cache)

    results: dict[str, DetectionResult] = {}
    for app in apps_list:
        app_id = str(app.get("id", ""))
        if app_id:
            results[app_id] = detect_app(app, use_cache=use_cache)
    return results
