"""Pengujian unit untuk modul PHP Standalone (core/php_standalone.py)."""

from pathlib import Path

from labinstaller.core.php_standalone import (
    configure_php_ini,
    install_ca_bundle,
    run_php_post_install_hook,
    verify_php_standalone,
)


def test_install_ca_bundle_from_source(tmp_path: Path) -> None:
    """Memastikan install_ca_bundle menyalin berkas CA bundle ke lokasi tujuan."""
    src_pem = tmp_path / "my_ca.pem"
    src_pem.write_text(
        "-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----\n", encoding="utf-8"
    )

    php_dir = tmp_path / "php"
    dest_pem = install_ca_bundle(php_dir, bundle_source=src_pem)

    assert dest_pem.is_file()
    assert dest_pem.parent.name == "ssl"
    assert dest_pem.name == "cacert.pem"
    assert "TEST" in dest_pem.read_text(encoding="utf-8")


def test_configure_php_ini_clean_and_extensions(tmp_path: Path) -> None:
    """Memastikan configure_php_ini mengatur nilai dasar dan hanya mengaktifkan ekstensi yang ada di ext\\."""
    php_dir = tmp_path / "php"
    ext_dir = php_dir / "ext"
    ext_dir.mkdir(parents=True)

    # Siapkan file DLL dummy hanya untuk curl dan mysqli
    (ext_dir / "php_curl.dll").write_bytes(b"\x90\x90")
    (ext_dir / "php_mysqli.dll").write_bytes(b"\x90\x90")

    # Siapkan template php.ini-development
    dev_template = (
        "[PHP]\n"
        ';extension_dir = "ext"\n'
        ";date.timezone =\n"
        ";memory_limit = 128M\n"
        ";extension=curl\n"
        ";extension=mysqli\n"
        ";extension=pdo_mysql\n"
    )
    (php_dir / "php.ini-development").write_text(dev_template, encoding="utf-8")

    ok, warnings = configure_php_ini(php_dir, profile_type="development")
    assert ok is True

    php_ini = php_dir / "php.ini"
    assert php_ini.is_file()
    content = php_ini.read_text(encoding="utf-8")

    # 1. Nilai dasar
    assert 'extension_dir = "' in content
    assert str(ext_dir.resolve()) in content
    assert 'date.timezone = "Asia/Jakarta"' in content
    assert "memory_limit = 512M" in content
    assert "upload_max_filesize = 64M" in content
    assert "max_execution_time = 120" in content

    # 2. CA bundle
    assert "curl.cainfo" in content
    assert "openssl.cafile" in content

    # 3. Ekstensi yang ada di ext\ harus aktif
    assert "extension=curl" in content
    assert "extension=mysqli" in content

    # 4. Ekstensi yang TIDAK ada di ext\ (pdo_mysql) tidak boleh diaktifkan tanpa komentar
    assert "extension=pdo_mysql" not in content or ";extension=pdo_mysql" in content
    assert any("pdo_mysql" in w for w in warnings)


def test_verify_php_standalone_missing_binary(tmp_path: Path) -> None:
    """Memastikan verify_php_standalone mendeteksi php.exe yang belum ada."""
    res = verify_php_standalone(tmp_path)
    assert res["ok"] is False
    assert any("tidak ditemukan" in err for err in res["errors"])


def test_run_php_post_install_hook(tmp_path: Path) -> None:
    """Memastikan run_php_post_install_hook mengorkestrasi penyiapan php.ini dan path."""
    php_dir = tmp_path / "php"
    php_dir.mkdir(parents=True)
    (php_dir / "php.ini-development").write_text("[PHP]\n", encoding="utf-8")

    res = run_php_post_install_hook(php_dir)
    assert res.status.value == "BERHASIL"
    assert (php_dir / "php.ini").is_file()
    assert "php.ini siap" in res.message
