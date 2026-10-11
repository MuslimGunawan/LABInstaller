"""Manajemen pembacaan, validasi skema, dan fallback konfigurasi.

Toleran terhadap UTF-8 BOM (utf-8-sig), memvalidasi skema dengan jsonschema,
menyediakan pemulihan dari state/last-good bila file rusak saat diedit admin,
dan tidak crash saat konfigurasi salah sintaks.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

try:
    import jsonschema

    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

from labinstaller.core.logger import log_debug, log_error, log_info, log_warn
from labinstaller.core.paths import (
    APPS_JSON,
    LAST_GOOD_DIR,
    LOCAL_JSON,
    MIRRORS_JSON,
    PORTS_JSON,
    PROFILES_JSON,
    SCHEMA_DIR,
    ensure_data_directories,
)


class ConfigError(Exception):
    """Kesalahan pemuatan atau validasi berkas konfigurasi."""

    def __init__(
        self, filename: str, message: str, line: int | None = None, column: int | None = None
    ) -> None:
        self.filename = filename
        self.message = message
        self.line = line
        self.column = column
        loc_str = f" [baris {line}, kolom {column}]" if line and column else ""
        super().__init__(f"Kesalahan konfigurasi pada {filename}{loc_str}: {message}")


def load_json_file(file_path: Path) -> tuple[Any | None, ConfigError | None]:
    """Membaca berkas JSON dengan encoding utf-8-sig (toleran BOM).

    Mengembalikan (data, None) jika sukses, atau (None, ConfigError) jika gagal.
    """
    if not file_path.exists():
        return None, ConfigError(file_path.name, f"Berkas tidak ditemukan: {file_path}")

    try:
        content = file_path.read_text(encoding="utf-8-sig")
        data = json.loads(content)
        return data, None
    except json.JSONDecodeError as exc:
        return None, ConfigError(
            filename=file_path.name,
            message=exc.msg,
            line=exc.lineno,
            column=exc.colno,
        )
    except Exception as exc:
        return None, ConfigError(file_path.name, str(exc))


def _basic_schema_validate(
    data: Any, schema: dict[str, Any], path_prefix: str = "root"
) -> str | None:
    """Validasi skema dasar bila paket jsonschema belum terpasang."""
    req_type = schema.get("type")
    if req_type == "object":
        if not isinstance(data, dict):
            return f"Bagian '{path_prefix}' harus berupa objek (dict)"
        for req_field in schema.get("required", []):
            if req_field not in data:
                return f"Bagian '{path_prefix}' wajib memiliki field '{req_field}'"
        properties = schema.get("properties", {})
        for k, v in data.items():
            if k in properties:
                sub_err = _basic_schema_validate(v, properties[k], f"{path_prefix}.{k}")
                if sub_err:
                    return sub_err
    elif req_type == "array":
        if not isinstance(data, list):
            return f"Bagian '{path_prefix}' harus berupa daftar (list)"
        item_schema = schema.get("items")
        if item_schema and isinstance(item_schema, dict):
            for idx, item in enumerate(data):
                sub_err = _basic_schema_validate(item, item_schema, f"{path_prefix}[{idx}]")
                if sub_err:
                    return sub_err
    return None


def validate_schema(data: Any, schema_path: Path) -> ConfigError | None:
    """Memvalidasi data terhadap berkas skema JSON."""
    if not schema_path.exists():
        return ConfigError(schema_path.name, f"Berkas skema tidak ditemukan: {schema_path}")

    schema_data, err = load_json_file(schema_path)
    if err or schema_data is None:
        return err or ConfigError(schema_path.name, "Gagal memuat skema JSON")

    target_name = schema_path.name.replace(".schema.json", ".json")

    if HAS_JSONSCHEMA:
        try:
            jsonschema.validate(instance=data, schema=schema_data)
            return None
        except jsonschema.ValidationError as exc:
            path_str = " -> ".join(str(p) for p in exc.path) if exc.path else "root"
            return ConfigError(
                filename=target_name,
                message=f"Validasi skema gagal pada bagian '{path_str}': {exc.message}",
            )
        except Exception as exc:
            return ConfigError(schema_path.name, f"Kesalahan validator: {exc}")

    # Fallback basic schema validation
    basic_err = _basic_schema_validate(data, schema_data)
    if basic_err:
        return ConfigError(filename=target_name, message=basic_err)
    return None


def load_config_with_fallback(
    config_path: Path,
    schema_path: Path,
) -> tuple[Any, bool, str | None]:
    """Memuat berkas konfigurasi, memvalidasi skema, dan menerapkan fallback last-good.

    Returns:
        (data, is_fallback, warning_message)
    """
    ensure_data_directories()
    filename = config_path.name
    last_good_file = LAST_GOOD_DIR / filename

    data, err = load_json_file(config_path)
    if err is None and data is not None:
        schema_err = validate_schema(data, schema_path)
        if schema_err is None:
            # Sukses dan valid: simpan salinan ke last-good
            try:
                shutil.copy2(config_path, last_good_file)
            except Exception as copy_exc:
                log_debug(f"Gagal mencadangkan last-good untuk {filename}: {copy_exc}")
            return data, False, None
        else:
            err = schema_err

    # Terjadi kesalahan: coba pemulihan dari last-good
    err_msg = err.message if err else "Kesalahan format tidak diketahui"
    warn_msg = f"Berkas {filename} tidak valid ({err_msg}). Mencoba memulihkan dari salinan terakhir yang valid..."
    log_warn(warn_msg)

    if last_good_file.exists():
        fallback_data, fb_err = load_json_file(last_good_file)
        if fb_err is None and fallback_data is not None:
            log_info(
                f"Berhasil menggunakan konfigurasi cadangan terakhir yang valid untuk {filename}."
            )
            return fallback_data, True, warn_msg

    # Jika last-good tidak ada atau rusak, lempar ConfigError
    log_error(f"Gagal memulihkan {filename} dari last-good: tidak ada salinan valid.")
    if err is not None:
        raise err
    raise ConfigError(filename, "Gagal memuat konfigurasi.")


class ConfigManager:
    """Manajer konfigurasi aplikasi terpusat."""

    def __init__(self) -> None:
        self.warnings: list[str] = []
        self._apps_data: dict[str, Any] | None = None
        self._mirrors_data: dict[str, Any] | None = None
        self._profiles_data: dict[str, Any] | None = None
        self._ports_data: dict[str, Any] | None = None
        self._local_data: dict[str, Any] | None = None

    def load_all(self) -> None:
        """Memuat seluruh konfigurasi yang dibutuhkan."""
        self.warnings.clear()

        # 1. Apps manifest
        apps, fb, warn = load_config_with_fallback(APPS_JSON, SCHEMA_DIR / "apps.schema.json")
        self._apps_data = apps
        if warn:
            self.warnings.append(warn)

        # 2. Mirrors
        mirrors, fb, warn = load_config_with_fallback(
            MIRRORS_JSON, SCHEMA_DIR / "mirrors.schema.json"
        )
        self._mirrors_data = mirrors
        if warn:
            self.warnings.append(warn)

        # 3. Profiles
        profiles, fb, warn = load_config_with_fallback(
            PROFILES_JSON, SCHEMA_DIR / "profiles.schema.json"
        )
        self._profiles_data = profiles
        if warn:
            self.warnings.append(warn)

        # 4. Ports
        ports, fb, warn = load_config_with_fallback(PORTS_JSON, SCHEMA_DIR / "ports.schema.json")
        self._ports_data = ports
        if warn:
            self.warnings.append(warn)

        # 5. Local config (opsional)
        if LOCAL_JSON.exists():
            local, err = load_json_file(LOCAL_JSON)
            if err:
                self.warnings.append(f"local.json tidak valid: {err.message}")
            else:
                self._local_data = local
        else:
            self._local_data = {}

    @property
    def apps(self) -> list[dict[str, Any]]:
        """Daftar aplikasi dalam manifest."""
        if self._apps_data is None:
            self.load_all()
        return self._apps_data.get("apps", []) if self._apps_data else []

    @property
    def manifest_version(self) -> str:
        """Versi manifest aplikasi."""
        if self._apps_data is None:
            self.load_all()
        return self._apps_data.get("manifestVersion", "unknown") if self._apps_data else "unknown"

    @property
    def profiles(self) -> list[dict[str, Any]]:
        """Daftar profil paket instalasi."""
        if self._profiles_data is None:
            self.load_all()
        return self._profiles_data.get("profiles", []) if self._profiles_data else []

    @property
    def ports(self) -> dict[str, Any]:
        """Peta port layanan."""
        if self._ports_data is None:
            self.load_all()
        return self._ports_data.get("services", {}) if self._ports_data else {}

    @property
    def mirrors(self) -> list[dict[str, Any]]:
        """Daftar mirror berkas."""
        if self._mirrors_data is None:
            self.load_all()
        return self._mirrors_data.get("files", []) if self._mirrors_data else []

    @property
    def local(self) -> dict[str, Any]:
        """Konfigurasi lokal PC lab."""
        if self._local_data is None:
            self.load_all()
        return self._local_data or {}


def check_all_configs() -> tuple[bool, list[str]]:
    """Memeriksa keabsahan semua berkas konfigurasi (digunakan oleh --check-config).

    Returns:
        (sukses, daftar_laporan)
    """
    configs_to_check = [
        ("apps.json", APPS_JSON, SCHEMA_DIR / "apps.schema.json"),
        ("mirrors.json", MIRRORS_JSON, SCHEMA_DIR / "mirrors.schema.json"),
        ("profiles.json", PROFILES_JSON, SCHEMA_DIR / "profiles.schema.json"),
        ("ports.json", PORTS_JSON, SCHEMA_DIR / "ports.schema.json"),
    ]
    if LOCAL_JSON.exists():
        configs_to_check.append(("local.json", LOCAL_JSON, SCHEMA_DIR / "local.schema.json"))

    reports: list[str] = []
    all_ok = True

    for name, path, schema in configs_to_check:
        data, err = load_json_file(path)
        if err:
            all_ok = False
            reports.append(f"[GAGAL] {name}: {err}")
            continue

        schema_err = validate_schema(data, schema)
        if schema_err:
            all_ok = False
            reports.append(f"[GAGAL] {name}: {schema_err}")
        else:
            reports.append(f"[OK] {name} valid sesuai skema.")

    return all_ok, reports
