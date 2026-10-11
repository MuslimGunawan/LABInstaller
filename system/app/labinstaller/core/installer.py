"""Modul eksekusi instalasi aplikasi laboratorium via Winget dan engine lokal.

Menerapkan aturan instalasi PRD 6.2 dan 6.4:
1. Memakai flag resmi: --source winget, --exact, --scope machine,
   --silent --disable-interactivity --accept-package-agreements --accept-source-agreements.
2. CREATE_NO_WINDOW dan SW_HIDE: tidak ada jendela hitam (cmd) yang muncul (PRD 5.1).
3. Pemantauan progres real-time per aplikasi dan total.
4. Penanganan exit code:
   - 0: Sukses.
   - 3010 / 0x80070bc2: Sukses, butuh reboot (ERROR_SUCCESS_REBOOT_REQUIRED).
   - -1978335189 / 0x8A15002B: Sudah terinstal (WINGET_INSTALLED_STATUS_ALREADY_INSTALLED).
   - -1978335212 / 0x8A150014: Tidak ada pembaruan berlaku.
5. Verifikasi pasca-instalasi wajib (PRD 6.2): Instal dianggap sukses HANYA JIKA
   verifikasi lolos via detect_app, bukan sekadar exit code 0.
6. Dukungan mode --dry-run dan token pembatalan (cancellation) yang berhenti rapi.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
from typing import Any

from labinstaller.core.detect import AppStatus, detect_app
from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import LOGS_DIR

# Kode keluar winget khusus
WINGET_SUCCESS = 0
WINGET_REBOOT_REQUIRED = 3010
WINGET_REBOOT_REQUIRED_HEX = 0x80070BC2
WINGET_ALREADY_INSTALLED = -1978335189  # 0x8A15002B
WINGET_NO_APPLICABLE_UPDATES = -1978335212  # 0x8A150014


class InstallStatus(str, Enum):
    BERHASIL = "BERHASIL"
    DILEWATI = "DILEWATI"
    GAGAL = "GAGAL"
    BUTUH_REBOOT = "BUTUH_REBOOT"
    DIBATALKAN = "DIBATALKAN"


@dataclass
class InstallResult:
    app_id: str
    app_name: str
    status: InstallStatus
    message: str
    exit_code: int | None = None
    duration_seconds: float = 0.0
    needs_reboot: bool = False
    log_file: str | None = None


# Tipe callback untuk antarmuka
ProgressCallback = Callable[[int, str], None]
CancelCheckCallback = Callable[[], bool]


class WingetInstaller:
    """Mesin instalasi otomatis berbasis Windows Package Manager (Winget)."""

    def __init__(
        self,
        timeout_seconds: int = 1800,  # 30 menit sesuai PRD 6.2
        dry_run: bool = False,
    ) -> None:
        self.timeout_seconds = timeout_seconds
        self.dry_run = dry_run
        self.winget_path = shutil.which("winget")

    def is_available(self) -> bool:
        """Mengecek ketersediaan winget di sistem."""
        return self.winget_path is not None

    def build_install_command(
        self,
        app_data: dict[str, Any],
        use_target_version: bool = True,
    ) -> list[str]:
        """Menyusun argumen perintah winget install sesuai aturan PRD 6.4."""
        winget_id = str(app_data.get("wingetId") or "")
        cmd = [
            "winget",
            "install",
            "--id",
            winget_id,
            "--exact",
            "--source",
            "winget",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--disable-interactivity",
        ]

        # Scope machine bila dideklarasikan
        scope = app_data.get("scope", "machine")
        if scope == "machine":
            cmd.extend(["--scope", "machine"])

        # Kunci versi jika ada target pasti dan diminta
        target_ver = app_data.get("versiTarget")
        if use_target_version and target_ver and target_ver != "latest-resolved":
            cmd.extend(["--version", str(target_ver)])

        return cmd

    def install(
        self,
        app_data: dict[str, Any],
        on_progress: ProgressCallback | None = None,
        is_cancelled: CancelCheckCallback | None = None,
    ) -> InstallResult:
        """Menjalankan proses instalasi satu aplikasi secara senyap dan terverifikasi."""
        start_time = time.time()
        app_id = str(app_data.get("id", "unknown"))
        app_name = str(app_data.get("nama", app_id))
        winget_id = app_data.get("wingetId")

        log_info(f"Memulai alur instalasi untuk {app_name} (ID: {app_id})...", app_id=app_id)

        # 1. Cek token pembatalan di awal langkah
        if is_cancelled and is_cancelled():
            log_warn("Instalasi dibatalkan oleh pengguna sebelum dimulai.", app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.DIBATALKAN,
                message="Instalasi dibatalkan oleh pengguna.",
                duration_seconds=time.time() - start_time,
            )

        # 2. Periksa status awal (Pre-install check)
        pre_detect = detect_app(app_data, use_cache=False)
        if pre_detect.status == AppStatus.SUDAH_TERPASANG:
            log_info(
                f"{app_name} sudah terpasang dan sesuai kebijakan ({pre_detect.display_text}). Melewati instalasi.",
                app_id=app_id,
            )
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.DILEWATI,
                message=f"Sudah terpasang dan sesuai ({pre_detect.display_text}).",
                duration_seconds=time.time() - start_time,
            )

        # 3. Tangani Mode Dry-Run
        if self.dry_run:
            log_info(
                f"[DRY-RUN] Mensimulasikan instalasi {app_name} via winget ID {winget_id}...",
                app_id=app_id,
            )
            if on_progress:
                on_progress(50, f"[Simulasi] Mengunduh {app_name}...")
                time.sleep(0.1)
                on_progress(100, f"[Simulasi] Memasang {app_name}...")
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.BERHASIL,
                message="[Simulasi Dry-Run] Sukses (tidak ada perubahan pada sistem).",
                duration_seconds=time.time() - start_time,
            )

        # 4. Validasi ketersediaan winget
        if not self.is_available() or not winget_id:
            msg = f"Winget tidak tersedia atau wingetId kosong untuk {app_name}."
            log_error(msg, app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=msg,
                duration_seconds=time.time() - start_time,
            )

        # 5. Persiapkan Berkas Log Spesifik Aplikasi
        timestamp_str = time.strftime("%Y%m%d-%H%M%S")
        app_log_path = LOGS_DIR / f"install-{app_id}-{timestamp_str}.log"

        # 6. Susun Perintah dan Eksekusi dengan CREATE_NO_WINDOW
        cmd = self.build_install_command(app_data, use_target_version=True)
        log_info(f"Menjalankan perintah: {' '.join(cmd)}", app_id=app_id)

        startupinfo = None
        creationflags = 0
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creationflags = 0x08000000  # CREATE_NO_WINDOW

        if on_progress:
            on_progress(10, f"Memulai pengunduhan {app_name} via Winget...")

        exit_code: int | None = None
        needs_reboot = False

        try:
            with open(app_log_path, "w", encoding="utf-8", errors="replace") as app_log_file:
                app_log_file.write(f"=== Log Instalasi {app_name} via Winget ===\n")
                app_log_file.write(f"Perintah: {' '.join(cmd)}\n\n")

                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                    startupinfo=startupinfo,
                    creationflags=creationflags,
                )

                last_percent = 10
                if proc.stdout:
                    for line in iter(proc.stdout.readline, ""):
                        clean_line = line.strip()
                        if not clean_line:
                            continue

                        app_log_file.write(line)
                        app_log_file.flush()

                        # Deteksi persentase dari output winget
                        pct_match = re.search(r"(\d{1,3})%", clean_line)
                        if pct_match:
                            try:
                                pct = int(pct_match.group(1))
                                if pct != last_percent:
                                    last_percent = pct
                                    if on_progress:
                                        on_progress(
                                            pct, f"Mengunduh/Memasang {app_name} ({pct}%)..."
                                        )
                            except ValueError:
                                pass
                        elif "Found" in clean_line or "Downloading" in clean_line:
                            if on_progress:
                                on_progress(20, f"Mengunduh paket {app_name}...")
                        elif "Installing" in clean_line or "Memasang" in clean_line:
                            if on_progress:
                                on_progress(80, f"Memasang {app_name} ke sistem...")

                try:
                    proc.wait(timeout=self.timeout_seconds)
                    exit_code = proc.returncode
                except subprocess.TimeoutExpired:
                    proc.kill()
                    log_error(
                        f"Instalasi {app_name} melampaui batas waktu ({self.timeout_seconds}s).",
                        app_id=app_id,
                    )
                    return InstallResult(
                        app_id=app_id,
                        app_name=app_name,
                        status=InstallStatus.GAGAL,
                        message=f"Batas waktu instalasi terlampaui ({self.timeout_seconds} detik).",
                        duration_seconds=time.time() - start_time,
                        log_file=str(app_log_path),
                    )

        except Exception as err:
            log_error(
                f"Gagal mengeksekusi winget untuk {app_name}: {err}", app_id=app_id, exc_info=True
            )
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=f"Kesalahan sistem saat menjalankan instalasi: {err}",
                duration_seconds=time.time() - start_time,
                log_file=str(app_log_path),
            )

        log_info(f"Winget selesai dengan exit code: {exit_code}", app_id=app_id)

        # 7. Evaluasi Exit Code Winget
        if exit_code in (WINGET_REBOOT_REQUIRED, WINGET_REBOOT_REQUIRED_HEX):
            needs_reboot = True
            log_warn(
                f"Instalasi {app_name} memerlukan restart sistem (Reboot Required).", app_id=app_id
            )
        elif exit_code not in (
            WINGET_SUCCESS,
            WINGET_ALREADY_INSTALLED,
            WINGET_NO_APPLICABLE_UPDATES,
        ):
            log_warn(
                f"Winget mengembalikan kode non-sukses {exit_code} untuk {app_name}.",
                app_id=app_id,
            )

        if on_progress:
            on_progress(90, f"Memverifikasi instalasi {app_name}...")

        # 8. Verifikasi Pasca-Instalasi (PRD 6.2 #5)
        # Instal dianggap sukses HANYA JIKA verifikasi lolos, bukan sekadar exit code 0
        post_detect = detect_app(app_data, use_cache=False)
        duration = time.time() - start_time

        if post_detect.status == AppStatus.SUDAH_TERPASANG:
            final_status = InstallStatus.BUTUH_REBOOT if needs_reboot else InstallStatus.BERHASIL
            msg = f"Berhasil dipasang dan diverifikasi ({post_detect.display_text})."
            log_info(f"{app_name}: {msg}", app_id=app_id)
            if on_progress:
                on_progress(100, f"{app_name} selesai terpasang!")
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=final_status,
                message=msg,
                exit_code=exit_code,
                duration_seconds=duration,
                needs_reboot=needs_reboot,
                log_file=str(app_log_path),
            )
        else:
            # Jika verifikasi gagal meskipun exit code 0
            err_msg = (
                f"Verifikasi pasca-instalasi gagal: status deteksi '{post_detect.display_text}' "
                f"(exit code winget: {exit_code})."
            )
            log_error(err_msg, app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=err_msg,
                exit_code=exit_code,
                duration_seconds=duration,
                needs_reboot=needs_reboot,
                log_file=str(app_log_path),
            )
