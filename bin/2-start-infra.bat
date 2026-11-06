@echo off
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Start infrastructure
set "JAVA_HOME=%JDK_HOME%"

echo.
echo ===== Start infrastructure (dependency order) =====
echo   APP_HOME = %APP_HOME%
echo   DATA_DIR = %DATA_DIR%
echo   local: mysql=%START_MYSQL% pg=%START_PG% redis=%START_REDIS% minio=%START_MINIO% mq=%START_MQ% nacos=%START_NACOS% geoserver=%START_GEOSERVER% nginx=%START_NGINX%
set "FAILED="
set "FAILED_LIST="
echo.

rem  this script writes logs, create the folder on demand (env.bat stays read-only)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

rem ---------- 1. MySQL ----------
if not "%START_MYSQL%"=="1" goto :PG
echo [1/9] MySQL ...
if not exist "%MYSQL_HOME%\bin\mysqld.exe" (
    echo   [FAIL] mysqld.exe not found: %MYSQL_HOME%\bin\mysqld.exe
    call :MARKFAIL MySQL
    goto :PG
)
if not exist "%MYSQL_DATA_DIR%\mysql" goto :NO_MYSQL
if not exist "%MYSQL_CNF%" goto :NO_MYSQL_CNF
call :PORTSKIP %PORT_MYSQL% "MySQL" mysqld.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL MySQL
if not "!PS_RC!"=="0" goto :PG
rem  a MySQL Windows service installed? start it via net start (no console window)
call :FIND_MYSQL_SERVICE
if not defined MS_SVC goto :MYSQL_DIRECT
echo   MySQL service found: %MS_SVC%, net start ...
net start "%MS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_MYSQL% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %MS_SVC% failed, fall back to mysqld.exe with configured parameters
        goto :MYSQL_DIRECT
    )
)
call :WAITPORT %PORT_MYSQL% %WAIT_MYSQL_SEC% "MySQL"
set "MYSQL_WAIT_RC=!errorlevel!"
if "!MYSQL_WAIT_RC!"=="0" (call :ENSURE_MYSQL_PWD) else (call :MARKFAIL MySQL)
goto :PG
:MYSQL_DIRECT
start "mysql" /D "%MYSQL_HOME%\bin" /MIN cmd /c "mysqld.exe --defaults-file="%MYSQL_CNF%" --datadir="%MYSQL_DATA_DIR%" --port=%MYSQL_PORT% >> "%LOG_DIR%\mysql.log" 2>&1"
call :WAITPORT %PORT_MYSQL% %WAIT_MYSQL_SEC% "MySQL"
set "MYSQL_WAIT_RC=!errorlevel!"
if "!MYSQL_WAIT_RC!"=="0" (call :ENSURE_MYSQL_PWD) else (call :MARKFAIL MySQL)
goto :PG
:NO_MYSQL_CNF
echo   [FAIL] MySQL config not found: %MYSQL_CNF%
call :MARKFAIL MySQL
goto :PG
:NO_MYSQL
echo   [SKIP] MySQL data dir not initialized: %MYSQL_DATA_DIR%
echo          Run bin\0-init.bat first.
call :MARKFAIL MySQL
:PG

rem ---------- 2. PostgreSQL ----------
if not "%START_PG%"=="1" goto :REDIS
echo [2/9] PostgreSQL ...
if not exist "%PG_DATA_DIR%\PG_VERSION" goto :NO_PG
call :PORTSKIP %PORT_PG% "PostgreSQL" postgres.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL PostgreSQL
if not "!PS_RC!"=="0" goto :REDIS
rem  prefer a Windows service hosting postgres.exe (net start, no console window)
call :FIND_PG_SERVICE
if not defined PG_SVC goto :PG_DIRECT
echo   OK   PostgreSQL service found: !PG_SVC!, net start ...
net start "!PG_SVC!" >nul 2>&1
call :WAITPORT %PORT_PG% 15 "PostgreSQL"
if not errorlevel 1 goto :REDIS
echo   WARN net start !PG_SVC! failed or port not ready, fall back to pg_ctl
:PG_DIRECT
if not exist "%PG_HOME%\bin\pg_ctl.exe" (
    echo   [FAIL] pg_ctl.exe not found: %PG_HOME%\bin\pg_ctl.exe
    call :MARKFAIL PostgreSQL
    goto :REDIS
)
rem  detached start: keeps postgres's handles away from the caller console
start "postgres" /D "%PG_HOME%\bin" /MIN cmd /c "pg_ctl.exe start -D "%PG_DATA_DIR%" -l "%LOG_DIR%\postgres.log" -o "-p %PG_PORT%" -w >> "%LOG_DIR%\pg_ctl.log" 2>&1"
call :WAITPORT %PORT_PG% %WAIT_PG_SEC% "PostgreSQL"
if errorlevel 1 call :MARKFAIL PostgreSQL
goto :REDIS
:NO_PG
echo   [SKIP] PostgreSQL data dir not initialized: %PG_DATA_DIR%
echo          Run bin\0-init.bat first.
call :MARKFAIL PostgreSQL
:REDIS

