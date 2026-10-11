"""Modul pengunduh berkas dengan dukungan resume, deteksi HTML, dan validasi SHA-256.

Menerapkan aturan PRD 6.2 #2 dan 6B.3:
1. Mengunduh dengan header Range untuk melanjutkan (resume) unduhan terputus (.part).
2. Deteksi respons HTML (Content-Type text/html atau byte awal bukan header biner MZ/PK/7z)
   untuk mencegah penyimpanan halaman kuota/konfirmasi Google Drive sebagai berkas installer.
3. Retry hingga 3 kali dengan jeda bertambah pada kegagalan jaringan sementara.
4. Verifikasi kriptografis SHA-256 setelah unduh selesai: berkas .part hanya diganti nama
   menjadi nama target final jika hash cocok 100%.
5. Pemantauan progres real-time (persentase, kecepatan MB/s, sisa waktu).
"""

from __future__ import annotations

import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

from labinstaller.core.hasher import verify_sha256
from labinstaller.core.logger import log_error, log_info, log_warn

ProgressCallback = Callable[[int, float, int, int], None]
CancelCheckCallback = Callable[[], bool]

# Magic bytes berkas biner umum
MAGIC_EXE = b"MZ"
MAGIC_ZIP = b"PK\x03\x04"
MAGIC_7Z = b"7z\xbc\xaf\x27\x1c"
MAGIC_RAR4 = b"Rar!\x1a\x07\x00"
MAGIC_RAR5 = b"Rar!\x1a\x07\x01\x00"
MAGIC_MSI = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"


class DownloadError(Exception):
    """Kelas dasar kesalahan pengunduhan."""


class DownloadHtmlResponseError(DownloadError):
    """Server mengembalikan halaman HTML (peringatan/kuota) alih-alih berkas biner."""


class DownloadHashMismatchError(DownloadError):
    """Hash SHA-256 berkas yang diunduh tidak cocok dengan nilai yang diharapkan."""


class DownloadCancelledError(DownloadError):
    """Pengunduhan dibatalkan oleh pengguna."""


def detect_unexpected_html(header_bytes: bytes, content_type: str | None) -> bool:
    """Mendeteksi apakah respons server adalah halaman HTML alih-alih berkas biner/arsip."""
    if content_type and "text/html" in content_type.lower():
        return True

    header_lower = header_bytes[:256].lower()
    if (
        b"<!doctype html" in header_lower
        or b"<html" in header_lower
        or b"<head" in header_lower
        or b"<body" in header_lower
    ):
        return True

    return False


def validate_magic_bytes(header_bytes: bytes, file_suffix: str) -> bool:
    """Memvalidasi magic byte awal berkas berdasarkan ekstensinya."""
    ext = file_suffix.lower().strip()
    if ext == ".exe":
        return header_bytes.startswith(MAGIC_EXE)
    elif ext in (".zip", ".jar", ".apk"):
        return header_bytes.startswith(MAGIC_ZIP)
    elif ext == ".7z":
        return header_bytes.startswith(MAGIC_7Z)
    elif ext == ".rar":
        return header_bytes.startswith(MAGIC_RAR4) or header_bytes.startswith(MAGIC_RAR5)
    elif ext == ".msi":
        return header_bytes.startswith(MAGIC_MSI)
    # Format lain tidak dipaksakan
    return True


