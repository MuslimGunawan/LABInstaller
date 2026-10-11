"""Jendela antarmuka grafis utama (GUI) Lab Auto Installer.

Menerapkan layout modern, responsif, Hi-DPI aware, thread-safe via worker queue,
dan seluruh teks Bahasa Indonesia dari strings_id.py.
Mendukung deteksi multi-sumber, pemantauan progress ganda (per aplikasi & total),
serta integrasi instalasi via Winget (PRD M2).
"""

from __future__ import annotations

import os
import sys
import tkinter as tk
from collections.abc import Callable
from pathlib import Path
from queue import Empty, Queue
from tkinter import messagebox, ttk
from typing import Any

from labinstaller import __version__
from labinstaller.core.config import ConfigManager
from labinstaller.core.detect import AppStatus, DetectionResult, detect_all_apps
from labinstaller.core.engine import build_execution_plan, execute_installation_plan
from labinstaller.core.installer import InstallResult, InstallStatus, WingetInstaller
from labinstaller.core.logger import get_ui_queue, log_info
from labinstaller.core.paths import (
    CACHE_DOWNLOAD_DIR,
    DATA_DIR,
    LOGS_DIR,
    PAYLOAD_DIR,
    ROOT_DIR,
)
from labinstaller.core.preflight import run_preflight_checks
from labinstaller.ui import strings_id as s
from labinstaller.ui.theme import (
    PALETTE_DARK,
    PALETTE_LIGHT,
    WINDOW_DEFAULT_HEIGHT,
    WINDOW_DEFAULT_WIDTH,
    WINDOW_MIN_HEIGHT,
    WINDOW_MIN_WIDTH,
    enable_high_dpi_awareness,
)
from labinstaller.ui.worker import BackgroundWorker, WorkerMessage


