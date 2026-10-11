"""Pengujian unit untuk eksekutor paket biner non-Winget (core/native_installer.py)."""

from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

from labinstaller.core.detect import AppStatus, DetectionResult
from labinstaller.core.hasher import calculate_sha256
from labinstaller.core.installer import InstallStatus
from labinstaller.core.native_installer import NativeInstaller


def test_build_command_exe_with_quoted_args(tmp_path: Path) -> None:
    """Memastikan tokenisasi argumen installer .exe menangani tanda kutip ganda."""
    installer = NativeInstaller()
    exe_file = tmp_path / "setup.exe"
    exe_file.touch()

    app_data: dict[str, Any] = {
        "id": "vscode",
        "metode": "exe",
        "silentArgs": '/VERYSILENT /NORESTART /MERGETASKS="!runcode,desktopicon"',
    }

    cmd = installer.build_command(exe_file, app_data)
    assert cmd[0] == str(exe_file)
    assert "/VERYSILENT" in cmd
    assert "/NORESTART" in cmd
    assert '/MERGETASKS="!runcode,desktopicon"' in cmd


def test_build_command_msi(tmp_path: Path) -> None:
    """Memastikan argumen msiexec tersusun secara baku untuk paket .msi."""
    installer = NativeInstaller()
    msi_file = tmp_path / "package.msi"
    msi_file.touch()

    app_data: dict[str, Any] = {
        "id": "nodejs",
        "metode": "msi",
        "silentArgs": "/qn /norestart",
    }

    cmd = installer.build_command(msi_file, app_data)
    assert cmd[0] == "msiexec.exe"
    assert "/i" in cmd
    assert str(msi_file) in cmd
    assert "/qn" in cmd
    assert "/norestart" in cmd


def test_install_file_dry_run(tmp_path: Path) -> None:
    """Memastikan mode dry-run mensimulasikan eksekusi dan mengembalikan BERHASIL."""
    installer = NativeInstaller(dry_run=True)
    exe_file = tmp_path / "installer.exe"
    exe_file.touch()

    app_data: dict[str, Any] = {
        "id": "test_app",
        "nama": "Test App",
        "versiTarget": "1.0.0",
        "metode": "exe",
    }

    with patch(
        "labinstaller.core.native_installer.detect_app",
        return_value=DetectionResult(
            app_id="test_app",
            status=AppStatus.BELUM_TERPASANG,
            installed_version=None,
            target_version="1.0.0",
            policy="minimum",
        ),
    ):
        res = installer.install_file(exe_file, app_data)
        assert res.status == InstallStatus.BERHASIL
        assert "[Simulasi Dry-Run]" in res.message


def test_install_file_sha256_mismatch_rejected(tmp_path: Path) -> None:
    """Memastikan berkas dengan hash tidak cocok ditolak sebelum eksekusi (PRD 6.2 #2)."""
    installer = NativeInstaller(dry_run=False)
    exe_file = tmp_path / "corrupt_installer.exe"
    exe_file.write_bytes(b"CORRUPTED_INSTALLER_BINARY")

    app_data: dict[str, Any] = {
        "id": "app_corrupt",
        "nama": "Corrupted App",
        "versiTarget": "1.0.0",
        "metode": "exe",
        "sha256": "0" * 64,  # Hash yang salah
    }

    with patch(
        "labinstaller.core.native_installer.detect_app",
        return_value=DetectionResult(
            app_id="app_corrupt",
            status=AppStatus.BELUM_TERPASANG,
            installed_version=None,
            target_version="1.0.0",
            policy="minimum",
        ),
    ):
        res = installer.install_file(exe_file, app_data)
        assert res.status == InstallStatus.GAGAL
        assert "tidak cocok dengan manifest" in res.message


def test_install_file_reboot_required_3010(tmp_path: Path) -> None:
    """Memastikan exit code 3010 menghasilkan status BUTUH_REBOOT."""
    installer = NativeInstaller(dry_run=False)
    exe_file = tmp_path / "vcredist.exe"
    exe_file.write_bytes(b"VCREDIST_DATA")

    actual_hash = calculate_sha256(exe_file)
    app_data: dict[str, Any] = {
        "id": "vcredist",
        "nama": "VC++ Redistributable",
        "versiTarget": "14.51",
        "metode": "exe",
        "sha256": actual_hash,
    }

    mock_pre = DetectionResult(
        app_id="vcredist",
        status=AppStatus.BELUM_TERPASANG,
        installed_version=None,
        target_version="14.51",
        policy="minimum",
    )
    mock_post = DetectionResult(
        app_id="vcredist",
        status=AppStatus.SUDAH_TERPASANG,
        installed_version="14.51",
        target_version="14.51",
        policy="minimum",
    )

    mock_proc = MagicMock()
    mock_proc.stdout = None
    mock_proc.wait.return_value = 3010
    mock_proc.returncode = 3010

    with patch(
        "labinstaller.core.native_installer.detect_app",
        side_effect=[mock_pre, mock_post],
    ):
        with patch("subprocess.Popen", return_value=mock_proc):
            res = installer.install_file(exe_file, app_data)
            assert res.status == InstallStatus.BUTUH_REBOOT
            assert res.needs_reboot is True


def test_install_file_already_running_1618(tmp_path: Path) -> None:
    """Memastikan exit code 1618 (installer lain berjalan) dilaporkan dengan tepat."""
    installer = NativeInstaller(dry_run=False)
    exe_file = tmp_path / "app.exe"
    exe_file.write_bytes(b"DATA")

    app_data: dict[str, Any] = {
        "id": "app_busy",
        "nama": "Busy App",
        "versiTarget": "1.0",
        "metode": "exe",
        "sha256": calculate_sha256(exe_file),
    }

    mock_proc = MagicMock()
    mock_proc.stdout = None
    mock_proc.wait.return_value = 1618
    mock_proc.returncode = 1618

    with patch(
        "labinstaller.core.native_installer.detect_app",
        return_value=DetectionResult(
            app_id="app_busy",
            status=AppStatus.BELUM_TERPASANG,
            installed_version=None,
            target_version="1.0",
            policy="minimum",
        ),
    ):
        with patch("subprocess.Popen", return_value=mock_proc):
            res = installer.install_file(exe_file, app_data)
            assert res.status == InstallStatus.GAGAL
            assert "installer lain sedang berjalan" in res.message