rem ---------- 3. Redis ----------
if not "%START_REDIS%"=="1" goto :MINIO
echo [3/9] Redis ...
if not exist "%REDIS_HOME%\redis-server.exe" (
    echo   [FAIL] redis-server.exe not found: %REDIS_HOME%\redis-server.exe
    call :MARKFAIL Redis
    goto :MINIO
)
if not exist "%REDIS_CNF%" goto :NO_REDIS_CNF
call :PORTSKIP %PORT_REDIS% "Redis" redis-server.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL Redis
if not "!PS_RC!"=="0" goto :MINIO
rem  a Redis Windows service installed? start it via net start (no console window)
call :FIND_REDIS_SERVICE
if not defined RS_SVC goto :START_REDIS_DIRECT
echo   Redis service found: !RS_SVC!, net start ...
net start "!RS_SVC!" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_REDIS% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] net start !RS_SVC! failed, fall back to redis-server.exe
        goto :START_REDIS_DIRECT
    )
)
goto :START_REDIS_WAIT
:START_REDIS_DIRECT
set "REDIS_AUTH="
if defined REDIS_PWD set REDIS_AUTH=--requirepass "%REDIS_PWD%"
start "redis" /D "%REDIS_HOME%" /MIN cmd /c "redis-server.exe "%REDIS_CNF%" --port %REDIS_PORT% %REDIS_AUTH% >> "%LOG_DIR%\redis.log" 2>&1"
set "REDIS_AUTH="
:START_REDIS_WAIT
call :WAITPORT %PORT_REDIS% %WAIT_REDIS_SEC% "Redis"
if errorlevel 1 call :MARKFAIL Redis
goto :MINIO
:NO_REDIS_CNF
echo   [FAIL] Redis config not found: %REDIS_CNF%
call :MARKFAIL Redis

rem ---------- 4. MinIO ----------
:MINIO
if not "%START_MINIO%"=="1" goto :MQ
echo [4/9] MinIO ...
if not exist "%MINIO_HOME%\minio.exe" (
    echo   [FAIL] minio.exe not found: %MINIO_HOME%\minio.exe
    call :MARKFAIL MinIO
    goto :MQ
)
set "MINIO_ROOT_USER=%MINIO_USER%"
set "MINIO_ROOT_PASSWORD=%MINIO_PWD%"
set "MINIO_ACCESS_KEY=%MINIO_USER%"
set "MINIO_SECRET_KEY=%MINIO_PWD%"
call :PORTSKIP %PORT_MINIO% "MinIO" minio.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL MinIO
if not "!PS_RC!"=="0" goto :MQ
rem  a MinIO Windows service installed? start it via net start (no console window)
call :FIND_MINIO_SERVICE
if not defined MIS_SVC goto :START_MINIO_DIRECT
echo   MinIO service found: !MIS_SVC!, net start ...
net start "!MIS_SVC!" >nul 2>&1
if errorlevel 1 (
    netstat -ano | findstr /r /c:":%PORT_MINIO% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] net start !MIS_SVC! failed, fall back to minio.exe
        goto :START_MINIO_DIRECT
    )
)
goto :START_MINIO_WAIT
:START_MINIO_DIRECT
start "minio" /D "%MINIO_HOME%" /MIN cmd /c "minio.exe server "%MINIO_DATA_DIR%" --address :%PORT_MINIO% --console-address :%PORT_MINIO_CONSOLE% >> "%LOG_DIR%\minio.log" 2>&1"
:START_MINIO_WAIT
call :WAITPORT %PORT_MINIO% %WAIT_MINIO_SEC% "MinIO"
if errorlevel 1 call :MARKFAIL MinIO

