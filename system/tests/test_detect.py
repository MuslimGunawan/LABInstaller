"""Pengujian unit untuk modul deteksi (core/detect.py)."""

from typing import Any
from unittest.mock import patch

from labinstaller.core.detect import (
    AppStatus,
    RegistryAppInfo,
    compare_versions,
    detect_all_apps,
    detect_app,
    parse_version_tuple,
)


def test_parse_version_tuple() -> None:
    """Memastikan ekstraksi tuple numerik berjalan presisi untuk berbagai format versi."""
    assert parse_version_tuple("1.141.0") == (1, 141, 0)
    assert parse_version_tuple("2.55.0.windows.5") == (2, 55, 0, 5)
    assert parse_version_tuple("25") == (25,)
    assert parse_version_tuple("v4.2.2") == (4, 2, 2)
    assert parse_version_tuple("21.0.12.101") == (21, 0, 12, 101)
    assert parse_version_tuple(None) == (0,)
    assert parse_version_tuple("") == (0,)
    assert parse_version_tuple("non-numeric") == (0,)


def test_compare_versions_exact() -> None:
    """Memastikan kebijakan 'exact' mencocokkan versi secara presisi."""
    assert compare_versions("1.141.0", "1.141.0", "exact") is True
    assert compare_versions("1.141.1", "1.141.0", "exact") is False
    assert compare_versions("25", "25.0", "exact") is True
    assert compare_versions("8.5.11", "8.5.12", "exact") is False


def test_compare_versions_exact_minor() -> None:
    """Memastikan kebijakan 'exact-minor' mencocokkan mayor dan minor."""
    assert compare_versions("3.13.15", "3.13.0", "exact-minor") is True
    assert compare_versions("3.13.2", "3.13.15", "exact-minor") is True
    assert compare_versions("3.12.5", "3.13.0", "exact-minor") is False


def test_compare_versions_minimum() -> None:
    """Memastikan kebijakan 'minimum' menerima versi yang sama atau lebih baru."""
    assert compare_versions("2.55.0.5", "2.40.0.0", "minimum") is True
    assert compare_versions("2.40.0.0", "2.40.0.0", "minimum") is True
    assert compare_versions("2.39.0.0", "2.40.0.0", "minimum") is False


def test_compare_versions_latest_resolved() -> None:
    """Memastikan target 'latest-resolved' menerima sembarang versi yang ada."""
    assert compare_versions("1.0.0", "latest-resolved", "exact") is True
    assert compare_versions("", "latest-resolved", "exact") is False


def test_detect_app_not_installed() -> None:
    """Memastikan aplikasi yang tidak ada di sistem menghasilkan status BELUM_TERPASANG."""
    app_data: dict[str, Any] = {
        "id": "non_existent_app_xyz",
        "nama": "Non Existent App",
        "versiTarget": "1.0.0",
        "kebijakanVersi": "exact",
        "deteksi": {"tipe": "file", "nilai": r"C:\path\to\non_existent_binary_xyz.exe"},
        "wingetId": "NonExistent.App.XYZ",
    }
    with patch("labinstaller.core.detect.scan_windows_registry_uninstall", return_value=[]):
        with patch("labinstaller.core.detect.scan_winget_installed_list", return_value={}):
            res = detect_app(app_data, use_cache=True)
            assert res.status == AppStatus.BELUM_TERPASANG
            assert res.installed_version is None
            assert res.display_text == "Belum Terpasang"


