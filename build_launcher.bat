@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo  NFS The Run - build nfsrun-launcher.exe (player launcher)
echo  Needs Go 1.23+ in PATH. Builds a 32-bit exe (the game must see it as a process).
echo ============================================================
where go >nul 2>nul
if errorlevel 1 (
  echo Go not found. Install from https://go.dev/dl/ and run again.
  pause
  exit /b 1
)
pushd source
set "GOOS=windows"
set "GOARCH=386"
set "CGO_ENABLED=0"
go test ./internal/lsx
if errorlevel 1 goto fail
set "GOOS="
set "GOARCH="
go run ./cmd/mkwinres
if errorlevel 1 goto fail
set "GOOS=windows"
set "GOARCH=386"
go build -trimpath -ldflags="-s -w -H windowsgui" -o "..\launcher\nfsrun-launcher.exe" ./cmd/nfsrun-launcher
if errorlevel 1 goto fail
popd
echo.
echo OK: launcher\nfsrun-launcher.exe
echo Player packages are created after server first-run setup.
pause
exit /b 0
:fail
popd
echo BUILD FAILED
pause
exit /b 1
