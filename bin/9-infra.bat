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
set "KPL_FAIL="
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
rem  graceful shutdown runs with delayed expansion off: a "!" in MYSQL_PWD
rem  would otherwise be stripped and the login would always fail
call :STOP_MYSQL_IMPL
if not errorlevel 1 exit /b 0
echo   WARN graceful shutdown failed, check MYSQL_USER / MYSQL_PWD in conf\deploy.properties
:STOP_MYSQL_KILL
call :KILLPORT %PORT_MYSQL%
exit /b !errorlevel!

:STOP_MYSQL_IMPL
setlocal DisableDelayedExpansion
if not exist "%MYSQL_HOME%\bin\mysqladmin.exe" (
    echo   WARN mysqladmin.exe not found: %MYSQL_HOME%\bin\mysqladmin.exe
    echo        set MYSQL_HOME in conf\components.properties to the install root, not its bin folder
    exit /b 1
)
if not defined MYSQL_PWD goto :SMI_NOPASS
"%MYSQL_HOME%\bin\mysqladmin.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=%MYSQL_USER% --password="%MYSQL_PWD%" shutdown >nul 2>&1
exit /b %errorlevel%
:SMI_NOPASS
"%MYSQL_HOME%\bin\mysqladmin.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=%MYSQL_USER% shutdown >nul 2>&1
exit /b %errorlevel%

:STOP_PG
echo   [STOP] PostgreSQL
if exist "%PG_DATA_DIR%" "%PG_HOME%\bin\pg_ctl.exe" stop -D "%PG_DATA_DIR%" -m fast >nul 2>&1
rem pg_ctl -m fast returns before every backend released the port, give it
rem a few seconds and only force-kill when it is still listening
call :WAITPORTFREE %PORT_PG% 5
if errorlevel 1 (
    call :KILLPORT %PORT_PG%
    exit /b !errorlevel!
)
exit /b 0

:STOP_REDIS
echo   [STOP] Redis
rem  redis-cli runs with delayed expansion off so a "!" in REDIS_PWD survives
call :STOP_REDIS_IMPL
:STOP_REDIS_KILL
call :KILLPORT %PORT_REDIS%
exit /b !errorlevel!

:STOP_REDIS_IMPL
setlocal DisableDelayedExpansion
if not exist "%REDIS_HOME%\redis-cli.exe" exit /b 1
if not defined REDIS_PWD goto :SRI_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% -a "%REDIS_PWD%" shutdown >nul 2>&1
exit /b %errorlevel%
:SRI_NOPASS
"%REDIS_HOME%\redis-cli.exe" -p %PORT_REDIS% shutdown >nul 2>&1
exit /b %errorlevel%

:STOP_MQ
echo   [STOP] RocketMQ
rem the vendor mqshutdown.cmd force-kills every RocketMQ JVM on this host,
rem so stop only the processes listening on our configured ports
call :KILLPORT %PORT_MQ_BROKER%
set "MQ_KILL_RC=!errorlevel!"
call :KILLPORT %PORT_MQ_NAMESRV%
if not "!errorlevel!"=="0" set "MQ_KILL_RC=1"
exit /b !MQ_KILL_RC!

:STOP_MINIO
echo   [STOP] MinIO
call :KILLPORT %PORT_MINIO%
set "MINIO_KILL_RC=!errorlevel!"
call :KILLPORT %PORT_MINIO_CONSOLE%
if not "!errorlevel!"=="0" set "MINIO_KILL_RC=1"
exit /b !MINIO_KILL_RC!

:STOP_NACOS
echo   [STOP] Nacos
if exist "%NACOS_HOME%\bin\shutdown.cmd" call "%NACOS_HOME%\bin\shutdown.cmd"
set /a NS_N=0
:STOP_NACOS_LOOP
netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
if errorlevel 1 exit /b 0
set /a NS_N+=1
if %NS_N% GEQ 15 goto :STOP_NACOS_KILL
ping -n 2 127.0.0.1 >nul
goto :STOP_NACOS_LOOP
:STOP_NACOS_KILL
call :KILLPORT %PORT_NACOS%
ping -n 2 127.0.0.1 >nul
netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
if errorlevel 1 exit /b 0
echo   FAIL Nacos still listening on port %PORT_NACOS%
exit /b 1

