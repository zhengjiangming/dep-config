@echo off
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Runtime status
echo.
echo ===== Infrastructure =====
call :SHOWI %PORT_MYSQL% MySQL "%MYSQL_HOST%" %START_MYSQL%
call :SHOWI %PORT_PG% PostgreSQL "%PG_HOST%" %START_PG%
call :SHOWI %PORT_REDIS% Redis "%REDIS_HOST%" %START_REDIS%
call :SHOWI %PORT_MQ_NAMESRV% RocketMQ-NameServer "%MQ_HOST%" %START_MQ%
call :SHOWI %PORT_MQ_BROKER% RocketMQ-Broker "%MQ_HOST%" %START_MQ%
call :SHOWI %PORT_MINIO% MinIO "%MINIO_HOST%" %START_MINIO%
call :SHOWI %PORT_NACOS% Nacos "%NACOS_HOST%" %START_NACOS%
call :SHOWI %PORT_GEOSERVER% GeoServer "%GEOSERVER_HOST%" %START_GEOSERVER%
call :SHOWI %PORT_NGINX% Nginx "%NGINX_HOST%" %START_NGINX%
echo.
echo ===== Services / Engine =====
if exist "%APP_HOME%\conf\apps.cfg" (
    for /f "usebackq eol=# tokens=1,3 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do call :SHOWSVC "%%A" "%%B"
) else (
    echo   [FAIL] conf\apps.cfg not found
)
echo.
echo Nacos console: http://%NACOS_HOST%:%PORT_NACOS%/nacos
if /i not "%~1"=="auto" pause
exit /b 0

:SHOWSVC
rem %1 name, %2 port
set "SH_HOST="
if exist "%APP_HOME%\conf\service-hosts.cfg" for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do if /i "%%X"=="%~1" set "SH_HOST=%%Y"
if /i "%SH_HOST%"=="localhost" set "SH_HOST=127.0.0.1"
set "SH_SELF=%DEPLOY_HOST%"
if /i "%SH_SELF%"=="localhost" set "SH_SELF=127.0.0.1"
if defined SH_HOST if /i not "%SH_HOST%"=="%SH_SELF%" (
    echo   [REMOTE] %~1  %~2 @ %SH_HOST%
    exit /b 0
)
call :SHOW "%~2" "%~1"
exit /b 0

:SHOWI
rem %1 port, %2 name, %3 host, %4 start flag
if not "%~4"=="1" (
    echo   [REMOTE] %~2  %~3:%~1
    exit /b 0
)
call :SHOW "%~1" "%~2"
exit /b 0

:SHOW
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if errorlevel 1 (echo   [DOWN] %~2  port %~1) else (echo   [ UP ] %~2  port %~1)
exit /b 0
