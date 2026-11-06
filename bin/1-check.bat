@echo off
rem  Validate the raw folder BEFORE env.bat runs: env.bat resolves APP_HOME with
rem  delayed expansion on, which silently drops a literal "!" from the path.
setlocal DisableDelayedExpansion
set "HOME_RAW=%APP_HOME%"
if not defined HOME_RAW set "HOME_RAW=%~dp0.."
for %%i in ("%HOME_RAW%") do set "HOME_RAW=%%~fi"
set "PRE_BAD="
if not "%HOME_RAW: =%"=="%HOME_RAW%" set "PRE_BAD=space"
rem  "%" cannot be searched with %VAR:%%=% (the pattern is ambiguous), use findstr
set "PCT=%%"
set HOME_RAW | findstr /l /c:"%PCT%" >nul 2>&1
if not errorlevel 1 set "PRE_BAD=%PRE_BAD% percent"
if not "%HOME_RAW:^=%"=="%HOME_RAW%" set "PRE_BAD=%PRE_BAD% caret"
if not "%HOME_RAW:&=%"=="%HOME_RAW%" set "PRE_BAD=%PRE_BAD% ampersand"
if not "%HOME_RAW:(=%"=="%HOME_RAW%" set "PRE_BAD=%PRE_BAD% open-parenthesis"
if not "%HOME_RAW:)=%"=="%HOME_RAW%" set "PRE_BAD=%PRE_BAD% parenthesis"
if not "%HOME_RAW:!=%"=="%HOME_RAW%" set "PRE_BAD=%PRE_BAD% exclamation"
endlocal & set "PRE_BAD=%PRE_BAD%"
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Deployment self-check
set "CHK_FAIL="
echo.
echo ===== Deployment self-check =====
ver
echo   ARCH=%PROCESSOR_ARCHITECTURE%   APP_HOME=%APP_HOME%
echo.

echo [1] Install path
rem  PRE_BAD comes from the raw path, checked before env.bat can drop a "!"
if defined PRE_BAD goto :BADPATH
setlocal DisableDelayedExpansion
set "BADCH="
if not "%APP_HOME: =%"=="%APP_HOME%" set "BADCH=%BADCH% space"
rem  "%" cannot be searched with %VAR:%%=% (the pattern is ambiguous), use findstr
set "PCT=%%"
set APP_HOME | findstr /l /c:"%PCT%" >nul 2>&1
if not errorlevel 1 set "BADCH=%BADCH% percent"
if not "%APP_HOME:^=%"=="%APP_HOME%" set "BADCH=%BADCH% caret"
if not "%APP_HOME:&=%"=="%APP_HOME%" set "BADCH=%BADCH% ampersand"
if not "%APP_HOME:(=%"=="%APP_HOME%" set "BADCH=%BADCH% open-parenthesis"
if not "%APP_HOME:)=%"=="%APP_HOME%" set "BADCH=%BADCH% parenthesis"
if not "%APP_HOME:!=%"=="%APP_HOME%" set "BADCH=%BADCH% exclamation"
endlocal & set "BADCH=%BADCH%"
if defined BADCH (
    echo   FAIL path contains %BADCH%, move to D:\bat_application
    echo   INFO other checks skipped, these characters break the batch scripts
    if /i not "%~1"=="auto" pause
    exit /b 1
)
echo   OK   install path is safe
if not exist "%DATA_DIR%" (echo   FAIL data dir missing: %DATA_DIR%, run bin\0-init.bat & set "CHK_FAIL=1")
if exist "%DEPLOY_FILE%" (echo   OK   deploy.properties) else (echo   WARN deploy.properties missing, run install.bat first)
echo   HOST=%DEPLOY_HOST%  NACOS=%NACOS_ADDR%  JDK=%JDK_HOME%
echo   mysql=%MYSQL_HOST% pg=%PG_HOST% redis=%REDIS_HOST% minio=%MINIO_HOST% mq=%MQ_HOST% nacos=%NACOS_HOST% geo=%GEOSERVER_HOST% nginx=%NGINX_HOST%
rem  env.bat loads deploy.properties with delayed expansion on: a literal "!"
rem  inside a value is dropped, so the deployment would use a wrong password
if exist "%DEPLOY_FILE%" call :CHK_VALUES

