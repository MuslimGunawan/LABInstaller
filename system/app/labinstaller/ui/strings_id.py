"""Kamus teks antarmuka (Bahasa Indonesia) terpusat untuk Lab Auto Installer.

Semua teks antarmuka grafis (GUI) dan dialog wajib berada di berkas ini.
"""

from __future__ import annotations

# Informasi Aplikasi
APP_TITLE = "LAB AUTO INSTALLER"
APP_SUBTITLE = "Otomasi Penyiapan Komputer Laboratorium Windows"

# Status Header
STATUS_LATEST = "✔ Terbaru"
STATUS_UPDATE_AVAILABLE = "⬆ Pembaruan Tersedia"
STATUS_OFFLINE = "Offline"
STATUS_DEV = "Versi Pengembangan"

# Tombol Header
BTN_CHECK_UPDATE = "Cek Update"

# Navigasi & Kategori
CAT_ALL = "Semua"
CAT_EDITOR = "Editor & IDE"
CAT_WEB = "Web Stack"
CAT_TOOLS = "Bahasa & Tools"
CAT_FLUTTER = "Flutter"
CAT_GIS = "GIS"

# Kolom Tabel
COL_SELECT = "Pilih"
COL_APP_NAME = "Aplikasi"
COL_TARGET_VERSION = "Versi Target"
COL_INSTALLED_VERSION = "Terpasang"
COL_STATUS = "Status"

# Lencana Status
BADGE_MATCH = "Sesuai"
BADGE_NOT_INSTALLED = "Belum Terpasang"
BADGE_DIFF_VERSION = "Versi Beda"
BADGE_WAITING_SOURCE = "Menunggu Sumber"
BADGE_CORRUPTED = "Rusak"
BADGE_REBOOT_REQUIRED = "Butuh Reboot"

# Pencarian & Filter
SEARCH_PLACEHOLDER = "Cari aplikasi..."
DROPDOWN_PACKAGE_DEFAULT = "Pilih Paket Profil..."
BTN_CLEAR_SELECTION = "Kosongkan"
BTN_SELECT_ALL = "Pilih Semua"

# Panel Ringkasan Bawah
LBL_SELECTED_COUNT = "Dipilih {count} aplikasi"
LBL_DOWNLOAD_SIZE = "Unduhan ±{size_mb:.1f} MB"
LBL_TIME_ESTIMATE = "Estimasi ±{minutes:.0f} menit (@20 Mbps)"
LBL_DISK_OK = "Ruang disk mencukupi ({free_gb:.1f} GB)"
LBL_DISK_WARNING = "Peringatan ruang disk kurang"

# Tombol Aksi Bawah
BTN_INSTALL_SELECTED = "INSTAL TERPILIH"
BTN_VERIFY_INSTALLATION = "Verifikasi"
BTN_MANUAL_HOSTING = "Butuh Hosting ({count})"
BTN_OPEN_FOLDER = "Buka Folder"
BTN_TOGGLE_LOG = "Panel Log"

# Opsi Menu Buka Folder
FOLDER_DATA = "Folder Data Lokal"
FOLDER_LOGS = "Folder Berkas Log"
FOLDER_PAYLOAD = "Folder Custom Payload"
FOLDER_DOWNLOADS = "Folder Cache Unduhan"

# Dialog & Konfirmasi
DLG_CONFIRM_TITLE = "Konfirmasi Tindakan"
DLG_CONFIRM_UNINSTALL = (
    "Aplikasi berikut akan di-uninstall dan diganti ke versi target:\n\n"
    "{app_list}\n\n"
    "Data penting (htdocs, www, database) akan dicadangkan otomatis ke folder backup.\n"
    "Apakah Anda yakin ingin melanjutkan?"
)
DLG_CANCEL_CONFIRM = "Instalasi sedang berjalan. Apakah Anda yakin ingin membatalkan secara aman?"

# Status Eksekusi Progres
PROGRESS_IDLE = "Siap untuk instalasi."
PROGRESS_PREFLIGHT = "Memeriksa kelayakan sistem (pre-flight)..."
PROGRESS_DOWNLOADING = "Mengunduh {app_name} ({percent:.1f}%, {speed_mb:.2f} MB/s)..."
PROGRESS_EXTRACTING = "Mengekstrak arsip {app_name}..."
PROGRESS_INSTALLING = "Memasang {app_name} secara silent..."
PROGRESS_VERIFYING = "Memverifikasi instalasi {app_name}..."
PROGRESS_COMPLETE = "Instalasi selesai!"
PROGRESS_CANCELLED = "Instalasi dibatalkan oleh pengguna."

# Ringkasan Akhir
SUMMARY_SUCCESS = "Berhasil: {count}"
SUMMARY_SKIPPED = "Dilewati: {count}"
SUMMARY_FAILED = "Gagal: {count}"
SUMMARY_REBOOT = "Perlu Reboot: {count}"
BTN_OPEN_LOG_FILE = "Buka Berkas Log"
BTN_RETRY_FAILED = "Coba Lagi yang Gagal"
BTN_COPY_SUMMARY = "Salin Ringkasan"
