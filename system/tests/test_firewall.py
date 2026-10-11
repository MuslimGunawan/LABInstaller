"""Pengujian unit untuk modul Windows Firewall (core/firewall.py)."""

from pathlib import Path
from unittest.mock import patch

from labinstaller.core.firewall import (
    add_firewall_rule,
    delete_firewall_rule,
    ensure_stack_firewall_rules,
)


def test_add_firewall_rule_missing_binary(tmp_path: Path) -> None:
    """Memastikan add_firewall_rule menolak biner yang tidak ada."""
    missing = tmp_path / "nonexistent.exe"
    ok = add_firewall_rule("Uji Rule", missing)
    assert ok is False


def test_add_firewall_rule_mocked_success(tmp_path: Path) -> None:
    """Memastikan add_firewall_rule memanggil netsh advfirewall dengan parameter yang benar."""
    exe_file = tmp_path / "httpd.exe"
    exe_file.write_bytes(b"\x90\x90")

    with patch("subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        ok = add_firewall_rule("LabInstaller - Test Apache", exe_file)

        assert ok is True
        mock_run.assert_called_once()
        cmd = mock_run.call_args[0][0]
        assert "netsh" in cmd
        assert "advfirewall" in cmd
        assert "name=LabInstaller - Test Apache" in cmd
        assert f"program={str(exe_file)}" in cmd


def test_delete_firewall_rule_mocked() -> None:
    """Memastikan delete_firewall_rule memanggil netsh advfirewall delete."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value.returncode = 0
        ok = delete_firewall_rule("LabInstaller - Test")
        assert ok is True
        cmd = mock_run.call_args[0][0]
        assert "delete" in cmd
        assert "name=LabInstaller - Test" in cmd


def test_ensure_stack_firewall_rules(tmp_path: Path) -> None:
    """Memastikan ensure_stack_firewall_rules menemukan httpd.exe dan mysqld.exe serta membuat aturan."""
    stack_dir = tmp_path / "xampp"
    httpd_exe = stack_dir / "apache" / "bin" / "httpd.exe"
    mysqld_exe = stack_dir / "mysql" / "bin" / "mysqld.exe"
    httpd_exe.parent.mkdir(parents=True)
    mysqld_exe.parent.mkdir(parents=True)
    httpd_exe.write_bytes(b"\x90\x90")
    mysqld_exe.write_bytes(b"\x90\x90")

    with patch("labinstaller.core.firewall.add_firewall_rule", return_value=True) as mock_add:
        rules = ensure_stack_firewall_rules("XAMPP", stack_dir)

        assert len(rules) == 2
        assert any("Apache" in r for r in rules)
        assert any("MySQL" in r for r in rules)
        assert mock_add.call_count == 2
