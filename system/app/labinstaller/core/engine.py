"""Mesin orkestrasi utama (Engine) Lab Auto Installer.

Bertanggung jawab menyusun rencana eksekusi, menyelesaikan dependensi secara topologis,
menjalankan simulasi rencana (--dry-run), dan pengujian mandiri (--selftest).
Modul ini mandiri dan tidak boleh mengimpor apa pun dari labinstaller.ui.
"""

from __future__ import annotations

import importlib
import platform
import sys
from dataclasses import dataclass, field
from typing import Any

from labinstaller.core.config import ConfigManager, check_all_configs
from labinstaller.core.logger import log_info
from labinstaller.core.paths import (
    ROOT_DIR,
    START_BAT,
)
from labinstaller.core.preflight import run_preflight_checks


@dataclass
class AppPlanItem:
    """Satu item dalam rencana eksekusi instalasi."""

    app_id: str
    nama: str
    kategori: str
    versi_target: str
    versi_terpasang: str | None
    status: str  # SESUAI, BELUM_TERPASANG, VERSI_BEDA, MENUNGGU_SUMBER
    metode: str
    ukuran_bytes: int
    dependensi: list[str] = field(default_factory=list)
    alasan_dependensi: str | None = None


@dataclass
class PlanResult:
    """Hasil penyusunan rencana eksekusi lengkap."""

    items: list[AppPlanItem]
    total_download_bytes: int
    estimasi_menit: float
    peringatan: list[str] = field(default_factory=list)


def resolve_dependencies(
    selected_ids: list[str],
    apps_by_id: dict[str, dict[str, Any]],
) -> tuple[list[str], dict[str, str]]:
    """Menyelesaikan urutan dependensi secara topologis.

    Returns:
        (urutan_terurut, kamus_alasan_karena_dependensi)
    """
    resolved: list[str] = []
    visited: set[str] = set()
    visiting: set[str] = set()
    reasons: dict[str, str] = {}

    def visit(app_id: str, parent_id: str | None = None) -> None:
        if app_id in visiting:
            # Siklus terdeteksi, lewati untuk mencegah rekursi tak berhingga
            return
        if app_id in visited:
            return

        visiting.add(app_id)
        app_meta = apps_by_id.get(app_id)
        if app_meta:
            for dep_id in app_meta.get("dependensi", []):
                if dep_id in apps_by_id:
                    if dep_id not in selected_ids and dep_id not in reasons:
                        reasons[dep_id] = f"Dibutuhkan oleh {app_meta.get('nama', app_id)}"
                    visit(dep_id, app_id)

        visiting.remove(app_id)
        visited.add(app_id)
        resolved.append(app_id)

    for selected_id in selected_ids:
        if selected_id not in visited and selected_id in apps_by_id:
            visit(selected_id)

    return resolved, reasons


def build_execution_plan(
    selected_app_ids: list[str],
    config_manager: ConfigManager,
) -> PlanResult:
    """Menyusun rencana instalasi berurutan berdasarkan dependensi dan status sumber."""
    all_apps = config_manager.apps
    apps_by_id = {app["id"]: app for app in all_apps}
    warnings: list[str] = list(config_manager.warnings)

    ordered_ids, reasons = resolve_dependencies(selected_app_ids, apps_by_id)

    plan_items: list[AppPlanItem] = []
    total_bytes = 0

    for app_id in ordered_ids:
        meta = apps_by_id[app_id]
        status_sumber = meta.get("statusSumber", "tersedia")

        # Status awal sebelum deteksi nyata di M2
        if status_sumber == "menunggu-hosting":
            status = "MENUNGGU_SUMBER"
        else:
            status = "BELUM_TERPASANG"

        ukuran = int(meta.get("ukuran", 0))
        total_bytes += ukuran

        plan_items.append(
            AppPlanItem(
                app_id=app_id,
                nama=meta.get("nama", app_id),
                kategori=meta.get("kategori", "Umum"),
                versi_target=meta.get("versiTarget", "unknown"),
                versi_terpasang=None,
                status=status,
                metode=meta.get("metode", "winget"),
                ukuran_bytes=ukuran,
                dependensi=meta.get("dependensi", []),
                alasan_dependensi=reasons.get(app_id),
            )
        )

    # Estimasi waktu unduhan berdasarkan koneksi 20 Mbps (±2.5 MB/s)
    # total_bytes / (2.5 * 1024 * 1024) detik -> menit
    mbps_effective_bytes_per_sec = (20.0 * 1024 * 1024) / 8.0  # ~2.62 MB/s
    estimasi_menit = round((total_bytes / mbps_effective_bytes_per_sec) / 60.0, 1)

    return PlanResult(
        items=plan_items,
        total_download_bytes=total_bytes,
        estimasi_menit=estimasi_menit,
        peringatan=warnings,
    )


