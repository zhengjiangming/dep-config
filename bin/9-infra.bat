@echo off
rem =====================================================================
rem  Start / stop / restart ONE infrastructure component.
rem  Usage: 9-infra.bat start|stop|restart <component>
rem  component: mysql | pg | redis | mq | minio | nacos | geoserver | nginx
rem  Remote components (START_* = 0) are refused.
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"

set "ACTION=%~1"
set "COMP=%~2"
if "%ACTION%"=="" goto :USAGE
if "%COMP%"=="" goto :USAGE

set "LOCAL="
if /i "%COMP%"=="mysql" set "LOCAL=%START_MYSQL%"
if /i "%COMP%"=="pg" set "LOCAL=%START_PG%"
if /i "%COMP%"=="redis" set "LOCAL=%START_REDIS%"
if /i "%COMP%"=="mq" set "LOCAL=%START_MQ%"
if /i "%COMP%"=="minio" set "LOCAL=%START_MINIO%"
if /i "%COMP%"=="nacos" set "LOCAL=%START_NACOS%"
if /i "%COMP%"=="geoserver" set "LOCAL=%START_GEOSERVER%"
if /i "%COMP%"=="nginx" set "LOCAL=%START_NGINX%"
if not defined LOCAL goto :BAD_COMP
if not "%LOCAL%"=="1" (
    echo   REMOTE %COMP% runs on another machine, skipped
    exit /b 1
)

if /i "%ACTION%"=="stop" goto :STOP
if /i "%ACTION%"=="restart" goto :RESTART
if /i "%ACTION%"=="start" goto :START
goto :USAGE

rem =====================================================================
:RESTART
call "%~f0" stop %COMP%
ping -n 2 127.0.0.1 >nul
call "%~f0" start %COMP%
exit /b %errorlevel%

rem =====================================================================
:STOP
if /i "%COMP%"=="mysql" goto :STOP_MYSQL
if /i "%COMP%"=="pg" goto :STOP_PG
if /i "%COMP%"=="redis" goto :STOP_REDIS
if /i "%COMP%"=="mq" goto :STOP_MQ
if /i "%COMP%"=="minio" goto :STOP_MINIO
if /i "%COMP%"=="nacos" goto :STOP_NACOS
if /i "%COMP%"=="geoserver" goto :STOP_GS
if /i "%COMP%"=="nginx" goto :STOP_NGINX
goto :USAGE

:STOP_MYSQL
echo   [STOP] MySQL
if exist "%MYSQL_HOME%\bin\mysqladmin.exe" "%MYSQL_HOME%\bin\mysqladmin.exe" --user=%MYSQL_USER% --password=%MYSQL_PWD% shutdown >nul 2>&1
call :KILLPORT %PORT_MYSQL%
exit /b 0

:STOP_PG
echo   [STOP] PostgreSQL
if exist "%DATA_DIR%\pg" "%PG_HOME%\bin\pg_ctl.exe" stop -D "%DATA_DIR%\pg" -m fast >nul 2>&1
call :KILLPORT %PORT_PG%
exit /b 0

:STOP_REDIS
echo   [STOP] Redis
if not exist "%REDIS_HOME%\redis-cli.exe" goto :STOP_REDIS_KILL
if not defined REDIS_PWD goto :STOP_REDIS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% -a %REDIS_PWD% shutdown >nul 2>&1
goto :STOP_REDIS_KILL
:STOP_REDIS_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% shutdown >nul 2>&1
:STOP_REDIS_KILL
call :KILLPORT %PORT_REDIS%
exit /b 0

:STOP_MQ
echo   [STOP] RocketMQ
pushd "%ROCKETMQ_HOME%\bin"
call mqshutdown.cmd broker >nul 2>&1
call mqshutdown.cmd namesrv >nul 2>&1
popd
call :KILLPORT %PORT_MQ_BROKER%
call :KILLPORT %PORT_MQ_NAMESRV%
exit /b 0

:STOP_MINIO
echo   [STOP] MinIO
call :KILLPORT %PORT_MINIO%
call :KILLPORT 9001
exit /b 0

:STOP_NACOS
echo   [STOP] Nacos
if exist "%NACOS_HOME%\bin\shutdown.cmd" (
    call "%NACOS_HOME%\bin\shutdown.cmd"
) else (
    call :KILLPORT %PORT_NACOS%
)
exit /b 0

:STOP_GS
echo   [STOP] GeoServer
call :KILLPORT %PORT_GEOSERVER%
exit /b 0

:STOP_NGINX
echo   [STOP] Nginx
if exist "%NGINX_HOME%\nginx.exe" "%NGINX_HOME%\nginx.exe" -p "%NGINX_HOME%" -c "%NGINX_CONF%" -s quit >nul 2>&1
call :KILLPORT %PORT_NGINX%
exit /b 0

rem =====================================================================
:START
if /i "%COMP%"=="mysql" goto :START_MYSQL
if /i "%COMP%"=="pg" goto :START_PG
if /i "%COMP%"=="redis" goto :START_REDIS
if /i "%COMP%"=="mq" goto :START_MQ
if /i "%COMP%"=="minio" goto :START_MINIO
if /i "%COMP%"=="nacos" goto :START_NACOS
if /i "%COMP%"=="geoserver" goto :START_GS
if /i "%COMP%"=="nginx" goto :START_NGINX
goto :USAGE