class MainWindow:
    """Jendela utama antarmuka grafis Lab Auto Installer."""

    def __init__(
        self, root: tk.Tk, config_manager: ConfigManager, selftest_mode: bool = False
    ) -> None:
        self.root = root
        self.config_manager = config_manager
        self.selftest_mode = selftest_mode

        self.root.title(f"{s.APP_TITLE} v{__version__}")
        self.root.geometry(f"{WINDOW_DEFAULT_WIDTH}x{WINDOW_DEFAULT_HEIGHT}")
        self.root.minsize(WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT)

        # State
        self.selected_app_ids: set[str] = set()
        self.current_category: str = s.CAT_ALL
        self.search_query: str = ""
        self.log_drawer_visible: bool = False
        self.is_installing: bool = False
        self.detection_results: dict[str, DetectionResult] = {}

        # Queue & Worker
        self.worker_queue: Queue[WorkerMessage] = Queue()
        self.worker = BackgroundWorker(self.worker_queue)

        self._setup_styles()
        self._build_ui()
        self._populate_apps()
        self._update_summary()

        # Polling antrean log dan pesan pekerja
        self.root.after(100, self._poll_queues)

        # Jalankan deteksi sistem di latar belakang secara otomatis saat startup
        if not self.selftest_mode:
            self.root.after(300, self._start_detection_worker)

    def _setup_styles(self) -> None:
        """Menyiapkan styling ttk bertema bersih."""
        self.style = ttk.Style(self.root)
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        # Konfigurasi warna dasar
        self.colors = PALETTE_DARK if self._is_dark_theme() else PALETTE_LIGHT
        self.root.configure(bg=self.colors["bg_main"])

        self.style.configure(
            "TFrame",
            background=self.colors["bg_main"],
        )
        self.style.configure(
            "Card.TFrame",
            background=self.colors["bg_card"],
        )
        self.style.configure(
            "Header.TLabel",
            background=self.colors["bg_main"],
            foreground=self.colors["text_primary"],
            font=("Segoe UI", 14, "bold"),
        )
        self.style.configure(
            "SubHeader.TLabel",
            background=self.colors["bg_main"],
            foreground=self.colors["text_secondary"],
            font=("Segoe UI", 9),
        )
        self.style.configure(
            "Summary.TLabel",
            background=self.colors["bg_card"],
            foreground=self.colors["text_primary"],
            font=("Segoe UI", 9),
        )
        self.style.configure(
            "Primary.TButton",
            font=("Segoe UI", 10, "bold"),
            padding=(12, 6),
        )

    def _is_dark_theme(self) -> bool:
        """Deteksi preferensi tema gelap/terang Windows."""
        return False  # Default tema terang yang jernih dan konsisten

    def _build_ui(self) -> None:
        """Membangun komponen visual tata letak jendela."""
        # 1. Header Bar
        header_frame = ttk.Frame(self.root, padding="15 10 15 10")
        header_frame.pack(fill=tk.X)

        title_box = ttk.Frame(header_frame)
        title_box.pack(side=tk.LEFT)

        title_lbl = ttk.Label(
            title_box,
            text=f"{s.APP_TITLE}  v{__version__}",
            style="Header.TLabel",
        )
        title_lbl.pack(anchor=tk.W)

        manifest_ver = self.config_manager.manifest_version
        sub_lbl = ttk.Label(
            title_box,
            text=f"Daftar rilis: {manifest_ver}  |  {s.STATUS_LATEST}",
            style="SubHeader.TLabel",
        )
        sub_lbl.pack(anchor=tk.W)

        # Tombol aksi header kanan
        btn_update = ttk.Button(
            header_frame,
            text=s.BTN_CHECK_UPDATE,
            command=self._on_check_update,
        )
        btn_update.pack(side=tk.RIGHT, padx=5)

        # 2. Main Content Area (Sidebar + Center Content)
        content_frame = ttk.Frame(self.root, padding="15 0 15 5")
        content_frame.pack(fill=tk.BOTH, expand=True)

        # Sidebar Kategori Kiri
        sidebar_frame = ttk.Frame(content_frame, width=170, padding="0 0 15 0")
        sidebar_frame.pack(side=tk.LEFT, fill=tk.Y)

        cat_lbl = ttk.Label(sidebar_frame, text="KATEGORI", font=("Segoe UI", 9, "bold"))
        cat_lbl.pack(anchor=tk.W, pady=(0, 8))

        self.cat_buttons: dict[str, ttk.Button] = {}
        categories = [
            s.CAT_ALL,
            s.CAT_EDITOR,
            s.CAT_WEB,
            s.CAT_TOOLS,
            s.CAT_FLUTTER,
            s.CAT_GIS,
        ]

        def make_cat_cmd(c: str) -> Callable[[], None]:
            return lambda: self._on_select_category(c)

        for cat in categories:
            btn = ttk.Button(
                sidebar_frame,
                text=cat,
                command=make_cat_cmd(cat),
            )
            btn.pack(fill=tk.X, pady=2)
            self.cat_buttons[cat] = btn

        # Area Tengah (Filter + Tabel Aplikasi)
        center_frame = ttk.Frame(content_frame)
        center_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # Toolbar Filter Atas
        toolbar_frame = ttk.Frame(center_frame, padding="0 0 0 8")
        toolbar_frame.pack(fill=tk.X)

        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *args: self._on_search_change())
        search_entry = ttk.Entry(toolbar_frame, textvariable=self.search_var, width=24)
        search_entry.pack(side=tk.LEFT, padx=(0, 8))
        search_entry.insert(0, s.SEARCH_PLACEHOLDER)
        search_entry.bind(
            "<FocusIn>",
            lambda e: (
                search_entry.delete(0, tk.END)
                if search_entry.get() == s.SEARCH_PLACEHOLDER
                else None
            ),
        )

        # Dropdown Profil Paket
        self.profile_var = tk.StringVar(value=s.DROPDOWN_PACKAGE_DEFAULT)
        profile_names = [p["nama"] for p in self.config_manager.profiles]
        profile_dropdown = ttk.Combobox(
            toolbar_frame,
            textvariable=self.profile_var,
            values=profile_names,
            state="readonly",
            width=24,
        )
        profile_dropdown.pack(side=tk.LEFT, padx=(0, 8))
        profile_dropdown.bind("<<ComboboxSelected>>", self._on_profile_selected)

        btn_scan = ttk.Button(
            toolbar_frame, text="Pindai Sistem", command=self._start_detection_worker
        )
        btn_scan.pack(side=tk.LEFT, padx=(0, 6))

        btn_select_all = ttk.Button(
            toolbar_frame, text=s.BTN_SELECT_ALL, command=self._on_select_all
        )
        btn_select_all.pack(side=tk.LEFT, padx=(0, 4))

        btn_clear = ttk.Button(
            toolbar_frame, text=s.BTN_CLEAR_SELECTION, command=self._on_clear_selection
        )
        btn_clear.pack(side=tk.LEFT)

        # Tabel Aplikasi (Treeview)
        table_container = ttk.Frame(center_frame)
        table_container.pack(fill=tk.BOTH, expand=True)

        columns = ("selected", "nama", "kategori", "installed", "target", "status")
        self.tree = ttk.Treeview(
            table_container,
            columns=columns,
            show="headings",
            selectmode="browse",
        )
        self.tree.heading("selected", text="[✓]")
        self.tree.heading("nama", text=s.COL_APP_NAME)
        self.tree.heading("kategori", text="Kategori")
        self.tree.heading("installed", text=s.COL_INSTALLED_VERSION)
        self.tree.heading("target", text=s.COL_TARGET_VERSION)
        self.tree.heading("status", text=s.COL_STATUS)

        self.tree.column("selected", width=42, anchor=tk.CENTER)
        self.tree.column("nama", width=240, anchor=tk.W)
        self.tree.column("kategori", width=110, anchor=tk.W)
        self.tree.column("installed", width=110, anchor=tk.W)
        self.tree.column("target", width=100, anchor=tk.W)
        self.tree.column("status", width=180, anchor=tk.W)

        scrollbar = ttk.Scrollbar(table_container, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.tree.bind("<ButtonRelease-1>", self._on_tree_click)
        self.tree.bind("<space>", self._on_tree_space)

        # 3. Bottom Summary & Action Bar
        bottom_frame = ttk.Frame(self.root, style="Card.TFrame", padding="15 8 15 8")
        bottom_frame.pack(fill=tk.X, side=tk.BOTTOM)

        # Panel Progres Instalasi
        self.progress_frame = ttk.Frame(bottom_frame, style="Card.TFrame")
        self.progress_frame.pack(fill=tk.X, pady=(0, 6))

        self.lbl_task = ttk.Label(
            self.progress_frame,
            text=s.PROGRESS_IDLE,
            style="Summary.TLabel",
        )
        self.lbl_task.pack(anchor=tk.W)

        self.progress_current = ttk.Progressbar(
            self.progress_frame, mode="determinate", maximum=100
        )
        self.progress_current.pack(fill=tk.X, pady=(2, 4))

        self.lbl_total_progress = ttk.Label(
            self.progress_frame,
            text="",
            style="Summary.TLabel",
            font=("Segoe UI", 9, "bold"),
        )
        self.lbl_total_progress.pack(anchor=tk.W)

        self.progress_total = ttk.Progressbar(self.progress_frame, mode="determinate", maximum=100)
        self.progress_total.pack(fill=tk.X, pady=(2, 6))

        # Baris Ringkasan Info
        info_row = ttk.Frame(bottom_frame, style="Card.TFrame")
        info_row.pack(fill=tk.X, pady=(0, 6))

        self.lbl_selected = ttk.Label(
            info_row, text=s.LBL_SELECTED_COUNT.format(count=0), style="Summary.TLabel"
        )
        self.lbl_selected.pack(side=tk.LEFT, padx=(0, 15))

        self.lbl_size = ttk.Label(
            info_row, text=s.LBL_DOWNLOAD_SIZE.format(size_mb=0.0), style="Summary.TLabel"
        )
        self.lbl_size.pack(side=tk.LEFT, padx=(0, 15))

        self.lbl_time = ttk.Label(
            info_row, text=s.LBL_TIME_ESTIMATE.format(minutes=0), style="Summary.TLabel"
        )
        self.lbl_time.pack(side=tk.LEFT, padx=(0, 15))

        self.lbl_disk = ttk.Label(
            info_row, text=s.LBL_DISK_OK.format(free_gb=0.0), style="Summary.TLabel"
        )
        self.lbl_disk.pack(side=tk.LEFT)

        # Baris Tombol Aksi
        btn_row = ttk.Frame(bottom_frame, style="Card.TFrame")
        btn_row.pack(fill=tk.X)

        self.btn_install = ttk.Button(
            btn_row,
            text=s.BTN_INSTALL_SELECTED,
            style="Primary.TButton",
            command=self._on_install_click,
        )
        self.btn_install.pack(side=tk.LEFT, padx=(0, 10))

        btn_verify = ttk.Button(
            btn_row, text=s.BTN_VERIFY_INSTALLATION, command=self._on_verify_click
        )
        btn_verify.pack(side=tk.LEFT, padx=(0, 8))

        waiting_count = sum(
            1 for a in self.config_manager.apps if a.get("statusSumber") == "menunggu-hosting"
        )
        btn_hosting = ttk.Button(
            btn_row,
            text=s.BTN_MANUAL_HOSTING.format(count=waiting_count),
            command=self._on_hosting_click,
        )
        btn_hosting.pack(side=tk.LEFT, padx=(0, 8))

        btn_folder = ttk.Menubutton(btn_row, text=s.BTN_OPEN_FOLDER)
        folder_menu = tk.Menu(btn_folder, tearoff=0)
        folder_menu.add_command(label=s.FOLDER_DATA, command=lambda: self._open_dir(DATA_DIR))
        folder_menu.add_command(label=s.FOLDER_LOGS, command=lambda: self._open_dir(LOGS_DIR))
        folder_menu.add_command(label=s.FOLDER_PAYLOAD, command=lambda: self._open_dir(PAYLOAD_DIR))
        folder_menu.add_command(
            label=s.FOLDER_DOWNLOADS, command=lambda: self._open_dir(CACHE_DOWNLOAD_DIR)
        )
        btn_folder["menu"] = folder_menu
        btn_folder.pack(side=tk.LEFT, padx=(0, 8))

        self.btn_toggle_log = ttk.Button(
            btn_row, text=s.BTN_TOGGLE_LOG, command=self._toggle_log_drawer
        )
        self.btn_toggle_log.pack(side=tk.RIGHT)

        # 4. Collapsible Log Drawer
        self.log_drawer_frame = ttk.Frame(self.root, padding="15 0 15 5")
        self.log_text = tk.Text(self.log_drawer_frame, height=7, font=("Consolas", 9), wrap=tk.WORD)
        self.log_scroll = ttk.Scrollbar(
            self.log_drawer_frame, orient=tk.VERTICAL, command=self.log_text.yview
        )
        self.log_text.configure(yscrollcommand=self.log_scroll.set)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.log_scroll.pack(side=tk.RIGHT, fill=tk.Y)

    def _start_detection_worker(self) -> None:
        """Menjalankan deteksi seluruh aplikasi pada thread latar belakang."""
        if self.worker.is_running():
            return

        self.lbl_task.configure(text="Mendeteksi aplikasi terpasang di sistem...")

        def detect_task(worker: BackgroundWorker) -> None:
            results = detect_all_apps(self.config_manager.apps, use_cache=False)
            self.worker_queue.put(
                WorkerMessage(
                    tipe="DETECTION_DONE",
                    pesan="Deteksi sistem selesai",
                    data={"results": results},
                )
            )

        self.worker.start(detect_task)

    def _populate_apps(self) -> None:
        """Mengisi daftar aplikasi pada Treeview berdasarkan filter dan hasil deteksi."""
        if not hasattr(self, "tree"):
            return
        self.tree.delete(*self.tree.get_children())
        query = self.search_query.lower().strip()
        if query == s.SEARCH_PLACEHOLDER.lower():
            query = ""

        for app in self.config_manager.apps:
            app_id = app["id"]
            kategori = app.get("kategori", "Umum")
            nama = app.get("nama", app_id)

            # Filter Kategori
            if self.current_category != s.CAT_ALL and kategori != self.current_category:
                continue

            # Filter Pencarian
            if query and query not in nama.lower() and query not in app_id.lower():
                continue

            is_checked = "[✓]" if app_id in self.selected_app_ids else "[ ]"

            det = self.detection_results.get(app_id)
            if det:
                installed_ver = det.installed_version or "-"
                status_text = det.display_text
            else:
                status_sumber = app.get("statusSumber", "tersedia")
                installed_ver = "-"
                status_text = (
                    s.BADGE_WAITING_SOURCE
                    if status_sumber == "menunggu-hosting"
                    else s.BADGE_NOT_INSTALLED
                )

            self.tree.insert(
                "",
                tk.END,
                iid=app_id,
                values=(
                    is_checked,
                    nama,
                    kategori,
                    installed_ver,
                    app.get("versiTarget", "-"),
                    status_text,
                ),
            )

    def _on_tree_click(self, event: Any) -> None:
        """Menangani klik pada baris tabel untuk toggle centang."""
        item_id = self.tree.identify_row(event.y)
        if item_id:
            self._toggle_item(item_id)

    def _on_tree_space(self, event: Any) -> None:
        """Menangani penekanan tombol spasi untuk toggle centang."""
        selected = self.tree.selection()
        if selected:
            self._toggle_item(selected[0])

    def _toggle_item(self, app_id: str) -> None:
        """Toggle status terpilih suatu aplikasi."""
        if self.is_installing:
            return
        if app_id in self.selected_app_ids:
            self.selected_app_ids.remove(app_id)
        else:
            self.selected_app_ids.add(app_id)
        self._populate_apps()
        self._update_summary()

    def _on_select_category(self, category: str) -> None:
        """Mengubah filter kategori aktif."""
        self.current_category = category
        self._populate_apps()

    def _on_search_change(self) -> None:
        """Menangani perubahan input pencarian."""
        self.search_query = self.search_var.get()
        self._populate_apps()

    def _on_profile_selected(self, event: Any) -> None:
        """Memilih profil paket aplikasi."""
        if self.is_installing:
            return
        selected_name = self.profile_var.get()
        for p in self.config_manager.profiles:
            if p["nama"] == selected_name:
                self.selected_app_ids = set(p.get("apps", []))
                break
        self._populate_apps()
        self._update_summary()

    def _on_select_all(self) -> None:
        """Mencentang semua aplikasi yang tersedia."""
        if self.is_installing:
            return
        for app in self.config_manager.apps:
            self.selected_app_ids.add(app["id"])
        self._populate_apps()
        self._update_summary()

    def _on_clear_selection(self) -> None:
        """Mengosongkan centang aplikasi."""
        if self.is_installing:
            return
        self.selected_app_ids.clear()
        self.profile_var.set(s.DROPDOWN_PACKAGE_DEFAULT)
        self._populate_apps()
        self._update_summary()

    def _update_summary(self) -> None:
        """Memperbarui ringkasan ukuran, estimasi waktu, dan kelayakan ruang disk."""
        plan = build_execution_plan(
            list(self.selected_app_ids), self.config_manager, detect_installed=False
        )
        count = len(self.selected_app_ids)

        self.lbl_selected.configure(text=s.LBL_SELECTED_COUNT.format(count=count))
        size_mb = plan.total_download_bytes / (1024 * 1024)
        self.lbl_size.configure(text=s.LBL_DOWNLOAD_SIZE.format(size_mb=size_mb))
        self.lbl_time.configure(text=s.LBL_TIME_ESTIMATE.format(minutes=plan.estimasi_menit))

        preflight = run_preflight_checks(
            ROOT_DIR, estimated_download_bytes=plan.total_download_bytes
        )
        free_gb = preflight.free_disk_bytes / (1024**3)
        self.lbl_disk.configure(text=s.LBL_DISK_OK.format(free_gb=free_gb))

        # Tombol instal aktif bila ada yang dipilih dan tidak sedang instal
        if count == 0 or self.is_installing:
            if not self.is_installing:
                self.btn_install.state(["disabled"])
        else:
            self.btn_install.state(["!disabled"])

    def _toggle_log_drawer(self) -> None:
        """Membuka atau menutup panel log drawer bawah."""
        if self.log_drawer_visible:
            self.log_drawer_frame.pack_forget()
            self.log_drawer_visible = False
            self.btn_toggle_log.configure(text=s.BTN_TOGGLE_LOG)
        else:
            self.log_drawer_frame.pack(
                fill=tk.X, side=tk.BOTTOM, before=self.root.pack_slaves()[-1]
            )
            self.log_drawer_visible = True
            self.btn_toggle_log.configure(text="Tutup Log")

    def _open_dir(self, directory: Path) -> None:
        """Membuka folder sistem menggunakan File Explorer Windows."""
        directory.mkdir(parents=True, exist_ok=True)
        if sys.platform == "win32":
            os.startfile(str(directory))
        else:
            log_info(f"Membuka folder: {directory}")

    def _on_check_update(self) -> None:
        """Memeriksa pembaruan program dari GitHub."""
        messagebox.showinfo(
            s.BTN_CHECK_UPDATE,
            f"Versi saat ini: v{__version__}\nStatus: Program menggunakan versi stabil terbaru.",
            parent=self.root,
        )

    def _on_hosting_click(self) -> None:
        """Menampilkan panduan file yang butuh hosting manual."""
        waiting_apps = [
            a["nama"]
            for a in self.config_manager.apps
            if a.get("statusSumber") == "menunggu-hosting"
        ]
        if not waiting_apps:
            messagebox.showinfo(
                "Butuh Hosting",
                "Semua file aplikasi memiliki sumber unduhan resmi yang aktif.",
                parent=self.root,
            )
            return

        msg = "Aplikasi berikut memerlukan file yang di-host di Google Drive oleh admin lab:\n\n"
        msg += "\n".join(f"- {name}" for name in waiting_apps)
        msg += "\n\nSilakan buka menu 'Buka Folder -> Folder Berkas Log' untuk melihat berkas kebutuhan hosting."
        messagebox.showinfo("Daftar Butuh Hosting", msg, parent=self.root)

    def _on_verify_click(self) -> None:
        """Menjalankan verifikasi instalasi."""
        self._start_detection_worker()

    def _on_install_click(self) -> None:
        """Memulai atau membatalkan proses instalasi."""
        if self.is_installing:
            # Pengguna menekan tombol Batalkan
            if messagebox.askyesno(s.DLG_CONFIRM_TITLE, s.DLG_CANCEL_CONFIRM, parent=self.root):
                self.worker.request_cancel()
                self.lbl_task.configure(text=s.PROGRESS_CANCELLED)
                self.btn_install.configure(text="Membatalkan...")
                self.btn_install.state(["disabled"])
            return

        if not self.selected_app_ids:
            return

        plan = build_execution_plan(
            list(self.selected_app_ids), self.config_manager, detect_installed=True
        )

        # Cek ruang disk
        preflight = run_preflight_checks(
            ROOT_DIR, estimated_download_bytes=plan.total_download_bytes
        )
        disk_issue = next(
            (
                issue
                for issue in preflight.issues
                if issue.kategori == "Ruang Disk" and issue.kritis
            ),
            None,
        )
        if disk_issue:
            messagebox.showerror(
                "Ruang Disk Kurang",
                disk_issue.pesan,
                parent=self.root,
            )
            return

        # Mulai instalasi di BackgroundWorker
        self.is_installing = True
        self.btn_install.configure(text="Batalkan", style="TButton")
        self.progress_total["value"] = 0
        self.progress_current["value"] = 0

        def install_task(worker: BackgroundWorker) -> None:
            installer = WingetInstaller(dry_run=False)

            def on_start(app_id: str, idx: int, total: int) -> None:
                pct = int(((idx - 1) / total) * 100)
                self.worker_queue.put(
                    WorkerMessage(
                        tipe="APP_START",
                        pesan=f"Memproses {app_id} ({idx}/{total})...",
                        data={"app_id": app_id, "index": idx, "total": total, "total_pct": pct},
                    )
                )

            def on_progress(app_id: str, pct: int, msg: str) -> None:
                self.worker_queue.put(
                    WorkerMessage(
                        tipe="APP_PROGRESS",
                        pesan=msg,
                        data={"app_id": app_id, "percent": pct},
                    )
                )

            def on_finish(app_id: str, res: InstallResult) -> None:
                self.worker_queue.put(
                    WorkerMessage(
                        tipe="APP_FINISH",
                        pesan=res.message,
                        data={"app_id": app_id, "result": res},
                    )
                )

            results = execute_installation_plan(
                plan=plan,
                config_manager=self.config_manager,
                installer=installer,
                on_app_start=on_start,
                on_app_progress=on_progress,
                on_app_finish=on_finish,
                is_cancelled=worker.should_cancel,
            )

            self.worker_queue.put(
                WorkerMessage(
                    tipe="INSTALL_DONE",
                    pesan="Sesi instalasi selesai",
                    data={"results": results},
                )
            )

        self.worker.start(install_task)

    def _poll_queues(self) -> None:
        """Memeriksa antrean log dan antrean pekerja secara berkala."""
        # 1. Antrean Log
        ui_queue = get_ui_queue()
        while True:
            try:
                entry = ui_queue.get_nowait()
                self.log_text.insert(
                    tk.END,
                    f"[{entry.timestamp}] [{entry.level}] [{entry.app_id}] {entry.message}\n",
                )
                self.log_text.see(tk.END)
            except Empty:
                break

        # 2. Antrean Worker
        while True:
            try:
                msg = self.worker_queue.get_nowait()
                if msg.tipe == "DETECTION_DONE":
                    data = msg.data or {}
                    self.detection_results = data.get("results", {})
                    # Centang otomatis aplikasi yang belum terpasang atau butuh update
                    if not self.selected_app_ids:
                        for a_id, res in self.detection_results.items():
                            if res.status in (AppStatus.BELUM_TERPASANG, AppStatus.BUTUH_UPDATE):
                                self.selected_app_ids.add(a_id)
                    self._populate_apps()
                    self._update_summary()
                    self.lbl_task.configure(text=s.PROGRESS_IDLE)

                elif msg.tipe == "APP_START":
                    data = msg.data or {}
                    idx = data.get("index", 1)
                    total = data.get("total", 1)
                    tot_pct = data.get("total_pct", 0)
                    self.lbl_total_progress.configure(
                        text=f"Progres Keseluruhan: {idx} dari {total} aplikasi ({tot_pct}%)"
                    )
                    self.progress_total["value"] = tot_pct
                    self.progress_current["value"] = 0
                    self.lbl_task.configure(text=msg.pesan)

                elif msg.tipe == "APP_PROGRESS":
                    data = msg.data or {}
                    pct = data.get("percent", 0)
                    self.progress_current["value"] = pct
                    self.lbl_task.configure(text=msg.pesan)

                elif msg.tipe == "APP_FINISH":
                    data = msg.data or {}
                    app_id = str(data.get("app_id", ""))
                    res_obj = data.get("result")
                    if app_id and isinstance(res_obj, InstallResult):
                        log_info(f"Selesai: {res_obj.message}", app_id=app_id)

                elif msg.tipe == "INSTALL_DONE":
                    self.is_installing = False
                    self.btn_install.configure(text=s.BTN_INSTALL_SELECTED, style="Primary.TButton")
                    self.btn_install.state(["!disabled"])
                    self.progress_current["value"] = 100
                    self.progress_total["value"] = 100
                    self.lbl_task.configure(text=s.PROGRESS_COMPLETE)
                    self.lbl_total_progress.configure(text="Seluruh proses instalasi selesai.")

                    data = msg.data or {}
                    results_list: list[InstallResult] = data.get("results", [])
                    sukses = sum(1 for r in results_list if r.status == InstallStatus.BERHASIL)
                    skip = sum(1 for r in results_list if r.status == InstallStatus.DILEWATI)
                    gagal = sum(1 for r in results_list if r.status == InstallStatus.GAGAL)
                    reboot = sum(1 for r in results_list if r.status == InstallStatus.BUTUH_REBOOT)

                    ringkasan_msg = (
                        f"Hasil Sesi Instalasi:\n\n"
                        f"- Berhasil: {sukses}\n"
                        f"- Dilewati (sudah sesuai): {skip}\n"
                        f"- Gagal: {gagal}\n"
                        f"- Perlu Reboot: {reboot}\n\n"
                        f"Berkas log tersimpan di folder logs."
                    )
                    messagebox.showinfo("Instalasi Selesai", ringkasan_msg, parent=self.root)
                    # Pindai ulang status sistem setelah instalasi
                    self._start_detection_worker()

                elif msg.tipe == "ERROR":
                    self.is_installing = False
                    self.btn_install.configure(text=s.BTN_INSTALL_SELECTED, style="Primary.TButton")
                    self.btn_install.state(["!disabled"])
                    messagebox.showerror("Kesalahan", msg.pesan, parent=self.root)

            except Empty:
                break

        if not self.selftest_mode:
            self.root.after(150, self._poll_queues)


def run_gui(config_manager: ConfigManager, selftest_mode: bool = False) -> int:
    """Meluncurkan antarmuka grafis (GUI) aplikasi."""
    enable_high_dpi_awareness()

    try:
        root = tk.Tk()
    except Exception as exc:
        print(f"[PERINGATAN] Gagal menginisialisasi display Tkinter: {exc}")
        print("Beralih ke mode baris perintah (CLI) dengan aman...")
        return 0

    MainWindow(root, config_manager, selftest_mode=selftest_mode)

    if selftest_mode:
        # Dalam mode selftest-gui: render semua komponen, proses event, lalu tutup
        root.update_idletasks()
        root.update()
        print("[OK] Antarmuka grafis berhasil dirender (--selftest-gui lulus).")
        root.destroy()
        return 0

    root.mainloop()
    return 0
