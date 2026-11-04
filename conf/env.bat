@echo off
rem =====================================================================
rem  Global config.
rem  Machine-specific values are read from conf\deploy.properties
rem  (written by install.bat). Never hardcode paths in application.yml:
rem  use ${APP_ROOT} / ${DATA_ROOT} / ${DEPLOY_HOST} / ${MYSQL_PORT} ...
rem =====================================================================

if not defined APP_HOME set "APP_HOME=%~dp0.."
for %%i in ("%APP_HOME%") do set "APP_HOME=%%~fi"

set "DATA_DIR=%APP_HOME%\data"
set "LOG_DIR=%APP_HOME%\logs"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

rem ---------- read deploy.properties (single source of per-machine values) ----------
set "DEPLOY_FILE=%APP_HOME%\conf\deploy.properties"
if exist "%DEPLOY_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%DEPLOY_FILE%") do set "%%A=%%B"

rem ---------- read components.properties (optional external component paths) ----------
set "COMP_FILE=%APP_HOME%\conf\components.properties"
if exist "%COMP_FILE%" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%COMP_FILE%") do set "%%A=%%B"

rem ---------- defaults (only when the key is absent) ----------
if not defined DEPLOY_HOST set "DEPLOY_HOST=127.0.0.1"
if not defined MYSQL_PORT set "MYSQL_PORT=3306"
if not defined MYSQL_USER set "MYSQL_USER=root"
if not defined PG_PORT set "PG_PORT=5432"
if not defined PG_USER set "PG_USER=postgres"
if not defined REDIS_PORT set "REDIS_PORT=6379"
if not defined MINIO_PORT set "MINIO_PORT=9000"
if not defined MINIO_USER set "MINIO_USER=minioadmin"
if not defined MQ_NAMESRV_PORT set "MQ_NAMESRV_PORT=9876"
if not defined MQ_BROKER_PORT set "MQ_BROKER_PORT=10911"
if not defined NACOS_PORT set "NACOS_PORT=8848"
if not defined NACOS_NAMESPACE set "NACOS_NAMESPACE=prod"
if not defined NACOS_GROUP set "NACOS_GROUP=DEFAULT_GROUP"
if not defined NACOS_PROFILE set "NACOS_PROFILE=prod"
if not defined GEOSERVER_PORT set "GEOSERVER_PORT=8080"
if not defined NGINX_PORT set "NGINX_PORT=80"

rem ---------- MinIO storage dir (blank = data\minio, relative resolved to APP_HOME) ----------
rem guard the substitution: when the key is blank, %VAR:"=% would produce garbage
if defined MINIO_DATA_DIR set "MINIO_DATA_DIR=%MINIO_DATA_DIR:"=%"
if not defined MINIO_DATA_DIR set "MINIO_DATA_DIR=%DATA_DIR%\minio"
if "%MINIO_DATA_DIR:~1,1%"==":" goto :minio_dir_ready
if "%MINIO_DATA_DIR:~0,2%"=="\\" goto :minio_dir_ready
set "MINIO_DATA_DIR=%APP_HOME%\%MINIO_DATA_DIR%"
:minio_dir_ready

rem ---------- per-component hosts (distributed deployment; blank = DEPLOY_HOST) ----------
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

rem ---------- JDKs: external override or bundled folder ----------
if not defined JDK17_HOME set "JDK17_HOME=%APP_HOME%\runtime\jdk17"
if not exist "%JDK17_HOME%\bin\java.exe" set "JDK17_HOME=%APP_HOME%\runtime\jdk17"
if not defined JDK21_HOME set "JDK21_HOME=%APP_HOME%\runtime\jdk21"
if not exist "%JDK21_HOME%\bin\java.exe" set "JDK21_HOME=%APP_HOME%\runtime\jdk21"
if not defined INFRA_JDK set "INFRA_JDK=17"
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
set "NGINX_CONF=%APP_HOME%\conf\nginx\nginx.conf"
set "GEOSERVER_DATA_DIR=%DATA_DIR%\geoserver"

rem ---------- port aliases used by start/stop/status scripts ----------
set "PORT_MYSQL=%MYSQL_PORT%"
set "PORT_PG=%PG_PORT%"
set "PORT_REDIS=%REDIS_PORT%"
set "PORT_MQ_NAMESRV=%MQ_NAMESRV_PORT%"
set "PORT_MQ_BROKER=%MQ_BROKER_PORT%"
set "PORT_MINIO=%MINIO_PORT%"
set "PORT_NACOS=%NACOS_PORT%"
set "PORT_GEOSERVER=%GEOSERVER_PORT%"
set "PORT_NGINX=%NGINX_PORT%"

rem ---------- Nacos options injected to every jar ----------
set "NACOS_AUTH_OPTS="
if defined NACOS_USER set "NACOS_AUTH_OPTS=-Dspring.cloud.nacos.username=%NACOS_USER% -Dspring.cloud.nacos.password=%NACOS_PWD%"
set "NACOS_OPTS=-Dspring.cloud.nacos.server-addr=%NACOS_ADDR% -Dspring.cloud.nacos.config.namespace=%NACOS_NAMESPACE% -Dspring.cloud.nacos.discovery.namespace=%NACOS_NAMESPACE% -Dspring.cloud.nacos.config.group=%NACOS_GROUP% -Dspring.cloud.nacos.discovery.group=%NACOS_GROUP% -DNACOSERVER=%NACOS_ADDR% -DNACOS_SERVER=%NACOS_ADDR% %NACOS_AUTH_OPTS%"

rem ---------- common JVM options (JDK17 + add-opens for legacy libs) ----------
set "JDK17_OPENS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED"
set "JVM_BASE=-Xms256m -Xmx512m -XX:MaxMetaspaceSize=256m -XX:+UseParallelGC -Dfile.encoding=UTF-8 -Djava.net.preferIPv4Stack=true -Duser.timezone=Asia/Shanghai %JDK17_OPENS%"

rem ---------- deploy placeholder values (use them in application.yml / Nacos) ----------
set "APP_OPTS=-DAPP_ROOT=%APP_HOME% -DDATA_ROOT=%DATA_DIR% -DLOG_ROOT=%LOG_DIR% -DDEPLOY_HOST=%DEPLOY_HOST% -DMYSQL_HOST=%MYSQL_HOST% -DMYSQL_PORT=%MYSQL_PORT% -DPG_HOST=%PG_HOST% -DPG_PORT=%PG_PORT% -DREDIS_HOST=%REDIS_HOST% -DREDIS_PORT=%REDIS_PORT% -DMINIO_HOST=%MINIO_HOST% -DMINIO_ENDPOINT=http://%MINIO_HOST%:%MINIO_PORT% -DMQ_HOST=%MQ_HOST% -DMQ_NAMESRV=%MQ_HOST%:%MQ_NAMESRV_PORT% -DNACOS_HOST=%NACOS_HOST% -DNACOS_PORT=%NACOS_PORT% -DGEOSERVER_HOST=%GEOSERVER_HOST% -DGEOSERVER_URL=http://%GEOSERVER_HOST%:%GEOSERVER_PORT% -DNGINX_HOST=%NGINX_HOST% -DNGINX_PORT=%NGINX_PORT%"
