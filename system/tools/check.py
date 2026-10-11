"""Skrip pemeriksa gerbang kualitas kode lokal (tools.check).

Menjalankan compileall, selftest, dry-run, pytest, ruff, dan mypy bila tersedia.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

ROOT_DIR = Path(__file__).resolve().parents[2]
APP_DIR = ROOT_DIR / "system" / "app"


def run_step(name: str, cmd: list[str]) -> bool:
    print(f"\n--- [GERBANG KUALITAS] {name} ---")
    print(f"Perintah: {' '.join(cmd)}")
    env = os.environ.copy()
    env["PYTHONPATH"] = str(APP_DIR)
    env["PYTHONUTF8"] = "1"
    env["LABINSTALLER_ROOT"] = str(ROOT_DIR)

    res = subprocess.run(cmd, cwd=str(ROOT_DIR), env=env)
    if res.returncode != 0:
        print(f"[GAGAL] Langkah '{name}' keluar dengan kode: {res.returncode}")
        return False
    print(f"[LULUS] Langkah '{name}' sukses.")
    return True


def main() -> int:
    print("==================================================")
    print("PEMERIKSA GERBANG KUALITAS KODE (LAB AUTO INSTALLER)")
    print("==================================================")
    all_ok = True

    # 1. Compileall
    if not run_step("Sintaks (compileall)", [sys.executable, "-m", "compileall", "-q", str(APP_DIR)]):
        all_ok = False

    # 2. Uji Mandiri (--selftest)
    if not run_step("Uji Mandiri (--selftest)", [sys.executable, "-m", "labinstaller", "--selftest"]):
        all_ok = False

    # 3. Dry-Run Semua Profil
    profiles = ["web", "flutter", "gis", "dasar", "semua"]
    for p in profiles:
        if not run_step(f"Simulasi Dry-Run (Profil {p})", [sys.executable, "-m", "labinstaller", "--dry-run", "--profile", p]):
            all_ok = False

    # 4. Uji GUI (--selftest-gui)
    if not run_step("Uji Render GUI (--selftest-gui)", [sys.executable, "-m", "labinstaller", "--selftest-gui"]):
        all_ok = False

    # 5. Pytest (bila terpasang)
    try:
        import pytest
        if not run_step("Uji Unit (pytest)", [sys.executable, "-m", "pytest", "system/tests"]):
            all_ok = False
    except ImportError:
        print("\n[INFO] pytest belum terpasang di Python host; pengujian unit akan dijalankan di CI.")

    # 6. Ruff (bila terpasang)
    try:
        import ruff
        if not run_step("Linter (ruff check)", [sys.executable, "-m", "ruff", "check", "system/app", "system/tests"]):
            all_ok = False
    except ImportError:
        pass

    # 7. Mypy (bila terpasang)
    try:
        import mypy
        if not run_step("Type Checker (mypy)", [sys.executable, "-m", "mypy", "--strict", "system/app/labinstaller"]):
            all_ok = False
    except ImportError:
        pass

    print("\n" + "=" * 50)
    if all_ok:
        print("HASIL AKHIR: SELURUH GERBANG KUALITAS LULUS!")
        print("=" * 50)
        return 0
    else:
        print("HASIL AKHIR: ADA GERBANG KUALITAS YANG GAGAL!")
        print("=" * 50)
        return 1


if __name__ == "__main__":
    sys.exit(main())
