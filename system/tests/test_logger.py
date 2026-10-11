"""Pengujian unit untuk modul core/logger.py."""

from pathlib import Path
from queue import Empty

from labinstaller.core import logger


def test_session_logger_creation() -> None:
    """Memastikan inisialisasi logger membuat berkas sesi dan mencatat pesan."""
    test_logger = logger.init_logger(app_version="1.0.0", is_cli=True)
    assert test_logger is not None

    log_file = logger.get_session_log_file()
    assert log_file is not None
    assert Path(log_file).exists()

    logger.log_info("Pesan uji informasi", app_id="TEST_APP")
    logger.log_warn("Pesan uji peringatan", app_id="TEST_APP")
    logger.log_error("Pesan uji kesalahan", app_id="TEST_APP")

    content = Path(log_file).read_text(encoding="utf-8")
    assert "Pesan uji informasi" in content
    assert "Pesan uji peringatan" in content
    assert "Pesan uji kesalahan" in content
    assert "[TEST_APP]" in content


def test_ui_queue_handler() -> None:
    """Memastikan pesan log diteruskan ke antrean UI."""
    q = logger.get_ui_queue()
    # Kosongkan antrean sebelumnya
    while not q.empty():
        try:
            q.get_nowait()
        except Empty:
            break

    logger.log_info("Pesan untuk antrean GUI", app_id="UI_TEST")
    assert not q.empty()
    entry = q.get_nowait()
    assert entry.app_id == "UI_TEST"
    assert entry.message == "Pesan untuk antrean GUI"
    assert entry.level == "INFO"
