"""Utilitas verifikasi integritas berkas kriptografis (SHA-256).

Menerapkan aturan PRD 6.2 #2, 6B.3, dan 6F.1:
- Validasi hash SHA256 sebelum eksekusi atau ekstraksi berkas biner/arsip.
- Pembacaan bertahap berbasis chunk (64 KB) agar hemat memori pada berkas berukuran gigabyte.
- Perbandingan string case-insensitive.
"""

from __future__ import annotations

import hashlib
from pathlib import Path


def calculate_sha256(filepath: str | Path, chunk_size: int = 65536) -> str:
    """Menghitung hash SHA-256 dari sebuah berkas di disk secara efisien.

    Args:
        filepath: Lokasi berkas di filesystem.
        chunk_size: Ukuran blok baca per iterasi (default 64 KB).

    Returns:
        String heksadesimal lowercase SHA-256.

    Raises:
        FileNotFoundError: Jika berkas tidak ditemukan.
        OSError: Jika terjadi kesalahan akses berkas.
    """
    path = Path(filepath)
    if not path.is_file():
        raise FileNotFoundError(f"Berkas tidak ditemukan untuk perhitungan hash: {path}")

    hasher = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(chunk_size):
            hasher.update(chunk)

    return hasher.hexdigest().lower()


def verify_sha256(filepath: str | Path, expected_hash: str | None) -> bool:
    """Memverifikasi kecocokan hash SHA-256 berkas dengan nilai yang diharapkan.

    Args:
        filepath: Lokasi berkas yang akan diperiksa.
        expected_hash: String hash yang diharapkan dari manifest/sumber resmi.
                      Jika None atau kosong, verifikasi dianggap gagal demi keamanan.

    Returns:
        True jika berkas ada dan hash cocok persis, False jika berbeda atau berkas tidak ada.
    """
    if not expected_hash or not str(expected_hash).strip():
        return False

    try:
        actual_hash = calculate_sha256(filepath)
        return actual_hash.lower() == expected_hash.strip().lower()
    except (FileNotFoundError, OSError):
        return False


def calculate_bytes_sha256(data: bytes) -> str:
    """Menghitung hash SHA-256 dari objek bytes di memori."""
    return hashlib.sha256(data).hexdigest().lower()
