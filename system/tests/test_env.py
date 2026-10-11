"""Pengujian unit untuk modul variabel lingkungan sistem (core/env.py)."""

import os
from pathlib import Path
from unittest.mock import MagicMock, patch

from labinstaller.core.env import (
    append_system_path,
    broadcast_setting_change,
    get_system_environment_variable,
    prepend_system_path,
    set_system_environment_variable,
)


def test_prepend_system_path_idempotent(tmp_path: Path) -> None:
    """Memastikan prepend_system_path menempatkan path di urutan paling depan dan tidak menduplikasi."""
    test_dir = tmp_path / "php"
    test_dir.mkdir()

    mock_key = MagicMock()
    with (
        patch("winreg.OpenKey", return_value=mock_key),
        patch("winreg.SetValueEx"),
        patch("winreg.CloseKey"),
        patch("winreg.QueryValueEx", return_value=("C:\\Windows", 1)),
    ):
        # Panggilan pertama
        ok1 = prepend_system_path(test_dir, broadcast=False)
        assert ok1 is True
        assert os.environ["PATH"].startswith(str(test_dir.resolve()))

        # Panggilan kedua (idempoten)
        ok2 = prepend_system_path(test_dir, broadcast=False)
        assert ok2 is True

        # Hitung jumlah kemunculan di PATH
        entries = [
            p for p in os.environ["PATH"].split(";") if p.lower() == str(test_dir.resolve()).lower()
        ]
        assert len(entries) == 1


def test_append_system_path(tmp_path: Path) -> None:
    """Memastikan append_system_path menambahkan path di akhir PATH sistem."""
    tool_dir = tmp_path / "tools"
    tool_dir.mkdir()

    mock_key = MagicMock()
    with (
        patch("winreg.OpenKey", return_value=mock_key),
        patch("winreg.SetValueEx"),
        patch("winreg.CloseKey"),
        patch("winreg.QueryValueEx", return_value=("C:\\Windows", 1)),
    ):
        ok = append_system_path(tool_dir, broadcast=False)
        assert ok is True
        assert str(tool_dir.resolve()) in os.environ["PATH"]

        # Panggilan berulang tidak menggandakan
        append_system_path(tool_dir, broadcast=False)
        count = sum(
            1 for p in os.environ["PATH"].split(";") if p.lower() == str(tool_dir.resolve()).lower()
        )
        assert count == 1


def test_set_and_get_system_environment_variable() -> None:
    """Memastikan set_system_environment_variable dan get_system_environment_variable bekerja konsisten."""
    mock_key = MagicMock()
    with (
        patch("winreg.OpenKey", return_value=mock_key),
        patch("winreg.SetValueEx"),
        patch("winreg.CloseKey"),
    ):
        ok = set_system_environment_variable("LAB_TEST_VAR", "NilaiUji123", broadcast=False)
        assert ok is True
        assert os.environ.get("LAB_TEST_VAR") == "NilaiUji123"

    with (
        patch("winreg.OpenKey", return_value=mock_key),
        patch("winreg.QueryValueEx", return_value=("NilaiUji123", 1)),
        patch("winreg.CloseKey"),
    ):
        val = get_system_environment_variable("LAB_TEST_VAR")
        assert val == "NilaiUji123"


def test_broadcast_setting_change() -> None:
    """Memastikan penyiaran WM_SETTINGCHANGE dapat dieksekusi secara aman."""
    res = broadcast_setting_change("Environment", timeout_ms=500)
    assert isinstance(res, bool)
