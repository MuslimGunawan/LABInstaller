"""Pengujian unit untuk mesin instalasi Winget (core/installer.py)."""

from typing import Any
from unittest.mock import MagicMock, patch

from labinstaller.core.detect import AppStatus, DetectionResult
from labinstaller.core.installer import (
    InstallStatus,
    WingetInstaller,
)


def test_winget_build_command_machine_and_version() -> None:
    """Memastikan parameter perintah winget tersusun sesuai PRD 6.4."""
    installer = WingetInstaller()
    app_data: dict[str, Any] = {
        "id": "git",
        "nama": "Git for Windows",
        "wingetId": "Git.Git",
        "versiTarget": "2.55.0.5",
        "scope": "machine",
    }
    cmd = installer.build_install_command(app_data, use_target_version=True)
    assert cmd[0] == "winget"
    assert "install" in cmd
    assert "--id" in cmd
    assert "Git.Git" in cmd
    assert "--exact" in cmd
    assert "--source" in cmd
    assert "winget" in cmd
    assert "--scope" in cmd
    assert "machine" in cmd
    assert "--version" in cmd
    assert "2.55.0.5" in cmd
    assert "--disable-interactivity" in cmd
    assert "--accept-source-agreements" in cmd
    assert "--accept-package-agreements" in cmd


def test_winget_build_command_latest_resolved() -> None:
    """Memastikan target 'latest-resolved' tidak menambahkan flag --version."""
    installer = WingetInstaller()
    app_data: dict[str, Any] = {
        "id": "vscode",
        "nama": "Visual Studio Code",
        "wingetId": "Microsoft.VisualStudioCode",
        "versiTarget": "latest-resolved",
        "scope": "machine",
    }
    cmd = installer.build_install_command(app_data, use_target_version=True)
    assert "--version" not in cmd


def test_winget_install_dry_run() -> None:
    """Memastikan mode dry-run mensimulasikan progres dan menghasilkan status BERHASIL tanpa eksekusi."""
    installer = WingetInstaller(dry_run=True)
    app_data: dict[str, Any] = {
        "id": "nodejs",
        "nama": "Node.js LTS",
        "wingetId": "OpenJS.NodeJS.LTS",
        "versiTarget": "24.20.0",
    }
    progress_updates: list[tuple[int, str]] = []

    def on_prog(pct: int, msg: str) -> None:
        progress_updates.append((pct, msg))

    with patch(
        "labinstaller.core.installer.detect_app",
        return_value=DetectionResult(
            app_id="nodejs",
            status=AppStatus.BELUM_TERPASANG,
            installed_version=None,
            target_version="24.20.0",
            policy="minimum",
        ),
    ):
        result = installer.install(app_data, on_progress=on_prog)
        assert result.status == InstallStatus.BERHASIL
        assert "[Simulasi Dry-Run]" in result.message
        assert len(progress_updates) >= 2


def test_winget_install_already_installed_skip() -> None:
    """Memastikan aplikasi yang sudah terpasang dan sesuai dilewati (DILEWATI) tanpa instalasi."""
    installer = WingetInstaller(dry_run=False)
    app_data: dict[str, Any] = {
        "id": "git",
        "nama": "Git for Windows",
        "wingetId": "Git.Git",
        "versiTarget": "2.55.0.5",
    }
    with patch(
        "labinstaller.core.installer.detect_app",
        return_value=DetectionResult(
            app_id="git",
            status=AppStatus.SUDAH_TERPASANG,
            installed_version="2.55.0.5",
            target_version="2.55.0.5",
            policy="minimum",
        ),
    ):
        result = installer.install(app_data)
        assert result.status == InstallStatus.DILEWATI
        assert "Sudah terpasang dan sesuai" in result.message


def test_winget_install_cancellation() -> None:
    """Memastikan token pembatalan menghentikan eksekusi sebelum memulai instalasi."""
    installer = WingetInstaller(dry_run=False)
    app_data: dict[str, Any] = {
        "id": "qgis",
        "nama": "QGIS Desktop",
        "wingetId": "OSGeo.QGIS",
        "versiTarget": "4.2.2",
    }
    result = installer.install(app_data, is_cancelled=lambda: True)
    assert result.status == InstallStatus.DIBATALKAN


