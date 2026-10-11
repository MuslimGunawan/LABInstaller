"""Modul ekstraksi mandiri dan pengelolaan arsip (core/archive.py).

Menerapkan aturan PRD 6F:
1. Ekstraksi mandiri tanpa bergantung pada 7-Zip/WinRAR di sistem host.
   - .zip: Modul bawaan Python zipfile (ekstraksi per entri dengan verifikasi keamanan).
   - .7z, .rar, multi-part, dsb: 7-Zip portabel internal di system\\tools\\7z\\ (7z.exe + 7z.dll),
     dengan fallback ke 7-Zip atau WinRAR di PATH jika tersedia.
2. Perlindungan keamanan Zip Slip: Menolak arsip dengan path traversal (.., path absolut,
   atau tautan di luar direktori staging).
3. Sifat idempoten via penanda .extracted-ok: Menggunakan kembali staging yang sudah
   lengkap dan tervalidasi hash-nya, serta membersihkan staging yang tidak lengkap.
4. Pembersihan Mark of the Web (Zone.Identifier) pada hasil ekstraksi.
5. Validasi berkas hasil ekstraksi terhadap isiDiharapkan.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import zipfile
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

from labinstaller.core.hasher import calculate_sha256
from labinstaller.core.logger import log_debug, log_error, log_info
from labinstaller.core.paths import TOOLS_7Z_EXE

ProgressCallback = Callable[[int, str], None]


class ArchiveError(Exception):
    """Kelas dasar kesalahan operasi arsip."""


class ZipSlipSecurityError(ArchiveError):
    """Kesalahan keamanan Zip Slip (percobaan path traversal terdeteksi)."""


class ExpectedFileNotFoundError(ArchiveError):
    """Berkas yang dideklarasikan dalam isiDiharapkan tidak ditemukan setelah ekstraksi."""


class UnsupportedArchiveFormatError(ArchiveError):
    """Format arsip tidak didukung atau ekstraktor yang sesuai tidak tersedia."""


def is_safe_extraction_path(target_directory: Path, entry_path: str) -> bool:
    """Memeriksa apakah path entri arsip aman dan tidak mengarah ke luar direktori target.

    Mencegah serangan Zip Slip / Path Traversal (PRD 6F.3).
    Menolak:
    - Path absolut (mis. C:\\Windows\\..., /etc/passwd)
    - Path yang mengandung komponen '..'
    - Path hasil resolusi yang berada di luar target_directory
    """
    # Normalisasi pemisah direktori
    clean_path = entry_path.replace("\\", "/").strip()

    # Tolak path kosong atau path absolut
    if not clean_path or clean_path.startswith("/") or ":" in clean_path:
        return False

    # Periksa komponen path untuk indikasi traversal '..'
    parts = [p for p in clean_path.split("/") if p]
    if ".." in parts:
        return False

    try:
        target_resolved = target_directory.resolve()
        destination = (target_directory / clean_path).resolve()
        # Pastikan destination dimulai dengan target_resolved
        return destination == target_resolved or str(destination).startswith(
            str(target_resolved) + os.sep
        )
    except Exception:
        return False


def remove_zone_identifier(target_dir: Path) -> None:
    """Menghapus stream Mark of the Web (Zone.Identifier) pada seluruh berkas hasil ekstraksi."""
    if sys.platform != "win32":
        return

    try:
        for root, _, files in os.walk(target_dir):
            for file_name in files:
                file_path = Path(root) / file_name
                stream_path = f"{file_path}:Zone.Identifier"
                try:
                    if os.path.exists(stream_path):
                        os.remove(stream_path)
                except OSError:
                    pass
    except Exception as err:
        log_debug(f"Pembersihan Zone.Identifier menghasilkan pesan: {err}")


def get_extracted_marker_path(staging_dir: Path) -> Path:
    """Mengembalikan lokasi berkas penanda .extracted-ok."""
    return staging_dir / ".extracted-ok"


def check_extracted_ok_marker(staging_dir: Path, expected_sha256: str | None) -> bool:
    """Memeriksa apakah direktori staging sudah memiliki penanda .extracted-ok yang valid."""
    marker_file = get_extracted_marker_path(staging_dir)
    if not marker_file.is_file():
        return False

    try:
        with open(marker_file, encoding="utf-8") as f:
            data = json.load(f)

        if not expected_sha256:
            return True

        stored_hash = str(data.get("archive_sha256", "")).lower()
        return stored_hash == expected_sha256.lower()
    except Exception:
        return False


def write_extracted_ok_marker(staging_dir: Path, archive_sha256: str, file_count: int) -> None:
    """Menuliskan berkas penanda .extracted-ok pada direktori staging."""
    marker_file = get_extracted_marker_path(staging_dir)
    payload = {
        "archive_sha256": archive_sha256.lower(),
        "extracted_at": datetime.now(timezone.utc).isoformat(),
        "file_count": file_count,
    }
    with open(marker_file, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def find_7z_binary() -> Path | None:
    """Mencari binary 7-Zip portabel internal atau instalasi host di sistem."""
    # 1. Prioritas utama: 7-Zip portabel yang dibawa program di system/tools/7z/
    if TOOLS_7Z_EXE.is_file():
        return TOOLS_7Z_EXE

    # 2. Cadangan: 7-Zip di Program Files
    prog_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    host_7z = Path(prog_files) / "7-Zip" / "7z.exe"
    if host_7z.is_file():
        return host_7z

    # 3. Cadangan: 7-Zip di PATH
    which_7z = shutil.which("7z")
    if which_7z:
        return Path(which_7z)

    return None


def extract_zip(
    archive_path: Path,
    staging_dir: Path,
    on_progress: ProgressCallback | None = None,
) -> int:
    """Mengekstrak berkas .zip menggunakan modul bawaan zipfile dengan proteksi Zip Slip."""
    staging_dir.mkdir(parents=True, exist_ok=True)
    extracted_count = 0

    with zipfile.ZipFile(archive_path, "r") as zf:
        infolist = zf.infolist()
        total_files = len(infolist)

        # 1. Prapemeriksaan: Validasi SELURUH entri terhadap Zip Slip sebelum menulis berkas apa pun
        for member in infolist:
            if not is_safe_extraction_path(staging_dir, member.filename):
                msg = (
                    f"Percobaan serangan Zip Slip terdeteksi pada arsip {archive_path.name}: "
                    f"entri mencurigakan '{member.filename}' mengarah ke luar folder staging!"
                )
                log_error(msg)
                raise ZipSlipSecurityError(msg)

        # 2. Ekstraksi aman per entri
        for idx, member in enumerate(infolist, 1):
            zf.extract(member, staging_dir)
            extracted_count += 1

            if on_progress and total_files > 0:
                pct = int((idx / total_files) * 100)
                if idx % 10 == 0 or idx == total_files:
                    on_progress(pct, f"Mengekstrak {archive_path.name} ({idx}/{total_files})...")

    return extracted_count


def extract_with_7z(
    seven_z_exe: Path,
    archive_path: Path,
    staging_dir: Path,
    on_progress: ProgressCallback | None = None,
) -> int:
    """Mengekstrak arsip (.7z, .rar, multi-part, dsb.) menggunakan 7-Zip eksternal."""
    staging_dir.mkdir(parents=True, exist_ok=True)

    # Susun perintah ekstraksi senyap
    cmd = [
        str(seven_z_exe),
        "x",
        "-y",
        f"-o{staging_dir}",
        str(archive_path),
    ]

    log_info(f"Mengekstrak arsip dengan 7-Zip: {archive_path.name} -> {staging_dir}")

    startupinfo = None
    creationflags = 0
    if sys.platform == "win32":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        creationflags = 0x08000000  # CREATE_NO_WINDOW

    if on_progress:
        on_progress(20, f"Mengekstrak {archive_path.name} via 7-Zip...")

    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=1800,  # 30 menit
        startupinfo=startupinfo,
        creationflags=creationflags,
    )

    if proc.returncode not in (0, 1):
        err_msg = f"7-Zip gagal mengekstrak {archive_path.name} (exit code {proc.returncode}): {proc.stderr}"
        log_error(err_msg)
        raise ArchiveError(err_msg)

    # Validasi seluruh file hasil ekstraksi terhadap Zip Slip
    extracted_count = 0
    staging_resolved = staging_dir.resolve()
    for root, _, files in os.walk(staging_dir):
        root_path = Path(root).resolve()
        if not (
            root_path == staging_resolved
            or str(root_path).startswith(str(staging_resolved) + os.sep)
        ):
            raise ZipSlipSecurityError(f"Hasil ekstraksi 7-Zip bocor ke luar staging: {root_path}")
        extracted_count += len(files)

    if on_progress:
        on_progress(100, f"Ekstraksi {archive_path.name} selesai.")

    return extracted_count


def extract_archive(
    archive_path: Path,
    staging_dir: Path,
    archive_format: str = "zip",
    expected_sha256: str | None = None,
    expected_files: list[str] | None = None,
    on_progress: ProgressCallback | None = None,
    force_reextract: bool = False,
) -> Path:
    """Mengekstrak arsip dengan verifikasi integritas, perlindungan Zip Slip, dan idempoten.

    Args:
        archive_path: Path berkas arsip sumber di disk.
        staging_dir: Direktori target staging hasil ekstraksi.
        archive_format: Format arsip ('zip', '7z', 'rar', dsb.).
        expected_sha256: Hash SHA-256 berkas arsip untuk penanda .extracted-ok.
        expected_files: Daftar path relatif berkas yang wajib ada di hasil ekstraksi.
        on_progress: Callback pembaruan persentase progres.
        force_reextract: Jika True, hapus staging dan ekstrak ulang dari awal.

    Returns:
        Path direktori staging hasil ekstraksi.

    Raises:
        FileNotFoundError: Jika berkas arsip sumber tidak ada.
        ZipSlipSecurityError: Jika ada entri path traversal berbahaya.
        ExpectedFileNotFoundError: Jika berkas yang diharapkan tidak ada.
        ArchiveError: Jika ekstraksi gagal.
    """
    if not archive_path.is_file():
        raise FileNotFoundError(f"Berkas arsip tidak ditemukan: {archive_path}")

    # 1. Cek sifat idempoten: jika staging sudah tervalidasi, pakai ulang
    sha256_to_record = expected_sha256 or calculate_sha256(archive_path)

    if not force_reextract and check_extracted_ok_marker(staging_dir, sha256_to_record):
        log_info(
            f"Staging {staging_dir.name} sudah tervalidasi (.extracted-ok cocok). Melewati ekstraksi ulang."
        )
        if on_progress:
            on_progress(
                100, f"Menggunakan hasil ekstraksi yang sudah ada untuk {archive_path.name}."
            )
        return staging_dir

    # 2. Bersihkan staging direktori jika sebelumnya korup atau tidak lengkap
    if staging_dir.exists():
        shutil.rmtree(staging_dir, ignore_errors=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    format_lower = archive_format.lower().strip()
    extracted_count = 0

    # 3. Pilih mesin ekstraksi
    if format_lower == "zip":
        extracted_count = extract_zip(archive_path, staging_dir, on_progress=on_progress)
    else:
        # Format .7z, .rar, dsb.
        seven_z = find_7z_binary()
        if not seven_z:
            msg = (
                f"Tidak ditemukan ekstraktor untuk format '{archive_format}' pada berkas {archive_path.name}. "
                f"Pastikan 7z.exe tersedia di {TOOLS_7Z_EXE} atau sistem host."
            )
            log_error(msg)
            raise UnsupportedArchiveFormatError(msg)

        extracted_count = extract_with_7z(
            seven_z, archive_path, staging_dir, on_progress=on_progress
        )

    # 4. Hapus penanda Mark of the Web (Zone.Identifier)
    remove_zone_identifier(staging_dir)

    # 5. Validasi berkas yang diharapkan (isiDiharapkan)
    if expected_files:
        for exp_rel in expected_files:
            target_file = staging_dir / exp_rel
            if not target_file.exists():
                err_msg = (
                    f"Validasi hasil ekstraksi gagal: berkas wajib '{exp_rel}' "
                    f"tidak ditemukan di {staging_dir}."
                )
                log_error(err_msg)
                raise ExpectedFileNotFoundError(err_msg)

    # 6. Tulis penanda sukses .extracted-ok
    write_extracted_ok_marker(staging_dir, sha256_to_record, extracted_count)
    log_info(
        f"Ekstraksi {archive_path.name} sukses ({extracted_count} berkas diekstrak ke {staging_dir})."
    )

    return staging_dir