:STOP_GS
echo   [STOP] GeoServer
call :KILLPORT %PORT_GEOSERVER%
exit /b !errorlevel!

:STOP_NGINX
echo   [STOP] Nginx
rem  service instance first: stopping the wrapper kills its whole process tree
call :FIND_NGINX_SERVICE
if defined NGX_SVC (
    sc query "%NGX_SVC%" 2>nul | findstr /c:"RUNNING" >nul 2>&1
    if not errorlevel 1 (
        echo   stopping service %NGX_SVC% ...
        net stop "%NGX_SVC%" >nul 2>&1
    )
)
rem  sweep any leftover direct-start instance via its pid file / port
if exist "%NGINX_HOME%\nginx.exe" "%NGINX_HOME%\nginx.exe" -p "%NGINX_HOME%" -c "%NGINX_RUN_CNF%" -s quit >nul 2>&1
call :KILLPORT %PORT_NGINX%
exit /b !errorlevel!

rem =====================================================================
:START
rem  this action writes logs, create the folder on demand (env.bat stays read-only)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
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
if not exist "%MYSQL_DATA_DIR%\mysql" (
    echo   FAIL MySQL data dir not initialized: %MYSQL_DATA_DIR%
    echo         Run bin\0-init.bat first
    exit /b 1
)
if not exist "%MYSQL_HOME%\bin\mysqld.exe" (
    echo   FAIL mysqld.exe not found: %MYSQL_HOME%\bin\mysqld.exe
    exit /b 1
)
if not exist "%MYSQL_CNF%" (
    echo   FAIL MySQL config not found: %MYSQL_CNF%
    exit /b 1
)
call :PORTSKIP %PORT_MYSQL% "MySQL" mysqld.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
rem  a MySQL Windows service installed? start it via net start (no console window)
call :FIND_MYSQL_SERVICE
if not defined MS_SVC goto :START_MYSQL_DIRECT
echo   MySQL service found: %MS_SVC%, net start ...
net start "%MS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_MYSQL% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %MS_SVC% failed, fall back to mysqld.exe with configured parameters
        goto :START_MYSQL_DIRECT
    )
)
goto :START_MYSQL_WAIT
:START_MYSQL_DIRECT
start "mysql" /D "%MYSQL_HOME%\bin" /MIN cmd /c "mysqld.exe --defaults-file="%MYSQL_CNF%" --datadir="%MYSQL_DATA_DIR%" --port=%MYSQL_PORT% >> "%LOG_DIR%\mysql.log" 2>&1"
:START_MYSQL_WAIT
call :WAITPORT %PORT_MYSQL% %WAIT_MYSQL_SEC% "MySQL"
set "WP_RC=%errorlevel%"
if "%WP_RC%"=="0" call :ENSURE_MYSQL_PWD
exit /b %WP_RC%

:ENSURE_MYSQL_PWD
rem  root is passwordless right after 0-init; apply MYSQL_PWD once if declared
rem  delayed expansion off: "%MYSQL_PWD%" must keep a literal "!" intact
setlocal DisableDelayedExpansion
if not defined MYSQL_PWD exit /b 0
if /i not "%MYSQL_USER%"=="root" exit /b 0
if not exist "%MYSQL_HOME%\bin\mysql.exe" exit /b 0
set "EMP_TMP=%MYSQL_PWD%"
set "EMP_SQL=%MYSQL_PWD:'=''%"
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

