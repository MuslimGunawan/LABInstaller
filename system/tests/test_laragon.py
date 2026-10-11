"""Pengujian unit untuk modul penanganan khusus Laragon 6 (core/laragon.py)."""

import shutil
from pathlib import Path
from unittest.mock import patch

from labinstaller.core.hasher import calculate_bytes_sha256
from labinstaller.core.laragon import (
    adjust_laragon_config,
    apply_custom_bin,
    backup_laragon,
    install_laragon_marker,
    rollback_laragon_bin,
    run_laragon_post_install_hook,
    validate_custom_payload,
    verify_laragon_binaries,
)


def test_validate_custom_payload_valid_and_invalid(tmp_path: Path) -> None:
    """Memastikan validasi payload custom bin mengenali struktur yang valid dan menolak yang rusak."""
    # 1. Payload kosong / struktur tidak valid
    empty_payload = tmp_path / "empty_payload"
    empty_payload.mkdir()
    valid, reason = validate_custom_payload(empty_payload)
    assert valid is False
    assert "tidak valid" in reason

    # 2. Payload valid (memiliki folder bin/php)
    valid_payload = tmp_path / "valid_payload"
    (valid_payload / "bin" / "php" / "php-8.5.11").mkdir(parents=True)
    valid, reason = validate_custom_payload(valid_payload)
    assert valid is True

    # 3. Payload berkas arsip dengan hash cocok
    archive_file = tmp_path / "custom.zip"
    archive_file.write_bytes(b"Simulated Zip Content")
    correct_hash = calculate_bytes_sha256(b"Simulated Zip Content")

    valid_arch, _ = validate_custom_payload(archive_file, expected_sha256=correct_hash)
    assert valid_arch is True

    # 4. Payload berkas arsip dengan hash salah
    invalid_arch, reason_arch = validate_custom_payload(
        archive_file, expected_sha256="wrong_hash_val"
    )
    assert invalid_arch is False
    assert "tidak cocok" in reason_arch


def test_backup_and_rollback_laragon(tmp_path: Path) -> None:
    """Memastikan pencadangan dan rollback folder bin Laragon bekerja secara aman dan utuh."""
    laragon_dir = tmp_path / "laragon"
    bin_dir = laragon_dir / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "original_file.txt").write_text("Versi Asli 1.0", encoding="utf-8")

    backup_root = tmp_path / "backup"
    backup_bin, _ = backup_laragon(laragon_dir, backup_root=backup_root)

    assert backup_bin is not None
    assert backup_bin.is_dir()
    assert (backup_bin / "original_file.txt").read_text(encoding="utf-8") == "Versi Asli 1.0"

    # Simulasikan kerusakan pada folder bin
    (bin_dir / "original_file.txt").write_text("Terkorupsi", encoding="utf-8")

    # Jalankan rollback
    success = rollback_laragon_bin(laragon_dir, backup_bin)
    assert success is True
    assert (bin_dir / "original_file.txt").read_text(encoding="utf-8") == "Versi Asli 1.0"


def test_apply_custom_bin_success(tmp_path: Path) -> None:
    """Memastikan penimpaan custom bin dari payload berhasil menyalin biner baru."""
    laragon_dir = tmp_path / "laragon"
    bin_dir = laragon_dir / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "old_php.txt").write_text("Old PHP", encoding="utf-8")

    payload_dir = tmp_path / "payload"
    (payload_dir / "bin" / "php" / "php-8.5.11").mkdir(parents=True)
    (payload_dir / "bin" / "php" / "php-8.5.11" / "php.exe").write_bytes(b"\x90\x90")

    backup_dir = tmp_path / "backup" / "laragon-bin-bak"
    backup_dir.mkdir(parents=True)
    (backup_dir / "old_php.txt").write_text("Old PHP", encoding="utf-8")

    success = apply_custom_bin(laragon_dir, payload_dir, backup_bin_dir=backup_dir)
    assert success is True

    # Pastikan file PHP baru masuk ke C:\laragon\bin
    new_php = laragon_dir / "bin" / "php" / "php-8.5.11" / "php.exe"
    assert new_php.is_file()


