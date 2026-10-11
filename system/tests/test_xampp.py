"""Pengujian unit untuk modul penanganan anti-bentrok XAMPP (core/xampp.py)."""

from pathlib import Path
from unittest.mock import patch

from labinstaller.core.xampp import (
    adjust_xampp_control_ini,
    adjust_xampp_httpd_conf,
    adjust_xampp_mysql_conf,
    adjust_xampp_phpmyadmin_conf,
    adjust_xampp_ssl_conf,
    install_xampp_marker,
    run_xampp_post_install_hook,
    verify_xampp_apache_syntax,
)


def test_adjust_xampp_httpd_conf(tmp_path: Path) -> None:
    """Memastikan penyesuaian httpd.conf mengubah port 80 menjadi 8080 dan membuat .bak."""
    conf_dir = tmp_path / "apache" / "conf"
    conf_dir.mkdir(parents=True)
    conf_file = conf_dir / "httpd.conf"
    initial_conf = "# Konfigurasi Apache Standar\nListen 80\nServerName localhost:80\n"
    conf_file.write_text(initial_conf, encoding="utf-8")

    ok = adjust_xampp_httpd_conf(tmp_path, http_port=8080)
    assert ok is True

    # Periksa cadangan .bak
    bak_file = conf_file.with_suffix(".conf.bak")
    assert bak_file.is_file()
    assert bak_file.read_text(encoding="utf-8") == initial_conf

    # Periksa isi hasil modifikasi
    updated = conf_file.read_text(encoding="utf-8")
    assert "Listen 8080" in updated
    assert "ServerName localhost:8080" in updated
    assert "Listen 80\n" not in updated


def test_adjust_xampp_ssl_conf(tmp_path: Path) -> None:
    """Memastikan penyesuaian httpd-ssl.conf mengubah port 443 menjadi 8443."""
    ssl_dir = tmp_path / "apache" / "conf" / "extra"
    ssl_dir.mkdir(parents=True)
    ssl_file = ssl_dir / "httpd-ssl.conf"
    initial_ssl = "Listen 443\n<VirtualHost _default_:443>\nServerName localhost:443\n"
    ssl_file.write_text(initial_ssl, encoding="utf-8")

    ok = adjust_xampp_ssl_conf(tmp_path, https_port=8443)
    assert ok is True

    updated = ssl_file.read_text(encoding="utf-8")
    assert "Listen 8443" in updated
    assert "<VirtualHost _default_:8443>" in updated
    assert "ServerName localhost:8443" in updated


def test_adjust_xampp_mysql_conf(tmp_path: Path) -> None:
    """Memastikan penyesuaian my.ini mengubah port MySQL menjadi 3307 pada client dan mysqld."""
    mysql_bin = tmp_path / "mysql" / "bin"
    mysql_bin.mkdir(parents=True)
    my_ini = mysql_bin / "my.ini"
    initial_ini = "[client]\nport=3306\n[mysqld]\nport=3306\n"
    my_ini.write_text(initial_ini, encoding="utf-8")

    ok = adjust_xampp_mysql_conf(tmp_path, mysql_port=3307)
    assert ok is True

    updated = my_ini.read_text(encoding="utf-8")
    assert "port=3307" in updated
    assert "port=3306" not in updated


def test_adjust_xampp_phpmyadmin_conf(tmp_path: Path) -> None:
    """Memastikan penyesuaian config.inc.php phpMyAdmin menyetel port 3307 dan host 127.0.0.1."""
    pma_dir = tmp_path / "phpMyAdmin"
    pma_dir.mkdir(parents=True)
    pma_file = pma_dir / "config.inc.php"
    initial_pma = (
        "<?php\n$cfg['Servers'][$i]['host'] = 'localhost';\n$cfg['Servers'][$i]['user'] = 'root';\n"
    )
    pma_file.write_text(initial_pma, encoding="utf-8")

    ok = adjust_xampp_phpmyadmin_conf(tmp_path, mysql_port=3307)
    assert ok is True

    updated = pma_file.read_text(encoding="utf-8")
    assert "$cfg['Servers'][$i]['port'] = '3307';" in updated
    assert "$cfg['Servers'][$i]['host'] = '127.0.0.1';" in updated


def test_adjust_xampp_control_ini(tmp_path: Path) -> None:
    """Memastikan xampp-control.ini mencatat port baru agar tombol Admin/Web mengarah tepat."""
    ini_file = tmp_path / "xampp-control.ini"
    initial_ini = "[ServicePorts]\nApache=80\nApacheSSL=443\nMySQL=3306\n"
    ini_file.write_text(initial_ini, encoding="utf-8")

    ok = adjust_xampp_control_ini(tmp_path, http_port=8080, https_port=8443, mysql_port=3307)
    assert ok is True

    updated = ini_file.read_text(encoding="utf-8")
    assert "Apache=8080" in updated
    assert "ApacheSSL=8443" in updated
    assert "MySQL=3307" in updated


