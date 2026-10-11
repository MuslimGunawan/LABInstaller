"""Pengujian unit untuk modul Composer dan Laravel Installer (core/composer.py)."""

from pathlib import Path
from unittest.mock import patch

from labinstaller.core.composer import (
    run_composer_post_install_hook,
    run_laravel_post_install_hook,
    setup_composer_wrapper,
    setup_multiuser_composer_env,
    verify_composer,
)


def test_setup_composer_wrapper(tmp_path: Path) -> None:
    """Memastikan setup_composer_wrapper membuat composer.bat yang memanggil php.exe secara eksplisit."""
    composer_dir = tmp_path / "composer"
    php_exe = tmp_path / "php" / "php.exe"
    php_exe.parent.mkdir(parents=True)
    php_exe.touch()

    bat_file = setup_composer_wrapper(composer_dir, php_exe=php_exe)
    assert bat_file.is_file()
    assert (composer_dir / "composer.phar").is_file()

    content = bat_file.read_text(encoding="utf-8")
    assert str(php_exe) in content
    assert str(composer_dir / "composer.phar") in content
    assert "%*" in content


def test_setup_multiuser_composer_env(tmp_path: Path) -> None:
    """Memastikan struktur multi-pengguna home, cache, dan vendor/bin terbuat dengan benar."""
    composer_dir = tmp_path / "composer"
    res = setup_multiuser_composer_env(composer_dir)

    assert (composer_dir / "home").is_dir()
    assert (composer_dir / "cache").is_dir()
    assert (composer_dir / "home" / "vendor" / "bin").is_dir()

    assert "COMPOSER_HOME" in res
    assert "COMPOSER_CACHE_DIR" in res
    assert "VENDOR_BIN" in res


def test_verify_composer_missing_bat(tmp_path: Path) -> None:
    """Memastikan verify_composer mendeteksi ketiadaan composer.bat dengan aman."""
    res = verify_composer(tmp_path)
    assert res["ok"] is False
    assert any("tidak ditemukan" in err for err in res["errors"])


def test_run_composer_post_install_hook(tmp_path: Path) -> None:
    """Memastikan run_composer_post_install_hook mengorkestrasi wrapper dan konfigurasi."""
    res = run_composer_post_install_hook(tmp_path)
    assert res.status.value == "BERHASIL"
    assert (tmp_path / "composer.bat").is_file()
    assert (tmp_path / "home").is_dir()


def test_run_laravel_post_install_hook(tmp_path: Path) -> None:
    """Memastikan run_laravel_post_install_hook mengeksekusi instalasi global Laravel."""
    with patch("labinstaller.core.composer.install_laravel_cli", return_value=(True, "OK")):
        res = run_laravel_post_install_hook(tmp_path)
        assert res.status.value == "BERHASIL"
        assert res.app_id == "laravel-installer"


def test_engine_executes_php_and_composer_hooks(tmp_path: Path) -> None:
    """Memastikan engine.py mengeksekusi hook php, composer, dan composer_laravel secara otomatis."""
    from labinstaller.core.config import ConfigManager
    from labinstaller.core.engine import AppPlanItem, PlanResult, execute_installation_plan
    from labinstaller.core.installer import InstallResult, InstallStatus

    cfg = ConfigManager()
    cfg._apps_data = {
        "apps": [
            {
                "id": "php-standalone",
                "nama": "PHP 8.5.11 Standalone",
                "kategori": "Web Stack",
                "metode": "arsip",
                "versiTarget": "8.5.11",
                "hook": "php",
                "sumber": [
                    {
                        "tipe": "resmi",
                        "url": "https://example.com/php.zip",
                        "fileId": None,
                        "prioritas": 1,
                    }
                ],
                "sha256": "abcdef",
                "ukuran": 50,
            },
            {
                "id": "composer",
                "nama": "Composer Package Manager",
                "kategori": "Web Stack",
                "metode": "exe",
                "versiTarget": "2.10.3",
                "hook": "composer",
                "sumber": [
                    {
                        "tipe": "resmi",
                        "url": "https://example.com/composer.phar",
                        "fileId": None,
                        "prioritas": 1,
                    }
                ],
                "sha256": "fedcba",
                "ukuran": 50,
            },
            {
                "id": "laravel-installer",
                "nama": "Laravel CLI Installer",
                "kategori": "Web Stack",
                "metode": "hook-only",
                "versiTarget": "latest",
                "hook": "composer_laravel",
                "sumber": [],
                "sha256": None,
                "ukuran": 0,
            },
        ]
    }

    plan = PlanResult(
        items=[
            AppPlanItem(
                app_id="php-standalone",
                nama="PHP 8.5.11 Standalone",
                kategori="Web Stack",
                versi_target="8.5.11",
                versi_terpasang=None,
                status="BELUM_TERPASANG",
                metode="arsip",
                ukuran_bytes=50,
            ),
            AppPlanItem(
                app_id="composer",
                nama="Composer Package Manager",
                kategori="Web Stack",
                versi_target="2.10.3",
                versi_terpasang=None,
                status="BELUM_TERPASANG",
                metode="exe",
                ukuran_bytes=50,
            ),
            AppPlanItem(
                app_id="laravel-installer",
                nama="Laravel CLI Installer",
                kategori="Web Stack",
                versi_target="latest",
                versi_terpasang=None,
                status="BELUM_TERPASANG",
                metode="hook-only",
                ukuran_bytes=0,
            ),
        ],
        total_download_bytes=100,
        estimasi_menit=0.1,
    )

    with (
        patch("labinstaller.core.engine.download_with_mirrors") as mock_dl,
        patch("labinstaller.core.engine.extract_archive"),
        patch(
            "labinstaller.core.native_installer.NativeInstaller.install_file",
            return_value=InstallResult(
                app_id="composer", app_name="Composer", status=InstallStatus.BERHASIL, message="OK"
            ),
        ),
        patch("labinstaller.core.engine.run_php_post_install_hook") as mock_php_hook,
        patch("labinstaller.core.engine.run_composer_post_install_hook") as mock_composer_hook,
        patch("labinstaller.core.engine.run_laravel_post_install_hook") as mock_laravel_hook,
    ):
        mock_dl.return_value.success = True
        mock_dl.return_value.file_path = tmp_path / "dummy.file"
        (tmp_path / "dummy.file").touch()

        mock_php_hook.return_value = InstallResult(
            app_id="php-standalone",
            app_name="PHP",
            status=InstallStatus.BERHASIL,
            message="PHP Hook OK",
        )
        mock_composer_hook.return_value = InstallResult(
            app_id="composer",
            app_name="Composer",
            status=InstallStatus.BERHASIL,
            message="Composer Hook OK",
        )
        mock_laravel_hook.return_value = InstallResult(
            app_id="laravel-installer",
            app_name="Laravel",
            status=InstallStatus.BERHASIL,
            message="Laravel Hook OK",
        )

        results = execute_installation_plan(plan, cfg)

        assert len(results) == 3
        assert all(r.status == InstallStatus.BERHASIL for r in results)
        mock_php_hook.assert_called_once()
        mock_composer_hook.assert_called_once()
        mock_laravel_hook.assert_called_once()
