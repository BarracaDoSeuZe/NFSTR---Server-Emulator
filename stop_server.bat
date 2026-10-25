@echo off
setlocal
cd /d "%~dp0"
rem Stops the running private server cleanly (same as pressing Q in its window):
rem the server closes its connections and race servers, then start_server.bat
rem stops the SSL gateway and the portable MariaDB.
tasklist /FI "IMAGENAME eq nfsrun-server.exe" 2>nul | find /I "nfsrun-server.exe" >nul
if errorlevel 1 (
  echo The server is not running.
  timeout /t 3 >nul
  exit /b 0
)
if not exist "run" mkdir "run"
type nul > "run\stop.request"
echo Stop requested, waiting for the server to close...
for /L %%i in (1,1,30) do (
  tasklist /FI "IMAGENAME eq nfsrun-server.exe" 2>nul | find /I "nfsrun-server.exe" >nul
  if errorlevel 1 (
    echo Server stopped.
    timeout /t 2 >nul
    exit /b 0
  )
  timeout /t 1 >nul
)
echo The server did not stop within 30 s. Close its window, or end nfsrun-server.exe in Task Manager.
pause
exit /b 1
