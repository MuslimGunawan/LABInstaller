"""Pengujian unit untuk modul ekstraksi mandiri dan keamanan Zip Slip (core/archive.py)."""

import zipfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from labinstaller.core.archive import (
    ExpectedFileNotFoundError,
    ZipSlipSecurityError,
    check_extracted_ok_marker,
    extract_archive,
    is_safe_extraction_path,
)


def test_is_safe_extraction_path(tmp_path: Path) -> None:
    """Memastikan filter path mendeteksi traversal berbahaya dan menerima path aman."""
    target_dir = tmp_path / "target"
    target_dir.mkdir()

    # Path aman
    assert is_safe_extraction_path(target_dir, "file.txt") is True
    assert is_safe_extraction_path(target_dir, "sub/dir/app.exe") is True
    assert is_safe_extraction_path(target_dir, "sub\\dir\\config.ini") is True

    # Path berbahaya (Zip Slip)
    assert is_safe_extraction_path(target_dir, "../outside.txt") is False
    assert is_safe_extraction_path(target_dir, "dir/../../outside.txt") is False
    assert is_safe_extraction_path(target_dir, "/etc/passwd") is False
    assert is_safe_extraction_path(target_dir, "C:\\Windows\\system32\\calc.exe") is False
    assert is_safe_extraction_path(target_dir, "\\evil.exe") is False


def test_extract_zip_clean(tmp_path: Path) -> None:
    """Memastikan ekstraksi arsip .zip bersih berjalan sukses dan menuliskan .extracted-ok."""
    archive_path = tmp_path / "clean_package.zip"
    staging_dir = tmp_path / "staging_clean"

    # Buat arsip zip uji
    with zipfile.ZipFile(archive_path, "w") as zf:
        zf.writestr("bin/app.exe", b"MOCK_APP_BINARY")
        zf.writestr("readme.txt", b"Panduan instalasi")

    result_dir = extract_archive(
        archive_path=archive_path,
        staging_dir=staging_dir,
        archive_format="zip",
        expected_files=["bin/app.exe", "readme.txt"],
    )

    assert result_dir == staging_dir
    assert (staging_dir / "bin" / "app.exe").is_file()
    assert (staging_dir / "readme.txt").is_file()
    assert check_extracted_ok_marker(staging_dir, None) is True


def test_extract_zip_rejects_zip_slip(tmp_path: Path) -> None:
    """Memastikan arsip yang memuat Zip Slip ditolak secara tegas (PRD 6F.3)."""
    malicious_zip = tmp_path / "malicious.zip"
    staging_dir = tmp_path / "staging_slip"
    outside_file = tmp_path / "escaped.txt"

    # Buat arsip zip jahat yang memuat entri "../escaped.txt"
    with zipfile.ZipFile(malicious_zip, "w") as zf:
        # Menulis entri dengan path traversal
        zinfo = zipfile.ZipInfo("../escaped.txt")
        zf.writestr(zinfo, b"MALICIOUS_CONTENT_OUTSIDE_STAGING")
        zf.writestr("valid.txt", b"VALID_CONTENT")

    # Ekstraksi wajib memicu ZipSlipSecurityError
    with pytest.raises(ZipSlipSecurityError):
        extract_archive(
            archive_path=malicious_zip,
            staging_dir=staging_dir,
            archive_format="zip",
        )

    # Pastikan tidak ada berkas yang bocor ke luar staging
    assert not outside_file.exists()


def test_idempotent_marker_reuse(tmp_path: Path) -> None:
    """Memastikan staging yang sudah lengkap dan berpenanda dipakai ulang tanpa ekstraksi ulang."""
    archive_path = tmp_path / "idempotent.zip"
    staging_dir = tmp_path / "staging_idem"

    with zipfile.ZipFile(archive_path, "w") as zf:
        zf.writestr("data.bin", b"DATA")

    # Ekstraksi pertama
    extract_archive(archive_path, staging_dir, "zip")
    assert (staging_dir / "data.bin").is_file()

    # Modifikasi isi file staging untuk membuktikan tidak tertimpa pada panggilan kedua
    (staging_dir / "data.bin").write_bytes(b"MODIFIED_STAGING_CONTENT")

    # Ekstraksi kedua (idempoten)
    extract_archive(archive_path, staging_dir, "zip")
    assert (staging_dir / "data.bin").read_bytes() == b"MODIFIED_STAGING_CONTENT"


def test_expected_files_validation_fails(tmp_path: Path) -> None:
    """Memastikan ketiadaan berkas yang dideklarasikan dalam isiDiharapkan memicu galat."""
    archive_path = tmp_path / "missing_target.zip"
    staging_dir = tmp_path / "staging_missing"

    with zipfile.ZipFile(archive_path, "w") as zf:
        zf.writestr("other.txt", b"OTHER")

    with pytest.raises(ExpectedFileNotFoundError):
        extract_archive(
            archive_path=archive_path,
            staging_dir=staging_dir,
            archive_format="zip",
            expected_files=["setup/setup.exe"],
        )


def test_extract_7z_with_mock(tmp_path: Path) -> None:
    """Memastikan ekstraksi format 7z memanggil binary 7-Zip dengan argumen yang benar."""
    archive_path = tmp_path / "archive.7z"
    archive_path.write_bytes(b"7z_DUMMY_DATA")
    staging_dir = tmp_path / "staging_7z"

    mock_proc = MagicMock()
    mock_proc.returncode = 0

    with patch("labinstaller.core.archive.find_7z_binary", return_value=Path("mock_7z.exe")):
        with patch("subprocess.run", return_value=mock_proc) as mock_run:
            extract_archive(archive_path, staging_dir, archive_format="7z")
            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            assert "mock_7z.exe" in args[0]
            assert "x" in args
            assert "-y" in args