echo.
echo [2] Bundled JDK17 / JDK21   infra uses JDK%INFRA_JDK%
if not exist "%JDK17_HOME%\bin\java.exe" goto :J17_MISS
echo   OK   %JDK17_HOME%
"%JDK17_HOME%\bin\java.exe" -version 2>&1 | findstr /i "version"
goto :J21
:J17_MISS
echo   FAIL runtime\jdk17 missing
set "CHK_FAIL=1"
:J21
if not exist "%JDK21_HOME%\bin\java.exe" goto :J21_MISS
echo   OK   %JDK21_HOME%
"%JDK21_HOME%\bin\java.exe" -version 2>&1 | findstr /i "version"
goto :JDK_DONE
:J21_MISS
echo   FAIL runtime\jdk21 missing
set "CHK_FAIL=1"
:JDK_DONE

echo.
echo [3] Middleware dirs  (external overrides come from conf\components.properties)
if exist "%MYSQL_HOME%\bin\mysqld.exe" (echo   OK   MySQL       %MYSQL_HOME%) else (echo   FAIL MySQL       %MYSQL_HOME% & set "CHK_FAIL=1")
if exist "%PG_HOME%\bin\pg_ctl.exe" (echo   OK   PostgreSQL  %PG_HOME%) else (echo   FAIL PostgreSQL  %PG_HOME% & set "CHK_FAIL=1")
if exist "%REDIS_HOME%\redis-server.exe" (echo   OK   Redis       %REDIS_HOME%) else (echo   FAIL Redis       %REDIS_HOME% & set "CHK_FAIL=1")
if exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" (echo   OK   RocketMQ    %ROCKETMQ_HOME%) else (echo   FAIL RocketMQ    %ROCKETMQ_HOME% & set "CHK_FAIL=1")
if exist "%MINIO_HOME%\minio.exe" (echo   OK   MinIO       %MINIO_HOME%) else (echo   FAIL MinIO       %MINIO_HOME% & set "CHK_FAIL=1")
if exist "%NACOS_HOME%\bin\startup.cmd" (echo   OK   Nacos       %NACOS_HOME%) else (echo   FAIL Nacos       %NACOS_HOME% & set "CHK_FAIL=1")
if exist "%GEOSERVER_HOME%\bin\startup.bat" (echo   OK   GeoServer   %GEOSERVER_HOME%) else (echo   FAIL GeoServer   %GEOSERVER_HOME% & set "CHK_FAIL=1")
if exist "%NGINX_HOME%\nginx.exe" (echo   OK   Nginx       %NGINX_HOME%) else (echo   FAIL Nginx       %NGINX_HOME% & set "CHK_FAIL=1")

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
if not exist "%APP_HOME%\conf\apps.cfg" (
    echo   FAIL conf\apps.cfg not found
    set "CHK_FAIL=1"
) else (
    for /f "usebackq eol=# tokens=1,2,3 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do call :CHKJAR "%%A" "%%B" "%%C"
)
echo.
if defined CHK_FAIL (
    echo RESULT: FAILED - fix the FAIL lines above
    if /i not "%~1"=="auto" pause
    exit /b 1
)
echo RESULT: OK
if /i not "%~1"=="auto" pause
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
if exist "%APP_HOME%\%~2" (echo   OK   %~1  port=%~3) else (echo   FAIL missing %~2 & set "CHK_FAIL=1")
exit /b 0

:ISFREE
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul 2>&1
if errorlevel 1 (echo   FREE %~2  port %~1) else (echo   USED %~2  port %~1 already in use)
exit /b 0

rem ---------- values env.bat cannot carry: "!" is dropped by delayed expansion ----------
:CHK_VALUES
setlocal DisableDelayedExpansion
findstr /r /c:"^[A-Za-z0-9_]*=.*!" "%DEPLOY_FILE%" >nul 2>&1
if errorlevel 1 exit /b 0
echo   FAIL deploy.properties has a "!" inside a value
echo   INFO env.bat drops it, so passwords would silently become a different string
echo   INFO remove the "!" from *_PWD / *_USER values, then run bin\1-check.bat again
endlocal & set "CHK_FAIL=1"
exit /b 0

rem ---------- the install folder itself is unusable: report and stop ----------
:BADPATH
echo   FAIL path contains %PRE_BAD%, move to D:\bat_application
echo   INFO other checks skipped, these characters break the batch scripts
if /i not "%~1"=="auto" pause
exit /b 1
