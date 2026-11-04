@echo off
setlocal
call "%~dp0..\conf\env.bat"
title Start infrastructure
set "JAVA_HOME=%JDK_HOME%"

echo.
echo ===== Start infrastructure (dependency order) =====
echo   APP_HOME = %APP_HOME%
echo   local: mysql=%START_MYSQL% pg=%START_PG% redis=%START_REDIS% minio=%START_MINIO% mq=%START_MQ% nacos=%START_NACOS% geoserver=%START_GEOSERVER% nginx=%START_NGINX%
set "FAILED="
set "FAILED_LIST="
echo.

rem ---------- 1. MySQL ----------
if not "%START_MYSQL%"=="1" goto :PG
echo [1/9] MySQL ...
if not exist "%DATA_DIR%\mysql" goto :NO_MYSQL
start "mysql" /D "%MYSQL_HOME%\bin" /MIN cmd /c "mysqld.exe --defaults-file=%MYSQL_HOME%\my.ini >> %LOG_DIR%\mysql.log 2>&1"
call :WAITPORT %PORT_MYSQL% 90 "MySQL"
if errorlevel 1 call :MARKFAIL MySQL
goto :PG
:NO_MYSQL
echo   [SKIP] MySQL not initialized, run bin\0-init.bat first
call :MARKFAIL MySQL
:PG

rem ---------- 2. PostgreSQL ----------
if not "%START_PG%"=="1" goto :REDIS
echo [2/9] PostgreSQL ...
if not exist "%DATA_DIR%\pg" goto :NO_PG
"%PG_HOME%\bin\pg_ctl.exe" start -D "%DATA_DIR%\pg" -l "%LOG_DIR%\postgres.log" -w
call :WAITPORT %PORT_PG% 60 "PostgreSQL"
if errorlevel 1 call :MARKFAIL PostgreSQL
goto :REDIS
:NO_PG
echo   [SKIP] PostgreSQL not initialized, run bin\0-init.bat first
call :MARKFAIL PostgreSQL
:REDIS

rem ---------- 3. Redis ----------
if not "%START_REDIS%"=="1" goto :MINIO
echo [3/9] Redis ...
start "redis" /D "%REDIS_HOME%" /MIN cmd /c "redis-server.exe redis.windows.conf >> %LOG_DIR%\redis.log 2>&1"
call :WAITPORT %PORT_REDIS% 30 "Redis"
if errorlevel 1 call :MARKFAIL Redis

rem ---------- 4. MinIO ----------
:MINIO
if not "%START_MINIO%"=="1" goto :MQ
echo [4/9] MinIO ...
set "MINIO_ROOT_USER=%MINIO_USER%"
set "MINIO_ROOT_PASSWORD=%MINIO_PWD%"
set "MINIO_ACCESS_KEY=%MINIO_USER%"
set "MINIO_SECRET_KEY=%MINIO_PWD%"
start "minio" /D "%MINIO_HOME%" /MIN cmd /c "minio.exe server "%MINIO_DATA_DIR%" --address :%PORT_MINIO% --console-address :9001 >> %LOG_DIR%\minio.log 2>&1"
call :WAITPORT %PORT_MINIO% 30 "MinIO"
if errorlevel 1 call :MARKFAIL MinIO

rem ---------- 5. RocketMQ NameServer ----------
:MQ
if not "%START_MQ%"=="1" goto :NACOS
echo [5/9] RocketMQ NameServer ...
start "mqnamesrv" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqnamesrv.cmd >> %LOG_DIR%\mqnamesrv.log 2>&1"
call :WAITPORT %PORT_MQ_NAMESRV% 60 "RocketMQ NameServer"
if errorlevel 1 (
    call :MARKFAIL RocketMQ-NameServer
    goto :NACOS
)

rem ---------- 6. RocketMQ Broker ----------
echo [6/9] RocketMQ Broker ...
start "mqbroker" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqbroker.cmd -n %MQ_HOST%:%PORT_MQ_NAMESRV% -c %ROCKETMQ_HOME%\conf\broker.conf >> %LOG_DIR%\mqbroker.log 2>&1"
call :WAITPORT %PORT_MQ_BROKER% 90 "RocketMQ Broker"
if errorlevel 1 call :MARKFAIL RocketMQ-Broker

rem ---------- 7. Nacos ----------
:NACOS
if not "%START_NACOS%"=="1" goto :GEOSERVER
echo [7/9] Nacos ...
rem Nacos 2.3.3: cap heap (default is 1g-2g) and allow JDK17 reflection access
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
if errorlevel 1 call :MARKFAIL Nacos

rem ---------- 8. GeoServer ----------
:GEOSERVER
if not "%START_GEOSERVER%"=="1" goto :NGINX
echo [8/9] GeoServer ...
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"
start "geoserver" /D "%GEOSERVER_HOME%\bin" /MIN cmd /c "startup.bat >> %LOG_DIR%\geoserver.log 2>&1"
call :WAITPORT %PORT_GEOSERVER% 180 "GeoServer"
if errorlevel 1 call :MARKFAIL GeoServer

rem ---------- 9. Nginx ----------
:NGINX
if not "%START_NGINX%"=="1" goto :DONE
echo [9/9] Nginx ...
if not exist "%NGINX_HOME%\nginx.exe" goto :NO_NGINX
if not exist "%NGINX_HOME%\logs" mkdir "%NGINX_HOME%\logs" >nul 2>&1
if not exist "%NGINX_HOME%\temp" mkdir "%NGINX_HOME%\temp" >nul 2>&1
if not exist "%NGINX_CONF%" echo   WARN nginx.conf not found: %NGINX_CONF%
findstr /c:"${" "%NGINX_CONF%" >nul 2>&1
if not errorlevel 1 echo   WARN nginx.conf still has ${...} placeholders, run Setup.exe - Nginx config - Inject variables
start "nginx" /D "%NGINX_HOME%" /MIN cmd /c "nginx.exe -p %NGINX_HOME% -c %NGINX_CONF% >> %LOG_DIR%\nginx.log 2>&1"
call :WAITPORT %PORT_NGINX% 30 "Nginx"
if errorlevel 1 call :MARKFAIL Nginx
goto :DONE
:NO_NGINX
echo   [SKIP] nginx not found: %NGINX_HOME%
call :MARKFAIL Nginx
:DONE

if defined FAILED (
    echo.
    echo FAILED components:%FAILED_LIST%
    echo Check logs in %LOG_DIR%
    if /i not "%~1"=="auto" pause
    exit /b 1
)
echo.
echo Infrastructure started. Next: bin\3-start-apps.bat
echo Logs: %LOG_DIR%
if /i not "%~1"=="auto" pause
exit /b 0

rem ---------- mark a failed component and keep going ----------
:MARKFAIL
set "FAILED=1"
set "FAILED_LIST=%FAILED_LIST% %~1"
exit /b 0

rem ---------- wait until port is listening ----------
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
