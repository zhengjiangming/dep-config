@echo off
rem =====================================================================
rem  Global config.
rem  Order: conf\deploy-defaults.properties (defaults)
rem         conf\deploy.properties         (per-machine values, wins)
rem         conf\components.properties     (external component paths, wins)
rem  Never hardcode paths in application.yml: use ${APP_ROOT} / ${DATA_ROOT}
rem  / ${DEPLOY_HOST} / ${MYSQL_PORT} ...
rem =====================================================================

if not defined APP_HOME set "APP_HOME=%~dp0.."
for %%i in ("%APP_HOME%") do set "APP_HOME=%%~fi"

set "DEFAULTS_FILE=%APP_HOME%\conf\deploy-defaults.properties"
set "DEPLOY_FILE=%APP_HOME%\conf\deploy.properties"
set "COMP_FILE=%APP_HOME%\conf\components.properties"

rem ---------- 0. inherited component paths are the LAST priority ----------
rem  A system-wide ROCKETMQ_HOME / MYSQL_HOME must not beat the packaged
rem  folders. Park the inherited values, clear them, and let
rem  conf\components.properties (then the bundled folder) decide. Ignored
rem  values are reported below so an intentional external path is not dropped
rem  silently.
if not defined _ENV_PARKED (
    set "_ENV_PARKED=1"
    set "_ENV_JDK17_HOME=%JDK17_HOME%"
    set "_ENV_JDK21_HOME=%JDK21_HOME%"
    set "_ENV_MYSQL_HOME=%MYSQL_HOME%"
    set "_ENV_PG_HOME=%PG_HOME%"
    set "_ENV_REDIS_HOME=%REDIS_HOME%"
    set "_ENV_ROCKETMQ_HOME=%ROCKETMQ_HOME%"
    set "_ENV_MINIO_HOME=%MINIO_HOME%"
    set "_ENV_NACOS_HOME=%NACOS_HOME%"
    set "_ENV_GEOSERVER_HOME=%GEOSERVER_HOME%"
    set "_ENV_NGINX_HOME=%NGINX_HOME%"
    set "JDK17_HOME="
    set "JDK21_HOME="
    set "MYSQL_HOME="
    set "PG_HOME="
    set "REDIS_HOME="
    set "ROCKETMQ_HOME="
    set "MINIO_HOME="
    set "NACOS_HOME="
    set "GEOSERVER_HOME="
    set "NGINX_HOME="
)

rem ---------- 1. defaults (environment variables are never overwritten) ----------
if exist "%DEFAULTS_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%DEFAULTS_FILE%") do if not defined %%A set "%%A=%%B"

rem ---------- 2. per-machine values ----------
if exist "%DEPLOY_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%DEPLOY_FILE%") do set "%%A=%%B"

rem ---------- 3. external component paths ----------
if exist "%COMP_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%COMP_FILE%") do set "%%A=%%B"

