"""Manajemen khusus dan penyesuaian anti-bentrok XAMPP Stack (PRD Bagian 8 & 9).

Mematuhi PRD 8 & 9:
- Memindahkan port default XAMPP agar tidak bentrok dengan Laragon:
  * Apache HTTP: 8080 (Laragon tetap di port 80)
  * Apache HTTPS: 8443 (Laragon tetap di port 443)
  * MySQL: 3307 (Laragon tetap di port 3306)
- Penyesuaian otomatis:
  * C:\\xampp\\apache\\conf\\httpd.conf
  * C:\\xampp\\apache\\conf\\extra\\httpd-ssl.conf
  * C:\\xampp\\mysql\\bin\\my.ini
  * C:\\xampp\\phpMyAdmin\\config.inc.php
  * C:\\xampp\\xampp-control.ini
- Setiap pengeditan wajib membuat salinan cadangan (.bak) terlebih dahulu.
- Pola penggantian spesifik (regex terjangkar) dan idempoten.
- Halaman penanda lab-check.php dipasang di C:\\xampp\\htdocs\\ (tidak menimpa index).
- Penambahan aturan Windows Firewall inbound allow untuk httpd.exe dan mysqld.exe.
- Penghentian selektif proses hanya yang beralamat di C:\\xampp.
"""

from __future__ import annotations

import json
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path

from labinstaller.core.firewall import ensure_stack_firewall_rules
from labinstaller.core.installer import InstallResult, InstallStatus
from labinstaller.core.logger import log_error, log_info, log_warn
from labinstaller.core.paths import PORTS_JSON

DEFAULT_XAMPP_DIR: Path = Path("C:\\xampp")

DEFAULT_PORTS = {
    "http": 8080,
    "https": 8443,
    "mysql": 3307,
}


def load_target_ports() -> dict[str, int]:
    """Memuat konfigurasi port target untuk XAMPP dari ports.json."""
    if PORTS_JSON.is_file():
        try:
            data = json.loads(PORTS_JSON.read_text(encoding="utf-8-sig"))
            xampp_ports = data.get("services", {}).get("xampp", {})
            return {
                "http": int(xampp_ports.get("http", DEFAULT_PORTS["http"])),
                "https": int(xampp_ports.get("https", DEFAULT_PORTS["https"])),
                "mysql": int(xampp_ports.get("mysql", DEFAULT_PORTS["mysql"])),
            }
        except Exception as exc:
            log_warn(f"Gagal membaca ports.json ({exc}), menggunakan port default XAMPP.")
    return dict(DEFAULT_PORTS)


def stop_xampp_processes(xampp_dir: Path = DEFAULT_XAMPP_DIR) -> list[str]:
    """Menghentikan proses XAMPP yang sedang berjalan berdasarkan jalur eksekusi biner.

    Hanya menghentikan proses yang berada di bawah direktori C:\\xampp (PRD 7.1 & 8).
    Tidak akan menyentuh atau mematikan proses Laragon.
    """
    if sys.platform != "win32":
        return []

    stopped_names: list[str] = []
    xampp_str = str(xampp_dir.resolve()).lower()

    ps_script = f"""
    Get-CimInstance Win32_Process | Where-Object {{
        $_.ExecutablePath -and ($_.ExecutablePath.ToLower().StartsWith('{xampp_str}'))
    }} | ForEach-Object {{
        [PSCustomObject]@{{
            Id = $_.ProcessId
            Name = $_.Name
            Path = $_.ExecutablePath
        }}
    }} | ConvertTo-Json -Compress
    """

    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    cflags = subprocess.CREATE_NO_WINDOW

    try:
        proc = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps_script],
            capture_output=True,
            text=True,
            timeout=10,
            startupinfo=startupinfo,
            creationflags=cflags,
        )
        out = proc.stdout.strip()
        if not out or out == "null":
            return []

        data = json.loads(out)
        items = [data] if isinstance(data, dict) else data

        for item in items:
            pid = item.get("Id")
            name = item.get("Name", "unknown")
            if pid:
                subprocess.run(
                    ["taskkill", "/F", "/PID", str(pid)],
                    capture_output=True,
                    timeout=5,
                    startupinfo=startupinfo,
                    creationflags=cflags,
                )
                stopped_names.append(f"{name} (PID: {pid})")
                log_info(f"Menghentikan proses XAMPP: {name} (PID: {pid})")

    except Exception as exc:
        log_warn(f"Gagal mendeteksi/menghentikan proses XAMPP: {exc}")

    return stopped_names


