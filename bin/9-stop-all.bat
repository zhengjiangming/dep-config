@echo off
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Stop all
set "STOP_FAIL="

echo.
echo ===== Stop services / engine (local only) =====
if exist "%APP_HOME%\conf\apps.cfg" (
    for /f "usebackq eol=# tokens=1,3 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do call :STOPSVC "%%A" "%%B"
) else (
    echo   WARN conf\apps.cfg not found, skip services
)

echo.
echo ===== Stop Nginx =====
if not "%START_NGINX%"=="1" goto :SKIP_NGINX
set "NGX_QUIT_CONF=%NGINX_RUN_CNF%"
if not exist "%NGX_QUIT_CONF%" set "NGX_QUIT_CONF=%NGINX_CONF%"
if exist "%NGINX_HOME%\nginx.exe" "%NGINX_HOME%\nginx.exe" -p "%NGINX_HOME%" -c "%NGX_QUIT_CONF%" -s quit >nul 2>&1
call :KILLPORT %PORT_NGINX%
:SKIP_NGINX

echo ===== Stop GeoServer =====
if not "%START_GEOSERVER%"=="1" goto :SKIP_GS
call :KILLPORT %PORT_GEOSERVER%
:SKIP_GS

echo ===== Stop Nacos =====
if not "%START_NACOS%"=="1" goto :SKIP_NACOS
if exist "%NACOS_HOME%\bin\shutdown.cmd" call "%NACOS_HOME%\bin\shutdown.cmd"
rem shutdown.cmd can report success while the JVM is still alive, always free the port
call :KILLPORT %PORT_NACOS%
:SKIP_NACOS

echo ===== Stop RocketMQ =====
if not "%START_MQ%"=="1" goto :SKIP_MQ
rem the vendor mqshutdown.cmd force-kills every RocketMQ JVM on this host,
rem so stop only the processes listening on our configured ports
call :KILLPORT %PORT_MQ_BROKER%
call :KILLPORT %PORT_MQ_NAMESRV%
:SKIP_MQ

echo ===== Stop MinIO =====
if not "%START_MINIO%"=="1" goto :SKIP_MINIO
call :KILLPORT %PORT_MINIO%
call :KILLPORT %PORT_MINIO_CONSOLE%
:SKIP_MINIO

echo ===== Stop Redis =====
if not "%START_REDIS%"=="1" goto :SKIP_REDIS
call :REDIS_SHUTDOWN
:REDIS_KILL
call :KILLPORT %PORT_REDIS%
:SKIP_REDIS

echo ===== Stop PostgreSQL =====
if not "%START_PG%"=="1" goto :SKIP_PG
if exist "%PG_DATA_DIR%" "%PG_HOME%\bin\pg_ctl.exe" stop -D "%PG_DATA_DIR%" -m fast
rem pg_ctl -m fast returns before every backend released the port, give it
rem a few seconds and only force-kill when it is still listening
call :WAITPORTFREE %PORT_PG% 5
if errorlevel 1 call :KILLPORT %PORT_PG%
:SKIP_PG

echo ===== Stop MySQL =====
if not "%START_MYSQL%"=="1" goto :SKIP_MYSQL
call :MYSQL_SHUTDOWN
if errorlevel 1 (
    echo   WARN graceful shutdown failed, check MYSQL_USER / MYSQL_PWD, trying force stop
    goto :MYSQL_KILL
)
rem graceful shutdown worked, never force-kill mysqld while InnoDB is closing
goto :SKIP_MYSQL
:MYSQL_KILL
call :KILLPORT %PORT_MYSQL%
:SKIP_MYSQL

echo.
if defined STOP_FAIL (
    echo Some processes could not be stopped. Check the [FAIL] lines above.
    if /i not "%~1"=="auto" pause
    exit /b 1
)
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
    echo   [REMOTE] %~1  %~2 @ %SP_HOST%  ^(skip^)
    exit /b 0
)
echo   stop %~1 ...
call :KILLPORT "%~2"
exit /b 0