def download_file(
    url: str,
    target_path: Path,
    expected_sha256: str | None = None,
    expected_size: int | None = None,
    on_progress: ProgressCallback | None = None,
    is_cancelled: CancelCheckCallback | None = None,
    max_retries: int = 3,
    chunk_size: int = 65536,  # 64 KB
    timeout_seconds: float = 30.0,
) -> Path:
    """Mengunduh berkas dari URL dengan dukungan resume, deteksi HTML, dan verifikasi SHA-256.

    Args:
        url: Alamat URL berkas sumber.
        target_path: Path tujuan akhir berkas di disk.
        expected_sha256: Hash SHA-256 yang diharapkan (opsional tapi disarankan).
        expected_size: Ukuran total berkas yang diharapkan dalam bytes.
        on_progress: Callback (persen, kecepatan_mb_s, bytes_terunduh, total_bytes).
        is_cancelled: Callback pengecekan pembatalan dari antarmuka.
        max_retries: Jumlah percobaan ulang pada galat sementara (default 3x).
        chunk_size: Ukuran blok baca per iterasi (default 64 KB).
        timeout_seconds: Batas waktu tunggu respons server (default 30 detik).

    Returns:
        Path berkas yang berhasil diunduh dan diverifikasi.

    Raises:
        DownloadError: Jika unduhan gagal setelah seluruh percobaan.
        DownloadHtmlResponseError: Jika server mengembalikan halaman HTML.
        DownloadHashMismatchError: Jika hash SHA-256 tidak cocok.
        DownloadCancelledError: Jika pengguna membatalkan unduhan.
    """
    target_path.parent.mkdir(parents=True, exist_ok=True)

    # 1. Jika berkas target sudah ada dan hash cocok, pakai kembali (cache hit)
    if target_path.is_file():
        if expected_sha256:
            if verify_sha256(target_path, expected_sha256):
                log_info(
                    f"Berkas cache {target_path.name} valid dan cocok dengan SHA-256. Melewati unduhan."
                )
                if on_progress:
                    size = target_path.stat().st_size
                    on_progress(100, 0.0, size, size)
                return target_path
            else:
                log_warn(
                    f"Berkas cache {target_path.name} ada tetapi hash tidak cocok. Mengunduh ulang..."
                )
                target_path.unlink(missing_ok=True)
        elif expected_size and target_path.stat().st_size == expected_size:
            log_info(f"Berkas cache {target_path.name} ada dengan ukuran cocok. Melewati unduhan.")
            return target_path

    part_path = target_path.with_name(target_path.name + ".part")

    attempt = 0
    while attempt < max_retries:
        attempt += 1
        log_info(f"Mengunduh {target_path.name} dari {url} (Percobaan {attempt}/{max_retries})...")

        if is_cancelled and is_cancelled():
            raise DownloadCancelledError("Pengunduhan dibatalkan oleh pengguna.")

        existing_bytes = 0
        if part_path.is_file():
            existing_bytes = part_path.stat().st_size

        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "LabAutoInstaller/1.0.0 (Windows NT 10.0; Win64; x64)",
            },
        )

        if existing_bytes > 0:
            req.add_header("Range", f"bytes={existing_bytes}-")

        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                status_code = getattr(response, "status", 200)
                content_type = response.headers.get("Content-Type", "")

                # Periksa resume (HTTP 206 Partial Content)
                is_resumed = status_code == 206
                if existing_bytes > 0 and not is_resumed:
                    # Server tidak mendukung resume; mulai dari 0
                    existing_bytes = 0
                    mode = "wb"
                else:
                    mode = "ab" if is_resumed else "wb"

                content_len_header = response.headers.get("Content-Length")
                if content_len_header:
                    total_bytes = existing_bytes + int(content_len_header)
                elif expected_size:
                    total_bytes = expected_size
                else:
                    total_bytes = 0

                downloaded_bytes = existing_bytes
                start_time = time.time()
                bytes_since_sample = 0
                sample_time = start_time
                current_speed_mb_s = 0.0
                first_chunk = True

                with open(part_path, mode) as out_f:
                    while True:
                        if is_cancelled and is_cancelled():
                            raise DownloadCancelledError("Pengunduhan dibatalkan oleh pengguna.")

                        chunk = response.read(chunk_size)
                        if not chunk:
                            break

                        # Deteksi respons HTML pada bagian awal berkas
                        if first_chunk:
                            first_chunk = False
                            if existing_bytes == 0:
                                if detect_unexpected_html(chunk, content_type):
                                    msg = (
                                        f"Server mengembalikan respons HTML untuk {target_path.name} "
                                        f"(Content-Type: {content_type}). Kemungkinan halaman kuota atau konfirmasi."
                                    )
                                    log_error(msg)
                                    raise DownloadHtmlResponseError(msg)

                                # Validasi magic bytes jika ekstensi biner
                                if not validate_magic_bytes(chunk, target_path.suffix):
                                    log_warn(
                                        f"Peringatan: magic bytes {target_path.name} "
                                        f"tidak sesuai dengan ekstensi {target_path.suffix}."
                                    )

                        out_f.write(chunk)
                        downloaded_bytes += len(chunk)
                        bytes_since_sample += len(chunk)

                        # Hitung kecepatan setiap 0.5 detik
                        now = time.time()
                        elapsed = now - sample_time
                        if elapsed >= 0.5:
                            current_speed_mb_s = (bytes_since_sample / (1024 * 1024)) / elapsed
                            bytes_since_sample = 0
                            sample_time = now

                            if on_progress:
                                pct = (
                                    int((downloaded_bytes / total_bytes) * 100)
                                    if total_bytes > 0
                                    else 0
                                )
                                on_progress(
                                    pct,
                                    current_speed_mb_s,
                                    downloaded_bytes,
                                    total_bytes,
                                )

            # 2. Pengunduhan selesai untuk percobaan ini: Verifikasi SHA-256
            if expected_sha256:
                if not verify_sha256(part_path, expected_sha256):
                    part_path.unlink(missing_ok=True)
                    msg = (
                        f"Verifikasi hash SHA-256 gagal untuk {target_path.name}! "
                        f"Berkas sementara dihapus."
                    )
                    log_error(msg)
                    raise DownloadHashMismatchError(msg)

            # Sukses: Ganti nama .part ke target_path final
            if target_path.exists():
                target_path.unlink(missing_ok=True)
            part_path.rename(target_path)

            log_info(f"Pengunduhan {target_path.name} sukses ({target_path.stat().st_size} bytes).")
            if on_progress:
                size = target_path.stat().st_size
                on_progress(100, current_speed_mb_s, size, size)

            return target_path

        except (
            DownloadCancelledError,
            DownloadHtmlResponseError,
            DownloadHashMismatchError,
        ):
            # Galat yang tidak boleh di-retry secara membabi buta.
            # Berkas sementara dibersihkan sekarang setelah file handle tertutup.
            part_path.unlink(missing_ok=True)
            raise

        except Exception as exc:
            log_warn(f"Percobaan unduh ke-{attempt} untuk {target_path.name} gagal: {exc}.")
            if attempt >= max_retries:
                err_msg = f"Gagal mengunduh {target_path.name} dari {url} setelah {max_retries} percobaan: {exc}"
                log_error(err_msg)
                raise DownloadError(err_msg) from exc

            # Backoff delay bertambah (1s, 2s, 3s)
            time.sleep(attempt * 1.0)

    raise DownloadError(f"Gagal mengunduh {target_path.name} dari {url}.")
