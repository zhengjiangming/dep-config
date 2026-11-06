@echo off
cd /d "%~dp0"
call bin\2-start-infra.bat auto
if errorlevel 1 goto :FAIL
call bin\3-start-apps.bat auto
if errorlevel 1 goto :FAIL
echo.
echo All start steps finished. Logs: %~dp0logs
pause
exit /b 0

:FAIL
echo.
echo Start aborted, fix the errors above and re-run start-all.bat
echo Logs: %~dp0logs
pause
exit /b 1
