"""Pengujian unit untuk modul manajemen hosts Windows (core/hosts.py)."""

from pathlib import Path

from labinstaller.core.hosts import (
    add_hosts_entry,
    backup_hosts_file,
    list_hosts_entries,
    remove_hosts_entry,
)


def test_backup_hosts_file(tmp_path: Path) -> None:
    """Memastikan backup_hosts_file membuat cadangan dengan isi yang identik."""
    hosts_file = tmp_path / "hosts"
    hosts_file.write_text("127.0.0.1 localhost\n", encoding="utf-8")

    backup_root = tmp_path / "backup"
    backup = backup_hosts_file(hosts_file, backup_root=backup_root)

    assert backup is not None
    assert backup.is_file()
    assert backup.read_text(encoding="utf-8") == "127.0.0.1 localhost\n"


def test_add_hosts_entry_new_and_idempotent(tmp_path: Path) -> None:
    """Memastikan entri baru ditambahkan dengan tag # LabInstaller dan tidak menduplikasi saat dipanggil ulang."""
    hosts_file = tmp_path / "hosts"
    hosts_file.write_text("127.0.0.1 localhost\n", encoding="utf-8")

    # 1. Tambah entri pertama
    ok = add_hosts_entry("127.0.0.1", "web.test", hosts_path=hosts_file)
    assert ok is True

    content = hosts_file.read_text(encoding="utf-8")
    assert "web.test" in content
    assert "# LabInstaller" in content

    # 2. Panggilan ulang idempoten (tidak boleh menambah baris ganda)
    ok2 = add_hosts_entry("127.0.0.1", "web.test", hosts_path=hosts_file)
    assert ok2 is True

    lines = [
        line for line in hosts_file.read_text(encoding="utf-8").splitlines() if "web.test" in line
    ]
    assert len(lines) == 1


def test_add_hosts_entry_updates_existing_ip(tmp_path: Path) -> None:
    """Memastikan jika IP berubah pada entri LabInstaller, baris tersebut diperbarui di tempat."""
    hosts_file = tmp_path / "hosts"
    hosts_file.write_text("127.0.0.1\tweb.test\t# LabInstaller\n", encoding="utf-8")

    ok = add_hosts_entry("192.168.1.100", "web.test", hosts_path=hosts_file)
    assert ok is True

    content = hosts_file.read_text(encoding="utf-8")
    assert "192.168.1.100\tweb.test\t# LabInstaller" in content
    assert "127.0.0.1\tweb.test" not in content


def test_remove_hosts_entry(tmp_path: Path) -> None:
    """Memastikan remove_hosts_entry hanya menghapus entri berpenanda # LabInstaller."""
    hosts_file = tmp_path / "hosts"
    initial_text = (
        "127.0.0.1 localhost\n127.0.0.1 original.domain\n127.0.0.1 custom.test # LabInstaller\n"
    )
    hosts_file.write_text(initial_text, encoding="utf-8")

    # Coba hapus entri asli sistem yang tidak bertanda LabInstaller (tidak boleh terhapus)
    remove_hosts_entry("original.domain", hosts_path=hosts_file)
    assert "original.domain" in hosts_file.read_text(encoding="utf-8")

    # Hapus entri berpenanda LabInstaller
    ok = remove_hosts_entry("custom.test", hosts_path=hosts_file)
    assert ok is True
    assert "custom.test" not in hosts_file.read_text(encoding="utf-8")
    assert "original.domain" in hosts_file.read_text(encoding="utf-8")


def test_list_hosts_entries(tmp_path: Path) -> None:
    """Memastikan list_hosts_entries memetakan entri aktif dan mendeteksi tag LabInstaller."""
    hosts_file = tmp_path / "hosts"
    hosts_file.write_text(
        "# Komentar\n127.0.0.1 localhost\n127.0.0.1 app.test # LabInstaller\n",
        encoding="utf-8",
    )

    entries = list_hosts_entries(hosts_path=hosts_file)
    assert len(entries) == 2
    assert ("127.0.0.1", "localhost", False) in entries
    assert ("127.0.0.1", "app.test", True) in entries
