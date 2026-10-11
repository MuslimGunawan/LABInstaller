"""Modul eksekutor paket biner non-Winget (.exe dan .msi).

Menerapkan aturan PRD 6.2, 6.3, dan 11.4:
1. Menjalankan installer .exe dengan parameter silent (Inno Setup, NSIS, WiX, dsb.)
   dan .msi via msiexec.exe /i "<path>" /qn /norestart.
2. Validasi integritas berkas via hash SHA256 sebelum eksekusi.
3. Eksekusi senyap dengan CREATE_NO_WINDOW dan SW_HIDE (tanpa jendela hitam cmd).
4. Penanganan batas waktu proses (timeout 1800 detik / 30 menit).
5. Penanganan exit code:
   - 0: Sukses.
   - 3010: Sukses, butuh reboot (ERROR_SUCCESS_REBOOT_REQUIRED).
   - 1618: Installer lain sedang berjalan (ERROR_INSTALL_ALREADY_RUNNING).
6. Verifikasi pasca-instalasi wajib (PRD 6.2 #5) via detect_app.
7. Dukungan mode --dry-run dan token pembatalan (cancellation).
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from labinstaller.core.detect import AppStatus, detect_app
from labinstaller.core.hasher import verify_sha256
from labinstaller.core.installer import InstallResult, InstallStatus
from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import LOGS_DIR

# Kode keluar Windows Installer umum
MSI_SUCCESS = 0
MSI_REBOOT_REQUIRED = 3010
MSI_ALREADY_RUNNING = 1618

ProgressCallback = Callable[[int, str], None]
CancelCheckCallback = Callable[[], bool]


@dataclass
class NativeInstaller:
    """Mesin instalasi langsung untuk berkas .exe dan .msi."""

    timeout_seconds: int = 1800  # 30 menit
    dry_run: bool = False

    def build_command(self, binary_path: Path, app_data: dict[str, Any]) -> list[str]:
        """Menyusun argumen perintah eksekusi installer."""
        metode = str(app_data.get("metode", "exe")).lower().strip()
        custom_args = str(app_data.get("silentArgs", "")).strip()

        ext = binary_path.suffix.lower()

        if metode == "msi" or ext == ".msi":
            # Perintah msiexec standar Windows
            cmd = ["msiexec.exe", "/i", str(binary_path)]
            if custom_args:
                cmd.extend(custom_args.split())
            else:
                cmd.extend(["/qn", "/norestart"])
            return cmd

        # Berkas .exe
        cmd = [str(binary_path)]
        if custom_args:
            # Dukung argumen dengan tanda kutip
            # Gunakan regex untuk memisahkan argumen yang memuat quote
            tokens = re.findall(r'(?:[^\s"]+|"[^"]*")+|(?:\S+)', custom_args)
            for t in tokens:
                clean_t = t.strip()
                if clean_t:
                    cmd.append(clean_t)

        return cmd

    def install_file(
        self,
        binary_path: Path,
        app_data: dict[str, Any],
        on_progress: ProgressCallback | None = None,
        is_cancelled: CancelCheckCallback | None = None,
    ) -> InstallResult:
        """Menjalankan instalasi berkas biner secara senyap dan terverifikasi."""
        start_time = time.time()
        app_id = str(app_data.get("id", "unknown"))
        app_name = str(app_data.get("nama", app_id))
        expected_sha256 = app_data.get("sha256")

        log_info(
            f"Memulai alur instalasi native untuk {app_name} ({binary_path.name})...",
            app_id=app_id,
        )

        # 1. Cek token pembatalan di awal
        if is_cancelled and is_cancelled():
            log_warn("Instalasi dibatalkan sebelum dimulai.", app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.DIBATALKAN,
                message="Instalasi dibatalkan oleh pengguna.",
                duration_seconds=time.time() - start_time,
            )

        # 2. Cek status terpasang sebelum memulai
        pre_detect = detect_app(app_data, use_cache=False)
        if pre_detect.status == AppStatus.SUDAH_TERPASANG:
            log_info(
                f"{app_name} sudah terpasang dan sesuai ({pre_detect.display_text}). Melewati instalasi.",
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
                f"[DRY-RUN] Mensimulasikan instalasi native {app_name} ({binary_path.name})...",
                app_id=app_id,
            )
            if on_progress:
                on_progress(50, f"[Simulasi] Menyiapkan installer {app_name}...")
                time.sleep(0.1)
                on_progress(100, f"[Simulasi] Memasang {app_name}...")
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.BERHASIL,
                message="[Simulasi Dry-Run] Sukses (tidak ada perubahan pada sistem).",
                duration_seconds=time.time() - start_time,
            )

        # 4. Validasi keberadaan berkas biner
        if not binary_path.is_file():
            err_msg = f"Berkas biner installer tidak ditemukan: {binary_path}"
            log_error(err_msg, app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=err_msg,
                duration_seconds=time.time() - start_time,
            )

        # 5. Validasi integritas hash SHA256 sebelum eksekusi (PRD 6.2 #2)
        if expected_sha256:
            if on_progress:
                on_progress(10, f"Memverifikasi hash SHA-256 berkas {binary_path.name}...")

            if not verify_sha256(binary_path, expected_sha256):
                err_msg = (
                    f"Integritas berkas {binary_path.name} tidak valid: "
                    f"hash SHA-256 tidak cocok dengan manifest!"
                )
                log_error(err_msg, app_id=app_id)
                return InstallResult(
                    app_id=app_id,
                    app_name=app_name,
                    status=InstallStatus.GAGAL,
                    message=err_msg,
                    duration_seconds=time.time() - start_time,
                )
            log_info(f"Verifikasi SHA-256 cocok untuk {binary_path.name}.", app_id=app_id)

        # 6. Siapkan Berkas Log Spesifik
        timestamp_str = time.strftime("%Y%m%d-%H%M%S")
        app_log_path = LOGS_DIR / f"install-native-{app_id}-{timestamp_str}.log"

        cmd = self.build_command(binary_path, app_data)
        log_info(f"Menjalankan perintah installer: {' '.join(cmd)}", app_id=app_id)

        startupinfo = None
        creationflags = 0
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creationflags = 0x08000000  # CREATE_NO_WINDOW

        if on_progress:
            on_progress(30, f"Menjalankan installer silent {app_name}...")

        exit_code: int | None = None
        needs_reboot = False

        try:
            with open(app_log_path, "w", encoding="utf-8", errors="replace") as log_f:
                log_f.write(f"=== Log Instalasi Native {app_name} ===\n")
                log_f.write(f"Perintah: {' '.join(cmd)}\n\n")

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

                if proc.stdout:
                    for line in iter(proc.stdout.readline, ""):
                        if not line:
                            break
                        log_f.write(line)
                        log_f.flush()

                try:
                    proc.wait(timeout=self.timeout_seconds)
                    exit_code = proc.returncode
                except subprocess.TimeoutExpired:
                    proc.kill()
                    err_msg = f"Instalasi {app_name} melampaui batas waktu ({self.timeout_seconds} detik)."
                    log_error(err_msg, app_id=app_id)
                    return InstallResult(
                        app_id=app_id,
                        app_name=app_name,
                        status=InstallStatus.GAGAL,
                        message=err_msg,
                        duration_seconds=time.time() - start_time,
                        log_file=str(app_log_path),
                    )

        except Exception as exc:
            err_msg = f"Gagal mengeksekusi installer native untuk {app_name}: {exc}"
            log_error(err_msg, app_id=app_id, exc_info=True)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=err_msg,
                duration_seconds=time.time() - start_time,
                log_file=str(app_log_path),
            )

        log_info(f"Installer selesai dengan exit code: {exit_code}", app_id=app_id)

        # 7. Evaluasi Exit Code
        if exit_code == MSI_REBOOT_REQUIRED:
            needs_reboot = True
            log_warn(
                f"Instalasi {app_name} memerlukan restart sistem (Exit Code 3010).",
                app_id=app_id,
            )
        elif exit_code == MSI_ALREADY_RUNNING:
            err_msg = (
                f"Instalasi {app_name} tertunda: installer lain sedang berjalan (Exit Code 1618)."
            )
            log_warn(err_msg, app_id=app_id)
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=InstallStatus.GAGAL,
                message=err_msg,
                exit_code=exit_code,
                duration_seconds=time.time() - start_time,
                log_file=str(app_log_path),
            )
        elif exit_code != MSI_SUCCESS:
            log_warn(
                f"Installer mengembalikan exit code non-sukses {exit_code} untuk {app_name}.",
                app_id=app_id,
            )

        if on_progress:
            on_progress(85, f"Memverifikasi instalasi {app_name} pasca-eksekusi...")

        # 8. Verifikasi Pasca-Instalasi Wajib (PRD 6.2 #5)
        post_detect = detect_app(app_data, use_cache=False)
        duration = time.time() - start_time

        if post_detect.status == AppStatus.SUDAH_TERPASANG:
            status = InstallStatus.BUTUH_REBOOT if needs_reboot else InstallStatus.BERHASIL
            msg = f"Berhasil dipasang dan diverifikasi ({post_detect.display_text})."
            log_info(f"{app_name}: {msg}", app_id=app_id)
            if on_progress:
                on_progress(100, f"{app_name} selesai terpasang!")
            return InstallResult(
                app_id=app_id,
                app_name=app_name,
                status=status,
                message=msg,
                exit_code=exit_code,
                duration_seconds=duration,
                needs_reboot=needs_reboot,
                log_file=str(app_log_path),
            )
        else:
            err_msg = (
                f"Verifikasi pasca-instalasi gagal: status deteksi '{post_detect.display_text}' "
                f"(exit code installer: {exit_code})."
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
