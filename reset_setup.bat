@echo off
setlocal
cd /d "%~dp0"
echo WARNING: This removes THIS PACKAGE'S config and MariaDB data.
echo It does not touch your game installation. The launcher HTTPS certificate
echo (certs\launcher.*) is kept, so existing player packages keep working.
echo.
set /p CONFIRM=Type RESET to continue: 
if /I not "%CONFIRM%"=="RESET" exit /b 0
if exist "config" rmdir /s /q "config"
if exist "mariadb\data" rmdir /s /q "mariadb\data"
if exist "certs\protossl_redirector.crt" del /q "certs\protossl_redirector.crt"
if exist "certs\protossl_redirector.key" del /q "certs\protossl_redirector.key"
if exist "certs\protossl_redirector.info.txt" del /q "certs\protossl_redirector.info.txt"
mkdir config 2>nul
echo Reset complete.
pause
