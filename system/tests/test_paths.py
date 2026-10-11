"""Pengujian unit untuk modul core/paths.py."""

from pathlib import Path

import pytest
from labinstaller.core import paths


def test_paths_derived_from_root() -> None:
    """Memastikan seluruh path diturunkan dari root direktori."""
    root = paths.ROOT_DIR
    assert paths.SYSTEM_DIR == root / "system"
    assert paths.APP_DIR == root / "system" / "app"
    assert paths.DATA_DIR == root / "system" / "data"
    assert paths.CONFIG_DIR == paths.APP_DIR / "config"
    assert paths.SCHEMA_DIR == paths.CONFIG_DIR / "schema"
    assert paths.START_BAT == root / "Start.bat"


def test_ensure_data_directories(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Memastikan fungsi ensure_data_directories membuat seluruh subfolder data."""
    test_data = tmp_path / "system" / "data"
    monkeypatch.setattr(paths, "DATA_DIR", test_data)
    monkeypatch.setattr(paths, "PAYLOAD_DIR", test_data / "payload")
    monkeypatch.setattr(paths, "CACHE_DIR", test_data / "cache")
    monkeypatch.setattr(paths, "CACHE_DOWNLOAD_DIR", test_data / "cache" / "download")
    monkeypatch.setattr(paths, "CACHE_EXTRACT_DIR", test_data / "cache" / "extract")
    monkeypatch.setattr(paths, "BACKUP_DIR", test_data / "backup")
    monkeypatch.setattr(paths, "LOGS_DIR", test_data / "logs")
    monkeypatch.setattr(paths, "STATE_DIR", test_data / "state")
    monkeypatch.setattr(paths, "LAST_GOOD_DIR", test_data / "state" / "last-good")

    paths.ensure_data_directories()

    assert (test_data / "logs").exists()
    assert (test_data / "cache" / "download").exists()
    assert (test_data / "state" / "last-good").exists()