def test_apply_custom_bin_failure_triggers_automatic_rollback(tmp_path: Path) -> None:
    """Memastikan kegagalan di tengah penimpaan memicu rollback otomatis dan memulihkan kondisi awal."""
    laragon_dir = tmp_path / "laragon"
    bin_dir = laragon_dir / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "safe_file.txt").write_text("Safe Original", encoding="utf-8")

    backup_dir = tmp_path / "backup_bin"
    backup_dir.mkdir(parents=True)
    (backup_dir / "safe_file.txt").write_text("Safe Original", encoding="utf-8")

    # Payload dengan struktur valid
    payload_dir = tmp_path / "payload"
    (payload_dir / "bin" / "php").mkdir(parents=True)

    # Simulasikan exception di tengah penyalinan (gagal pada call pertama, berhasil pada rollback)
    real_copytree = shutil.copytree
    call_count = 0

    def mock_copytree(src: object, dst: object, **kwargs: object) -> object:
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise OSError("Disk write error simulasi")
        return real_copytree(src, dst, **kwargs)

    with patch("shutil.copytree", side_effect=mock_copytree):
        success = apply_custom_bin(laragon_dir, payload_dir, backup_bin_dir=backup_dir)

    assert success is False
    # Folder bin harus terpulihkan kembali dari backup
    assert (laragon_dir / "bin" / "safe_file.txt").read_text(encoding="utf-8") == "Safe Original"


def test_adjust_laragon_config(tmp_path: Path) -> None:
    """Memastikan penyesuaian laragon.ini dan php.ini berjalan otomatis dan idempoten."""
    laragon_dir = tmp_path / "laragon"
    usr_dir = laragon_dir / "usr"
    usr_dir.mkdir(parents=True)
    ini_file = usr_dir / "laragon.ini"
    ini_file.write_text("[Laragon]\nPHP=php-7.4.0\n", encoding="utf-8")

    # Buat folder PHP baru di bin\php\
    php_dir = laragon_dir / "bin" / "php" / "php-8.5.11"
    php_dir.mkdir(parents=True)
    php_ini = php_dir / "php.ini-development"
    php_ini.write_text(';extension_dir = "ext"\n;extension=mysqli\n', encoding="utf-8")

    changes = adjust_laragon_config(laragon_dir)
    assert len(changes) >= 1

    # laragon.ini harus merujuk ke php-8.5.11
    updated_ini = ini_file.read_text(encoding="utf-8")
    assert "PHP=php-8.5.11" in updated_ini

    # php.ini harus memiliki extension_dir = "ext" dan extension=mysqli
    created_php_ini = (php_dir / "php.ini").read_text(encoding="utf-8")
    assert 'extension_dir = "ext"' in created_php_ini
    assert "extension=mysqli" in created_php_ini


def test_install_laragon_marker(tmp_path: Path) -> None:
    """Memastikan halaman penanda lab-check.php dipasang di www dengan format yang tepat."""
    laragon_dir = tmp_path / "laragon"
    marker = install_laragon_marker(laragon_dir)

    assert marker.is_file()
    assert marker.name == "lab-check.php"
    content = marker.read_text(encoding="utf-8")
    assert "STACK=LARAGON" in content
    assert "DB_PORT=3306" in content
    assert "SERVER_PORT" in content


def test_run_laragon_post_install_hook_with_broken_payload(tmp_path: Path) -> None:
    """Memastikan hook dengan payload rusak membatalkan penimpaan dan membiarkan Laragon utuh (PRD 7.1 #3)."""
    laragon_dir = tmp_path / "laragon"
    bin_dir = laragon_dir / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "standard_laragon.txt").write_text("Standar", encoding="utf-8")

    # Payload rusak (kosong tanpa bin)
    broken_payload = tmp_path / "broken_payload"
    broken_payload.mkdir()

    res = run_laragon_post_install_hook(
        laragon_dir=laragon_dir,
        custom_payload_override=broken_payload,
    )

    assert res.status.value == "BERHASIL"
    assert "penimpaan dibatalkan" in res.message
    # File standar tetap utuh
    assert (bin_dir / "standard_laragon.txt").read_text(encoding="utf-8") == "Standar"
    # lab-check.php tetap terpasang
    assert (laragon_dir / "www" / "lab-check.php").is_file()


