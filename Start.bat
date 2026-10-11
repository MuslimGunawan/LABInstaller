@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: Lab Auto Installer - Launcher Utama (Start.bat)
:: Memeriksa hak Administrator, memverifikasi runtime, dan meluncurkan bootstrap.
:: ============================================================================

:: 1. Pindah ke direktori tempat berkas ini berada
cd /d "%~dp0"

:: 2. Periksa apakah argumen meminta mode non-interaktif
set "IS_AUTOMATED=0"
for %%A in (%*) do (
    if "%%A"=="--selftest" set "IS_AUTOMATED=1"
    if "%%A"=="--selftest-gui" set "IS_AUTOMATED=1"
    if "%%A"=="--dry-run" set "IS_AUTOMATED=1"
    if "%%A"=="--check-config" set "IS_AUTOMATED=1"
    if "%%A"=="--version" set "IS_AUTOMATED=1"
    if "%%A"=="--unattended" set "IS_AUTOMATED=1"
    if "%%A"=="--cli" set "IS_AUTOMATED=1"
)

:: 3. Periksa Hak Administrator (hanya bila mode interaktif penuh)
if "%IS_AUTOMATED%"=="0" (
    fltmc >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo [INFO] Meminta hak Administrator untuk menjalankan instalasi...
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
        exit /b %ERRORLEVEL%
    )
)

:: 4. Deteksi Interpreter Python (Prioritaskan runtime portabel internal)
set "PYTHON_EXE=%~dp0system\runtime\python\python.exe"
set "PYTHONW_EXE=%~dp0system\runtime\python\pythonw.exe"

if exist "%PYTHONW_EXE%" (
    if "%IS_AUTOMATED%"=="1" (
        set "RUN_PYTHON=%PYTHON_EXE%"
    ) else (
        set "RUN_PYTHON=%PYTHONW_EXE%"
    )
) else if exist "%PYTHON_EXE%" (
    set "RUN_PYTHON=%PYTHON_EXE%"
) else (
    :: Fallback bila runtime portabel belum diekstrak (gunakan python sistem untuk bootstrap)
    where python >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        set "RUN_PYTHON=python"
    ) else (
        echo [ERROR] Runtime Python portabel tidak ditemukan di system\runtime\python\
        echo         dan Python sistem tidak tersedia.
        echo         Menjalankan pemulihan runtime darurat...
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0system\boot\recover.ps1" -Repair
        if exist "%PYTHON_EXE%" (
            set "RUN_PYTHON=%PYTHON_EXE%"
        ) else (
            echo [GAGAL] Pemulihan runtime gagal. Silakan hubungi admin lab.
            if "%IS_AUTOMATED%"=="0" pause
            exit /b 2
        )
    )
)

:: 5. Tetapkan variabel lingkungan UTF-8
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "LABINSTALLER_ROOT=%~dp0"

:: 6. Jalankan Bootstrap Program
:RUN_LOOP
"%RUN_PYTHON%" -X utf8 "%~dp0system\boot\bootstrap.py" %*
set "EXIT_CODE=%ERRORLEVEL%"

:: 7. Tangani Exit Code 10 (Permintaan Tukar Runtime dari updater)
if %EXIT_CODE% equ 10 (
    echo [INFO] Memperbarui runtime Python portabel...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0system\boot\recover.ps1" -Apply
    if %ERRORLEVEL% equ 0 (
        goto RUN_LOOP
    ) else (
        echo [ERROR] Gagal menerapkan pembaruan runtime.
        set "EXIT_CODE=6"
    )
)

:: 8. Tangani Selesai
if "%IS_AUTOMATED%"=="1" (
    exit /b %EXIT_CODE%
)

if %EXIT_CODE% neq 0 (
    if %EXIT_CODE% neq 5 (
        echo.
        echo Program berhenti dengan kode keluar: %EXIT_CODE%
        pause
    )
)

exit /b %EXIT_CODE%