def test_winget_install_success_with_verification() -> None:
    """Memastikan instalasi sukses diverifikasi pasca-instalasi (PRD 6.2 #5)."""
    installer = WingetInstaller(dry_run=False)
    installer.winget_path = "mock_winget"
    app_data: dict[str, Any] = {
        "id": "nodejs",
        "nama": "Node.js LTS",
        "wingetId": "OpenJS.NodeJS.LTS",
        "versiTarget": "24.20.0",
    }

    mock_pre = DetectionResult(
        app_id="nodejs",
        status=AppStatus.BELUM_TERPASANG,
        installed_version=None,
        target_version="24.20.0",
        policy="minimum",
    )
    mock_post = DetectionResult(
        app_id="nodejs",
        status=AppStatus.SUDAH_TERPASANG,
        installed_version="24.20.0",
        target_version="24.20.0",
        policy="minimum",
    )

    mock_process = MagicMock()
    mock_process.stdout = None
    mock_process.wait.return_value = 0
    mock_process.returncode = 0

    with patch("labinstaller.core.installer.detect_app", side_effect=[mock_pre, mock_post]):
        with patch("subprocess.Popen", return_value=mock_process):
            res = installer.install(app_data)
            assert res.status == InstallStatus.BERHASIL
            assert res.exit_code == 0
            assert "Berhasil dipasang dan diverifikasi" in res.message


def test_winget_install_verification_failure() -> None:
    """Memastikan instalasi gagal jika verifikasi pasca-instalasi gagal meskipun exit code 0."""
    installer = WingetInstaller(dry_run=False)
    installer.winget_path = "mock_winget"
    app_data: dict[str, Any] = {
        "id": "netbeans",
        "nama": "Apache NetBeans",
        "wingetId": "Apache.NetBeans",
        "versiTarget": "25",
    }

    mock_pre = DetectionResult(
        app_id="netbeans",
        status=AppStatus.BELUM_TERPASANG,
        installed_version=None,
        target_version="25",
        policy="minimum",
    )
    mock_post = DetectionResult(
        app_id="netbeans",
        status=AppStatus.BELUM_TERPASANG,
        installed_version=None,
        target_version="25",
        policy="minimum",
    )

    mock_process = MagicMock()
    mock_process.stdout = None
    mock_process.wait.return_value = 0
    mock_process.returncode = 0

    with patch("labinstaller.core.installer.detect_app", side_effect=[mock_pre, mock_post]):
        with patch("subprocess.Popen", return_value=mock_process):
            res = installer.install(app_data)
            assert res.status == InstallStatus.GAGAL
            assert "Verifikasi pasca-instalasi gagal" in res.message


def test_winget_install_reboot_required() -> None:
    """Memastikan kode 3010 menghasilkan status BUTUH_REBOOT."""
    installer = WingetInstaller(dry_run=False)
    installer.winget_path = "mock_winget"
    app_data: dict[str, Any] = {
        "id": "vcredist",
        "nama": "Visual C++ Redistributable",
        "wingetId": "Microsoft.VCRedist.2015+.x64",
        "versiTarget": "14.51.36247.0",
    }

    mock_pre = DetectionResult(
        app_id="vcredist",
        status=AppStatus.BELUM_TERPASANG,
        installed_version=None,
        target_version="14.51.36247.0",
        policy="minimum",
    )
    mock_post = DetectionResult(
        app_id="vcredist",
        status=AppStatus.SUDAH_TERPASANG,
        installed_version="14.51.36247.0",
        target_version="14.51.36247.0",
        policy="minimum",
    )

    mock_process = MagicMock()
    mock_process.stdout = None
    mock_process.wait.return_value = 3010
    mock_process.returncode = 3010

    with patch("labinstaller.core.installer.detect_app", side_effect=[mock_pre, mock_post]):
        with patch("subprocess.Popen", return_value=mock_process):
            res = installer.install(app_data)
            assert res.status == InstallStatus.BUTUH_REBOOT
            assert res.needs_reboot is True