rem ---------- 5. RocketMQ NameServer ----------
:MQ
if not "%START_MQ%"=="1" goto :NACOS
echo [5/9] RocketMQ NameServer ...
if not exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" (
    echo   [FAIL] mqnamesrv.cmd not found: %ROCKETMQ_HOME%\bin\mqnamesrv.cmd
    call :MARKFAIL RocketMQ-NameServer
    goto :NACOS
)
call :PORTSKIP %PORT_MQ_NAMESRV% "RocketMQ NameServer" java.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL RocketMQ-NameServer
if not "!PS_RC!"=="0" goto :MQ_BROKER
call :FIND_MQ_SERVICE
if not defined MQNS_SVC goto :START_MQ_NS_DIRECT
echo   RocketMQ NameServer service found: !MQNS_SVC!, net start ...
net start "!MQNS_SVC!" >nul 2>&1
if errorlevel 1 (
    netstat -ano | findstr /r /c:":%PORT_MQ_NAMESRV% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] net start !MQNS_SVC! failed, fall back to mqnamesrv.cmd
        goto :START_MQ_NS_DIRECT
    )
)
goto :START_MQ_NS_WAIT
:START_MQ_NS_DIRECT
start "mqnamesrv" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqnamesrv.cmd >> "%LOG_DIR%\mqnamesrv.log" 2>&1"
:START_MQ_NS_WAIT
call :WAITPORT %PORT_MQ_NAMESRV% %WAIT_MQ_NS_SEC% "RocketMQ NameServer"
if errorlevel 1 (
    call :MARKFAIL RocketMQ-NameServer
    goto :NACOS
)

rem ---------- 6. RocketMQ Broker ----------
:MQ_BROKER
echo [6/9] RocketMQ Broker ...
if not exist "%ROCKETMQ_HOME%\bin\mqbroker.cmd" (
    echo   [FAIL] mqbroker.cmd not found: %ROCKETMQ_HOME%\bin\mqbroker.cmd
    call :MARKFAIL RocketMQ-Broker
    goto :NACOS
)
call :PORTSKIP %PORT_MQ_BROKER% "RocketMQ Broker" java.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL RocketMQ-Broker
if not "!PS_RC!"=="0" goto :NACOS
if not defined MQBR_SVC goto :START_MQ_BR_DIRECT
echo   RocketMQ Broker service found: !MQBR_SVC!, net start ...
net start "!MQBR_SVC!" >nul 2>&1
if errorlevel 1 (
    netstat -ano | findstr /r /c:":%PORT_MQ_BROKER% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] net start !MQBR_SVC! failed, fall back to mqbroker.cmd
        goto :START_MQ_BR_DIRECT
    )
)
goto :START_MQ_BR_WAIT
:START_MQ_BR_DIRECT
call "%~dp0_lib.bat" render-mq
if errorlevel 1 (
    echo   [FAIL] cannot render broker config from %MQ_BROKER_CNF%
    call :MARKFAIL RocketMQ-Broker
    goto :NACOS
)
start "mqbroker" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqbroker.cmd -n %MQ_HOST%:%PORT_MQ_NAMESRV% -c "%MQ_BROKER_RUN_CNF%" >> "%LOG_DIR%\mqbroker.log" 2>&1"
:START_MQ_BR_WAIT
call :WAITPORT %PORT_MQ_BROKER% %WAIT_MQ_BROKER_SEC% "RocketMQ Broker"
if errorlevel 1 call :MARKFAIL RocketMQ-Broker

rem ---------- 7. Nacos ----------
:NACOS
if not "%START_NACOS%"=="1" goto :GEOSERVER
echo [7/9] Nacos ...
if not exist "%NACOS_HOME%\bin\startup.cmd" (
    echo   [FAIL] startup.cmd not found: %NACOS_HOME%\bin\startup.cmd
    call :MARKFAIL Nacos
    goto :GEOSERVER
)
call :PORTSKIP %PORT_NACOS% "Nacos" java.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL Nacos
if not "!PS_RC!"=="0" goto :GEOSERVER
rem  a Nacos Windows service installed? start it via net start (no console window)
call :FIND_NACOS_SERVICE
if not defined NAS_SVC goto :START_NACOS_DIRECT
echo   Nacos service found: !NAS_SVC!, net start ...
net start "!NAS_SVC!" >nul 2>&1
if errorlevel 1 (
    netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] net start !NAS_SVC! failed, fall back to startup.cmd
        goto :START_NACOS_DIRECT
    )
)
goto :START_NACOS_WAIT
:START_NACOS_DIRECT
rem Nacos 2.3.3: heap and port come from deploy.properties
set "JVM_XMS=%NACOS_JVM_XMS%"
set "JVM_XMX=%NACOS_JVM_XMX%"
set "JVM_XMN=%NACOS_JVM_XMN%"
set "JAVA_OPT_EXT=-Xms%NACOS_JVM_XMS% -Xmx%NACOS_JVM_XMX% -Xmn%NACOS_JVM_XMN% -Dserver.port=%NACOS_PORT% %NACOS_EXTRA_OPTS%"
set "JAVA_TOOL_OPTIONS=%NACOS_JAVA_TOOL_OPTIONS%"
start "nacos" /D "%NACOS_HOME%\bin" /MIN cmd /c "startup.cmd -m standalone >> "%LOG_DIR%\nacos.log" 2>&1"
set "JAVA_TOOL_OPTIONS="
set "JAVA_OPT_EXT="
set "JVM_XMS="
set "JVM_XMX="
set "JVM_XMN="
:START_NACOS_WAIT
call :WAITPORT %PORT_NACOS% %WAIT_NACOS_SEC% "Nacos"
if errorlevel 1 call :MARKFAIL Nacos

