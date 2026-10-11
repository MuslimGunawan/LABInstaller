"""Manajemen thread pekerja latar (Worker Thread) dan antrean komunikasi UI.

Memastikan operasi berat tidak memblokir antarmuka grafis (UI tidak pernah membeku).
"""

from __future__ import annotations

import threading
from collections.abc import Callable
from dataclasses import dataclass
from queue import Queue
from typing import Any


@dataclass
class WorkerMessage:
    """Pesan status yang dikirimkan thread pekerja ke antarmuka grafis."""

    tipe: str  # 'PROGRESS', 'LOG', 'COMPLETE', 'ERROR', 'CANCELLED'
    pesan: str
    data: dict[str, Any] | None = None


class BackgroundWorker:
    """Pekerja di thread latar belakang untuk operasi asinkron."""

    def __init__(self, ui_update_queue: Queue[WorkerMessage]) -> None:
        self.queue = ui_update_queue
        self._thread: threading.Thread | None = None
        self._cancel_requested = threading.Event()

    def is_running(self) -> bool:
        """Memeriksa apakah pekerjaan sedang berjalan."""
        return self._thread is not None and self._thread.is_alive()

    def request_cancel(self) -> None:
        """Meminta pembatalan pekerjaan secara aman."""
        self._cancel_requested.set()

    def should_cancel(self) -> bool:
        """Memeriksa apakah ada permintaan pembatalan dari pengguna."""
        return self._cancel_requested.is_set()

    def start(self, target_func: Callable[[BackgroundWorker], None]) -> None:
        """Memulai tugas di thread latar baru."""
        if self.is_running():
            return

        self._cancel_requested.clear()

        def runner() -> None:
            try:
                target_func(self)
            except Exception as exc:
                self.queue.put(
                    WorkerMessage(
                        tipe="ERROR",
                        pesan=f"Kesalahan internal pada thread pekerja: {exc}",
                        data={"exception": str(exc)},
                    )
                )

        self._thread = threading.Thread(target=runner, daemon=True)
        self._thread.start()

    def send_progress(self, message: str, percent: float = 0.0, current_app: str = "") -> None:
        """Mengirimkan pembaruan progres ke antarmuka."""
        self.queue.put(
            WorkerMessage(
                tipe="PROGRESS",
                pesan=message,
                data={"percent": percent, "current_app": current_app},
            )
        )

    def send_complete(self, message: str, summary_data: dict[str, Any] | None = None) -> None:
        """Mengirimkan sinyal bahwa pekerjaan selesai."""
        self.queue.put(
            WorkerMessage(
                tipe="COMPLETE",
                pesan=message,
                data=summary_data,
            )
        )
