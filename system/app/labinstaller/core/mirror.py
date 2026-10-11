"""Modul pengelolaan sumber unduhan multi-jalur dan mirror Google Drive (core/mirror.py).

Menerapkan aturan PRD 6B dan 11.5:
1. Urutan sumber unduhan (PRD 6B.1):
   - Cache lokal (cache\\download\\ atau cache\\) yang terverifikasi SHA-256.
   - Payload lokal / shared folder LAN.
   - Sumber resmi (URL resmi) dengan batas waktu ketat.
   - Mirror Google Drive 1 s/d 4.
   - Khusus aplikasi lambat/tidakBisaDiunduh: urutan menjadi Cache -> LAN -> Mirror Google Drive -> Resmi.
2. Failover antar mirror Google Drive (PRD 6B.2):
   - Urutan mirror diacak per PC berdasarkan seed mesin/hostname agar beban terbagi merata.
   - Batas waktu koneksi 15 detik; penanganan stall (30 detik tanpa byte).
   - Cooldown 30-60 menit untuk mirror yang terkena kuota (403/429/HTML kuota) atau timeout.
   - Maksimal 2x percobaan per mirror sebelum beralih ke mirror berikutnya.
3. Deteksi jebakan respons Google Drive (PRD 6B.3):
   - Menggunakan format resmi direct download:
     https://drive.usercontent.google.com/download?id=<FILE_ID>&export=download&confirm=t
     dengan fallback ke https://drive.google.com/uc?export=download&id=<FILE_ID>&confirm=t.
   - Mendeteksi halaman HTML kuota/konfirmasi tanpa pernah menyimpan berkas HTML sebagai installer.
4. Pelaporan "Butuh Hosting Manual" & format CSV/TXT (PRD 6B.4):
   - Jika semua sumber gagal, buat laporan butuh-hosting-<timestamp>.txt dan .csv.
   - Aplikasi ditandai "menunggu sumber" tanpa mematikan aplikasi lain.
5. Fitur Publish to Share (--publish-to-share) untuk mendistribusikan berkas terverifikasi ke LAN.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import random
import socket
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

from labinstaller.core.downloader import (
    CancelCheckCallback,
    DownloadCancelledError,
    DownloadHashMismatchError,
    DownloadHtmlResponseError,
    ProgressCallback,
    download_file,
)
from labinstaller.core.hasher import calculate_sha256, verify_sha256
from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import (
    CACHE_DOWNLOAD_DIR,
    LOGS_DIR,
    PAYLOAD_DIR,
    STATE_DIR,
    STATE_JSON,
)

# Placeholder standar untuk file ID yang belum diisi oleh admin
PLACEHOLDER_GDRIVE_ID = "ISI_FILE_ID_GDRIVE"

# Durasi cooldown default untuk mirror yang gagal / terkena kuota (30 menit)
DEFAULT_COOLDOWN_SECONDS = 1800


class DownloadSourceType(str, Enum):
    """Jenis sumber yang berhasil digunakan untuk mendapatkan berkas."""

    CACHE_LOKAL = "cache_lokal"
    LAN_SHARE = "lan_share"
    RESMI = "resmi"
    GDRIVE_MIRROR = "gdrive_mirror"


@dataclass
class HostingEntry:
    """Entri laporan aplikasi yang butuh di-hosting manual di Google Drive."""

    app_id: str
    app_name: str
    version: str
    filename: str
    official_url: str
    failure_reason: str
    expected_size: int
    expected_sha256: str
    file_ids: list[str] = field(default_factory=list)


@dataclass
class MirrorDownloadResult:
    """Hasil operasi pengunduhan multi-jalur."""

    success: bool
    source_type: DownloadSourceType | None = None
    file_path: Path | None = None
    used_mirror_id: str | None = None
    message: str = ""
    error_type: str | None = None
    hosting_entry: HostingEntry | None = None


def get_gdrive_download_url(file_id: str) -> str:
    """Menyusun tautan unduhan langsung Google Drive sesuai spesifikasi PRD 6B.3."""
    clean_id = file_id.strip()
    return f"https://drive.usercontent.google.com/download?id={clean_id}&export=download&confirm=t"


def get_gdrive_fallback_url(file_id: str) -> str:
    """Tautan cadangan format Google Drive klasik."""
    clean_id = file_id.strip()
    return f"https://drive.google.com/uc?export=download&id={clean_id}&confirm=t"


def is_quota_exceeded_text(text_or_err: str) -> bool:
    """Mendeteksi apakah pesan kesalahan mengindikasikan limit kuota unduhan Google Drive."""
    low = text_or_err.lower()
    return (
        "quota" in low
        or "kuota" in low
        or "terlalu banyak pengguna" in low
        or "download quota" in low
        or "403" in low
        or "429" in low
        or "rate limit" in low
        or "access denied" in low
    )


def get_machine_seed() -> str:
    """Mendapatkan identitas unik/stabil PC untuk seeding acak beban mirror."""
    try:
        hostname = socket.gethostname()
        username = os.environ.get("USERNAME", "user")
        return f"{hostname}_{username}"
    except Exception:
        return "default_lab_pc"


def get_shuffled_mirror_ids(file_ids: list[str], machine_seed: str | None = None) -> list[str]:
    """Mengacak urutan mirror per PC (PRD 6B.2) agar beban dan kuota Drive terbagi rata."""
    valid_ids = [fid.strip() for fid in file_ids if fid and not fid.startswith("ISI_FILE_ID")]
    if not valid_ids:
        return []

    seed = machine_seed or get_machine_seed()
    # Buat seed angka stabil dari string seed
    seed_int = int(hashlib.md5(seed.encode("utf-8")).hexdigest()[:8], 16)

    shuffled = list(valid_ids)
    rng = random.Random(seed_int)
    rng.shuffle(shuffled)
    return shuffled


class MirrorStateManager:
    """Pengelola status cooldown dan kegagalan mirror Google Drive."""

    def __init__(self, state_file: Path = STATE_JSON) -> None:
        self.state_file = state_file
        self._cooldowns: dict[str, float] = {}
        self._load_state()

    def _load_state(self) -> None:
        """Memuat state cooldown dari berkas disk jika ada."""
        if not self.state_file.exists():
            return
        try:
            data = json.loads(self.state_file.read_text(encoding="utf-8"))
            cooldowns = data.get("mirror_cooldowns", {})
            now = time.time()
            # Hanya simpan cooldown yang belum kadaluarsa
            self._cooldowns = {k: float(v) for k, v in cooldowns.items() if float(v) > now}
        except Exception as exc:
            log_warn(f"Gagal memuat mirror state dari {self.state_file.name}: {exc}")
            self._cooldowns = {}

    def save_state(self) -> None:
        """Menyimpan status cooldown ke berkas disk."""
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            now = time.time()
            active_cooldowns = {k: v for k, v in self._cooldowns.items() if v > now}

            existing_data: dict[str, Any] = {}
            if self.state_file.exists():
                try:
                    existing_data = json.loads(self.state_file.read_text(encoding="utf-8"))
                except Exception:
                    existing_data = {}

            existing_data["mirror_cooldowns"] = active_cooldowns
            existing_data["last_updated"] = datetime.now(timezone.utc).isoformat()

            # Tulis atomik
            tmp_file = self.state_file.with_suffix(".tmp")
            tmp_file.write_text(json.dumps(existing_data, indent=2), encoding="utf-8")
            if self.state_file.exists():
                self.state_file.unlink(missing_ok=True)
            tmp_file.rename(self.state_file)
        except Exception as exc:
            log_warn(f"Gagal menyimpan mirror state: {exc}")

    def is_in_cooldown(self, file_id: str) -> bool:
        """Memeriksa apakah mirror ID masih berada dalam masa cooldown."""
        expire_time = self._cooldowns.get(file_id)
        if not expire_time:
            return False
        if time.time() >= expire_time:
            del self._cooldowns[file_id]
            return False
        return True

    def mark_cooldown(self, file_id: str, duration_seconds: int = DEFAULT_COOLDOWN_SECONDS) -> None:
        """Menandai mirror ID dalam masa cooldown."""
        self._cooldowns[file_id] = time.time() + duration_seconds
        self.save_state()
        log_warn(f"Mirror ID '{file_id}' diberi cooldown selama {duration_seconds // 60} menit.")

    def clear_cooldown(self, file_id: str) -> None:
        """Menghapus status cooldown mirror."""
        if file_id in self._cooldowns:
            del self._cooldowns[file_id]
            self.save_state()


def write_butuh_hosting_report(
    entries: list[HostingEntry],
    log_dir: Path | None = None,
) -> tuple[Path, Path]:
    """Menulis berkas laporan butuh-hosting-<timestamp>.txt dan .csv (PRD 6B.4).

    Returns:
        (path_txt, path_csv)
    """
    target_dir = log_dir or LOGS_DIR
    target_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")

    txt_file = target_dir / f"butuh-hosting-{ts}.txt"
    csv_file = target_dir / f"butuh-hosting-{ts}.csv"

    # 1. Tulis TXT
    lines: list[str] = [
        "================================================================================",
        "LAPORAN BERKAS BUTUH HOSTING MANUAL (GOOGLE DRIVE)",
        f"Waktu Dibuat: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        "Lab Auto Installer - Komputer Lab Windows",
        "================================================================================",
        "",
        "Instruksi Admin:",
        "1. Unduh berkas dari sumber resmi pada jaringan/PC yang memiliki akses.",
        "2. Cocokkan hash SHA-256 berkas dengan nilai yang tercantum di bawah.",
        "3. Unggah 4 salinan identik ke Google Drive (akses: 'Siapa saja yang memiliki tautan').",
        "4. Masukkan File ID ke system/app/config/mirrors.json pada bagian gdriveFileIds.",
        "",
        "-" * 80,
    ]

    for idx, e in enumerate(entries, 1):
        lines.extend(
            [
                f"[{idx}] Aplikasi      : {e.app_name} (ID: {e.app_id})",
                f"    Versi Target  : {e.version}",
                f"    Nama Berkas   : {e.filename}",
                f"    Ukuran Resmi  : {e.expected_size} bytes ({e.expected_size / (1024 * 1024):.2f} MB)",
                f"    SHA-256 Resmi : {e.expected_sha256}",
                f"    URL Resmi     : {e.official_url or '-'}",
                f"    Penyebab Gagal: {e.failure_reason}",
                f"    File ID 1     : {e.file_ids[0] if len(e.file_ids) > 0 else 'ISI_FILE_ID_GDRIVE'}",
                f"    File ID 2     : {e.file_ids[1] if len(e.file_ids) > 1 else 'ISI_FILE_ID_GDRIVE'}",
                f"    File ID 3     : {e.file_ids[2] if len(e.file_ids) > 2 else 'ISI_FILE_ID_GDRIVE'}",
                f"    File ID 4     : {e.file_ids[3] if len(e.file_ids) > 3 else 'ISI_FILE_ID_GDRIVE'}",
                "-" * 80,
            ]
        )

    txt_file.write_text("\n".join(lines), encoding="utf-8")

    # 2. Tulis CSV
    with open(csv_file, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "Aplikasi",
                "Versi",
                "NamaBerkas",
                "URLResmi",
                "PenyebabGagal",
                "UkuranBytes",
                "SHA256",
                "FileId1",
                "FileId2",
                "FileId3",
                "FileId4",
            ]
        )
        for e in entries:
            fid1 = e.file_ids[0] if len(e.file_ids) > 0 else ""
            fid2 = e.file_ids[1] if len(e.file_ids) > 1 else ""
            fid3 = e.file_ids[2] if len(e.file_ids) > 2 else ""
            fid4 = e.file_ids[3] if len(e.file_ids) > 3 else ""
            writer.writerow(
                [
                    e.app_name,
                    e.version,
                    e.filename,
                    e.official_url,
                    e.failure_reason,
                    e.expected_size,
                    e.expected_sha256,
                    fid1,
                    fid2,
                    fid3,
                    fid4,
                ]
            )

    log_info(f"Laporan Butuh Hosting Manual ditulis: {txt_file.name} dan {csv_file.name}")
    return txt_file, csv_file


def calculate_file_hash_for_admin(file_path: Path) -> dict[str, Any]:
    """Menghitung hash SHA-256 dan ukuran berkas untuk fitur bantuan admin di menu H."""
    if not file_path.is_file():
        raise FileNotFoundError(f"Berkas tidak ditemukan: {file_path}")

    size = file_path.stat().st_size
    sha256 = calculate_sha256(file_path)
    return {
        "filename": file_path.name,
        "size": size,
        "sha256": sha256,
        "size_mb": round(size / (1024 * 1024), 2),
    }


def publish_file_to_share(source_file: Path, share_dir: Path) -> Path | None:
    """Menyalin berkas terverifikasi ke folder bersama LAN (--publish-to-share) secara atomik."""
    if not source_file.is_file():
        return None

    try:
        share_dir.mkdir(parents=True, exist_ok=True)
        target_dest = share_dir / source_file.name
        tmp_dest = share_dir / f"{source_file.name}.tmp.{os.getpid()}"

        # Salin chunk per chunk
        with open(source_file, "rb") as sf, open(tmp_dest, "wb") as df:
            while True:
                buf = sf.read(65536)
                if not buf:
                    break
                df.write(buf)

        # Ganti nama atomik
        if target_dest.exists():
            target_dest.unlink(missing_ok=True)
        tmp_dest.rename(target_dest)

        log_info(f"[Publish] Berkas {source_file.name} berhasil disalin ke share LAN {share_dir}.")
        return target_dest
    except Exception as exc:
        log_warn(f"[Publish] Gagal menyalin {source_file.name} ke {share_dir}: {exc}")
        return None


def download_with_mirrors(
    app_meta: dict[str, Any],
    target_path: Path,
    mirrors_config: dict[str, Any] | None = None,
    lan_share_dir: Path | None = None,
    on_progress: ProgressCallback | None = None,
    is_cancelled: CancelCheckCallback | None = None,
    state_manager: MirrorStateManager | None = None,
) -> MirrorDownloadResult:
    """Mengunduh berkas dengan orkestrasi 4 jalur sumber dan failover otomatis (PRD 6B).

    Jalur evaluasi:
    1. Cache lokal (cache\\download\\ atau payload\\) -> verifikasi SHA-256.
    2. LAN Share -> verifikasi SHA-256.
    3. Sumber resmi vs Mirror Drive (sesuai flag lambat/tidakBisaDiunduh).
    4. Google Drive 1 s/d 4 dengan shuffle per PC dan deteksi kuota.
    5. Jika seluruh jalur gagal -> catat laporan Butuh Hosting Manual.
    """
    app_id = str(app_meta.get("id", "unknown"))
    app_name = str(app_meta.get("nama", app_id))
    version = str(app_meta.get("versiTarget", "unknown"))
    expected_sha256 = app_meta.get("sha256")
    expected_size = int(app_meta.get("ukuran", 0))

    if state_manager is None:
        state_manager = MirrorStateManager()

    # 1. Jalur 1: Cache Lokal (PRD 6B.1 #1)
    # Periksa direktori target dan PAYLOAD_DIR
    candidates_cache = [
        target_path,
        CACHE_DOWNLOAD_DIR / target_path.name,
        PAYLOAD_DIR / target_path.name,
    ]
    for cand in candidates_cache:
        if cand.is_file():
            if expected_sha256:
                if verify_sha256(cand, expected_sha256):
                    log_info(
                        f"Menggunakan berkas cache lokal tervalidasi: {cand.name}", app_id=app_id
                    )
                    if on_progress:
                        sz = cand.stat().st_size
                        on_progress(100, 0.0, sz, sz)
                    return MirrorDownloadResult(
                        success=True,
                        source_type=DownloadSourceType.CACHE_LOKAL,
                        file_path=cand,
                        message=f"Cache hit lokal: {cand.name}",
                    )
                else:
                    log_warn(
                        f"Berkas di {cand} ada tetapi SHA-256 tidak cocok. Mengabaikan...",
                        app_id=app_id,
                    )
            elif expected_size and cand.stat().st_size == expected_size:
                log_info(
                    f"Menggunakan berkas cache lokal dengan ukuran cocok: {cand.name}",
                    app_id=app_id,
                )
                return MirrorDownloadResult(
                    success=True,
                    source_type=DownloadSourceType.CACHE_LOKAL,
                    file_path=cand,
                    message=f"Cache hit lokal (ukuran cocok): {cand.name}",
                )

    # 2. Jalur 2: Shared Folder LAN (PRD 6B.1 #2)
    if lan_share_dir and lan_share_dir.is_dir():
        lan_file = lan_share_dir / target_path.name
        if lan_file.is_file():
            if expected_sha256 and verify_sha256(lan_file, expected_sha256):
                log_info(f"Mengambil berkas dari shared folder LAN: {lan_file}", app_id=app_id)
                # Salin ke direktori target lokal
                target_path.parent.mkdir(parents=True, exist_ok=True)
                part_target = target_path.with_name(target_path.name + ".part")
                try:
                    with open(lan_file, "rb") as sf, open(part_target, "wb") as df:
                        while True:
                            buf = sf.read(65536)
                            if not buf:
                                break
                            df.write(buf)
                    if target_path.exists():
                        target_path.unlink(missing_ok=True)
                    part_target.rename(target_path)
                    return MirrorDownloadResult(
                        success=True,
                        source_type=DownloadSourceType.LAN_SHARE,
                        file_path=target_path,
                        message=f"Diambil dari LAN share: {lan_file.name}",
                    )
                except Exception as exc:
                    log_warn(f"Gagal menyalin dari LAN share: {exc}", app_id=app_id)

    # Ambil metadata mirror Google Drive dari mirrors_config atau app_meta
    gdrive_ids: list[str] = []
    if mirrors_config:
        for f_entry in mirrors_config.get("files", []):
            if f_entry.get("appId") == app_id or f_entry.get("filename") == target_path.name:
                gdrive_ids.extend(f_entry.get("gdriveFileIds", []))

    for src in app_meta.get("sumber", []):
        if src.get("tipe") == "gdrive" and src.get("fileId"):
            gdrive_ids.append(src["fileId"])

    # Ambil URL sumber resmi
    official_url: str | None = None
    for src in app_meta.get("sumber", []):
        if src.get("tipe") == "resmi" and src.get("url"):
            official_url = src["url"]
            break

    is_slow_app = bool(app_meta.get("lambat", False) or app_meta.get("tidakBisaDiunduh", False))
    last_error_reason = ""

    # Helper fungsi coba unduh resmi
    def try_official() -> Path | None:
        nonlocal last_error_reason
        if not official_url:
            return None
        log_info(f"Mencoba mengunduh dari sumber resmi: {official_url}", app_id=app_id)
        try:
            return download_file(
                url=official_url,
                target_path=target_path,
                expected_sha256=expected_sha256,
                expected_size=expected_size,
                on_progress=on_progress,
                is_cancelled=is_cancelled,
                timeout_seconds=15.0,  # Batas waktu ketat 15 detik (PRD 6B.1)
                max_retries=2,
            )
        except DownloadCancelledError:
            raise
        except Exception as exc:
            last_error_reason = str(exc)
            log_warn(f"Sumber resmi gagal untuk {app_name}: {exc}", app_id=app_id)
            return None

    # Helper fungsi coba unduh Google Drive
    def try_gdrive_mirrors() -> tuple[Path | None, str | None]:
        nonlocal last_error_reason
        shuffled_ids = get_shuffled_mirror_ids(gdrive_ids)
        if not shuffled_ids:
            return None, None

        log_info(
            f"Mencoba {len(shuffled_ids)} mirror Google Drive (urutan acak per PC)...",
            app_id=app_id,
        )

        for mirror_idx, fid in enumerate(shuffled_ids, 1):
            if is_cancelled and is_cancelled():
                raise DownloadCancelledError("Dibatalkan oleh pengguna.")

            if state_manager.is_in_cooldown(fid):
                log_info(
                    f"Mirror #{mirror_idx} ({fid}) sedang dalam masa cooldown. Melompati...",
                    app_id=app_id,
                )
                continue

            # Tiap mirror dicoba max 2x (PRD 6B.2)
            for attempt_m in range(1, 3):
                if is_cancelled and is_cancelled():
                    raise DownloadCancelledError("Dibatalkan oleh pengguna.")

                # Coba URL direct download utama, lalu fallback jika attempt 2
                download_link = (
                    get_gdrive_download_url(fid) if attempt_m == 1 else get_gdrive_fallback_url(fid)
                )

                log_info(
                    f"Mirror #{mirror_idx} ({fid}) Percobaan {attempt_m}/2...",
                    app_id=app_id,
                )

                try:
                    res_path = download_file(
                        url=download_link,
                        target_path=target_path,
                        expected_sha256=expected_sha256,
                        expected_size=expected_size,
                        on_progress=on_progress,
                        is_cancelled=is_cancelled,
                        timeout_seconds=20.0,
                        max_retries=1,  # Retry dikelola oleh loop mirror
                    )
                    log_info(
                        f"Sukses mengunduh dari mirror Google Drive ID '{fid}'.", app_id=app_id
                    )
                    return res_path, fid

                except DownloadCancelledError:
                    raise

                except DownloadHtmlResponseError as html_err:
                    err_str = str(html_err)
                    last_error_reason = f"Respons HTML Drive: {err_str}"
                    if is_quota_exceeded_text(err_str):
                        log_warn(
                            f"Mirror ID '{fid}' terkena kuota Drive! Memberikan cooldown.",
                            app_id=app_id,
                        )
                        state_manager.mark_cooldown(fid, DEFAULT_COOLDOWN_SECONDS)
                        break  # Langsung ganti mirror lain
                    else:
                        log_warn(
                            f"Mirror ID '{fid}' mengembalikan HTML tidak terduga: {err_str}",
                            app_id=app_id,
                        )

                except DownloadHashMismatchError as hash_err:
                    last_error_reason = f"Hash SHA-256 korup di mirror: {hash_err}"
                    log_error(
                        f"Mirror ID '{fid}' menyimpan berkas korup! Memberikan cooldown.",
                        app_id=app_id,
                    )
                    state_manager.mark_cooldown(fid, DEFAULT_COOLDOWN_SECONDS * 2)
                    break  # Berkas korup, jangan diulang

                except Exception as exc:
                    err_str = str(exc)
                    last_error_reason = err_str
                    log_warn(
                        f"Mirror ID '{fid}' gagal pada percobaan {attempt_m}: {exc}", app_id=app_id
                    )
                    if is_quota_exceeded_text(err_str):
                        state_manager.mark_cooldown(fid, DEFAULT_COOLDOWN_SECONDS)
                        break

            # Jika kedua percobaan gagal, beri cooldown ringan agar tidak membebani PC berikutnya
            if not state_manager.is_in_cooldown(fid):
                state_manager.mark_cooldown(fid, 600)  # 10 menit

        return None, None

    # Tentukan urutan eksekusi sumber online (PRD 6B.1)
    if is_slow_app:
        # Jalur khusus: GDrive Mirrors terlebih dahulu
        dl_file, used_id = try_gdrive_mirrors()
        if dl_file:
            return MirrorDownloadResult(
                success=True,
                source_type=DownloadSourceType.GDRIVE_MIRROR,
                file_path=dl_file,
                used_mirror_id=used_id,
                message=f"Berhasil diunduh dari Google Drive mirror ({used_id}).",
            )
        # Fallback ke sumber resmi
        dl_file = try_official()
        if dl_file:
            return MirrorDownloadResult(
                success=True,
                source_type=DownloadSourceType.RESMI,
                file_path=dl_file,
                message="Berhasil diunduh dari sumber resmi.",
            )
    else:
        # Jalur standar: Sumber resmi terlebih dahulu
        dl_file = try_official()
        if dl_file:
            return MirrorDownloadResult(
                success=True,
                source_type=DownloadSourceType.RESMI,
                file_path=dl_file,
                message="Berhasil diunduh dari sumber resmi.",
            )
        # Failover ke GDrive Mirrors
        dl_file, used_id = try_gdrive_mirrors()
        if dl_file:
            return MirrorDownloadResult(
                success=True,
                source_type=DownloadSourceType.GDRIVE_MIRROR,
                file_path=dl_file,
                used_mirror_id=used_id,
                message=f"Berhasil diunduh dari Google Drive mirror ({used_id}) setelah failover.",
            )

    # 5. Seluruh Sumber Gagal: Buat entri Butuh Hosting Manual (PRD 6B.4)
    failure_msg = (
        f"[{app_name} {version}] tidak bisa diunduh dari sumber resmi "
        f"(alasan: {last_error_reason or 'semua mirror/sumber gagal'}). "
        f"Mohon taruh file '{target_path.name}' di Google Drive Anda dan berikan ID filenya."
    )
    log_error(failure_msg, app_id=app_id)

    hosting_entry = HostingEntry(
        app_id=app_id,
        app_name=app_name,
        version=version,
        filename=target_path.name,
        official_url=official_url or "",
        failure_reason=last_error_reason or "Semua sumber dan mirror tidak dapat dijangkau",
        expected_size=expected_size,
        expected_sha256=expected_sha256 or "BELUM_DIKETAHUI",
        file_ids=gdrive_ids,
    )

    return MirrorDownloadResult(
        success=False,
        file_path=None,
        message=failure_msg,
        error_type="BUTUH_HOSTING_MANUAL",
        hosting_entry=hosting_entry,
    )