def test_install_xampp_marker(tmp_path: Path) -> None:
    """Memastikan pemasangan lab-check.php di htdocs dengan target port 3307."""
    marker = install_xampp_marker(tmp_path, mysql_port=3307)
    assert marker.is_file()
    assert marker.name == "lab-check.php"

    content = marker.read_text(encoding="utf-8")
    assert "STACK=XAMPP" in content
    assert "DB_PORT=3307" in content
    assert "SERVER_PORT" in content


def test_verify_xampp_apache_syntax_missing_binary(tmp_path: Path) -> None:
    """Memastikan verifikasi mendeteksi ketiadaan biner httpd.exe dengan aman."""
    ok, msg = verify_xampp_apache_syntax(tmp_path)
    assert ok is False
    assert "tidak ditemukan" in msg


def test_run_xampp_post_install_hook(tmp_path: Path) -> None:
    """Memastikan run_xampp_post_install_hook mengorkestrasi penyesuaian lengkap secara mulus."""
    # Siapkan berkas dasar
    (tmp_path / "apache" / "conf").mkdir(parents=True)
    (tmp_path / "apache" / "conf" / "httpd.conf").write_text("Listen 80\n", encoding="utf-8")
    (tmp_path / "mysql" / "bin").mkdir(parents=True)
    (tmp_path / "mysql" / "bin" / "my.ini").write_text("port=3306\n", encoding="utf-8")
    (tmp_path / "phpMyAdmin").mkdir(parents=True)
    (tmp_path / "phpMyAdmin" / "config.inc.php").write_text("<?php\n", encoding="utf-8")

    with patch("labinstaller.core.xampp.ensure_stack_firewall_rules", return_value=[]):
        res = run_xampp_post_install_hook(tmp_path)

        assert res.status.value == "BERHASIL"
        assert (tmp_path / "htdocs" / "lab-check.php").is_file()
        assert "Listen 8080" in (tmp_path / "apache" / "conf" / "httpd.conf").read_text(
            encoding="utf-8"
        )
        assert "port=3307" in (tmp_path / "mysql" / "bin" / "my.ini").read_text(encoding="utf-8")


def test_engine_executes_xampp_hook(tmp_path: Path) -> None:
    """Memastikan engine.py memanggil hook pasca-instalasi XAMPP secara otomatis."""
    from labinstaller.core.config import ConfigManager
    from labinstaller.core.engine import AppPlanItem, PlanResult, execute_installation_plan
    from labinstaller.core.installer import InstallResult, InstallStatus

    cfg = ConfigManager()
    cfg._apps_data = {
        "apps": [
            {
                "id": "xampp",
                "nama": "XAMPP Stack (Port 8080/3307)",
                "kategori": "Web Stack",
                "metode": "exe",
                "versiTarget": "8.2.12-0",
                "hook": "xampp",
                "sumber": [
                    {
                        "tipe": "resmi",
                        "url": "https://example.com/xampp.exe",
                        "fileId": None,
                        "prioritas": 1,
                    }
                ],
                "sha256": "123456",
                "ukuran": 200,
            }
        ]
    }

    plan = PlanResult(
        items=[
            AppPlanItem(
                app_id="xampp",
                nama="XAMPP Stack (Port 8080/3307)",
                kategori="Web Stack",
                versi_target="8.2.12-0",
                versi_terpasang=None,
                status="BELUM_TERPASANG",
                metode="exe",
                ukuran_bytes=200,
            )
        ],
        total_download_bytes=200,
        estimasi_menit=0.2,
    )

    with (
        patch(
            "labinstaller.core.native_installer.NativeInstaller.install_file",
            return_value=InstallResult(
                app_id="xampp", app_name="XAMPP", status=InstallStatus.BERHASIL, message="OK"
            ),
        ),
        patch("labinstaller.core.engine.download_with_mirrors") as mock_dl,
        patch("labinstaller.core.engine.run_xampp_post_install_hook") as mock_hook,
    ):
        mock_dl.return_value.success = True
        mock_dl.return_value.file_path = tmp_path / "xampp.exe"
        (tmp_path / "xampp.exe").touch()

        mock_hook.return_value = InstallResult(
            app_id="xampp",
            app_name="XAMPP Stack (Port 8080/3307)",
            status=InstallStatus.BERHASIL,
            message="Hook XAMPP Selesai (Port 8080/3307)",
        )

        results = execute_installation_plan(plan, cfg)

        assert len(results) == 1
        assert results[0].status == InstallStatus.BERHASIL
        assert "Hook: Hook XAMPP Selesai" in results[0].message
        mock_hook.assert_called_once()
