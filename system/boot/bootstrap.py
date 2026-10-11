"""Bootstrap peluncur Lab Auto Installer.

Modul ini berukuran kecil, stabil, dan bertugas:
1. Menyembunyikan folder system/ pada sistem Windows agar root hanya menampilkan Start.bat.
2. Memastikan sys.path mengenali paket labinstaller di system/app.
3. Memeriksa dan menerapkan update paket (bila ada) sebelum meluncurkan aplikasi utama.
4. Menjalankan labinstaller.__main__.main() dan meneruskan exit code ke Start.bat.
"""

from __future__ import annotations

import ctypes
import os
from pathlib import Path
import subprocess
import sys


def hide_system_directory(system_dir: Path) -> None:
    """Memberi atribut Hidden pada direktori system di Windows."""
    if sys.platform != "win32":
        return

    try:
        # FILE_ATTRIBUTE_HIDDEN = 0x02
        attrs = ctypes.windll.kernel32.GetFileAttributesW(str(system_dir))
        if attrs != -1 and not (attrs & 0x02):
            ctypes.windll.kernel32.SetFileAttributesW(str(system_dir), attrs | 0x02)
    except Exception:
        pass


def main() -> int:
    """Fungsi utama bootstrap."""
    boot_dir = Path(__file__).resolve().parent
    system_dir = boot_dir.parent
    root_dir = system_dir.parent
    app_dir = system_dir / "app"

    # 1. Sembunyikan direktori system/
    hide_system_directory(system_dir)

    # 2. Tambahkan system/app ke sys.path
    app_dir_str = str(app_dir)
    if app_dir_str not in sys.path:
        sys.path.insert(0, app_dir_str)

    # 3. Jalankan aplikasi utama
    try:
        from labinstaller.__main__ import main as app_main
        return app_main()
    except Exception as exc:
        print(f"[FATAL BOOTSTRAP] Gagal meluncurkan aplikasi utama: {exc}", file=sys.stderr)
        return 6


if __name__ == "__main__":
    sys.exit(main())
