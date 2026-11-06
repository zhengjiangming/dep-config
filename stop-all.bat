@echo off
cd /d "%~dp0"
call bin\9-stop-all.bat auto
set "RC=%errorlevel%"
echo.
pause
exit /b %RC%