:START_PG
echo   [START] PostgreSQL port=%PORT_PG%
if not exist "%PG_DATA_DIR%\PG_VERSION" (
    echo   FAIL PostgreSQL data dir not initialized: %PG_DATA_DIR%
    echo         Run bin\0-init.bat first
    exit /b 1
)
call :PORTSKIP %PORT_PG% "PostgreSQL" postgres.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
rem  prefer a Windows service hosting postgres.exe (net start, no console window)
call :FIND_PG_SERVICE
if not defined PG_SVC goto :PG_DIRECT
echo   OK   PostgreSQL service found: %PG_SVC%, net start ...
net start "%PG_SVC%" >nul 2>&1
call :WAITPORT %PORT_PG% 15 "PostgreSQL"
if not errorlevel 1 exit /b 0
echo   WARN net start %PG_SVC% failed or port not ready, fall back to pg_ctl
:PG_DIRECT
if not exist "%PG_HOME%\bin\pg_ctl.exe" (
    echo   FAIL pg_ctl.exe not found: %PG_HOME%\bin\pg_ctl.exe
    exit /b 1
)
rem  detached start: pg_ctl in a minimized console keeps postgres's handles
rem  away from the caller (Setup.exe would otherwise stay "running" on it)
start "postgres" /D "%PG_HOME%\bin" /MIN cmd /c "pg_ctl.exe start -D "%PG_DATA_DIR%" -l "%LOG_DIR%\postgres.log" -o "-p %PG_PORT%" -w >> "%LOG_DIR%\pg_ctl.log" 2>&1"
call :WAITPORT %PORT_PG% %WAIT_PG_SEC% "PostgreSQL"
exit /b %errorlevel%

:START_REDIS
echo   [START] Redis port=%PORT_REDIS%
if not exist "%REDIS_HOME%\redis-server.exe" (
    echo   FAIL redis-server.exe not found: %REDIS_HOME%\redis-server.exe
    exit /b 1
)
if not exist "%REDIS_CNF%" (
    echo   FAIL Redis config not found: %REDIS_CNF%
    exit /b 1
)
call :PORTSKIP %PORT_REDIS% "Redis" redis-server.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
rem  a Redis Windows service installed? start it via net start (no console window)
call :FIND_REDIS_SERVICE
if not defined RS_SVC goto :START_REDIS_DIRECT
echo   Redis service found: %RS_SVC%, net start ...
net start "%RS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_REDIS% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %RS_SVC% failed, fall back to redis-server.exe with configured parameters
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
exit /b %errorlevel%

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

:START_MINIO
echo   [START] MinIO port=%PORT_MINIO% console=%PORT_MINIO_CONSOLE%
if not exist "%MINIO_HOME%\minio.exe" (
    echo   FAIL minio.exe not found: %MINIO_HOME%\minio.exe
    exit /b 1
)
set "MINIO_ROOT_USER=%MINIO_USER%"
set "MINIO_ROOT_PASSWORD=%MINIO_PWD%"
set "MINIO_ACCESS_KEY=%MINIO_USER%"
set "MINIO_SECRET_KEY=%MINIO_PWD%"
call :PORTSKIP %PORT_MINIO% "MinIO" minio.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
rem  a MinIO Windows service installed? start it via net start (no console window)
call :FIND_MINIO_SERVICE
if not defined MIS_SVC goto :START_MINIO_DIRECT
echo   MinIO service found: %MIS_SVC%, net start ...
net start "%MIS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_MINIO% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %MIS_SVC% failed, fall back to minio.exe with configured parameters
        goto :START_MINIO_DIRECT
    )
)
goto :START_MINIO_WAIT
:START_MINIO_DIRECT
start "minio" /D "%MINIO_HOME%" /MIN cmd /c "minio.exe server "%MINIO_DATA_DIR%" --address :%PORT_MINIO% --console-address :%PORT_MINIO_CONSOLE% >> "%LOG_DIR%\minio.log" 2>&1"
:START_MINIO_WAIT
call :WAITPORT %PORT_MINIO% %WAIT_MINIO_SEC% "MinIO"
exit /b %errorlevel%

rem ---------- resolve the MinIO Windows service name, if any ----------
rem  prefer MINIO_SERVICE_NAME, then any other minio.exe service on this
rem  machine. MIS_SVC stays empty when neither exists
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

