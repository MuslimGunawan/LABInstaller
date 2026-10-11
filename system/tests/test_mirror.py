"""Pengujian unit untuk modul pengelolaan mirror Google Drive (core/mirror.py)."""

from pathlib import Path
from unittest.mock import patch

from labinstaller.core.downloader import (
    DownloadHashMismatchError,
    DownloadHtmlResponseError,
)
from labinstaller.core.hasher import calculate_bytes_sha256
from labinstaller.core.mirror import (
    DEFAULT_COOLDOWN_SECONDS,
    DownloadSourceType,
    HostingEntry,
    MirrorStateManager,
    calculate_file_hash_for_admin,
    download_with_mirrors,
    get_gdrive_download_url,
    get_gdrive_fallback_url,
    get_shuffled_mirror_ids,
    is_quota_exceeded_text,
    publish_file_to_share,
    write_butuh_hosting_report,
)


def test_get_gdrive_urls() -> None:
    """Memastikan URL unduhan Google Drive sesuai format spesifikasi PRD 6B.3."""
    file_id = "1AbCdEfGhIjKlMnOpQrStUvWxYz"
    main_url = get_gdrive_download_url(file_id)
    fallback_url = get_gdrive_fallback_url(file_id)

    assert "drive.usercontent.google.com/download" in main_url
    assert f"id={file_id}" in main_url
    assert "confirm=t" in main_url

    assert "drive.google.com/uc" in fallback_url
    assert f"id={file_id}" in fallback_url


def test_shuffled_mirror_ids_deterministic_per_machine() -> None:
    """Memastikan pengacakan mirror stabil pada mesin yang sama dan mengabaikan placeholder."""
    raw_ids = [
        "ID_MIRROR_1",
        "ISI_FILE_ID_GDRIVE",
        "ID_MIRROR_2",
        "ID_MIRROR_3",
        "ISI_FILE_ID_GDRIVE_4",
    ]

    shuffled_1 = get_shuffled_mirror_ids(raw_ids, machine_seed="PC-LAB-01")
    shuffled_2 = get_shuffled_mirror_ids(raw_ids, machine_seed="PC-LAB-01")

    # Harus identik pada mesin/seed yang sama
    assert shuffled_1 == shuffled_2
    # Placeholder wajib tersaring
    assert "ISI_FILE_ID_GDRIVE" not in shuffled_1
    assert len(shuffled_1) == 3

    # Pada mesin berbeda harus memiliki peluang urutan berbeda
    shuffled_other = get_shuffled_mirror_ids(raw_ids, machine_seed="PC-LAB-99")
    assert len(shuffled_other) == 3


def test_mirror_cooldown_tracking(tmp_path: Path) -> None:
    """Memastikan status cooldown mirror dicatat dan dipersistensikan dengan benar."""
    state_file = tmp_path / "state.json"
    mgr = MirrorStateManager(state_file=state_file)

    fid = "GDRIVE_ABC_123"
    assert mgr.is_in_cooldown(fid) is False

    # Tandai cooldown 1800 detik
    mgr.mark_cooldown(fid, duration_seconds=DEFAULT_COOLDOWN_SECONDS)
    assert mgr.is_in_cooldown(fid) is True

    # Muat instance baru dari disk
    mgr_reloaded = MirrorStateManager(state_file=state_file)
    assert mgr_reloaded.is_in_cooldown(fid) is True

    # Bersihkan cooldown
    mgr.clear_cooldown(fid)
    assert mgr.is_in_cooldown(fid) is False


def test_quota_exceeded_detection() -> None:
    """Memastikan deteksi teks kuota mengenali respons kuota Google Drive."""
    assert is_quota_exceeded_text("Maaf, kuota unduhan untuk file ini telah terlampaui.") is True
    assert is_quota_exceeded_text("Download quota exceeded for this file.") is True
    assert is_quota_exceeded_text("Terlalu banyak pengguna yang mengunduh berkas ini.") is True
    assert is_quota_exceeded_text("HTTP Error 403: Forbidden") is True
    assert is_quota_exceeded_text("Berkas normal berhasil diunduh") is False


def test_write_butuh_hosting_report(tmp_path: Path) -> None:
    """Memastikan laporan butuh hosting manual format TXT dan CSV terbentuk sesuai PRD 6B.4."""
    entries = [
        HostingEntry(
            app_id="php",
            app_name="PHP 8.5.11 NTS",
            version="8.5.11",
            filename="php-8.5.11-Win32-vs17-x64.zip",
            official_url="https://windows.php.net/downloads/releases/php-8.5.11-nts-Win32-vs17-x64.zip",
            failure_reason="Timeout koneksi (sumber resmi tidak terjangkau)",
            expected_size=33554432,
            expected_sha256="d4a5be17a9a379924f250577da65d969fee85a627918864e13fbf4ec3ccd9341",
            file_ids=["GDRIVE_ID_1", "GDRIVE_ID_2"],
        )
    ]

    txt_path, csv_path = write_butuh_hosting_report(entries, log_dir=tmp_path)

    assert txt_path.is_file()
    assert csv_path.is_file()

    txt_content = txt_path.read_text(encoding="utf-8")
    assert "PHP 8.5.11 NTS" in txt_content
    assert "php-8.5.11-Win32-vs17-x64.zip" in txt_content
    assert "d4a5be17a9a379924f250577da65d969fee85a627918864e13fbf4ec3ccd9341" in txt_content

    csv_content = csv_path.read_text(encoding="utf-8-sig")
    assert "Aplikasi,Versi,NamaBerkas" in csv_content
    assert "PHP 8.5.11 NTS,8.5.11,php-8.5.11-Win32-vs17-x64.zip" in csv_content


