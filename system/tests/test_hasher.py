"""Pengujian unit untuk modul verifikasi kriptografis (core/hasher.py)."""

from pathlib import Path

from labinstaller.core.hasher import (
    calculate_bytes_sha256,
    calculate_sha256,
    verify_sha256,
)


def test_calculate_bytes_sha256() -> None:
    """Memastikan perhitungan hash bytes cocok dengan nilai acuan standar."""
    data = b"Lab Auto Installer 2026"
    expected = "d4a5be17a9a379924f250577da65d969fee85a627918864e13fbf4ec3ccd9341"
    assert calculate_bytes_sha256(data) == expected


def test_calculate_sha256_file(tmp_path: Path) -> None:
    """Memastikan perhitungan hash berkas di disk berjalan presisi."""
    sample_file = tmp_path / "sample.txt"
    sample_file.write_text("Hello Lab Installer", encoding="utf-8")

    # Hash dari "Hello Lab Installer"
    hash_val = calculate_sha256(sample_file)
    assert len(hash_val) == 64
    assert hash_val.islower()


def test_verify_sha256_matching_and_case_insensitive(tmp_path: Path) -> None:
    """Memastikan verifikasi hash case-insensitive dan mendeteksi perbedaan."""
    sample_file = tmp_path / "test.bin"
    sample_file.write_bytes(b"\x00\x01\x02\x03\x04\x05")

    actual_hash = calculate_sha256(sample_file)
    # Harus cocok baik huruf kecil maupun kapital
    assert verify_sha256(sample_file, actual_hash.lower()) is True
    assert verify_sha256(sample_file, actual_hash.upper()) is True

    # Hash salah harus ditolak
    fake_hash = "0" * 64
    assert verify_sha256(sample_file, fake_hash) is False

    # Berkas tidak ada harus menghasilkan False
    assert verify_sha256(tmp_path / "non_existent.bin", actual_hash) is False