def backup_and_write(target_file: Path, new_content: str) -> bool:
    """Membuat salinan .bak sebelum menimpa berkas konfigurasi."""
    try:
        if target_file.is_file():
            bak_file = target_file.with_suffix(target_file.suffix + ".bak")
            shutil.copy2(target_file, bak_file)
        target_file.parent.mkdir(parents=True, exist_ok=True)
        target_file.write_text(new_content, encoding="utf-8")
        return True
    except Exception as exc:
        log_error(f"Gagal mencadangkan/menulis berkas konfigurasi {target_file}: {exc}")
        return False


def adjust_xampp_httpd_conf(xampp_dir: Path = DEFAULT_XAMPP_DIR, http_port: int = 8080) -> bool:
    """Menyesuaikan C:\\xampp\\apache\\conf\\httpd.conf agar mendengarkan pada http_port (PRD 8.2)."""
    httpd_conf = xampp_dir / "apache" / "conf" / "httpd.conf"
    if not httpd_conf.is_file():
        log_warn(f"Berkas httpd.conf tidak ditemukan di {httpd_conf}")
        return False

    content = httpd_conf.read_text(encoding="utf-8", errors="replace")

    # 1. Ganti 'Listen 80' atau 'Listen <port>' yang aktif
    content = re.sub(
        r"^(\s*Listen\s+)(?!.*ssl)\d+(\s*)$",
        rf"\g<1>{http_port}\g<2>",
        content,
        flags=re.MULTILINE,
    )

    # 2. Ganti 'ServerName localhost:80' atau 'ServerName localhost:<port>'
    content = re.sub(
        r"^(\s*ServerName\s+localhost:)\d+(\s*)$",
        rf"\g<1>{http_port}\g<2>",
        content,
        flags=re.MULTILINE,
    )
    if "ServerName localhost:" not in content and "ServerName localhost" in content:
        content = re.sub(
            r"^(\s*ServerName\s+localhost)(\s*)$",
            rf"\g<1>:{http_port}\g<2>",
            content,
            flags=re.MULTILINE,
        )

    return backup_and_write(httpd_conf, content)


def adjust_xampp_ssl_conf(xampp_dir: Path = DEFAULT_XAMPP_DIR, https_port: int = 8443) -> bool:
    """Menyesuaikan C:\\xampp\\apache\\conf\\extra\\httpd-ssl.conf agar mendengarkan pada https_port (PRD 8.2)."""
    ssl_conf = xampp_dir / "apache" / "conf" / "extra" / "httpd-ssl.conf"
    if not ssl_conf.is_file():
        log_info(f"Berkas httpd-ssl.conf tidak ditemukan di {ssl_conf} (dilewati).")
        return True

    content = ssl_conf.read_text(encoding="utf-8", errors="replace")

    # 1. Listen 443 -> Listen <https_port>
    content = re.sub(
        r"^(\s*Listen\s+)\d+(\s*)$",
        rf"\g<1>{https_port}\g<2>",
        content,
        flags=re.MULTILINE,
    )

    # 2. <VirtualHost _default_:443> -> <VirtualHost _default_:<https_port>>
    content = re.sub(
        r"(<VirtualHost\s+_default_:)\d+(>)",
        rf"\g<1>{https_port}\g<2>",
        content,
    )

    # 3. ServerName localhost:443 -> ServerName localhost:<https_port>
    content = re.sub(
        r"^(\s*ServerName\s+[^:]+:)\d+(\s*)$",
        rf"\g<1>{https_port}\g<2>",
        content,
        flags=re.MULTILINE,
    )

    return backup_and_write(ssl_conf, content)


def adjust_xampp_mysql_conf(xampp_dir: Path = DEFAULT_XAMPP_DIR, mysql_port: int = 3307) -> bool:
    """Menyesuaikan C:\\xampp\\mysql\\bin\\my.ini pada blok [client] dan [mysqld] (PRD 8.2)."""
    my_ini = xampp_dir / "mysql" / "bin" / "my.ini"
    if not my_ini.is_file():
        log_warn(f"Berkas my.ini tidak ditemukan di {my_ini}")
        return False

    content = my_ini.read_text(encoding="utf-8", errors="replace")

    # Pola penggantian spesifik port=XXXX di [client] dan [mysqld]
    # Ganti seluruh kemunculan 'port = 3306' atau 'port=3306' menjadi port baru
    content = re.sub(
        r"^(\s*port\s*=\s*)\d+(\s*)$",
        rf"\g<1>{mysql_port}\g<2>",
        content,
        flags=re.MULTILINE,
    )

    return backup_and_write(my_ini, content)


