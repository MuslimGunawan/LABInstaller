"""Sistem pencatatan log terpusat untuk Lab Auto Installer.

Mencatat log per sesi ke system/data/logs/install-YYYYMMDD-HHmmss.log,
meneruskan pesan ke antrean UI, dan mencetak ke konsol bila dalam mode CLI.
"""

from __future__ import annotations

import logging
import sys
from dataclasses import dataclass
from datetime import datetime
from queue import Queue

from labinstaller.core.paths import LOGS_DIR, ensure_data_directories


@dataclass
class LogEntry:
    """Representasi satu entri log untuk dikonsumsi antarmuka pengguna."""

    timestamp: str
    level: str
    app_id: str
    message: str


class UIQueueHandler(logging.Handler):
    """Logging handler yang mengirim entri log ke antrean antarmuka grafis."""

    def __init__(self, message_queue: Queue[LogEntry]) -> None:
        super().__init__()
        self.message_queue = message_queue

    def emit(self, record: logging.LogRecord) -> None:
        app_id = getattr(record, "app_id", "SYSTEM")
        entry = LogEntry(
            timestamp=datetime.fromtimestamp(record.created).strftime("%Y-%m-%d %H:%M:%S"),
            level=record.levelname,
            app_id=app_id,
            message=record.getMessage(),
        )
        self.message_queue.put(entry)


_GLOBAL_LOGGER: logging.Logger | None = None
_UI_QUEUE: Queue[LogEntry] = Queue()
_SESSION_LOG_FILE: str | None = None


def get_ui_queue() -> Queue[LogEntry]:
    """Mendapatkan antrean pesan log untuk antarmuka pengguna."""
    return _UI_QUEUE


def get_session_log_file() -> str | None:
    """Mendapatkan path berkas log sesi saat ini."""
    return _SESSION_LOG_FILE


def init_logger(app_version: str = "1.0.0", is_cli: bool = False) -> logging.Logger:
    """Menginisialisasi logger sesi baru."""
    global _GLOBAL_LOGGER, _SESSION_LOG_FILE

    if _GLOBAL_LOGGER is not None:
        return _GLOBAL_LOGGER

    ensure_data_directories()

    timestamp_str = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = LOGS_DIR / f"install-{timestamp_str}.log"
    _SESSION_LOG_FILE = str(log_path)

    logger = logging.getLogger("labinstaller")
    logger.setLevel(logging.DEBUG)
    logger.propagate = False

    # Bersihkan handler lama jika ada
    logger.handlers.clear()

    # File Handler (UTF-8 eksplisit)
    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)-5s] [%(app_id)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    class AppIdFilter(logging.Filter):
        def filter(self, record: logging.LogRecord) -> bool:
            if not hasattr(record, "app_id"):
                record.app_id = "SYSTEM"
            return True

    file_handler.addFilter(AppIdFilter())
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)

    # Queue Handler untuk GUI
    queue_handler = UIQueueHandler(_UI_QUEUE)
    queue_handler.setLevel(logging.INFO)
    queue_handler.addFilter(AppIdFilter())
    logger.addHandler(queue_handler)

    # Console Handler untuk mode CLI
    if is_cli:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)
        console_handler.addFilter(AppIdFilter())
        console_formatter = logging.Formatter("[%(levelname)s] [%(app_id)s] %(message)s")
        console_handler.setFormatter(console_formatter)
        logger.addHandler(console_handler)

    # Header log sesi
    header_extra = {"app_id": "SYSTEM"}
    logger.info(
        f"=== Sesi Lab Auto Installer v{app_version} Dimulai pada {datetime.now().isoformat()} ===",
        extra=header_extra,
    )
    logger.info(f"Berkas Log: {log_path}", extra=header_extra)

    _GLOBAL_LOGGER = logger
    return logger


def log_info(message: str, app_id: str = "SYSTEM") -> None:
    """Mencatat informasi."""
    logger = _GLOBAL_LOGGER or init_logger()
    logger.info(message, extra={"app_id": app_id})


def log_warn(message: str, app_id: str = "SYSTEM") -> None:
    """Mencatat peringatan."""
    logger = _GLOBAL_LOGGER or init_logger()
    logger.warning(message, extra={"app_id": app_id})


def log_error(message: str, app_id: str = "SYSTEM", exc_info: bool = False) -> None:
    """Mencatat kesalahan."""
    logger = _GLOBAL_LOGGER or init_logger()
    logger.error(message, extra={"app_id": app_id}, exc_info=exc_info)


def log_debug(message: str, app_id: str = "SYSTEM") -> None:
    """Mencatat debug."""
    logger = _GLOBAL_LOGGER or init_logger()
    logger.debug(message, extra={"app_id": app_id})