def run_dry_run(
    selected_app_ids: list[str],
    config_manager: ConfigManager,
    profile_name: str | None = None,
) -> int:
    """Menjalankan mode simulasi rencana instalasi (--dry-run)."""
    header = f"=== SIMULASI RENCANA INSTALASI (DRY-RUN) {f'[{profile_name}]' if profile_name else ''} ==="
    log_info(header)
    print("\n" + header)

    plan = build_execution_plan(selected_app_ids, config_manager)

    # Jalankan pre-flight ringan
    preflight = run_preflight_checks(
        target_drive=ROOT_DIR,
        estimated_download_bytes=plan.total_download_bytes,
    )

    print(f"Status Pre-flight: {'LULUS' if preflight.lulus else 'PERINGATAN/GAGAL'}")
    for issue in preflight.issues:
        prefix = "[KRITIS]" if issue.kritis else "[INFO]"
        print(f"  {prefix} {issue.kategori}: {issue.pesan}")

    print(f"\nJumlah aplikasi dalam rencana: {len(plan.items)}")
    total_mb = plan.total_download_bytes / (1024 * 1024)
    print(
        f"Estimasi total unduhan       : {total_mb:.1f} MB (~{plan.estimasi_menit} menit @ 20 Mbps)"
    )
    print("-" * 80)
    print(f"{'No':<3} | {'Aplikasi':<32} | {'Target':<12} | {'Metode':<8} | {'Status'}")
    print("-" * 80)

    for idx, item in enumerate(plan.items, 1):
        dep_info = f" ({item.alasan_dependensi})" if item.alasan_dependensi else ""
        print(
            f"{idx:<3} | {item.nama[:32]:<32} | {item.versi_target:<12} | {item.metode:<8} | {item.status}{dep_info}"
        )

    print("-" * 80)
    if plan.peringatan:
        print("\nPeringatan Konfigurasi:")
        for w in plan.peringatan:
            print(f"  - {w}")

    print("\n[OK] Simulasi dry-run selesai. Tidak ada perubahan yang dilakukan ke sistem.\n")
    return 0


def run_selftest() -> int:
    """Menjalankan pengujian mandiri (--selftest).

    Mengimpor seluruh modul, memvalidasi konfigurasi, memeriksa integritas runtime,
    Tkinter, dan utilitas pendukung tanpa mengubah sistem. Exit code 0 jika lulus.
    """
    print("\n=== UJI MANDIRI (SELFTEST) LAB AUTO INSTALLER ===")
    selftest_ok = True

    # 1. Verifikasi Direktori Root & Launcher
    print("[1/6] Memeriksa struktur direktori root...")
    if not START_BAT.exists():
        print("  [GAGAL] Start.bat tidak ditemukan di root program!")
        selftest_ok = False
    else:
        print(f"  [OK] Root terdeteksi: {ROOT_DIR}")

    # 2. Impor Seluruh Modul Core & UI
    print("[2/6] Mengimpor seluruh modul program...")
    modules_to_test = [
        "labinstaller.core.paths",
        "labinstaller.core.logger",
        "labinstaller.core.config",
        "labinstaller.core.preflight",
        "labinstaller.core.engine",
        "labinstaller.cli",
        "labinstaller.ui.strings_id",
        "labinstaller.ui.theme",
        "labinstaller.ui.worker",
    ]
    for mod_name in modules_to_test:
        try:
            importlib.import_module(mod_name)
            print(f"  [OK] Modul '{mod_name}' berhasil diimpor.")
        except Exception as exc:
            print(f"  [GAGAL] Modul '{mod_name}' gagal diimpor: {exc}")
            selftest_ok = False

    # 3. Pemeriksaan Batas Arsitektur (core tidak boleh impor ui)
    print("[3/6] Memeriksa kepatuhan batas arsitektur (core tidak boleh impor ui)...")
    core_modules = [m for name, m in sys.modules.items() if name.startswith("labinstaller.core.")]
    for cm in core_modules:
        cm_dict = getattr(cm, "__dict__", {})
        for _var_name, var_val in cm_dict.items():
            mod_origin = getattr(var_val, "__module__", "")
            if "labinstaller.ui" in str(mod_origin):
                print(f"  [GAGAL] Pelanggaran arsitektur: modul core '{cm.__name__}' mengimpor UI!")
                selftest_ok = False
    print("  [OK] Batas arsitektur core <-> ui bersih.")

    # 4. Validasi Konfigurasi & Skema
    print("[4/6] Memvalidasi seluruh berkas konfigurasi...")
    configs_ok, reports = check_all_configs()
    for rep in reports:
        print(f"  {rep}")
    if not configs_ok:
        selftest_ok = False

    # 5. Pemeriksaan Pustaka GUI (Tkinter)
    print("[5/6] Memeriksa ketersediaan pustaka GUI (Tkinter)...")
    try:
        import tkinter

        tk_ver = getattr(tkinter, "TkVersion", 0.0)
        print(f"  [OK] Tkinter tersedia (Tcl/Tk versi {tk_ver}).")
    except Exception as exc:
        print(f"  [PERINGATAN] Tkinter tidak dapat dimuat: {exc}")
        # Pada lingkungan headless CI Linux, berikan toleransi bila di-skip
        if platform.system() == "Windows":
            selftest_ok = False

    # 6. Pre-flight Sistem Ringan
    print("[6/6] Memeriksa kelayakan preflight sistem...")
    preflight = run_preflight_checks(target_drive=ROOT_DIR)
    print(
        f"  [INFO] Admin: {preflight.is_admin}, Internet: {preflight.has_internet}, winget: {preflight.has_winget}"
    )
    for issue in preflight.issues:
        print(f"  [{'KRITIS' if issue.kritis else 'INFO'}] {issue.kategori}: {issue.pesan}")

    print("-" * 60)
    if selftest_ok:
        print("HASIL: UJI MANDIRI (SELFTEST) LULUS (Exit Code 0)\n")
        return 0
    else:
        print("HASIL: UJI MANDIRI (SELFTEST) GAGAL (Exit Code 4)\n")
        return 4