def test_run_laragon_post_install_hook_with_valid_payload(tmp_path: Path) -> None:
    """Memastikan hook dengan payload valid berhasil menimpa bin, menyesuaikan config, dan memasang marker."""
    laragon_dir = tmp_path / "laragon"
    bin_dir = laragon_dir / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "old_laragon.txt").write_text("Standar Lama", encoding="utf-8")
    (laragon_dir / "usr").mkdir(parents=True)
    (laragon_dir / "usr" / "laragon.ini").write_text("[Laragon]\nPHP=php-7.4.0\n", encoding="utf-8")

    # Valid payload
    valid_payload = tmp_path / "custom_bin"
    php_dir = valid_payload / "bin" / "php" / "php-8.5.11"
    php_dir.mkdir(parents=True)
    (php_dir / "php.exe").write_bytes(b"\x90\x90")
    (php_dir / "php.ini-development").write_text(
        ';extension_dir = "ext"\n;extension=curl\n', encoding="utf-8"
    )

    res = run_laragon_post_install_hook(
        laragon_dir=laragon_dir,
        custom_payload_override=valid_payload,
    )

    assert res.status.value == "BERHASIL"
    assert (laragon_dir / "bin" / "php" / "php-8.5.11" / "php.exe").is_file()
    assert (laragon_dir / "www" / "lab-check.php").is_file()
    assert "PHP=php-8.5.11" in (laragon_dir / "usr" / "laragon.ini").read_text(encoding="utf-8")


def test_engine_executes_laragon_hook(tmp_path: Path) -> None:
    """Memastikan engine.py secara otomatis memanggil run_laragon_post_install_hook setelah instalasi sukses."""
    from labinstaller.core.config import ConfigManager
    from labinstaller.core.engine import AppPlanItem, PlanResult, execute_installation_plan
    from labinstaller.core.installer import InstallResult, InstallStatus

    cfg = ConfigManager()
    cfg._apps_data = {
        "apps": [
            {
                "id": "laragon",
                "nama": "Laragon 6 WAMP Stack",
                "kategori": "Web Stack",
                "metode": "exe",
                "versiTarget": "6.0.0",
                "hook": "laragon",
                "sumber": [
                    {
                        "tipe": "resmi",
                        "url": "https://example.com/laragon.exe",
                        "fileId": None,
                        "prioritas": 1,
                    }
                ],
                "sha256": "abcdef",
                "ukuran": 100,
            }
        ]
    }

    plan = PlanResult(
        items=[
            AppPlanItem(
                app_id="laragon",
                nama="Laragon 6 WAMP Stack",
                kategori="Web Stack",
                versi_target="6.0.0",
                versi_terpasang=None,
                status="BELUM_TERPASANG",
                metode="exe",
                ukuran_bytes=100,
            )
        ],
        total_download_bytes=100,
        estimasi_menit=0.1,
    )

    with (
        patch(
            "labinstaller.core.native_installer.NativeInstaller.install_file",
            return_value=InstallResult(
                app_id="laragon", app_name="Laragon", status=InstallStatus.BERHASIL, message="OK"
            ),
        ),
        patch("labinstaller.core.engine.download_with_mirrors") as mock_dl,
        patch("labinstaller.core.engine.run_laragon_post_install_hook") as mock_hook,
    ):
        mock_dl.return_value.success = True
        mock_dl.return_value.file_path = tmp_path / "laragon.exe"
        (tmp_path / "laragon.exe").touch()

        mock_hook.return_value = InstallResult(
            app_id="laragon",
            app_name="Laragon 6 WAMP Stack",
            status=InstallStatus.BERHASIL,
            message="Hook Laragon Selesai",
        )

        results = execute_installation_plan(plan, cfg)

        assert len(results) == 1
        assert results[0].status == InstallStatus.BERHASIL
        assert "Hook: Hook Laragon Selesai" in results[0].message
        mock_hook.assert_called_once()


def test_verify_laragon_binaries(tmp_path: Path) -> None:
    """Memastikan verify_laragon_binaries memeriksa biner php, apache, dan mysql."""
    laragon_dir = tmp_path / "laragon"
    res_empty = verify_laragon_binaries(laragon_dir)
    assert res_empty["ok"] is False

    # Mock struktur bin dengan php dummy
    bin_php = laragon_dir / "bin" / "php" / "php-8.5.11"
    bin_php.mkdir(parents=True)
    php_exe = bin_php / "php.exe"
    php_exe.write_bytes(b"\x90\x90")

    res = verify_laragon_binaries(laragon_dir)
    assert isinstance(res["messages"], list)
