"""Pengujian integritas arsitektur: memastikan core tidak mengimpor modul ui."""

import ast

from labinstaller.core.paths import APP_DIR


def test_core_does_not_import_ui() -> None:
    """Memindai AST seluruh berkas Python di core/ untuk memastikan tidak ada impor dari ui/."""
    core_dir = APP_DIR / "labinstaller" / "core"
    assert core_dir.exists()

    py_files = list(core_dir.glob("*.py"))
    assert len(py_files) > 0

    violations = []

    for file_path in py_files:
        tree = ast.parse(file_path.read_text(encoding="utf-8"), filename=str(file_path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if "labinstaller.ui" in alias.name:
                        violations.append(f"{file_path.name}: import {alias.name}")
            elif isinstance(node, ast.ImportFrom):
                mod = node.module or ""
                if "labinstaller.ui" in mod or mod.startswith("ui"):
                    violations.append(f"{file_path.name}: from {mod} import ...")

    assert violations == [], f"Pelanggaran batas arsitektur ditemukan di modul core: {violations}"