rem ---------- 3.1 relative paths from config files resolve against APP_HOME ----------
rem  (same rule DATA_DIR / LOG_DIR already use; without this a relative component
rem  path depends on the caller's current directory)
call :NORMALIZE JDK17_HOME "%JDK17_HOME%"
call :NORMALIZE JDK21_HOME "%JDK21_HOME%"
call :NORMALIZE MYSQL_HOME "%MYSQL_HOME%"
call :NORMALIZE PG_HOME "%PG_HOME%"
call :NORMALIZE REDIS_HOME "%REDIS_HOME%"
call :NORMALIZE ROCKETMQ_HOME "%ROCKETMQ_HOME%"
call :NORMALIZE MINIO_HOME "%MINIO_HOME%"
call :NORMALIZE NACOS_HOME "%NACOS_HOME%"
call :NORMALIZE GEOSERVER_HOME "%GEOSERVER_HOME%"
call :NORMALIZE NGINX_HOME "%NGINX_HOME%"
call :NORMALIZE MYSQL_CNF "%MYSQL_CNF%"
call :NORMALIZE REDIS_CNF "%REDIS_CNF%"
call :NORMALIZE MQ_BROKER_CNF "%MQ_BROKER_CNF%"
call :NORMALIZE NGINX_CONF "%NGINX_CONF%"
rem ---------- rendered-output paths are ALWAYS machine-derived from the
rem ---------- template path (xxx.conf -> xxx.run.conf); any configured value
rem ---------- (e.g. written by the GUI) is intentionally overridden here
call :DERIVE_RUN_CNF MQ_BROKER_RUN_CNF "%MQ_BROKER_CNF%"
call :DERIVE_RUN_CNF NGINX_RUN_CNF "%NGINX_CONF%"
call :NORMALIZE NACOS_CONF_DIR "%NACOS_CONF_DIR%"
call :NORMALIZE CURL_EXE "%CURL_EXE%"
call :NORMALIZE VCREDIST_EXE "%VCREDIST_EXE%"
call :NORMALIZE POWERSHELL_EXE "%POWERSHELL_EXE%"

rem ---------- core defaults (also valid when deploy-defaults is missing) ----------
if not defined DEPLOY_HOST set "DEPLOY_HOST=127.0.0.1"
if not defined INFRA_JDK set "INFRA_JDK=17"
if not defined MYSQL_PORT set "MYSQL_PORT=3306"
if not defined MYSQL_USER set "MYSQL_USER=root"
if not defined PG_PORT set "PG_PORT=5432"
if not defined PG_USER set "PG_USER=postgres"
if not defined REDIS_PORT set "REDIS_PORT=6379"
if not defined MINIO_PORT set "MINIO_PORT=9000"
if not defined MINIO_CONSOLE_PORT set "MINIO_CONSOLE_PORT=9001"
if not defined MINIO_USER set "MINIO_USER=minioadmin"
if not defined MQ_NAMESRV_PORT set "MQ_NAMESRV_PORT=9876"
if not defined MQ_BROKER_PORT set "MQ_BROKER_PORT=10911"
if not defined MQ_HA_PORT set "MQ_HA_PORT=10912"
if not defined NACOS_PORT set "NACOS_PORT=8848"
if not defined NACOS_NAMESPACE set "NACOS_NAMESPACE=prod"
if not defined NACOS_GROUP set "NACOS_GROUP=DEFAULT_GROUP"
if not defined NACOS_PROFILE set "NACOS_PROFILE=prod"
if not defined GEOSERVER_PORT set "GEOSERVER_PORT=8080"
if not defined NGINX_PORT set "NGINX_PORT=80"

rem Nacos 2.x opens two extra ports at server.port + 1000 / + 1001
if not defined NACOS_CLUSTER_PORT set /a "NACOS_CLUSTER_PORT=%NACOS_PORT%+1000"
if not defined NACOS_CLUSTER_PORT2 set /a "NACOS_CLUSTER_PORT2=%NACOS_PORT%+1001"
rem RocketMQ VIP channel listens on broker port - 2
if not defined MQ_VIP_PORT set /a "MQ_VIP_PORT=%MQ_BROKER_PORT%-2"

rem ---------- directories (relative values are resolved to APP_HOME) ----------
if not defined DATA_DIR set "DATA_DIR=%APP_HOME%\data"
if "%DATA_DIR:~1,1%"==":" goto :DATA_DIR_OK
if "%DATA_DIR:~0,2%"=="\\" goto :DATA_DIR_OK
if "%DATA_DIR:~0,1%"=="\" goto :DATA_DIR_OK
set "DATA_DIR=%APP_HOME%\%DATA_DIR%"
:DATA_DIR_OK
if not defined LOG_DIR set "LOG_DIR=%APP_HOME%\logs"
if "%LOG_DIR:~1,1%"==":" goto :LOG_DIR_OK
if "%LOG_DIR:~0,2%"=="\\" goto :LOG_DIR_OK
if "%LOG_DIR:~0,1%"=="\" goto :LOG_DIR_OK
set "LOG_DIR=%APP_HOME%\%LOG_DIR%"
:LOG_DIR_OK

if not defined MYSQL_DATA_DIR set "MYSQL_DATA_DIR=%DATA_DIR%\mysql"
if not defined PG_DATA_DIR set "PG_DATA_DIR=%DATA_DIR%\pg"
if not defined MQ_DATA_DIR set "MQ_DATA_DIR=%DATA_DIR%\rocketmq"
if not defined MINIO_DATA_DIR set "MINIO_DATA_DIR=%DATA_DIR%\minio"
if not defined GEOSERVER_DATA_DIR set "GEOSERVER_DATA_DIR=%DATA_DIR%\geoserver"
if not defined NODE_OUT_DIR set "NODE_OUT_DIR=%APP_HOME%\nodes"
if "%MYSQL_DATA_DIR:~1,1%"==":" goto :MYSQL_DATA_OK
if "%MYSQL_DATA_DIR:~0,2%"=="\\" goto :MYSQL_DATA_OK
if "%MYSQL_DATA_DIR:~0,1%"=="\" goto :MYSQL_DATA_OK
set "MYSQL_DATA_DIR=%APP_HOME%\%MYSQL_DATA_DIR%"
:MYSQL_DATA_OK
if "%PG_DATA_DIR:~1,1%"==":" goto :PG_DATA_OK
if "%PG_DATA_DIR:~0,2%"=="\\" goto :PG_DATA_OK
if "%PG_DATA_DIR:~0,1%"=="\" goto :PG_DATA_OK
set "PG_DATA_DIR=%APP_HOME%\%PG_DATA_DIR%"
:PG_DATA_OK
if "%MQ_DATA_DIR:~1,1%"==":" goto :MQ_DATA_OK
if "%MQ_DATA_DIR:~0,2%"=="\\" goto :MQ_DATA_OK
if "%MQ_DATA_DIR:~0,1%"=="\" goto :MQ_DATA_OK
set "MQ_DATA_DIR=%APP_HOME%\%MQ_DATA_DIR%"
:MQ_DATA_OK
if "%MINIO_DATA_DIR:~1,1%"==":" goto :MINIO_DATA_OK
if "%MINIO_DATA_DIR:~0,2%"=="\\" goto :MINIO_DATA_OK
if "%MINIO_DATA_DIR:~0,1%"=="\" goto :MINIO_DATA_OK
set "MINIO_DATA_DIR=%APP_HOME%\%MINIO_DATA_DIR%"
:MINIO_DATA_OK
if "%GEOSERVER_DATA_DIR:~1,1%"==":" goto :GEOSERVER_DATA_OK
if "%GEOSERVER_DATA_DIR:~0,2%"=="\\" goto :GEOSERVER_DATA_OK
if "%GEOSERVER_DATA_DIR:~0,1%"=="\" goto :GEOSERVER_DATA_OK
set "GEOSERVER_DATA_DIR=%APP_HOME%\%GEOSERVER_DATA_DIR%"
:GEOSERVER_DATA_OK
if "%NODE_OUT_DIR:~1,1%"==":" goto :NODE_OUT_OK
if "%NODE_OUT_DIR:~0,2%"=="\\" goto :NODE_OUT_OK
if "%NODE_OUT_DIR:~0,1%"=="\" goto :NODE_OUT_OK
set "NODE_OUT_DIR=%APP_HOME%\%NODE_OUT_DIR%"
:NODE_OUT_OK

rem ---------- directories are created on demand, never by this loader ----------
rem  bin\0-init.bat creates DATA_DIR / LOG_DIR; start scripts create LOG_DIR
rem  before they write logs. env.bat is sourced by read-only helpers
rem  (1-check, 4-status, Setup.exe), so it must not touch the disk.

rem ---------- per-component hosts (blank = DEPLOY_HOST) ----------
if not defined MYSQL_HOST set "MYSQL_HOST=%DEPLOY_HOST%"
if not defined PG_HOST set "PG_HOST=%DEPLOY_HOST%"
if not defined REDIS_HOST set "REDIS_HOST=%DEPLOY_HOST%"
if not defined MINIO_HOST set "MINIO_HOST=%DEPLOY_HOST%"
if not defined MQ_HOST set "MQ_HOST=%DEPLOY_HOST%"
if not defined NACOS_HOST set "NACOS_HOST=%DEPLOY_HOST%"
if not defined GEOSERVER_HOST set "GEOSERVER_HOST=%DEPLOY_HOST%"
if not defined NGINX_HOST set "NGINX_HOST=%DEPLOY_HOST%"
if not defined NACOS_ADDR set "NACOS_ADDR=%NACOS_HOST%:%NACOS_PORT%"

rem ---------- components started on THIS machine (1 local / 0 remote) ----------
if not defined START_MYSQL set "START_MYSQL=1"
if not defined START_PG set "START_PG=1"
if not defined START_REDIS set "START_REDIS=1"
if not defined START_MINIO set "START_MINIO=1"
if not defined START_MQ set "START_MQ=1"
if not defined START_NACOS set "START_NACOS=1"
if not defined START_GEOSERVER set "START_GEOSERVER=1"
if not defined START_NGINX set "START_NGINX=1"

rem ---------- report ignored system overrides ----------
set "ENV_OVERRIDES="
if defined _ENV_JDK17_HOME if not defined JDK17_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% JDK17_HOME"
if defined _ENV_JDK21_HOME if not defined JDK21_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% JDK21_HOME"
if defined _ENV_MYSQL_HOME if not defined MYSQL_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% MYSQL_HOME"
if defined _ENV_PG_HOME if not defined PG_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% PG_HOME"
if defined _ENV_REDIS_HOME if not defined REDIS_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% REDIS_HOME"
if defined _ENV_ROCKETMQ_HOME if not defined ROCKETMQ_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% ROCKETMQ_HOME"
if defined _ENV_MINIO_HOME if not defined MINIO_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% MINIO_HOME"
if defined _ENV_NACOS_HOME if not defined NACOS_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% NACOS_HOME"
if defined _ENV_GEOSERVER_HOME if not defined GEOSERVER_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% GEOSERVER_HOME"
if defined _ENV_NGINX_HOME if not defined NGINX_HOME set "ENV_OVERRIDES=%ENV_OVERRIDES% NGINX_HOME"

rem ---------- JDKs: components.properties or bundled folder ----------
if not defined JDK17_HOME set "JDK17_HOME=%APP_HOME%\runtime\jdk17"
if not exist "%JDK17_HOME%\bin\java.exe" set "JDK17_HOME=%APP_HOME%\runtime\jdk17"
if not defined JDK21_HOME set "JDK21_HOME=%APP_HOME%\runtime\jdk21"
if not exist "%JDK21_HOME%\bin\java.exe" set "JDK21_HOME=%APP_HOME%\runtime\jdk21"
set "JDK_HOME=%APP_HOME%\runtime\jdk%INFRA_JDK%"
if /i "%INFRA_JDK%"=="17" set "JDK_HOME=%JDK17_HOME%"
if /i "%INFRA_JDK%"=="21" set "JDK_HOME=%JDK21_HOME%"
rem fall back to JDK17 when the selected JDK is missing, never start with an empty JAVA_HOME
if not exist "%JDK_HOME%\bin\java.exe" (
    if /i not "%INFRA_JDK%"=="17" echo   [WARN] JDK%INFRA_JDK% not found, falling back to JDK17
    set "INFRA_JDK=17"
    set "JDK_HOME=%JDK17_HOME%"
)
if not exist "%JDK_HOME%\bin\java.exe" echo   [WARN] JDK17 runtime not found, infrastructure may fail to start
set "JAVA_HOME=%JDK_HOME%"
set "PATH=%JDK_HOME%\bin;%PATH%"

rem ---------- middleware: external override or bundled folder ----------
if not defined MYSQL_HOME set "MYSQL_HOME=%APP_HOME%\infra\mysql"
if not exist "%MYSQL_HOME%\bin\mysqld.exe" set "MYSQL_HOME=%APP_HOME%\infra\mysql"
if not defined PG_HOME set "PG_HOME=%APP_HOME%\infra\postgres"
if not exist "%PG_HOME%\bin\pg_ctl.exe" set "PG_HOME=%APP_HOME%\infra\postgres"
if not defined REDIS_HOME set "REDIS_HOME=%APP_HOME%\infra\redis"
if not exist "%REDIS_HOME%\redis-server.exe" set "REDIS_HOME=%APP_HOME%\infra\redis"
if not defined ROCKETMQ_HOME set "ROCKETMQ_HOME=%APP_HOME%\infra\rocketmq"
if not exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" set "ROCKETMQ_HOME=%APP_HOME%\infra\rocketmq"
if not defined MINIO_HOME set "MINIO_HOME=%APP_HOME%\infra\minio"
if not exist "%MINIO_HOME%\minio.exe" set "MINIO_HOME=%APP_HOME%\infra\minio"
if not defined NACOS_HOME set "NACOS_HOME=%APP_HOME%\infra\nacos"
if not exist "%NACOS_HOME%\bin\startup.cmd" set "NACOS_HOME=%APP_HOME%\infra\nacos"
if not defined GEOSERVER_HOME set "GEOSERVER_HOME=%APP_HOME%\infra\geoserver"
if not exist "%GEOSERVER_HOME%\bin\startup.bat" set "GEOSERVER_HOME=%APP_HOME%\infra\geoserver"
if not defined NGINX_HOME set "NGINX_HOME=%APP_HOME%\infra\nginx"
if not exist "%NGINX_HOME%\nginx.exe" set "NGINX_HOME=%APP_HOME%\infra\nginx"

if defined ENV_OVERRIDES if not defined _ENV_WARNED echo   [WARN] ignoring system%ENV_OVERRIDES%, set it in conf\components.properties instead
if defined ENV_OVERRIDES set "_ENV_WARNED=1"

rem ---------- managed config files ----------
if not defined MYSQL_CNF set "MYSQL_CNF=%MYSQL_HOME%\my.ini"
if not defined REDIS_CNF set "REDIS_CNF=%REDIS_HOME%\redis.windows.conf"
if not defined MQ_BROKER_CNF set "MQ_BROKER_CNF=%APP_HOME%\conf\rocketmq\broker.conf"
if not defined MQ_BROKER_RUN_CNF set "MQ_BROKER_RUN_CNF=%ROCKETMQ_HOME%\conf\broker.run.conf"
if not defined NGINX_CONF set "NGINX_CONF=%APP_HOME%\conf\nginx\nginx.conf"
if not defined NGINX_RUN_CNF set "NGINX_RUN_CNF=%NGINX_HOME%\conf\nginx.run.conf"
if not defined NACOS_CONF_DIR set "NACOS_CONF_DIR=%APP_HOME%\conf\nacos"
if not defined CURL_EXE set "CURL_EXE=%APP_HOME%\runtime\curl\curl.exe"
if not defined VCREDIST_EXE set "VCREDIST_EXE=%APP_HOME%\runtime\vc_redist.x64.exe"
if not defined POWERSHELL_EXE set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not defined FIREWALL_RULE_NAME set "FIREWALL_RULE_NAME=bat_application"

rem ---------- port aliases used by start/stop/status scripts ----------
set "PORT_MYSQL=%MYSQL_PORT%"
set "PORT_PG=%PG_PORT%"
set "PORT_REDIS=%REDIS_PORT%"
set "PORT_MQ_NAMESRV=%MQ_NAMESRV_PORT%"
set "PORT_MQ_BROKER=%MQ_BROKER_PORT%"
set "PORT_MQ_VIP=%MQ_VIP_PORT%"
set "PORT_MQ_HA=%MQ_HA_PORT%"
set "PORT_MINIO=%MINIO_PORT%"
set "PORT_MINIO_CONSOLE=%MINIO_CONSOLE_PORT%"
set "PORT_NACOS=%NACOS_PORT%"
set "PORT_NACOS_CLUSTER=%NACOS_CLUSTER_PORT%"
set "PORT_NACOS_CLUSTER2=%NACOS_CLUSTER_PORT2%"
set "PORT_GEOSERVER=%GEOSERVER_PORT%"
set "PORT_NGINX=%NGINX_PORT%"

rem ---------- port wait timeouts (seconds, override in deploy.properties) ----------
if not defined WAIT_MYSQL_SEC set "WAIT_MYSQL_SEC=90"
if not defined WAIT_PG_SEC set "WAIT_PG_SEC=60"
if not defined WAIT_REDIS_SEC set "WAIT_REDIS_SEC=30"
if not defined WAIT_MINIO_SEC set "WAIT_MINIO_SEC=30"
if not defined WAIT_MQ_NS_SEC set "WAIT_MQ_NS_SEC=60"
if not defined WAIT_MQ_BROKER_SEC set "WAIT_MQ_BROKER_SEC=90"
if not defined WAIT_NACOS_SEC set "WAIT_NACOS_SEC=180"
if not defined WAIT_GEOSERVER_SEC set "WAIT_GEOSERVER_SEC=180"
if not defined WAIT_NGINX_SEC set "WAIT_NGINX_SEC=30"
if not defined WAIT_APP_SEC set "WAIT_APP_SEC=180"
if not defined WAIT_NACOS_HTTP_SEC set "WAIT_NACOS_HTTP_SEC=180"
if not defined HTTP_TIMEOUT_SEC set "HTTP_TIMEOUT_SEC=3"
if not defined IMPORT_TIMEOUT_SEC set "IMPORT_TIMEOUT_SEC=20"

rem ---------- Nacos options injected to every jar ----------
set "NACOS_AUTH_OPTS="
if defined NACOS_USER set "NACOS_AUTH_OPTS=-Dspring.cloud.nacos.username=%NACOS_USER% -Dspring.cloud.nacos.password=%NACOS_PWD%"
set "NACOS_OPTS=-Dspring.cloud.nacos.server-addr=%NACOS_ADDR% -Dspring.cloud.nacos.config.namespace=%NACOS_NAMESPACE% -Dspring.cloud.nacos.discovery.namespace=%NACOS_NAMESPACE% -Dspring.cloud.nacos.config.group=%NACOS_GROUP% -Dspring.cloud.nacos.discovery.group=%NACOS_GROUP% -DNACOSERVER=%NACOS_ADDR% -DNACOS_SERVER=%NACOS_ADDR% %NACOS_AUTH_OPTS%"

rem ---------- common JVM options (JDK17 + add-opens for legacy libs) ----------
if not defined JDK17_OPENS set "JDK17_OPENS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED"
if not defined JVM_BASE set "JVM_BASE=-Xms256m -Xmx512m -XX:MaxMetaspaceSize=256m -XX:+UseParallelGC -Dfile.encoding=UTF-8 -Djava.net.preferIPv4Stack=true -Duser.timezone=Asia/Shanghai %JDK17_OPENS%"

rem ---------- Nacos JVM (startup.cmd reads these) ----------
if not defined NACOS_JVM_XMS set "NACOS_JVM_XMS=512m"
if not defined NACOS_JVM_XMX set "NACOS_JVM_XMX=512m"
if not defined NACOS_JVM_XMN set "NACOS_JVM_XMN=256m"
if not defined NACOS_JAVA_TOOL_OPTIONS set "NACOS_JAVA_TOOL_OPTIONS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"

rem ---------- processes that may be force-stopped by port ----------
if not defined KILL_PROC_LIST set "KILL_PROC_LIST=java.exe javaw.exe nginx.exe mysqld.exe postgres.exe redis-server.exe minio.exe"

rem ---------- deploy placeholder values (use them in application.yml / Nacos) ----------
set "APP_OPTS=-DAPP_ROOT="%APP_HOME%" -DDATA_ROOT="%DATA_DIR%" -DLOG_ROOT="%LOG_DIR%" -DDEPLOY_HOST=%DEPLOY_HOST% -DMYSQL_HOST=%MYSQL_HOST% -DMYSQL_PORT=%MYSQL_PORT% -DPG_HOST=%PG_HOST% -DPG_PORT=%PG_PORT% -DREDIS_HOST=%REDIS_HOST% -DREDIS_PORT=%REDIS_PORT% -DMINIO_HOST=%MINIO_HOST% -DMINIO_ENDPOINT=http://%MINIO_HOST%:%MINIO_PORT% -DMINIO_CONSOLE_PORT=%MINIO_CONSOLE_PORT% -DMQ_HOST=%MQ_HOST% -DMQ_NAMESRV=%MQ_HOST%:%MQ_NAMESRV_PORT% -DMQ_VIP_PORT=%MQ_VIP_PORT% -DMQ_HA_PORT=%MQ_HA_PORT% -DNACOS_HOST=%NACOS_HOST% -DNACOS_PORT=%NACOS_PORT% -DGEOSERVER_HOST=%GEOSERVER_HOST% -DGEOSERVER_URL=http://%GEOSERVER_HOST%:%GEOSERVER_PORT% -DNGINX_HOST=%NGINX_HOST% -DNGINX_PORT=%NGINX_PORT%"
goto :ENV_END

rem ---------- resolve a relative path against APP_HOME (drive/UNC/absolute are kept) ----------
:NORMALIZE
set "NV=%~2"
if not defined NV goto :eof
if "%NV:~1,1%"==":" goto :eof
if "%NV:~0,2%"=="\\" goto :eof
if "%NV:~0,1%"=="\" goto :eof
set "%~1=%APP_HOME%\%NV%"
goto :eof

:DERIVE_RUN_CNF
rem %1 = output variable, %2 = template path; derives <dir>\<name>.run.conf
set "DV_SRC=%~2"
if not defined DV_SRC goto :eof
for %%P in ("%DV_SRC%") do set "%~1=%%~dpP%%~nP.run.conf"
goto :eof

:ENV_END
exit /b 0