def test_calculate_file_hash_for_admin(tmp_path: Path) -> None:
    """Memastikan kalkulasi hash berkas untuk fitur admin menghasilkan hash presisi."""
    sample = tmp_path / "test.bin"
    sample.write_bytes(b"Lab Auto Installer Test Payload")

    res = calculate_file_hash_for_admin(sample)
    assert res["filename"] == "test.bin"
    assert res["size"] == len(b"Lab Auto Installer Test Payload")
    assert res["sha256"] == calculate_bytes_sha256(b"Lab Auto Installer Test Payload")


def test_publish_file_to_share(tmp_path: Path) -> None:
    """Memastikan fitur --publish-to-share menyalin berkas secara atomik."""
    source_file = tmp_path / "installer.exe"
    source_file.write_bytes(b"\x90\x90\x90")

    share_dir = tmp_path / "lan_share"
    published = publish_file_to_share(source_file, share_dir)

    assert published is not None
    assert published.is_file()
    assert published.parent == share_dir
    assert published.read_bytes() == b"\x90\x90\x90"


def test_download_with_mirrors_cache_hit(tmp_path: Path) -> None:
    """Memastikan download_with_mirrors mengenali cache lokal dan melewatinya (PRD 6B.1)."""
    target = tmp_path / "app.exe"
    payload = b"Sample Installer Binary"
    target.write_bytes(payload)
    sha256_val = calculate_bytes_sha256(payload)

    app_meta = {
        "id": "app_test",
        "nama": "App Test",
        "sha256": sha256_val,
        "ukuran": len(payload),
    }

    res = download_with_mirrors(app_meta, target)
    assert res.success is True
    assert res.source_type == DownloadSourceType.CACHE_LOKAL
    assert res.file_path == target


def test_download_with_mirrors_failover_to_gdrive(tmp_path: Path) -> None:
    """Memastikan failover dari sumber resmi ke Google Drive mirror berjalan mulus."""
    target = tmp_path / "app.zip"
    payload = b"Drive payload data"
    sha256_val = calculate_bytes_sha256(payload)

    app_meta = {
        "id": "app_failover",
        "nama": "App Failover",
        "versiTarget": "1.0",
        "sha256": sha256_val,
        "ukuran": len(payload),
        "sumber": [
            {"tipe": "resmi", "url": "https://broken-vendor.com/app.zip", "prioritas": 1},
            {"tipe": "gdrive", "fileId": "VALID_GDRIVE_ID", "prioritas": 2},
        ],
    }

    # Mock download_file: resmi gagal (DownloadHtmlResponseError), gdrive sukses
    def fake_download_file(url: str, target_path: Path, **kwargs: object) -> Path:
        if "broken-vendor" in url:
            raise DownloadHtmlResponseError("404 Not Found")
        # Google drive link
        target_path.write_bytes(payload)
        return target_path

    with patch("labinstaller.core.mirror.download_file", side_effect=fake_download_file):
        res = download_with_mirrors(app_meta, target)

    assert res.success is True
    assert res.source_type == DownloadSourceType.GDRIVE_MIRROR
    assert res.used_mirror_id == "VALID_GDRIVE_ID"


def test_download_with_mirrors_all_fail_creates_hosting_entry(tmp_path: Path) -> None:
    """Memastikan kegagalan seluruh sumber menghasilkan status gagal ramah dan HostingEntry."""
    target = tmp_path / "app.rar"

    app_meta = {
        "id": "app_hard",
        "nama": "App Hard",
        "versiTarget": "2.0",
        "sha256": "fake_sha",
        "ukuran": 5000,
        "sumber": [
            {"tipe": "resmi", "url": "https://unavailable.com/app.rar", "prioritas": 1},
            {"tipe": "gdrive", "fileId": "FAIL_GDRIVE_ID", "prioritas": 2},
        ],
    }

    def fake_download_all_fail(url: str, **kwargs: object) -> Path:
        raise DownloadHashMismatchError("Corrupted mirror data")

    with patch("labinstaller.core.mirror.download_file", side_effect=fake_download_all_fail):
        res = download_with_mirrors(app_meta, target)

    assert res.success is False
    assert res.error_type == "BUTUH_HOSTING_MANUAL"
    assert res.hosting_entry is not None
    assert res.hosting_entry.app_id == "app_hard"
    assert "tidak bisa diunduh dari sumber resmi" in res.message
