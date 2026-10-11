"""Pengujian unit untuk modul core/config.py."""

import json
from pathlib import Path

import pytest
from labinstaller.core import config


def test_real_configs_valid_against_schema() -> None:
    """Memastikan semua berkas konfigurasi bawaan rilis valid terhadap skemanya."""
    all_ok, reports = config.check_all_configs()
    for r in reports:
        print(r)
    assert all_ok is True


def test_bom_tolerance(tmp_path: Path) -> None:
    """Memastikan berkas JSON dengan UTF-8 BOM terbaca tanpa error."""
    bom_file = tmp_path / "bom_test.json"
    content = '{"test": "berhasil"}'
    # Tulis dengan encoding utf-8-sig
    bom_file.write_text(content, encoding="utf-8-sig")

    data, err = config.load_json_file(bom_file)
    assert err is None
    assert data == {"test": "berhasil"}


def test_broken_json_syntax_reporting(tmp_path: Path) -> None:
    """Memastikan syntax error JSON menghasilkan laporan baris dan kolom yang jelas."""
    bad_file = tmp_path / "broken.json"
    bad_file.write_text('{\n  "nama": "test",\n  "salah": \n}', encoding="utf-8")

    data, err = config.load_json_file(bad_file)
    assert data is None
    assert err is not None
    assert err.line == 4 or err.line == 3
    assert err.column is not None


def test_fallback_to_last_good(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Memastikan program menggunakan last-good jika berkas config diedit dan menjadi rusak."""
    cfg_file = tmp_path / "test_cfg.json"
    schema_file = tmp_path / "test_cfg.schema.json"
    last_good_dir = tmp_path / "last-good"
    last_good_dir.mkdir()

    monkeypatch.setattr(config, "LAST_GOOD_DIR", last_good_dir)

    # 1. Buat skema sederhana
    schema_file.write_text(
        json.dumps(
            {
                "$schema": "http://json-schema.org/draft-07/schema#",
                "type": "object",
                "required": ["versi"],
                "properties": {"versi": {"type": "string"}},
            }
        ),
        encoding="utf-8",
    )

    # 2. Muat versi yang valid pertama kali -> disimpan ke last-good
    cfg_file.write_text(json.dumps({"versi": "1.0.0"}), encoding="utf-8")
    data, is_fallback, warn = config.load_config_with_fallback(cfg_file, schema_file)
    assert is_fallback is False
    assert data["versi"] == "1.0.0"
    assert (last_good_dir / "test_cfg.json").exists()

    # 3. Rusak file konfigurasi utama
    cfg_file.write_text("{ broken json: true", encoding="utf-8")

    # 4. Muat ulang -> harus memulihkan dari last-good tanpa crash
    data2, is_fallback2, warn2 = config.load_config_with_fallback(cfg_file, schema_file)
    assert is_fallback2 is True
    assert data2["versi"] == "1.0.0"
    assert warn2 is not None