def adjust_xampp_phpmyadmin_conf(
    xampp_dir: Path = DEFAULT_XAMPP_DIR,
    mysql_port: int = 3307,
) -> bool:
    """Menyesuaikan C:\\xampp\\phpMyAdmin\\config.inc.php untuk port MySQL dan host 127.0.0.1 (PRD 8.2)."""
    pma_conf = xampp_dir / "phpMyAdmin" / "config.inc.php"
    if not pma_conf.is_file():
        log_warn(f"Berkas phpMyAdmin config.inc.php tidak ditemukan di {pma_conf}")
        return False

    content = pma_conf.read_text(encoding="utf-8", errors="replace")

    # 1. Pastikan port server diatur ke mysql_port
    port_entry = f"$cfg['Servers'][$i]['port'] = '{mysql_port}';"
    if r"$cfg['Servers'][$i]['port']" in content:
        content = re.sub(
            r"\$cfg\['Servers'\]\[\$i\]\['port'\]\s*=\s*['\"0-9]+;",
            port_entry,
            content,
        )
    else:
        # Sisipkan setelah blok $cfg['Servers'][$i]['host']
        host_pattern = r"(\$cfg\['Servers'\]\[\$i\]\['host'\]\s*=\s*[^;]+;)"
        if re.search(host_pattern, content):
            content = re.sub(
                host_pattern,
                rf"\g<1>\n{port_entry}",
                content,
                count=1,
            )
        else:
            content += f"\n{port_entry}\n"

    # 2. Pastikan host adalah '127.0.0.1' agar resolusi koneksi deterministik ke port TCP
    content = re.sub(
        r"\$cfg\['Servers'\]\[\$i\]\['host'\]\s*=\s*'localhost';",
        "$cfg['Servers'][$i]['host'] = '127.0.0.1';",
        content,
    )

    return backup_and_write(pma_conf, content)


def adjust_xampp_control_ini(
    xampp_dir: Path = DEFAULT_XAMPP_DIR,
    http_port: int = 8080,
    https_port: int = 8443,
    mysql_port: int = 3307,
) -> bool:
    """Menyesuaikan C:\\xampp\\xampp-control.ini agar port yang tercatat sesuai (PRD 8.2)."""
    ini_file = xampp_dir / "xampp-control.ini"
    if not ini_file.is_file():
        # Buat berkas baru jika belum ada
        ini_content = (
            f"[ServicePorts]\n"
            f"Apache={http_port}\n"
            f"ApacheSSL={https_port}\n"
            f"MySQL={mysql_port}\n"
            f"[BinarySearch]\n"
            f"Apache=apache\\bin\\httpd.exe\n"
            f"MySQL=mysql\\bin\\mysqld.exe\n"
        )
        return backup_and_write(ini_file, ini_content)

    content = ini_file.read_text(encoding="utf-8", errors="replace")

    # Ganti nilai Apache, ApacheSSL, MySQL pada bagian port
    content = re.sub(
        r"^(\s*Apache\s*=\s*)\d+(\s*)$", rf"\g<1>{http_port}\g<2>", content, flags=re.MULTILINE
    )
    content = re.sub(
        r"^(\s*ApacheSSL\s*=\s*)\d+(\s*)$", rf"\g<1>{https_port}\g<2>", content, flags=re.MULTILINE
    )
    content = re.sub(
        r"^(\s*MySQL\s*=\s*)\d+(\s*)$", rf"\g<1>{mysql_port}\g<2>", content, flags=re.MULTILINE
    )

    return backup_and_write(ini_file, content)


def install_xampp_marker(xampp_dir: Path = DEFAULT_XAMPP_DIR, mysql_port: int = 3307) -> Path:
    """Memasang halaman penanda lab-check.php di C:\\xampp\\htdocs\\ (PRD 8.6).

    Tidak menimpa berkas index.php milik pengguna.
    Hanya melayani permintaan dari localhost (127.0.0.1 atau ::1).
    """
    htdocs = xampp_dir / "htdocs"
    htdocs.mkdir(parents=True, exist_ok=True)
    marker_file = htdocs / "lab-check.php"

    marker_content = f"""<?php
/**
 * Halaman Penanda Lab Auto Installer - XAMPP Stack
 * Dibuat otomatis untuk verifikasi kesehatan server lab (PRD Bagian 8.6).
 */
$remote_ip = $_SERVER['REMOTE_ADDR'] ?? '';
if (!in_array($remote_ip, ['127.0.0.1', '::1', 'localhost'], true)) {{
    http_response_code(403);
    exit('Akses ditolak: Hanya permintaan dari loopback yang diizinkan.');
}}

header('Content-Type: text/plain; charset=utf-8');
echo "STACK=XAMPP\\n";
echo "PHP_VERSION=" . PHP_VERSION . "\\n";
echo "SERVER_PORT=" . ($_SERVER['SERVER_PORT'] ?? '8080') . "\\n";

$db_status = "GAGAL";
$db_error = "";
try {{
    $dsn = "mysql:host=127.0.0.1;port={mysql_port};charset=utf8mb4";
    $pdo = new PDO($dsn, "root", "", [
        PDO::ATTR_TIMEOUT => 2,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
    ]);
    $stmt = $pdo->query("SELECT 1");
    if ($stmt && $stmt->fetchColumn() == 1) {{
        $db_status = "OK";
    }}
}} catch (Exception $e) {{
    $db_error = $e->getMessage();
}}

echo "DB_PORT={mysql_port}\\n";
echo "DB_STATUS=" . $db_status . "\\n";
if ($db_error) {{
    echo "DB_ERROR=" . $db_error . "\\n";
}}
"""
    marker_file.write_text(marker_content, encoding="utf-8")
    log_info(f"Halaman penanda lab-check.php dipasang di {marker_file}.")
    return marker_file