rem ---------- 8. GeoServer ----------
:GEOSERVER
if not "%START_GEOSERVER%"=="1" goto :NGINX
echo [8/9] GeoServer ...
if not exist "%GEOSERVER_HOME%\bin\startup.bat" (
    echo   [FAIL] startup.bat not found: %GEOSERVER_HOME%\bin\startup.bat
    call :MARKFAIL GeoServer
    goto :NGINX
)
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"
call :PORTSKIP %PORT_GEOSERVER% "GeoServer" java.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL GeoServer
if not "!PS_RC!"=="0" goto :NGINX
rem GeoServer startup.bat reads PORT for the Jetty connector
set "PORT=%GEOSERVER_PORT%"
start "geoserver" /D "%GEOSERVER_HOME%\bin" /MIN cmd /c "startup.bat >> "%LOG_DIR%\geoserver.log" 2>&1"
set "PORT="
call :WAITPORT %PORT_GEOSERVER% %WAIT_GEOSERVER_SEC% "GeoServer"
if errorlevel 1 call :MARKFAIL GeoServer

rem ---------- 9. Nginx ----------
:NGINX
if not "%START_NGINX%"=="1" goto :DONE
echo [9/9] Nginx ...
if not exist "%NGINX_HOME%\nginx.exe" goto :NO_NGINX
if not exist "%NGINX_HOME%\logs" mkdir "%NGINX_HOME%\logs" >nul 2>&1
if not exist "%NGINX_HOME%\temp" mkdir "%NGINX_HOME%\temp" >nul 2>&1
if not exist "%NGINX_CONF%" (
    echo   FAIL nginx.conf not found: %NGINX_CONF%
    call :MARKFAIL Nginx
    goto :DONE
)
call "%~dp0_lib.bat" render-nginx
if errorlevel 1 (
    echo   FAIL cannot render nginx.conf placeholders
    call :MARKFAIL Nginx
    goto :DONE
)
call :PORTSKIP %PORT_NGINX% "Nginx" nginx.exe
set "PS_RC=!errorlevel!"
if "!PS_RC!"=="2" call :MARKFAIL Nginx
if not "!PS_RC!"=="0" goto :DONE
call :FIND_NGINX_SERVICE
if defined NGX_SVC (
    echo   Nginx service found: %NGX_SVC%, net start ...
    net start "%NGX_SVC%" >nul 2>&1
    if not errorlevel 1 goto :NGINX_WAIT
    call :PORTSKIP %PORT_NGINX% "Nginx" nginx.exe
    if errorlevel 1 goto :NGINX_WAIT
    echo   WARN net start %NGX_SVC% failed, fall back to direct start
)
start "nginx" /D "%NGINX_HOME%" /MIN cmd /c "nginx.exe -p "%NGINX_HOME%" -c "%NGINX_RUN_CNF%" >> "%LOG_DIR%\nginx.log" 2>&1"
:NGINX_WAIT
call :WAITPORT %PORT_NGINX% %WAIT_NGINX_SEC% "Nginx"
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

