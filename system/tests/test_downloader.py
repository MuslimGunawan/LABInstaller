"""Pengujian unit untuk modul pengunduh berkas (core/downloader.py)."""

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from labinstaller.core.downloader import (
    MAGIC_7Z,
    MAGIC_EXE,
    MAGIC_MSI,
    MAGIC_ZIP,
    DownloadHashMismatchError,
    DownloadHtmlResponseError,
    detect_unexpected_html,
    download_file,
    validate_magic_bytes,
)
from labinstaller.core.hasher import calculate_sha256


def test_detect_unexpected_html() -> None:
    """Memastikan deteksi respons HTML mengenali header atau konten HTML."""
    assert detect_unexpected_html(b"MZ\x90\x00", "text/html; charset=utf-8") is True
    assert (
        detect_unexpected_html(
            b"<!DOCTYPE html><html><body>Quota Exceeded</body></html>", "application/octet-stream"
        )
        is True
    )
    assert detect_unexpected_html(b"<HTML><HEAD><TITLE>Warning</TITLE></HEAD></HTML>", None) is True
    assert (
        detect_unexpected_html(MAGIC_EXE + b"\x90\x00\x03\x00", "application/x-msdownload") is False
    )
    assert detect_unexpected_html(MAGIC_ZIP + b"\x14\x00\x00\x00", "application/zip") is False


def test_validate_magic_bytes() -> None:
    """Memastikan validasi magic bytes mengenali format binary secara akurat."""
    assert validate_magic_bytes(MAGIC_EXE + b"\x00\x00", ".exe") is True
    assert validate_magic_bytes(b"INVALID_HEADER", ".exe") is False
    assert validate_magic_bytes(MAGIC_ZIP + b"\x00\x00", ".zip") is True
    assert validate_magic_bytes(MAGIC_7Z + b"\x00\x00", ".7z") is True
    assert validate_magic_bytes(MAGIC_MSI + b"\x00\x00", ".msi") is True


def test_download_file_cached(tmp_path: Path) -> None:
    """Memastikan berkas yang sudah ada dengan hash cocok tidak diunduh ulang."""
    cached_file = tmp_path / "cached_app.exe"
    cached_file.write_bytes(b"EXISTING_CACHED_BINARY_DATA")

    actual_hash = calculate_sha256(cached_file)

    # Memanggil download_file harus langsung mengembalikan path tanpa membuka koneksi jaringan
    result = download_file(
        url="https://example.com/cached_app.exe",
        target_path=cached_file,
        expected_sha256=actual_hash,
    )
    assert result == cached_file


def test_download_file_rejects_html_response(tmp_path: Path) -> None:
    """Memastikan respons HTML dari Google Drive / server kuota ditolak (PRD 6B.3)."""
    target_file = tmp_path / "installer.exe"
    html_content = b"<!DOCTYPE html><html><body>Drive download quota exceeded</body></html>"

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.headers = {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Length": str(len(html_content)),
    }
    mock_resp.read.side_effect = [html_content, b""]
    mock_resp.__enter__.return_value = mock_resp

    with patch("urllib.request.urlopen", return_value=mock_resp):
        with pytest.raises(DownloadHtmlResponseError):
            download_file(
                url="https://drive.usercontent.google.com/download?id=MOCK_ID",
                target_path=target_file,
            )

    # Pastikan file .part dihapus dan target_file tidak terbuat
    assert not target_file.exists()
    assert not target_file.with_name(target_file.name + ".part").exists()


def test_download_file_rejects_hash_mismatch(tmp_path: Path) -> None:
    """Memastikan berkas yang hash-nya tidak cocok dibatalkan dan dihapus (PRD 6B.3)."""
    target_file = tmp_path / "package.zip"
    binary_content = MAGIC_ZIP + b"CORRUPTED_DOWNLOAD_STREAM"

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.headers = {
        "Content-Type": "application/zip",
        "Content-Length": str(len(binary_content)),
    }
    mock_resp.read.side_effect = [binary_content, b""]
    mock_resp.__enter__.return_value = mock_resp

    fake_expected_hash = "1" * 64

    with patch("urllib.request.urlopen", return_value=mock_resp):
        with pytest.raises(DownloadHashMismatchError):
            download_file(
                url="https://example.com/package.zip",
                target_path=target_file,
                expected_sha256=fake_expected_hash,
            )

    assert not target_file.exists()
    assert not target_file.with_name(target_file.name + ".part").exists()


def test_download_file_success(tmp_path: Path) -> None:
    """Memastikan pengunduhan sukses menyimpan berkas dengan hash valid."""
    target_file = tmp_path / "clean_tool.exe"
    binary_content = MAGIC_EXE + b"\x90\x00\x03\x00CLEAN_TOOL_BINARY"

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.headers = {
        "Content-Type": "application/octet-stream",
        "Content-Length": str(len(binary_content)),
    }
    mock_resp.read.side_effect = [binary_content, b""]
    mock_resp.__enter__.return_value = mock_resp

    # Hitung hash yang benar
    from labinstaller.core.hasher import calculate_bytes_sha256

    correct_hash = calculate_bytes_sha256(binary_content)

    with patch("urllib.request.urlopen", return_value=mock_resp):
        res = download_file(
            url="https://example.com/clean_tool.exe",
            target_path=target_file,
            expected_sha256=correct_hash,
        )

    assert res == target_file
    assert target_file.is_file()
    assert target_file.read_bytes() == binary_content
