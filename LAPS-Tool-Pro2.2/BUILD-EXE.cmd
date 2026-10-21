@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD-EXE.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (
    echo La compilation a echoue. Copiez le message d'erreur ci-dessus.
) else (
    echo Compilation terminee.
)
echo.
pause
exit /b %RESULT%
