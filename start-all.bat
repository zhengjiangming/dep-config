@echo off
cd /d "%~dp0"
call bin\2-start-infra.bat auto
call bin\3-start-apps.bat auto
echo.
echo All start steps finished. Logs: %~dp0logs
pause
