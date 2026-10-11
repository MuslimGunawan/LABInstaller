"""Pengujian unit untuk modul core/preflight.py."""

from pathlib import Path

from labinstaller.core import preflight


def test_windows_version_check() -> None:
    """Memastikan pengecekan versi OS Windows berjalan tanpa error."""
    ok, msg = preflight.check_windows_version()
    assert isinstance(ok, bool)
    assert isinstance(msg, str)


def test_disk_space_calculation(tmp_path: Path) -> None:
    """Memastikan kalkulasi ruang disk menyertakan margin 30%."""
    cukup, bebas, butuh = preflight.check_disk_space(
        target_dir=tmp_path,
        required_bytes=1000,
        margin_percent=30.0,
    )
    assert butuh == 1300
    assert isinstance(bebas, int)
    assert isinstance(cukup, bool)


def test_preflight_checks_execution(tmp_path: Path) -> None:
    """Memastikan run_preflight_checks mengembalikan struktur PreflightResult lengkap."""
    result = preflight.run_preflight_checks(
        target_drive=tmp_path,
        estimated_download_bytes=1000000,
    )
    assert isinstance(result.lulus, bool)
    assert isinstance(result.issues, list)
    assert isinstance(result.free_disk_bytes, int)
