"""Konfigurasi tema visual, warna, font, dan penanganan DPI tinggi (Hi-DPI)."""

from __future__ import annotations

import ctypes
import platform


def enable_high_dpi_awareness() -> None:
    """Mengaktifkan kesadaran DPI tinggi (Per-Monitor DPI Aware) di Windows sebelum jendela dibuat."""
    if platform.system() != "Windows":
        return

    try:
        # Windows 8.1 / 10 / 11: SetProcessDpiAwareness(2) -> Per-Monitor V2, (1) -> System Aware
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            # Fallback untuk Windows Vista / 7
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


# Dimensi Jendela
WINDOW_DEFAULT_WIDTH = 1100
WINDOW_DEFAULT_HEIGHT = 700
WINDOW_MIN_WIDTH = 960
WINDOW_MIN_HEIGHT = 600

# Palet Warna Terang & Gelap
PALETTE_DARK: dict[str, str] = {
    "bg_main": "#1e1e24",
    "bg_card": "#282830",
    "bg_sidebar": "#18181c",
    "accent_primary": "#2563eb",
    "accent_hover": "#1d4ed8",
    "text_primary": "#f8fafc",
    "text_secondary": "#94a3b8",
    "badge_green_bg": "#064e3b",
    "badge_green_fg": "#34d399",
    "badge_blue_bg": "#1e3a8a",
    "badge_blue_fg": "#60a5fa",
    "badge_amber_bg": "#78350f",
    "badge_amber_fg": "#fbbf24",
    "badge_red_bg": "#7f1d1d",
    "badge_red_fg": "#f87171",
    "border": "#334155",
}

PALETTE_LIGHT: dict[str, str] = {
    "bg_main": "#f8fafc",
    "bg_card": "#ffffff",
    "bg_sidebar": "#f1f5f9",
    "accent_primary": "#2563eb",
    "accent_hover": "#1d4ed8",
    "text_primary": "#0f172a",
    "text_secondary": "#64748b",
    "badge_green_bg": "#d1fae5",
    "badge_green_fg": "#065f46",
    "badge_blue_bg": "#dbeafe",
    "badge_blue_fg": "#1e40af",
    "badge_amber_bg": "#fef3c7",
    "badge_amber_fg": "#92400e",
    "badge_red_bg": "#fee2e2",
    "badge_red_fg": "#991b1b",
    "border": "#e2e8f0",
}
