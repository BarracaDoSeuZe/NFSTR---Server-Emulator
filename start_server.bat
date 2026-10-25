@echo off
setlocal
cd /d "%~dp0"
title NFS The Run Private Server

rem First start: create the database, configuration and certificates.
if not exist "config\.initialized" (
    echo.
    echo   NFS The Run Private Server - first run setup
    echo   --------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\first_run_setup.ps1"
    if errorlevel 1 (
        echo.
        echo   Setup failed. The server was not started.
        pause >nul
        exit /b 1
    )
    echo.
    echo   Press any key to start the server.
    pause >nul
)

rem The server window takes single keys: C = command line, Q = stop, L = log view, H = help.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_server.ps1"
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo   The server exited with code %EXITCODE%. Details: logs\server.log
echo   Press any key to close this window.
pause >nul
exit /b %EXITCODE%
