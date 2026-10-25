@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo NFS The Run Private Server - Build All
echo Go backend + player launcher + legacy SSLv3 gateway
echo ============================================================
echo.

where go >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Go was not found in PATH.
    echo Install Go 1.23 or newer, reopen this prompt, then run Build_All.bat again.
    pause
    exit /b 1
)

echo [1/2] Testing and building Go components...
pushd source
set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=0"
go test ./...
if errorlevel 1 (popd & goto :go_fail)
go build -trimpath -ldflags="-s -w" -o "..\nfsrun-server.exe" .\cmd\nfsrun-server
if errorlevel 1 (popd & goto :go_fail)
set "GOOS="
set "GOARCH="
rem launcher icon, version info and manifest (cmd\nfsrun-launcher\rsrc_windows_*.syso)
go run .\cmd\mkwinres
if errorlevel 1 (popd & goto :go_fail)
set "GOOS=windows"
set "GOARCH=386"
rem -H windowsgui: the launcher is a window, no console
go build -trimpath -ldflags="-s -w -H windowsgui" -o "..\launcher\nfsrun-launcher.exe" .\cmd\nfsrun-launcher
if errorlevel 1 (set "GOARCH=amd64" & popd & goto :go_fail)
set "GOARCH=amd64"
popd

echo.
echo [2/2] Building x86 legacy SSLv3 gateway...
call legacy_gateway\build_x86.bat
if errorlevel 1 goto :gateway_fail

echo.
echo ============================================================
echo BUILD COMPLETE
echo ============================================================
echo Server:      nfsrun-server.exe
echo Launcher:    launcher\nfsrun-launcher.exe
echo SSL gateway: legacy_gateway\build\nfsrun-ssl-gateway.exe
echo OpenSSL CLI: legacy_gateway\build\openssl-1.0.2u.exe
echo.
echo Next step: put a portable MariaDB distribution in mariadb\,
echo then run start_server.bat. First-run setup creates configuration,
echo certificates and a configured player package in dist\.
echo.
echo No game executable or dedicated-server executable is distributed.
echo If dedicated race servers are enabled during setup, the server creates
echo NFSTR_DedicatedServer.exe from the owner's own game executable.
echo ============================================================
exit /b 0

:go_fail
echo [ERROR] Go tests or build failed.
pause
exit /b 1

:gateway_fail
echo [ERROR] Legacy SSL gateway build failed.
pause
exit /b 1