rem =====================================================================
:FIND_NGINX_SERVICE
rem  resolve the Nginx Windows service name, if any: prefer the configured
rem  NGINX_SERVICE_NAME, then scan for any service whose binary is nginx.exe
set "NGX_SVC="
if defined NGINX_SERVICE_NAME (
    sc query "%NGINX_SERVICE_NAME%" >nul 2>&1
    if not errorlevel 1 set "NGX_SVC=%NGINX_SERVICE_NAME%"
)
if defined NGX_SVC exit /b 0
for /f "tokens=2" %%a in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME"') do (
    if not defined NGX_SVC (
        sc qc %%a 2>nul | findstr /i /c:"nginx.exe" >nul 2>&1 && set "NGX_SVC=%%a"
    )
)
exit /b 0

rem ---------- mark a failed component and keep going ----------
:MARKFAIL
set "FAILED=1"
set "FAILED_LIST=%FAILED_LIST% %~1"
exit /b 0

rem ---------- resolve the MySQL Windows service name, if any ----------
rem  prefer the service registered by bin\0-init.bat (MYSQL_SERVICE_NAME),
rem  then any other mysqld.exe service on this machine. MS_SVC stays empty
rem  when neither exists (caller starts mysqld.exe directly)
:FIND_MYSQL_SERVICE
set "MS_SVC="
if not defined MYSQL_SERVICE_NAME goto :FMS_SCAN
sc query "%MYSQL_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 goto :FMS_SCAN
set "MS_SVC=%MYSQL_SERVICE_NAME%"
exit /b 0
:FMS_SCAN
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"mysql"') do (
    if not defined MS_SVC (
        sc qc "%%S" 2>nul | findstr /i /c:"mysqld.exe" >nul 2>&1 && set "MS_SVC=%%S"
    )
)
exit /b 0

rem ---------- resolve the Redis Windows service name, if any ----------
rem  prefer REDIS_SERVICE_NAME (bin\install-redis.bat registers "redis-server"),
rem  then any other redis-server.exe service on this machine. RS_SVC stays
rem  empty when neither exists (caller starts redis-server.exe directly)
:FIND_REDIS_SERVICE
set "RS_SVC="
if not defined REDIS_SERVICE_NAME goto :FRS_SCAN
sc query "%REDIS_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 goto :FRS_SCAN
set "RS_SVC=%REDIS_SERVICE_NAME%"
exit /b 0
:FRS_SCAN
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"redis"') do (
    if not defined RS_SVC (
        sc qc "%%S" 2>nul | findstr /i /c:"redis-server.exe" >nul 2>&1 && set "RS_SVC=%%S"
    )
)
exit /b 0

rem ---------- resolve the MinIO Windows service name, if any ----------
:FIND_MINIO_SERVICE
set "MIS_SVC="
if not defined MINIO_SERVICE_NAME goto :FIS_SCAN
sc query "%MINIO_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 goto :FIS_SCAN
set "MIS_SVC=%MINIO_SERVICE_NAME%"
exit /b 0
:FIS_SCAN
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"minio"') do (
    if not defined MIS_SVC (
        sc qc "%%S" 2>nul | findstr /i /c:"minio.exe" >nul 2>&1 && set "MIS_SVC=%%S"
    )
)
exit /b 0

rem ---------- resolve RocketMQ Windows service names, if any ----------
:FIND_MQ_SERVICE
set "MQNS_SVC="
set "MQBR_SVC="
if defined MQ_SERVICE_NAME (
    sc query "%MQ_SERVICE_NAME%" >nul 2>&1 && set "MQNS_SVC=%MQ_SERVICE_NAME%"
)
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"rocketmq" /c:"mqnamesrv" /c:"mqbroker"') do (
    echo %%S| findstr /i /c:"broker" >nul 2>&1
    if not errorlevel 1 (
        rem  classify by service NAME: ...broker... (covers rocketmq-broker.exe)
        if not defined MQBR_SVC set "MQBR_SVC=%%S"
    ) else (
        echo %%S| findstr /i /c:"namesrv" >nul 2>&1
        if not errorlevel 1 if not defined MQNS_SVC set "MQNS_SVC=%%S"
    )
)
exit /b 0

rem ---------- resolve the Nacos Windows service name, if any ----------
:FIND_NACOS_SERVICE
set "NAS_SVC="
if not defined NACOS_SERVICE_NAME goto :FNS_SCAN
sc query "%NACOS_SERVICE_NAME%" >nul 2>&1
if errorlevel 1 goto :FNS_SCAN
set "NAS_SVC=%NACOS_SERVICE_NAME%"
exit /b 0
:FNS_SCAN
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"nacos"') do (
    if not defined NAS_SVC (
        sc qc "%%S" 2>nul | findstr /i /c:"nacos" >nul 2>&1 && set "NAS_SVC=%%S"
    )
)
exit /b 0

