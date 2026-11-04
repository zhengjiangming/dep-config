@echo off
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Stop all

echo.
echo ===== Stop services / engine (local only) =====
for /f "usebackq eol=# tokens=1,3 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do call :STOPSVC %%A %%B

echo.
echo ===== Stop Nginx =====
if not "%START_NGINX%"=="1" goto :SKIP_NGINX
if exist "%NGINX_HOME%\nginx.exe" "%NGINX_HOME%\nginx.exe" -p "%NGINX_HOME%" -c "%NGINX_CONF%" -s quit >nul 2>&1
call :KILLPORT %PORT_NGINX%
:SKIP_NGINX

echo ===== Stop GeoServer =====
if not "%START_GEOSERVER%"=="1" goto :SKIP_GS
call :KILLPORT %PORT_GEOSERVER%
:SKIP_GS

echo ===== Stop Nacos =====
if not "%START_NACOS%"=="1" goto :SKIP_NACOS
if exist "%NACOS_HOME%\bin\shutdown.cmd" (
    call "%NACOS_HOME%\bin\shutdown.cmd"
) else (
    call :KILLPORT %PORT_NACOS%
)
:SKIP_NACOS

echo ===== Stop RocketMQ =====
if not "%START_MQ%"=="1" goto :SKIP_MQ
pushd "%ROCKETMQ_HOME%\bin"
call mqshutdown.cmd broker >nul 2>&1
call mqshutdown.cmd namesrv >nul 2>&1
popd
call :KILLPORT %PORT_MQ_BROKER%
call :KILLPORT %PORT_MQ_NAMESRV%
:SKIP_MQ

echo ===== Stop MinIO =====
if not "%START_MINIO%"=="1" goto :SKIP_MINIO
call :KILLPORT %PORT_MINIO%
call :KILLPORT 9001
:SKIP_MINIO

echo ===== Stop Redis =====
if not "%START_REDIS%"=="1" goto :SKIP_REDIS
if not exist "%REDIS_HOME%\redis-cli.exe" goto :REDIS_KILL
if not defined REDIS_PWD goto :REDIS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% -a %REDIS_PWD% shutdown >nul 2>&1
goto :REDIS_KILL
:REDIS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% shutdown >nul 2>&1
:REDIS_KILL
call :KILLPORT %PORT_REDIS%
:SKIP_REDIS

echo ===== Stop PostgreSQL =====
if not "%START_PG%"=="1" goto :SKIP_PG
if exist "%DATA_DIR%\pg" "%PG_HOME%\bin\pg_ctl.exe" stop -D "%DATA_DIR%\pg" -m fast
call :KILLPORT %PORT_PG%
:SKIP_PG

echo ===== Stop MySQL =====
if not "%START_MYSQL%"=="1" goto :SKIP_MYSQL
if exist "%MYSQL_HOME%\bin\mysqladmin.exe" "%MYSQL_HOME%\bin\mysqladmin.exe" --user=%MYSQL_USER% --password=%MYSQL_PWD% shutdown >nul 2>&1
call :KILLPORT %PORT_MYSQL%
:SKIP_MYSQL

echo.
echo All stopped.
if /i not "%~1"=="auto" pause
exit /b 0

:STOPSVC
rem %1 name, %2 port
set "SP_HOST="
if exist "%APP_HOME%\conf\service-hosts.cfg" for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do if /i "%%X"=="%~1" set "SP_HOST=%%Y"
if /i "%SP_HOST%"=="localhost" set "SP_HOST=127.0.0.1"
set "SP_SELF=%DEPLOY_HOST%"
if /i "%SP_SELF%"=="localhost" set "SP_SELF=127.0.0.1"
if defined SP_HOST if /i not "%SP_HOST%"=="%SP_SELF%" (
    echo   [REMOTE] %~1  %~2 @ %SP_HOST%  (skip)
    exit /b 0
)
echo   stop %~1 ...
call :KILLPORT %~2
exit /b 0

rem ---------- kill process by listening port ----------
:KILLPORT
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do taskkill /F /PID %%P >nul 2>&1
exit /b 0
