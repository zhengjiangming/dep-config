@echo off
setlocal
call "%~dp0..\conf\env.bat"
title Deployment self-check
echo.
echo ===== Deployment self-check =====
ver
echo   ARCH=%PROCESSOR_ARCHITECTURE%   APP_HOME=%APP_HOME%
echo.

echo [1] Install path
if "%APP_HOME: =%"=="%APP_HOME%" (echo   OK   no space in path) else (echo   FAIL path contains space, move to D:\bat_application)
if not exist "%APP_HOME%\data" (echo   FAIL data dir missing)
if exist "%DEPLOY_FILE%" (echo   OK   deploy.properties) else (echo   WARN deploy.properties missing, run install.bat first)
echo   HOST=%DEPLOY_HOST%  NACOS=%NACOS_ADDR%  JDK=%JDK_HOME%
echo   mysql=%MYSQL_HOST% pg=%PG_HOST% redis=%REDIS_HOST% minio=%MINIO_HOST% mq=%MQ_HOST% nacos=%NACOS_HOST% geo=%GEOSERVER_HOST% nginx=%NGINX_HOST%

echo.
echo [2] Bundled JDK17 / JDK21   infra uses JDK%INFRA_JDK%
if not exist "%JDK17_HOME%\bin\java.exe" goto :J17_MISS
echo   OK   %JDK17_HOME%
"%JDK17_HOME%\bin\java.exe" -version 2>&1 | findstr /i "version"
goto :J21
:J17_MISS
echo   FAIL runtime\jdk17 missing
:J21
if not exist "%JDK21_HOME%\bin\java.exe" goto :J21_MISS
echo   OK   %JDK21_HOME%
"%JDK21_HOME%\bin\java.exe" -version 2>&1 | findstr /i "version"
goto :JDK_DONE
:J21_MISS
echo   FAIL runtime\jdk21 missing
:JDK_DONE

echo.
echo [3] Middleware dirs  (external overrides come from conf\components.properties)
if exist "%MYSQL_HOME%\bin\mysqld.exe" (echo   OK   MySQL       %MYSQL_HOME%) else (echo   FAIL MySQL       %MYSQL_HOME%)
if exist "%PG_HOME%\bin\pg_ctl.exe" (echo   OK   PostgreSQL  %PG_HOME%) else (echo   FAIL PostgreSQL  %PG_HOME%)
if exist "%REDIS_HOME%\redis-server.exe" (echo   OK   Redis       %REDIS_HOME%) else (echo   FAIL Redis       %REDIS_HOME%)
if exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" (echo   OK   RocketMQ    %ROCKETMQ_HOME%) else (echo   FAIL RocketMQ    %ROCKETMQ_HOME%)
if exist "%MINIO_HOME%\minio.exe" (echo   OK   MinIO       %MINIO_HOME%) else (echo   FAIL MinIO       %MINIO_HOME%)
if exist "%NACOS_HOME%\bin\startup.cmd" (echo   OK   Nacos       %NACOS_HOME%) else (echo   FAIL Nacos       %NACOS_HOME%)
if exist "%GEOSERVER_HOME%\bin\startup.bat" (echo   OK   GeoServer   %GEOSERVER_HOME%) else (echo   FAIL GeoServer   %GEOSERVER_HOME%)
if exist "%NGINX_HOME%\nginx.exe" (echo   OK   Nginx       %NGINX_HOME%) else (echo   FAIL Nginx       %NGINX_HOME%)

echo.
echo [4] Ports (FREE = local and free, REMOTE = runs on another machine)
if "%START_MYSQL%"=="1" (call :ISFREE %PORT_MYSQL% MySQL) else (echo   REMOTE MySQL  %MYSQL_HOST%:%PORT_MYSQL%)
if "%START_PG%"=="1" (call :ISFREE %PORT_PG% PostgreSQL) else (echo   REMOTE PostgreSQL  %PG_HOST%:%PORT_PG%)
if "%START_REDIS%"=="1" (call :ISFREE %PORT_REDIS% Redis) else (echo   REMOTE Redis  %REDIS_HOST%:%PORT_REDIS%)
if "%START_MQ%"=="1" (call :ISFREE %PORT_MQ_NAMESRV% RocketMQ-NameServer) else (echo   REMOTE RocketMQ-NameServer  %MQ_HOST%:%PORT_MQ_NAMESRV%)
if "%START_MQ%"=="1" (call :ISFREE %PORT_MQ_BROKER% RocketMQ-Broker) else (echo   REMOTE RocketMQ-Broker  %MQ_HOST%:%PORT_MQ_BROKER%)
if "%START_MINIO%"=="1" (call :ISFREE %PORT_MINIO% MinIO) else (echo   REMOTE MinIO  %MINIO_HOST%:%PORT_MINIO%)
if "%START_NACOS%"=="1" (call :ISFREE %PORT_NACOS% Nacos) else (echo   REMOTE Nacos  %NACOS_HOST%:%PORT_NACOS%)
if "%START_GEOSERVER%"=="1" (call :ISFREE %PORT_GEOSERVER% GeoServer) else (echo   REMOTE GeoServer  %GEOSERVER_HOST%:%PORT_GEOSERVER%)
if "%START_NGINX%"=="1" (call :ISFREE %PORT_NGINX% Nginx) else (echo   REMOTE Nginx  %NGINX_HOST%:%PORT_NGINX%)

echo.
echo [5] Jar list from conf\apps.cfg
for /f "usebackq eol=# tokens=1,2,3 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do call :CHKJAR "%%A" "%%B" "%%C"
echo.
pause
exit /b 0

:CHKJAR
rem %1 name, %2 jar, %3 port
set "CJ_HOST="
if exist "%APP_HOME%\conf\service-hosts.cfg" for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do if /i "%%X"=="%~1" set "CJ_HOST=%%Y"
if /i "%CJ_HOST%"=="localhost" set "CJ_HOST=127.0.0.1"
set "CJ_SELF=%DEPLOY_HOST%"
if /i "%CJ_SELF%"=="localhost" set "CJ_SELF=127.0.0.1"
if defined CJ_HOST if /i not "%CJ_HOST%"=="%CJ_SELF%" (
    echo   [REMOTE] %~1  %~3 @ %CJ_HOST%
    exit /b 0
)
if exist "%APP_HOME%\%~2" (echo   OK   %~1  port=%~3) else (echo   FAIL missing %~2)
exit /b 0

:ISFREE
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if errorlevel 1 (echo   FREE %~2  port %~1) else (echo   USED %~2  port %~1 already in use)
exit /b 0
