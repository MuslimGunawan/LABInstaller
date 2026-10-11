"""Manajemen path terpusat untuk Lab Auto Installer.

Semua path diturunkan secara dinamis dari satu root (lokasi berkas Start.bat)
menggunakan pathlib.Path. Dilarang melakukan hardcode path absolut di kode.
"""

from __future__ import annotations

import os
from pathlib import Path


def get_root_dir() -> Path:
    """Mendapatkan direktori root program (lokasi Start.bat)."""
    env_root = os.environ.get("LABINSTALLER_ROOT")
    if env_root:
        return Path(env_root).resolve()
    # Path modul ini: system/app/labinstaller/core/paths.py -> 4 level ke atas
    return Path(__file__).resolve().parents[4]


ROOT_DIR: Path = get_root_dir()
SYSTEM_DIR: Path = ROOT_DIR / "system"
BOOT_DIR: Path = SYSTEM_DIR / "boot"
RUNTIME_DIR: Path = SYSTEM_DIR / "runtime"
APP_DIR: Path = SYSTEM_DIR / "app"
TOOLS_DIR: Path = SYSTEM_DIR / "tools"
DOCS_DIR: Path = SYSTEM_DIR / "docs"
DATA_DIR: Path = SYSTEM_DIR / "data"

# Subdirektori App & Konfigurasi
CONFIG_DIR: Path = APP_DIR / "config"
SCHEMA_DIR: Path = CONFIG_DIR / "schema"
ASSETS_DIR: Path = APP_DIR / "assets"
VERSION_FILE: Path = APP_DIR / "VERSION"
VERSION_JSON_FILE: Path = APP_DIR / "version.json"

# Berkas Konfigurasi Utama
APPS_JSON: Path = CONFIG_DIR / "apps.json"
MIRRORS_JSON: Path = CONFIG_DIR / "mirrors.json"
PROFILES_JSON: Path = CONFIG_DIR / "profiles.json"
PORTS_JSON: Path = CONFIG_DIR / "ports.json"

# Subdirektori Data Lokal PC (Tidak pernah ditimpa update / masuk Git)
PAYLOAD_DIR: Path = DATA_DIR / "payload"
CACHE_DIR: Path = DATA_DIR / "cache"
CACHE_DOWNLOAD_DIR: Path = CACHE_DIR / "download"
CACHE_EXTRACT_DIR: Path = CACHE_DIR / "extract"
BACKUP_DIR: Path = DATA_DIR / "backup"
LOGS_DIR: Path = DATA_DIR / "logs"
STATE_DIR: Path = DATA_DIR / "state"
LAST_GOOD_DIR: Path = STATE_DIR / "last-good"
LOCAL_JSON: Path = DATA_DIR / "local.json"
LOCK_FILE: Path = STATE_DIR / "app.lock"

# Tools
TOOLS_7Z_DIR: Path = TOOLS_DIR / "7z"
TOOLS_7Z_EXE: Path = TOOLS_7Z_DIR / "7z.exe"
TOOLS_7ZA_EXE: Path = TOOLS_7Z_DIR / "7za.exe"

# Root launcher
START_BAT: Path = ROOT_DIR / "Start.bat"


def ensure_data_directories() -> None:
    """Membuat direktori data yang dibutuhkan jika belum ada."""
    for directory in (
        DATA_DIR,
        PAYLOAD_DIR,
        CACHE_DIR,
        CACHE_DOWNLOAD_DIR,
        CACHE_EXTRACT_DIR,
        BACKUP_DIR,
        LOGS_DIR,
        STATE_DIR,
        LAST_GOOD_DIR,
    ):
        directory.mkdir(parents=True, exist_ok=True)