:START_MYSQL
echo   [START] MySQL port=%PORT_MYSQL%
if not exist "%DATA_DIR%\mysql" (
    echo   FAIL MySQL not initialized, run bin\0-init.bat first
    exit /b 1
)
start "mysql" /D "%MYSQL_HOME%\bin" /MIN cmd /c "mysqld.exe --defaults-file=%MYSQL_HOME%\my.ini >> %LOG_DIR%\mysql.log 2>&1"
call :WAITPORT %PORT_MYSQL% 90 "MySQL"
exit /b %errorlevel%

:START_PG
echo   [START] PostgreSQL port=%PORT_PG%
if not exist "%DATA_DIR%\pg" (
    echo   FAIL PostgreSQL not initialized, run bin\0-init.bat first
    exit /b 1
)
"%PG_HOME%\bin\pg_ctl.exe" start -D "%DATA_DIR%\pg" -l "%LOG_DIR%\postgres.log" -w
call :WAITPORT %PORT_PG% 60 "PostgreSQL"
exit /b %errorlevel%

:START_REDIS
echo   [START] Redis port=%PORT_REDIS%
start "redis" /D "%REDIS_HOME%" /MIN cmd /c "redis-server.exe redis.windows.conf >> %LOG_DIR%\redis.log 2>&1"
call :WAITPORT %PORT_REDIS% 30 "Redis"
exit /b %errorlevel%

:START_MINIO
echo   [START] MinIO port=%PORT_MINIO%
set "MINIO_ROOT_USER=%MINIO_USER%"
set "MINIO_ROOT_PASSWORD=%MINIO_PWD%"
set "MINIO_ACCESS_KEY=%MINIO_USER%"
set "MINIO_SECRET_KEY=%MINIO_PWD%"
start "minio" /D "%MINIO_HOME%" /MIN cmd /c "minio.exe server "%MINIO_DATA_DIR%" --address :%PORT_MINIO% --console-address :9001 >> %LOG_DIR%\minio.log 2>&1"
call :WAITPORT %PORT_MINIO% 30 "MinIO"
exit /b %errorlevel%

:START_MQ
echo   [START] RocketMQ NameServer port=%PORT_MQ_NAMESRV%
start "mqnamesrv" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqnamesrv.cmd >> %LOG_DIR%\mqnamesrv.log 2>&1"
call :WAITPORT %PORT_MQ_NAMESRV% 60 "RocketMQ NameServer"
if errorlevel 1 exit /b 1
echo   [START] RocketMQ Broker port=%PORT_MQ_BROKER%
start "mqbroker" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqbroker.cmd -n %MQ_HOST%:%PORT_MQ_NAMESRV% -c %ROCKETMQ_HOME%\conf\broker.conf >> %LOG_DIR%\mqbroker.log 2>&1"
call :WAITPORT %PORT_MQ_BROKER% 90 "RocketMQ Broker"
exit /b %errorlevel%

:START_NACOS
echo   [START] Nacos port=%PORT_NACOS%
set "JVM_XMS=512m"
set "JVM_XMX=512m"
set "JVM_XMN=256m"
set "JAVA_OPT_EXT=-Xms512m -Xmx512m -Xmn256m"
set "JAVA_TOOL_OPTIONS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"
start "nacos" /D "%NACOS_HOME%\bin" /MIN cmd /c "startup.cmd -m standalone >> %LOG_DIR%\nacos.log 2>&1"
set "JAVA_TOOL_OPTIONS="
set "JAVA_OPT_EXT="
set "JVM_XMS="
set "JVM_XMX="
set "JVM_XMN="
call :WAITPORT %PORT_NACOS% 180 "Nacos"
exit /b %errorlevel%

:START_GS
echo   [START] GeoServer port=%PORT_GEOSERVER%
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"
start "geoserver" /D "%GEOSERVER_HOME%\bin" /MIN cmd /c "startup.bat >> %LOG_DIR%\geoserver.log 2>&1"
call :WAITPORT %PORT_GEOSERVER% 180 "GeoServer"
exit /b %errorlevel%

:START_NGINX
echo   [START] Nginx port=%PORT_NGINX%
if not exist "%NGINX_HOME%\nginx.exe" (
    echo   FAIL nginx not found: %NGINX_HOME%
    exit /b 1
)
if not exist "%NGINX_HOME%\logs" mkdir "%NGINX_HOME%\logs" >nul 2>&1
if not exist "%NGINX_HOME%\temp" mkdir "%NGINX_HOME%\temp" >nul 2>&1
if not exist "%NGINX_CONF%" (
    echo   FAIL nginx.conf not found: %NGINX_CONF%
    exit /b 1
)
start "nginx" /D "%NGINX_HOME%" /MIN cmd /c "nginx.exe -p %NGINX_HOME% -c %NGINX_CONF% >> %LOG_DIR%\nginx.log 2>&1"
call :WAITPORT %PORT_NGINX% 30 "Nginx"
exit /b %errorlevel%

rem =====================================================================
:USAGE
echo Usage: 9-infra.bat start^|stop^|restart ^<mysql^|pg^|redis^|mq^|minio^|nacos^|geoserver^|nginx^>
exit /b 1

:BAD_COMP
echo   FAIL unknown component: %COMP%
exit /b 1

rem ---------- helpers ----------
:WAITPORT
set /a WP_N=0
:WAITPORT_LOOP
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo   OK   %~3 port %~1 ready
    exit /b 0
)
set /a WP_N+=1
if %WP_N% GEQ %~2 (
    echo   FAIL %~3 port %~1 timeout, check logs in %LOG_DIR%
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :WAITPORT_LOOP

:KILLPORT
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do taskkill /F /PID %%P >nul 2>&1
exit /b 0