rem ---------- kill process by listening port ----------
rem  %1 = port. Only kill processes belonging to this deployment, so a port
rem  taken by IIS / another Java app is never force-killed by accident.
:KILLPORT
call :VALIDPORT "%~1"
if errorlevel 1 exit /b 0
rem  a dual stack listener reports the same PID twice, only kill it once
set "KPL_SEEN="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do call :KILLPID %%P "%~1"
exit /b 0

rem  exit /b 1 unless %1 is an integer in 1..65535.
rem  An empty port would make the netstat regex match every listener.
:VALIDPORT
if "%~1"=="" exit /b 1
for /f "delims=0123456789" %%A in ("%~1") do exit /b 1
if %~1 LEQ 0 exit /b 1
if %~1 GTR 65535 exit /b 1
exit /b 0

rem  wait %2 seconds for %1 to be released; exit 1 when still listening
:WAITPORTFREE
call :VALIDPORT "%~1"
if errorlevel 1 exit /b 0
set /a "WF_N=0"
:WAITPORTFREE_LOOP
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if errorlevel 1 exit /b 0
set /a "WF_N+=1"
if !WF_N! GEQ %~2 exit /b 1
ping -n 2 127.0.0.1 >nul
goto :WAITPORTFREE_LOOP

:KILLPID
if defined KPL_SEEN for %%S in (!KPL_SEEN!) do if "%%S"=="%~1" exit /b 0
set "KPL_SEEN=!KPL_SEEN! %~1"
set "KP_IMG="
for /f "tokens=1 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul ^| findstr /v /b /c:"INFO:"') do set "KP_IMG=%%~I"
if not defined KP_IMG exit /b 0
set "KP_OK="
for %%I in (%KILL_PROC_LIST%) do if /i "!KP_IMG!"=="%%I" set "KP_OK=1"
if not defined KP_OK (
    echo   [SKIP] port %~2 is held by !KP_IMG! ^(PID %~1^), not a deployment process
    exit /b 0
)
set "KP_TK="
for /f "delims=" %%E in ('taskkill /F /PID %~1 2^>^&1') do if not defined KP_TK set "KP_TK=%%E"
if not errorlevel 1 exit /b 0
rem taskkill 对已退出的进程也会报错，进程确实还在才算失败
set "KP_ALIVE="
for /f "tokens=2 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul ^| findstr /v /b /c:"INFO:"') do set "KP_ALIVE=1"
if defined KP_ALIVE (
    echo   [FAIL] cannot stop !KP_IMG! ^(PID %~1^) on port %~2
    if defined KP_TK echo          taskkill: !KP_TK!
    echo          Windows service: stop it in services.msc. Otherwise start this tool as administrator
    set "STOP_FAIL=1"
)
exit /b 0

rem ---------- graceful shutdown, delayed expansion off so "!" in passwords survives ----------
:REDIS_SHUTDOWN
setlocal DisableDelayedExpansion
if not exist "%REDIS_HOME%\redis-cli.exe" exit /b 1
if not defined REDIS_PWD goto :RS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% -a "%REDIS_PWD%" shutdown >nul 2>&1
exit /b %errorlevel%
:RS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% shutdown >nul 2>&1
exit /b %errorlevel%

:MYSQL_SHUTDOWN
setlocal DisableDelayedExpansion
if not exist "%MYSQL_HOME%\bin\mysqladmin.exe" exit /b 1
if not defined MYSQL_PWD goto :MS_NOPASS
"%MYSQL_HOME%\bin\mysqladmin.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=%MYSQL_USER% --password="%MYSQL_PWD%" shutdown >nul 2>&1
exit /b %errorlevel%
:MS_NOPASS
"%MYSQL_HOME%\bin\mysqladmin.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=%MYSQL_USER% shutdown >nul 2>&1
exit /b %errorlevel%