def test_detect_app_registry_installed_and_matches() -> None:
    """Memastikan aplikasi terdeteksi via registry uninstall dan status SUDAH_TERPASANG."""
    app_data: dict[str, Any] = {
        "id": "mock_app",
        "nama": "Mock Application",
        "versiTarget": "2.0.0",
        "kebijakanVersi": "minimum",
        "deteksi": {"tipe": "command", "nilai": "mock_cmd_not_in_path"},
        "wingetId": "Mock.Application",
    }
    mock_reg = [
        RegistryAppInfo(
            display_name="Mock Application 2026",
            display_version="2.5.0",
            install_location=r"C:\Program Files\Mock",
            uninstall_string="uninstall.exe",
            quiet_uninstall_string="uninstall.exe /S",
            publisher="Mock Corp",
            hive="HKLM_64",
            key_name="{MOCK-GUID}",
            is_msi=False,
        )
    ]
    with patch("labinstaller.core.detect.scan_windows_registry_uninstall", return_value=mock_reg):
        with patch("labinstaller.core.detect.scan_winget_installed_list", return_value={}):
            res = detect_app(app_data, use_cache=True)
            assert res.status == AppStatus.SUDAH_TERPASANG
            assert res.installed_version == "2.5.0"
            assert "v2.5.0" in res.display_text
            assert "vv" not in res.display_text


def test_detect_app_needs_update() -> None:
    """Memastikan aplikasi terdeteksi versi lama menghasilkan BUTUH_UPDATE."""
    app_data: dict[str, Any] = {
        "id": "mock_old_app",
        "nama": "Old Application",
        "versiTarget": "3.0.0",
        "kebijakanVersi": "minimum",
        "deteksi": {"tipe": "command", "nilai": "old_cmd"},
        "wingetId": "Old.App",
    }
    mock_reg = [
        RegistryAppInfo(
            display_name="Old Application",
            display_version="1.5.0",
            install_location=r"C:\Program Files\OldApp",
            uninstall_string="uninstall.exe",
            quiet_uninstall_string="uninstall.exe /S",
            publisher="Old Corp",
            hive="HKLM_64",
            key_name="{OLD-GUID}",
            is_msi=False,
        )
    ]
    with patch("labinstaller.core.detect.scan_windows_registry_uninstall", return_value=mock_reg):
        with patch("labinstaller.core.detect.scan_winget_installed_list", return_value={}):
            res = detect_app(app_data, use_cache=True)
            assert res.status == AppStatus.BUTUH_UPDATE
            assert res.installed_version == "1.5.0"
            assert "Butuh Update (v1.5.0 -> v3.0.0)" in res.display_text


def test_detect_app_command_success() -> None:
    """Memastikan deteksi berbasis command berhasil mengekstrak versi."""
    app_data: dict[str, Any] = {
        "id": "mock_git",
        "nama": "Git for Windows",
        "versiTarget": "2.40.0",
        "kebijakanVersi": "minimum",
        "deteksi": {"tipe": "command", "nilai": "git", "argumen": "--version"},
        "wingetId": "Git.Git",
    }
    with patch(
        "labinstaller.core.detect.check_command_version",
        return_value=("2.45.1", r"C:\Program Files\Git\bin\git.exe"),
    ):
        with patch("labinstaller.core.detect.scan_windows_registry_uninstall", return_value=[]):
            res = detect_app(app_data, use_cache=True)
            assert res.status == AppStatus.SUDAH_TERPASANG
            assert res.installed_version == "2.45.1"
            assert res.detected_by == "command"


def test_detect_all_apps_batch() -> None:
    """Memastikan deteksi batch seluruh aplikasi menghasilkan dictionary yang lengkap."""
    sample_apps: list[dict[str, Any]] = [
        {"id": "app1", "nama": "App 1", "versiTarget": "1.0", "kebijakanVersi": "minimum"},
        {"id": "app2", "nama": "App 2", "versiTarget": "2.0", "kebijakanVersi": "minimum"},
    ]
    with patch("labinstaller.core.detect.scan_windows_registry_uninstall", return_value=[]):
        with patch("labinstaller.core.detect.scan_winget_installed_list", return_value={}):
            results = detect_all_apps(sample_apps, use_cache=True)
            assert len(results) == 2
            assert "app1" in results
            assert "app2" in results