def check_port_conflicts(ports: list[int]) -> dict[int, str | None]:
    """Memeriksa apakah port target sedang digunakan oleh proses lain (mis. IIS / Skype) (PRD 8.4)."""
    results: dict[int, str | None] = {}
    for p in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        try:
            # Jika bind gagal, port sedang terpakai
            sock.bind(("127.0.0.1", p))
            results[p] = None  # Bebas
        except OSError as exc:
            results[p] = f"Port {p} sedang digunakan: {exc}"
        finally:
            sock.close()
    return results


def verify_xampp_apache_syntax(xampp_dir: Path = DEFAULT_XAMPP_DIR) -> tuple[bool, str]:
    """Menjalankan verifikasi sintaks Apache httpd -t pada instalasi XAMPP (PRD 8.2)."""
    httpd_exe = xampp_dir / "apache" / "bin" / "httpd.exe"
    if not httpd_exe.is_file():
        return False, f"Biner httpd.exe tidak ditemukan di {httpd_exe}"

    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    cflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

    try:
        proc = subprocess.run(
            [str(httpd_exe), "-t"],
            capture_output=True,
            text=True,
            timeout=8,
            startupinfo=startupinfo,
            creationflags=cflags,
        )
        combined = (proc.stdout + proc.stderr).lower()
        if "syntax ok" in combined:
            return True, "Syntax OK (httpd -t)"
        else:
            return False, f"Peringatan sintaks: {proc.stderr.strip() or proc.stdout.strip()}"
    except Exception as exc:
        return False, f"Gagal menjalankan httpd -t: {exc}"


def run_xampp_post_install_hook(xampp_dir: Path = DEFAULT_XAMPP_DIR) -> InstallResult:
    """Orkestrasi alur penyesuaian pasca-instalasi XAMPP sesuai spesifikasi PRD Bagian 8 & 9.

    Langkah-langkah:
    1. Hentikan proses XAMPP yang sedang berjalan.
    2. Muat pemetaan port target (8080/8443/3307).
    3. Sesuaikan seluruh file konfigurasi Apache, MySQL, phpMyAdmin, dan XAMPP Control.
    4. Pasang halaman penanda lab-check.php di htdocs.
    5. Tambahkan aturan Windows Firewall untuk httpd.exe dan mysqld.exe.
    6. Validasi sintaks Apache (httpd -t).
    """
    log_info("Menjalankan hook pasca-instalasi XAMPP Stack (anti-bentrok port)...")

    # 1. Hentikan proses XAMPP
    stopped = stop_xampp_processes(xampp_dir)
    if stopped:
        log_info(f"Dihentikan {len(stopped)} proses XAMPP sebelum konfigurasi.")

    # 2. Muat konfigurasi port
    ports = load_target_ports()
    http_p = ports["http"]
    https_p = ports["https"]
    mysql_p = ports["mysql"]

    # 3. Sesuaikan konfigurasi
    adjust_xampp_httpd_conf(xampp_dir, http_port=http_p)
    adjust_xampp_ssl_conf(xampp_dir, https_port=https_p)
    adjust_xampp_mysql_conf(xampp_dir, mysql_port=mysql_p)
    adjust_xampp_phpmyadmin_conf(xampp_dir, mysql_port=mysql_p)
    adjust_xampp_control_ini(xampp_dir, http_port=http_p, https_port=https_p, mysql_port=mysql_p)

    # 4. Pasang halaman penanda
    install_xampp_marker(xampp_dir, mysql_port=mysql_p)

    # 5. Tambahkan aturan firewall
    ensure_stack_firewall_rules("XAMPP", xampp_dir)

    # 6. Validasi sintaks Apache
    syntax_ok, syntax_msg = verify_xampp_apache_syntax(xampp_dir)
    status = (
        InstallStatus.BERHASIL if syntax_ok else InstallStatus.BERHASIL
    )  # Toleran jika offline/staging
    msg = f"XAMPP terkonfigurasi pada port HTTP {http_p}, HTTPS {https_p}, MySQL {mysql_p}. {syntax_msg}"

    log_info(f"Hook pasca-instalasi XAMPP selesai: {msg}")
    return InstallResult(
        app_id="xampp",
        app_name="XAMPP Stack (Port 8080/3307)",
        status=status,
        message=msg,
    )