:START_MQ
echo   [START] RocketMQ NameServer port=%PORT_MQ_NAMESRV%
if not exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" (
    echo   FAIL mqnamesrv.cmd not found: %ROCKETMQ_HOME%\bin\mqnamesrv.cmd
    exit /b 1
)
call :PORTSKIP %PORT_MQ_NAMESRV% "RocketMQ NameServer" java.exe
if errorlevel 2 exit /b 1
if errorlevel 1 goto :START_MQ_BROKER
call :FIND_MQ_SERVICE
if not defined MQNS_SVC goto :START_MQ_NS_DIRECT
echo   RocketMQ NameServer service found: %MQNS_SVC%, net start ...
net start "%MQNS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_MQ_NAMESRV% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %MQNS_SVC% failed, fall back to mqnamesrv.cmd
        goto :START_MQ_NS_DIRECT
    )
)
goto :START_MQ_NS_WAIT
:START_MQ_NS_DIRECT
start "mqnamesrv" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqnamesrv.cmd >> "%LOG_DIR%\mqnamesrv.log" 2>&1"
:START_MQ_NS_WAIT
call :WAITPORT %PORT_MQ_NAMESRV% %WAIT_MQ_NS_SEC% "RocketMQ NameServer"
if errorlevel 1 exit /b 1
:START_MQ_BROKER
echo   [START] RocketMQ Broker port=%PORT_MQ_BROKER% ha=%PORT_MQ_HA%
if not exist "%ROCKETMQ_HOME%\bin\mqbroker.cmd" (
    echo   FAIL mqbroker.cmd not found: %ROCKETMQ_HOME%\bin\mqbroker.cmd
    exit /b 1
)
call :PORTSKIP %PORT_MQ_BROKER% "RocketMQ Broker" java.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
if not defined MQBR_SVC goto :START_MQ_BR_DIRECT
echo   RocketMQ Broker service found: %MQBR_SVC%, net start ...
net start "%MQBR_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_MQ_BROKER% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %MQBR_SVC% failed, fall back to mqbroker.cmd
        goto :START_MQ_BR_DIRECT
    )
)
goto :START_MQ_BR_WAIT
:START_MQ_BR_DIRECT
call "%~dp0_lib.bat" render-mq
if errorlevel 1 (
    echo   FAIL cannot render broker config from %MQ_BROKER_CNF%
    exit /b 1
)
start "mqbroker" /D "%ROCKETMQ_HOME%\bin" /MIN cmd /c "mqbroker.cmd -n %MQ_HOST%:%PORT_MQ_NAMESRV% -c "%MQ_BROKER_RUN_CNF%" >> "%LOG_DIR%\mqbroker.log" 2>&1"
:START_MQ_BR_WAIT
call :WAITPORT %PORT_MQ_BROKER% %WAIT_MQ_BROKER_SEC% "RocketMQ Broker"
exit /b %errorlevel%

rem ---------- resolve RocketMQ Windows service names, if any ----------
rem  prefer MQ_SERVICE_NAME for the NameServer; scans for services whose
rem  binary references mqnamesrv / mqbroker (WinSW-style wrappers match).
rem  MQNS_SVC / MQBR_SVC stay empty when nothing matches
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

:START_NACOS
echo   [START] Nacos port=%PORT_NACOS%
if not exist "%NACOS_HOME%\bin\startup.cmd" (
    echo   FAIL startup.cmd not found: %NACOS_HOME%\bin\startup.cmd
    exit /b 1
)
call :PORTSKIP %PORT_NACOS% "Nacos" java.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
rem  a Nacos Windows service installed? start it via net start (no console window)
call :FIND_NACOS_SERVICE
if not defined NAS_SVC goto :START_NACOS_DIRECT
echo   Nacos service found: %NAS_SVC%, net start ...
net start "%NAS_SVC%" >nul 2>&1
if errorlevel 1 (
    rem  failed (admin rights / broken service), but the port may already listen
    netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   WARN net start %NAS_SVC% failed, fall back to startup.cmd
        goto :START_NACOS_DIRECT
    )
)
goto :START_NACOS_WAIT
:START_NACOS_DIRECT
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
exit /b %errorlevel%

