"""Pintu masuk eksekusi utama Lab Auto Installer.

Menangani inisialisasi faulthandler, penangan error global, pemilahan mode GUI vs CLI,
serta pelaporan exit code terstandarisasi sesuai PRD bagian 10.1.
"""

from __future__ import annotations

import faulthandler
import sys
import traceback
from typing import Any

from labinstaller import __version__
from labinstaller.cli import parse_arguments, run_cli_mode
from labinstaller.core.config import ConfigManager
from labinstaller.core.logger import get_session_log_file, init_logger, log_error
from labinstaller.ui.app import run_gui


def setup_global_exception_handler() -> None:
    """Mengaktifkan faulthandler dan penangan uncaught exception global."""
    try:
        faulthandler.enable()
    except Exception:
        pass

    def handle_uncaught_exception(
        exc_type: type[BaseException], exc_value: BaseException, exc_traceback: Any
    ) -> None:
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_traceback)
            return

        tb_lines = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        log_error(f"Kesalahan internal tidak tertangani:\n{tb_lines}")

        log_path = get_session_log_file() or "folder system/data/logs"
        user_message = (
            f"Terjadi kesalahan internal tak terduga pada program:\n\n"
            f"{exc_value}\n\n"
            f"Detail lengkap telah dicatat di berkas log:\n{log_path}"
        )

        # Jika di lingkungan GUI, coba tampilkan dialog ramah
        if "--cli" not in sys.argv and not any(
            a in sys.argv for a in ["--selftest", "--check-config", "--dry-run"]
        ):
            try:
                import tkinter as tk
                from tkinter import messagebox

                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Kesalahan Internal", user_message)
                root.destroy()
            except Exception:
                print(f"\n[ERROR] {user_message}\n", file=sys.stderr)
        else:
            print(f"\n[ERROR] {user_message}\n", file=sys.stderr)

        sys.exit(6)

    sys.excepthook = handle_uncaught_exception


def main() -> int:
    """Fungsi utama program."""
    setup_global_exception_handler()
    args = parse_arguments()

    # Inisialisasi konfigurasi
    config_manager = ConfigManager()

    # Periksa mode CLI
    is_cli = (
        args.cli
        or args.dry_run
        or args.apps is not None
        or args.profile is not None
        or args.unattended
        or args.check_config
        or args.selftest
        or args.version
        or args.verify
        or args.hosting_list
        or args.clean_cache
    )

    if is_cli:
        return run_cli_mode(args)

    # Inisialisasi logger untuk mode GUI
    init_logger(app_version=__version__, is_cli=False)

    try:
        config_manager.load_all()
    except Exception as exc:
        log_error(f"Gagal memuat konfigurasi saat membuka GUI: {exc}")
        print(f"[ERROR] Gagal memuat konfigurasi: {exc}")
        return 4

    if args.selftest_gui:
        return run_gui(config_manager, selftest_mode=True)

    return run_gui(config_manager, selftest_mode=False)


if __name__ == "__main__":
    sys.exit(main())
