@echo off
rem =====================================================================
rem  Shared helpers.
rem  Usage: call "%~dp0_lib.bat" render-mq
rem         call "%~dp0_lib.bat" render-nginx
rem  The caller must load conf\env.bat first: this script only replaces
rem  ${...} placeholders with the variables already in the environment.
rem =====================================================================
setlocal enabledelayedexpansion
if /i "%~1"=="render-mq" goto :RENDER_MQ
if /i "%~1"=="render-nginx" goto :RENDER_NGINX
exit /b 1

rem ---------- render RocketMQ broker.conf: replace ${...} placeholders ----------
:RENDER_MQ
rem  template and rendered output MUST be different files: the redirect below
rem  would truncate the template if both paths are equal
if /i "%MQ_BROKER_CNF%"=="%MQ_BROKER_RUN_CNF%" (
    echo   FAIL MQ_BROKER_CNF and MQ_BROKER_RUN_CNF point to the same file: "%MQ_BROKER_CNF%"
    exit /b 1
)
if not exist "%MQ_BROKER_CNF%" exit /b 1
if not exist "%MQ_DATA_DIR%" mkdir "%MQ_DATA_DIR%" >nul 2>&1
for %%P in ("%MQ_BROKER_RUN_CNF%") do if not exist "%%~dpP" mkdir "%%~dpP" >nul 2>&1
> "%MQ_BROKER_RUN_CNF%" (
    for /f "usebackq delims=" %%L in ("%MQ_BROKER_CNF%") do (
        set "L=%%L"
        set "L=!L:${MQ_BROKER_PORT}=%MQ_BROKER_PORT%!"
        set "L=!L:${MQ_HA_PORT}=%MQ_HA_PORT%!"
        set "L=!L:${MQ_DATA_DIR}=%MQ_DATA_DIR%!"
        echo !L!
    )
)
findstr /c:"${MQ_BROKER_PORT}" /c:"${MQ_HA_PORT}" /c:"${MQ_DATA_DIR}" "%MQ_BROKER_RUN_CNF%" >nul 2>&1
if not errorlevel 1 exit /b 1
exit /b 0

rem ---------- render nginx.conf: replace ${...} placeholders ----------
:RENDER_NGINX
rem  template and rendered output MUST be different files: the redirect below
rem  would truncate the template if both paths are equal
if /i "%NGINX_CONF%"=="%NGINX_RUN_CNF%" (
    echo   FAIL NGINX_CONF and NGINX_RUN_CNF point to the same file: "%NGINX_CONF%"
    echo        set NGINX_RUN_CNF to a different path, e.g. conf\nginx.run.conf
    exit /b 1
)
if not exist "%NGINX_CONF%" exit /b 1
for %%P in ("%NGINX_RUN_CNF%") do if not exist "%%~dpP" mkdir "%%~dpP" >nul 2>&1
> "%NGINX_RUN_CNF%" (
    for /f "usebackq delims=" %%L in ("%NGINX_CONF%") do (
        set "L=%%L"
        set "L=!L:${NGINX_PORT}=%NGINX_PORT%!"
        set "L=!L:${NGINX_HOST}=%NGINX_HOST%!"
        set "L=!L:${DEPLOY_HOST}=%DEPLOY_HOST%!"
        echo !L!
    )
)
findstr /c:"${NGINX_PORT}" /c:"${NGINX_HOST}" /c:"${DEPLOY_HOST}" "%NGINX_RUN_CNF%" >nul 2>&1
if not errorlevel 1 exit /b 1
exit /b 0
