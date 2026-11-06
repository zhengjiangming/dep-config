@echo off
rem =====================================================================
rem  Install the bundled VC++ 2015-2022 x64 runtime (needed by MySQL,
rem  PostgreSQL and MinIO on a clean Windows).
rem  Usage: 11-vcredist.bat [auto]   (auto = no pause)
rem  Set VCREDIST_EXE in deploy.properties to use a different installer.
rem =====================================================================
setlocal
call "%~dp0..\conf\env.bat"
title VC++ runtime
set "NO_PAUSE="
if /i "%~1"=="auto" set "NO_PAUSE=1"

echo.
echo ===== VC++ 2015-2022 x64 runtime =====
if not exist "%VCREDIST_EXE%" (
    echo   SKIP installer not found: %VCREDIST_EXE%
    echo   If MySQL/PG/MinIO cannot start, install the runtime manually,
    echo   or install Windows 7 UCRT update KB2999226.
    if not defined NO_PAUSE pause
    exit /b 0
)

echo   Installing %VCREDIST_EXE% ...
"%VCREDIST_EXE%" /install /quiet /norestart
set "RC=%ERRORLEVEL%"
rem 0 = ok, 1638 = a newer runtime is already installed, 3010 = reboot required
if "%RC%"=="0" goto :OK
if "%RC%"=="1638" goto :OK
if "%RC%"=="3010" goto :OK
echo   WARN installer exit code %RC%
if not defined NO_PAUSE pause
exit /b 1

:OK
echo   OK   runtime available ^(exit %RC%^)
if not defined NO_PAUSE pause
exit /b 0