rem ---------- resolve the PostgreSQL Windows service name, if any ----------
rem  PG_SVC = first service whose name contains "postgres" and whose binary is
rem  postgres.exe or pg_ctl.exe (the installer service runs pg_ctl runservice);
rem  empty when none found (caller falls back to pg_ctl start)
:FIND_PG_SERVICE
set "PG_SVC="
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /i /c:"SERVICE_NAME" ^| findstr /i /c:"postgres"') do (
    if not defined PG_SVC (
        sc qc "%%S" 2>nul | findstr /i /c:"postgres.exe" /c:"pg_ctl.exe" >nul 2>&1 && set "PG_SVC=%%S"
    )
)
exit /b 0

rem ---------- apply MYSQL_PWD to a freshly initialized root account ----------
rem  0-init.bat uses --initialize-insecure, so root has no password. When the
rem  deployment declares MYSQL_PWD, set it once here so 6-init-data and the
rem  applications can authenticate. Only done when root is still passwordless.
:ENSURE_MYSQL_PWD
rem  delayed expansion off: "%MYSQL_PWD%" must keep a literal "!" intact
setlocal DisableDelayedExpansion
if not defined MYSQL_PWD exit /b 0
if /i not "%MYSQL_USER%"=="root" exit /b 0
if not exist "%MYSQL_HOME%\bin\mysql.exe" exit /b 0
set "EMP_TMP=%MYSQL_PWD%"
set "EMP_SQL=%MYSQL_PWD:'=''%"
rem  clear it for the probe: the mysql client reads MYSQL_PWD from the environment
set "MYSQL_PWD="
"%MYSQL_HOME%\bin\mysql.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=root -e "SELECT 1" >nul 2>&1
if errorlevel 1 (
    set "MYSQL_PWD=%EMP_TMP%"
    exit /b 0
)
"%MYSQL_HOME%\bin\mysql.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%EMP_SQL%'; FLUSH PRIVILEGES;" >nul 2>&1
set "EMP_RC=%errorlevel%"
set "MYSQL_PWD=%EMP_TMP%"
if not "%EMP_RC%"=="0" (
    echo   WARN cannot apply MYSQL_PWD automatically, run the command printed by bin\0-init.bat
    exit /b 0
)
echo   OK   MySQL root password applied from MYSQL_PWD
exit /b 0

rem config rendering lives in bin\_lib.bat (shared with 9-infra and 7-reload-nginx)

rem ---------- wait until port is listening ----------
:WAITPORT
call :VALIDPORT "%~1"
if errorlevel 1 (
    echo   FAIL %~3 invalid port "%~1"
    exit /b 1
)
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

rem ---------- port helpers ----------
rem  exit /b 1 unless %1 is an integer in 1..65535.
rem  An empty port would make the netstat regex match every listener.
:VALIDPORT
if "%~1"=="" exit /b 1
for /f "delims=0123456789" %%A in ("%~1") do exit /b 1
if %~1 LEQ 0 exit /b 1
if %~1 GTR 65535 exit /b 1
exit /b 0

rem  %1 port, %2 component, %3 expected process image
rem  exit 0 = port is free, start the component
rem  exit 1 = port is held by the expected process, assume it is running
rem  exit 2 = port is held by another program, report a failure and skip
:PORTSKIP
call :VALIDPORT "%~1"
if errorlevel 1 exit /b 0
set "PS_PIDS="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do set "PS_PIDS=!PS_PIDS! %%P"
if not defined PS_PIDS exit /b 0
set "PS_FOREIGN="
for %%P in (!PS_PIDS!) do (
    call :PORTIMAGE %%P "%~3"
    if errorlevel 1 set "PS_FOREIGN=!PS_FOREIGN! %%P"
)
if defined PS_FOREIGN (
    echo   [FAIL] %~2 port %~1 is held by another program, PID:!PS_FOREIGN!
    echo          expected %~3, stop that program or change the port
    exit /b 2
)
echo   [SKIP] %~2 port %~1 already listening ^(%~3^), assume it is running
exit /b 1

rem  exit 0 when PID %1 runs as image %2, exit 1 otherwise
:PORTIMAGE
set "PI_IMG="
for /f "tokens=1 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul ^| findstr /v /b /c:"INFO:"') do set "PI_IMG=%%~I"
if defined PI_IMG if /i "!PI_IMG!"=="%~2" exit /b 0
exit /b 1
