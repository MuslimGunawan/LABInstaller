"""Pengujian unit untuk modul core/engine.py."""

from labinstaller.core.config import ConfigManager
from labinstaller.core.engine import (
    build_execution_plan,
    resolve_dependencies,
    run_dry_run,
    run_selftest,
)


def test_resolve_dependencies_ordering() -> None:
    """Memastikan urutan dependensi diselesaikan dengan benar (dependensi sebelum dependen)."""
    mock_apps = {
        "app_c": {"id": "app_c", "nama": "App C", "dependensi": ["app_b"]},
        "app_b": {"id": "app_b", "nama": "App B", "dependensi": ["app_a"]},
        "app_a": {"id": "app_a", "nama": "App A", "dependensi": []},
    }

    resolved, reasons = resolve_dependencies(["app_c"], mock_apps)
    assert resolved == ["app_a", "app_b", "app_c"]
    assert "app_a" in reasons
    assert "app_b" in reasons


def test_build_execution_plan_with_config() -> None:
    """Memastikan pembuatan rencana eksekusi dari ConfigManager menghasilkan total unduhan dan estimasi menit."""
    cm = ConfigManager()
    cm.load_all()

    plan = build_execution_plan(["vscode", "git"], cm)
    assert len(plan.items) >= 2
    assert plan.total_download_bytes > 0
    assert plan.estimasi_menit > 0


def test_run_dry_run_execution() -> None:
    """Memastikan run_dry_run mengembalikan exit code 0."""
    cm = ConfigManager()
    cm.load_all()

    code = run_dry_run(["vscode"], cm, profile_name="Uji Dry Run")
    assert code == 0


def test_run_selftest_execution() -> None:
    """Memastikan run_selftest memverifikasi seluruh komponen dan mengembalikan exit code 0."""
    code = run_selftest()
    assert code == 0