rem ---------- resolve the Nacos Windows service name, if any ----------
rem  prefer NACOS_SERVICE_NAME (bin\install-nacos.bat registers "nacos"),
rem  then any other service whose binary references nacos. NAS_SVC stays
rem  empty when neither exists (caller starts startup.cmd directly)
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

:START_GS
echo   [START] GeoServer port=%PORT_GEOSERVER%
if not exist "%GEOSERVER_HOME%\bin\startup.bat" (
    echo   FAIL startup.bat not found: %GEOSERVER_HOME%\bin\startup.bat
    exit /b 1
)
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"
call :PORTSKIP %PORT_GEOSERVER% "GeoServer" java.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
set "PORT=%GEOSERVER_PORT%"
start "geoserver" /D "%GEOSERVER_HOME%\bin" /MIN cmd /c "startup.bat >> "%LOG_DIR%\geoserver.log" 2>&1"
set "PORT="
call :WAITPORT %PORT_GEOSERVER% %WAIT_GEOSERVER_SEC% "GeoServer"
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
call "%~dp0_lib.bat" render-nginx
if errorlevel 1 (
    echo   FAIL cannot render nginx.conf placeholders
    exit /b 1
)
call :PORTSKIP %PORT_NGINX% "Nginx" nginx.exe
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
call :FIND_NGINX_SERVICE
if defined NGX_SVC (
    echo   Nginx service found: %NGX_SVC%, net start ...
    net start "%NGX_SVC%" >nul 2>&1
    if not errorlevel 1 goto :START_NGINX_WAIT
    call :PORTSKIP %PORT_NGINX% "Nginx" nginx.exe
    if errorlevel 1 goto :START_NGINX_WAIT
    echo   WARN net start %NGX_SVC% failed, fall back to direct start
)
start "nginx" /D "%NGINX_HOME%" /MIN cmd /c "nginx.exe -p "%NGINX_HOME%" -c "%NGINX_RUN_CNF%" >> "%LOG_DIR%\nginx.log" 2>&1"
:START_NGINX_WAIT
call :WAITPORT %PORT_NGINX% %WAIT_NGINX_SEC% "Nginx"
exit /b %errorlevel%

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

rem =====================================================================
:USAGE
echo Usage: 9-infra.bat start^|stop^|restart ^<mysql^|pg^|redis^|mq^|minio^|nacos^|geoserver^|nginx^>
exit /b 1

:BAD_COMP
echo   FAIL unknown component: %COMP%
exit /b 1

rem ---------- helpers ----------
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

rem  %1 = port. Only kill processes belonging to this deployment, so a port
rem  taken by IIS / another Java app is never force-killed by accident.
:KILLPORT
call :VALIDPORT "%~1"
if errorlevel 1 exit /b 0
rem  a dual stack listener reports the same PID twice, only kill it once
set "KPL_SEEN="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do call :KILLPID %%P %~1
if defined KPL_FAIL exit /b 1
exit /b 0

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
ping -n 2 127.0.0.1 >nul
rem  taskkill may fail silently (service, session 0), so confirm the process is gone
set "KP2_IMG="
for /f "tokens=1 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul ^| findstr /v /b /c:"INFO:"') do set "KP2_IMG=%%~I"
if /i "!KP2_IMG!"=="!KP_IMG!" (
    echo   FAIL port %~2 process %~1 ^(!KP_IMG!^) is still running
    if defined KP_TK echo        taskkill: !KP_TK!
    echo        Windows service: stop it in services.msc. Otherwise start this tool as administrator
    set "KPL_FAIL=1"
)
exit /b 0

rem config rendering lives in bin\_lib.bat (shared with 2-start-infra and 7-reload-nginx)
