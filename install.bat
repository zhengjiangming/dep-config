@echo off
rem =====================================================================
rem  bat_application offline installer (portable, no environment needed)
rem  Run this file after extracting the package to its final folder,
rem  e.g. D:\bat_application  (path must NOT contain spaces).
rem  Every value has a default: press Enter to accept it.
rem =====================================================================
setlocal enabledelayedexpansion
rem  validate the raw install folder BEFORE env.bat: env.bat resolves APP_HOME
rem  with delayed expansion on and would silently drop a literal "!"
call :CHECK_HOME_RAW
if defined HOME_BAD goto :BAD_HOME
cd /d "%~dp0"
call "conf\env.bat"
title bat_application installer
mode con cols=100 lines=45 >nul 2>&1

echo ============================================================
echo   bat_application offline installer
echo   Bundled: JDK17 + JDK21, MySQL, PostgreSQL, Redis, RocketMQ,
echo            Nacos, MinIO, GeoServer, 13 services, mapserver, qrule
echo   Defaults: conf\deploy-defaults.properties
echo ============================================================
echo.

rem ------------------------------------------------------------
echo [1/5] System check
ver
echo   ARCH=%PROCESSOR_ARCHITECTURE%   DIR=%APP_HOME%
if not "%PROCESSOR_ARCHITECTURE%"=="AMD64" goto :BAD_ARCH
rem  check with delayed expansion off, otherwise a "!" in the path is eaten
setlocal DisableDelayedExpansion
set "PATH_BAD="
call :CHECKPATH APP_HOME
if defined PATH_BAD goto :BAD_PATH
endlocal
if not exist "%APP_HOME%\conf\deploy-defaults.properties" echo   WARN conf\deploy-defaults.properties missing, using built-in defaults
if not exist "%JDK17_HOME%\bin\java.exe" echo   WARN JDK17 not found: %JDK17_HOME%
if not exist "%JDK21_HOME%\bin\java.exe" echo   WARN JDK21 not found: %JDK21_HOME%
echo   OK

rem ------------------------------------------------------------
echo.
echo [2/5] Install parameters
echo   Press Enter to keep the value shown in [brackets].
echo.
rem use the detected IPv4 only on first install, never overwrite an existing deploy.properties
rem prefer the NIC that owns the default route (ipconfig alone may return VMware/WSL adapters)
set "DETECTED_IP="
if exist "%POWERSHELL_EXE%" (
    "%POWERSHELL_EXE%" -NoProfile -Command "$r=Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1; Get-NetIPAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 | Select-Object -First 1 -ExpandProperty IPAddress" > "%TEMP%\ba_detect_ip.txt" 2>nul
    if exist "%TEMP%\ba_detect_ip.txt" for /f "usebackq delims=" %%A in ("%TEMP%\ba_detect_ip.txt") do set "DETECTED_IP=%%A"
    del "%TEMP%\ba_detect_ip.txt" >nul 2>&1
)
if not defined DETECTED_IP for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /c:"IPv4"') do if not defined DETECTED_IP set "DETECTED_IP=%%A"
if defined DETECTED_IP set "DETECTED_IP=%DETECTED_IP: =%"
if not defined DEPLOY_HOST set "DEPLOY_HOST=127.0.0.1"
if not exist "%APP_HOME%\conf\deploy.properties" if defined DETECTED_IP set "DEPLOY_HOST=%DETECTED_IP%"

call :ASK DEPLOY_HOST "  IP that other machines use to access this server"
call :ASK INFRA_JDK "  JDK for Nacos/GeoServer/RocketMQ, 17 or 21"

set /p "DEFPORTS=  Use default ports? [Y/n]: "
if /i "%DEFPORTS%"=="n" goto :ASK_PORTS
goto :PORTS_DONE
:ASK_PORTS
call :ASK MYSQL_PORT "  MySQL port"
call :ASK PG_PORT "  PostgreSQL port"
call :ASK REDIS_PORT "  Redis port"
call :ASK MINIO_PORT "  MinIO API port"
call :ASK MINIO_CONSOLE_PORT "  MinIO console port"
call :ASK MQ_NAMESRV_PORT "  RocketMQ NameServer port"
call :ASK MQ_BROKER_PORT "  RocketMQ Broker listen port"
call :ASK MQ_HA_PORT "  RocketMQ Broker HA port"
call :ASK NACOS_PORT "  Nacos HTTP port"
call :ASK GEOSERVER_PORT "  GeoServer port"
call :ASK NGINX_PORT "  Nginx port"
:PORTS_DONE

echo.
echo   Accounts
echo   Do not use double quotes in values.
call :ASK MYSQL_USER "  MySQL user"
call :ASK MYSQL_PWD "  MySQL password"
call :ASK PG_USER "  PostgreSQL user"
call :ASK PG_PWD "  PostgreSQL password"
call :ASK MINIO_USER "  MinIO access key"
call :ASK MINIO_PWD "  MinIO secret key"
call :ASK REDIS_PWD "  Redis password (blank = no auth)"
call :ASK NACOS_USER "  Nacos user (blank = auth disabled)"
call :ASK NACOS_PWD "  Nacos password"

echo.
set /p "DEFDIRS=  Use default directories? [Y/n]: "
if /i "%DEFDIRS%"=="n" goto :ASK_DIRS
goto :DIRS_DONE
:ASK_DIRS
echo   Do not use spaces in directory values.
call :ASK DATA_DIR "  Data root directory"
call :ASK LOG_DIR "  Log directory"
call :ASK MYSQL_DATA_DIR "  MySQL data directory"
call :ASK PG_DATA_DIR "  PostgreSQL data directory"
call :ASK MQ_DATA_DIR "  RocketMQ data directory"
call :ASK MINIO_DATA_DIR "  MinIO data directory"
call :ASK GEOSERVER_DATA_DIR "  GeoServer data directory"
call :ASK NODE_OUT_DIR "  Node package output directory"
:DIRS_DONE

echo.
set /p "DEFCOMP=  Use bundled component folders? [Y/n]: "
if /i "%DEFCOMP%"=="n" goto :ASK_COMPONENTS
goto :COMPONENTS_DONE
:ASK_COMPONENTS
set "CUSTOM_COMPONENTS=1"
echo   External paths may be absolute. Do not use spaces.
call :ASK JDK17_HOME "  JDK17 home"
call :ASK JDK21_HOME "  JDK21 home"
call :ASK MYSQL_HOME "  MySQL home"
call :ASK PG_HOME "  PostgreSQL home"
call :ASK REDIS_HOME "  Redis home"
call :ASK ROCKETMQ_HOME "  RocketMQ home"
call :ASK MINIO_HOME "  MinIO home"
call :ASK NACOS_HOME "  Nacos home"
call :ASK GEOSERVER_HOME "  GeoServer home"
call :ASK NGINX_HOME "  Nginx home"
:COMPONENTS_DONE

echo.
set /p "ADV=  Configure advanced options (timeouts / JVM / config file paths)? [y/N]: "
if /i not "%ADV%"=="y" goto :ADV_DONE

echo.
echo   Wait timeouts, in seconds
call :ASK WAIT_MYSQL_SEC "  MySQL"
call :ASK WAIT_PG_SEC "  PostgreSQL"
call :ASK WAIT_REDIS_SEC "  Redis"
call :ASK WAIT_MINIO_SEC "  MinIO"
call :ASK WAIT_MQ_NS_SEC "  RocketMQ NameServer"
call :ASK WAIT_MQ_BROKER_SEC "  RocketMQ Broker"
call :ASK WAIT_NACOS_SEC "  Nacos port"
call :ASK WAIT_NACOS_HTTP_SEC "  Nacos HTTP health"
call :ASK WAIT_GEOSERVER_SEC "  GeoServer"
call :ASK WAIT_NGINX_SEC "  Nginx"
call :ASK WAIT_APP_SEC "  Service"
call :ASK HTTP_TIMEOUT_SEC "  HTTP probe timeout"
call :ASK IMPORT_TIMEOUT_SEC "  Nacos config upload timeout"

echo.
echo   Nacos JVM
call :ASK NACOS_JVM_XMS "  Xms"
call :ASK NACOS_JVM_XMX "  Xmx"
call :ASK NACOS_JVM_XMN "  Xmn"
call :ASK NACOS_EXTRA_OPTS "  extra JVM options"
call :ASK NACOS_JAVA_TOOL_OPTIONS "  JAVA_TOOL_OPTIONS"

echo.
echo   Managed config files (blank = bundled default)
call :ASK MYSQL_CNF "  MySQL config file"
call :ASK REDIS_CNF "  Redis config file"
call :ASK MQ_BROKER_CNF "  RocketMQ broker template"
call :ASK MQ_BROKER_RUN_CNF "  RocketMQ rendered config"
call :ASK NGINX_CONF "  Nginx template"
call :ASK NGINX_RUN_CNF "  Nginx rendered config"
call :ASK NACOS_CONF_DIR "  Nacos config directory"
call :ASK CURL_EXE "  curl.exe"
call :ASK VCREDIST_EXE "  VC++ installer"
call :ASK POWERSHELL_EXE "  PowerShell"
call :ASK FIREWALL_RULE_NAME "  Firewall rule name"

echo.
echo   Application JVM / runtime
call :ASK JVM_BASE "  JVM_BASE"
call :ASK JDK17_OPENS "  JDK17 add-opens"
call :ASK KILL_PROC_LIST "  processes that may be force-stopped"
:ADV_DONE

rem ---------- validate paths early: scripts pass them unquoted ----------
rem  delayed expansion off here too: "!" must be detected, not stripped
setlocal DisableDelayedExpansion
set "PATH_BAD="
for %%V in (DATA_DIR LOG_DIR MYSQL_DATA_DIR PG_DATA_DIR MQ_DATA_DIR MINIO_DATA_DIR GEOSERVER_DATA_DIR NODE_OUT_DIR JDK17_HOME JDK21_HOME MYSQL_HOME PG_HOME REDIS_HOME ROCKETMQ_HOME MINIO_HOME NACOS_HOME GEOSERVER_HOME NGINX_HOME MYSQL_CNF REDIS_CNF MQ_BROKER_CNF MQ_BROKER_RUN_CNF NGINX_CONF NGINX_RUN_CNF NACOS_CONF_DIR CURL_EXE VCREDIST_EXE POWERSHELL_EXE) do call :CHECKPATH %%V
if defined PATH_BAD (
    echo.
    echo   ERROR: some paths contain characters the batch scripts cannot handle:
    echo          space, percent, exclamation, caret, ampersand, pipe,
    echo          less-than, greater-than, parenthesis or a quote.
    echo          Move the package or adjust those paths, then re-run.
    pause
    exit /b 1
)
endlocal

rem ------------------------------------------------------------
echo.
echo [3/5] Write conf\deploy.properties and conf\components.properties
set "F=%APP_HOME%\conf\deploy.properties"
rem  re-running on a node must keep its per-component hosts / start flags
set "HAS_OLD="
if exist "%F%" set "HAS_OLD=1"
if exist "%F%" copy /y "%F%" "%F%.bak" >nul
set "PUT_FILE=%F%"
> "%F%" echo # generated by install.bat %DATE% %TIME%
call :PUT DEPLOY_HOST
call :PUT INFRA_JDK
call :PUT MYSQL_PORT
call :PUT MYSQL_USER
call :PUT MYSQL_PWD
call :PUT PG_PORT
call :PUT PG_USER
call :PUT PG_PWD
call :PUT REDIS_PORT
call :PUT REDIS_PWD
call :PUT MINIO_PORT
call :PUT MINIO_CONSOLE_PORT
call :PUT MINIO_USER
call :PUT MINIO_PWD
call :PUT MQ_NAMESRV_PORT
call :PUT MQ_BROKER_PORT
call :PUT MQ_HA_PORT
call :PUT NACOS_PORT
call :PUT NACOS_NAMESPACE
call :PUT NACOS_GROUP
call :PUT NACOS_PROFILE
call :PUT NACOS_USER
call :PUT NACOS_PWD
call :PUT GEOSERVER_PORT
call :PUT NGINX_PORT
if defined HAS_OLD (
call :PUT MYSQL_HOST
call :PUT PG_HOST
call :PUT REDIS_HOST
call :PUT MINIO_HOST
call :PUT MQ_HOST
call :PUT NACOS_HOST
call :PUT GEOSERVER_HOST
call :PUT NGINX_HOST
)
call :PUT DATA_DIR
call :PUT LOG_DIR
call :PUT MYSQL_DATA_DIR
call :PUT PG_DATA_DIR
call :PUT MQ_DATA_DIR
call :PUT MINIO_DATA_DIR
call :PUT GEOSERVER_DATA_DIR
call :PUT NODE_OUT_DIR
call :PUT MYSQL_CNF
call :PUT REDIS_CNF
call :PUT MQ_BROKER_CNF
call :PUT MQ_BROKER_RUN_CNF
call :PUT NGINX_CONF
call :PUT NGINX_RUN_CNF
call :PUT NACOS_CONF_DIR
call :PUT CURL_EXE
call :PUT VCREDIST_EXE
call :PUT POWERSHELL_EXE
call :PUT FIREWALL_RULE_NAME
call :PUT WAIT_MYSQL_SEC
call :PUT WAIT_PG_SEC
call :PUT WAIT_REDIS_SEC
call :PUT WAIT_MINIO_SEC
call :PUT WAIT_MQ_NS_SEC
call :PUT WAIT_MQ_BROKER_SEC
call :PUT WAIT_NACOS_SEC
call :PUT WAIT_NACOS_HTTP_SEC
call :PUT WAIT_GEOSERVER_SEC
call :PUT WAIT_NGINX_SEC
call :PUT WAIT_APP_SEC
call :PUT HTTP_TIMEOUT_SEC
call :PUT IMPORT_TIMEOUT_SEC
call :PUT SCRIPT_TIMEOUT_SEC
call :PUT NACOS_JVM_XMS
call :PUT NACOS_JVM_XMX
call :PUT NACOS_JVM_XMN
call :PUT NACOS_EXTRA_OPTS
call :PUT NACOS_JAVA_TOOL_OPTIONS
call :PUT JVM_BASE
call :PUT JDK17_OPENS
call :PUT KILL_PROC_LIST
if defined HAS_OLD (
call :PUT START_MYSQL
call :PUT START_PG
call :PUT START_REDIS
call :PUT START_MINIO
call :PUT START_MQ
call :PUT START_NACOS
call :PUT START_GEOSERVER
call :PUT START_NGINX
)
echo   Written: %F%

set "CF=%APP_HOME%\conf\components.properties"
set "HAS_OLD_COMP="
if exist "%CF%" set "HAS_OLD_COMP=1"
if exist "%CF%" copy /y "%CF%" "%CF%.bak" >nul
if defined CUSTOM_COMPONENTS (
set "PUT_FILE=%CF%"
> "%CF%" echo # generated by install.bat %DATE% %TIME%
>>"%CF%" echo # blank = use the bundled folder under APP_HOME
call :PUT JDK17_HOME
call :PUT JDK21_HOME
call :PUT MYSQL_HOME
call :PUT PG_HOME
call :PUT REDIS_HOME
call :PUT ROCKETMQ_HOME
call :PUT MINIO_HOME
call :PUT NACOS_HOME
call :PUT GEOSERVER_HOME
call :PUT NGINX_HOME
echo   Written: %CF%
) else if defined HAS_OLD_COMP (
rem  bundled folders selected: keep the existing components.properties untouched
echo   Kept: %CF% - existing component paths preserved
) else (
(
echo # generated by install.bat %DATE% %TIME%
echo # blank = use the bundled folder under APP_HOME
echo JDK17_HOME=
echo JDK21_HOME=
echo MYSQL_HOME=
echo PG_HOME=
echo REDIS_HOME=
echo ROCKETMQ_HOME=
echo MINIO_HOME=
echo NACOS_HOME=
echo GEOSERVER_HOME=
echo NGINX_HOME=
) > "%CF%"
echo   Written: %CF%
)

if not exist "%APP_HOME%\conf\mapserver" mkdir "%APP_HOME%\conf\mapserver"
if not exist "%APP_HOME%\conf\qrule" mkdir "%APP_HOME%\conf\qrule"
if not exist "%APP_HOME%\conf\nacos" mkdir "%APP_HOME%\conf\nacos"
if not exist "%APP_HOME%\conf\nginx" mkdir "%APP_HOME%\conf\nginx"
if not exist "%APP_HOME%\conf\rocketmq" mkdir "%APP_HOME%\conf\rocketmq"

rem ------------------------------------------------------------
echo.
echo [4/5] Post-install steps
call :RUN_SELECTED_STEPS

rem ------------------------------------------------------------
echo.
echo [5/5] Install summary.
echo   1) config check : bin\1-check.bat
echo   2) start all    : start-all.bat
echo   3) status       : bin\4-status.bat
echo   4) import Nacos : bin\5-import-config.bat  ^(after infrastructure is up^)
echo   5) stop all     : stop-all.bat
echo Keep this folder together; data is stored in %DATA_DIR%, logs in %LOG_DIR%.
if defined STEP_FATAL (
    echo.
    echo   RESULT: FAILED - a mandatory post-install step failed.
    pause
    exit /b 1
)
if defined STEP_FAIL echo   RESULT: finished with warnings.
if not defined STEP_FAIL echo   RESULT: OK
pause
exit /b 0

rem ------------------------------------------------------------
:BAD_ARCH
echo   ERROR: 32-bit Windows is not supported by this package.
pause
exit /b 1
:BAD_PATH
echo   ERROR: install path contains a character the batch scripts cannot handle.
echo          Move this folder to a simple path such as D:\bat_application
pause
exit /b 1
:BAD_HOME
echo   ERROR: the install folder contains a %HOME_BAD% character.
echo          Move this folder to a simple path such as D:\bat_application
pause
exit /b 1

rem ------------------------------------------------------------
rem  %1 = variable name, %2 = prompt
:ASK
set "OLD=!%~1!"
set "NEW="
set /p "NEW=%~2 [!OLD!]: "
rem  delayed expansion (not %NEW%) keeps & | < > ^ ( ) % and ! in the value
if defined NEW set "%~1=!NEW!"
exit /b 0

rem ------------------------------------------------------------
rem  %1 = variable name; append "NAME=value" to %PUT_FILE%
rem  echo( + delayed expansion writes the value verbatim, so passwords
rem  with special characters no longer break the surrounding block
:PUT
set "PV=!%~1!"
>>"%PUT_FILE%" echo(%~1=!PV!
exit /b 0

rem ------------------------------------------------------------
rem  Always called from a scope with delayed expansion disabled: "%CV%" keeps
rem  a literal "!" intact, while substitution would swallow it.
:CHECKPATH
call set "CV=%%%~1%%"
if not defined CV exit /b 0
set "BADCH="
if not "%CV: =%"=="%CV%" set "BADCH=space"
rem  "%" cannot be searched with %VAR:%%=% (the pattern is ambiguous), use findstr
set "PCT=%%"
set CV | findstr /l /c:"%PCT%" >nul 2>&1
if not errorlevel 1 set "BADCH=percent"
if not "%CV:^=%"=="%CV%" set "BADCH=caret"
if not "%CV:&=%"=="%CV%" set "BADCH=ampersand"
if not "%CV:|=%"=="%CV%" set "BADCH=pipe"
if not "%CV:<=%"=="%CV%" set "BADCH=less-than"
if not "%CV:>=%"=="%CV%" set "BADCH=greater-than"
if not "%CV:(=%"=="%CV%" set "BADCH=open-parenthesis"
if not "%CV:)=%"=="%CV%" set "BADCH=parenthesis"
if not "%CV:!=%"=="%CV%" set "BADCH=exclamation"
if defined BADCH (
    echo   PATH ERROR: %~1 contains a %BADCH% character
    set "PATH_BAD=1"
)
exit /b 0

rem ------------------------------------------------------------
rem  Same check for the install folder, but done before env.bat so a "!" is
rem  still in the value (env.bat resolves APP_HOME with delayed expansion on).
:CHECK_HOME_RAW
setlocal DisableDelayedExpansion
set "H0=%APP_HOME%"
if not defined H0 set "H0=%~dp0.."
for %%i in ("%H0%") do set "H0=%%~fi"
set "HOME_BAD="
if not "%H0: =%"=="%H0%" set "HOME_BAD=space"
set "PCT=%%"
set H0 | findstr /l /c:"%PCT%" >nul 2>&1
if not errorlevel 1 set "HOME_BAD=%HOME_BAD% percent"
if not "%H0:^=%"=="%H0%" set "HOME_BAD=%HOME_BAD% caret"
if not "%H0:&=%"=="%H0%" set "HOME_BAD=%HOME_BAD% ampersand"
if not "%H0:|=%"=="%H0%" set "HOME_BAD=%HOME_BAD% pipe"
if not "%H0:<=%"=="%H0%" set "HOME_BAD=%HOME_BAD% less-than"
if not "%H0:>=%"=="%H0%" set "HOME_BAD=%HOME_BAD% greater-than"
if not "%H0:(=%"=="%H0%" set "HOME_BAD=%HOME_BAD% open-parenthesis"
if not "%H0:)=%"=="%H0%" set "HOME_BAD=%HOME_BAD% parenthesis"
if not "%H0:!=%"=="%H0%" set "HOME_BAD=%HOME_BAD% exclamation"
endlocal & set "HOME_BAD=%HOME_BAD%"
exit /b 0

rem ------------------------------------------------------------
rem  Read conf\install-steps.cfg, show numbered list, run the selected steps
rem  in file order. Format: name^|script^|default^|stop-on-fail^|desc
:RUN_SELECTED_STEPS
set "STEPS_FILE=%APP_HOME%\conf\install-steps.cfg"
if not exist "%STEPS_FILE%" (
    echo   SKIP: conf\install-steps.cfg not found, no post-install step run.
    exit /b 0
)

set /a STEP_COUNT=0
set "STEP_DEFAULT="
for /f "usebackq eol=# tokens=1-5 delims=|" %%A in ("%STEPS_FILE%") do (
    set /a STEP_COUNT+=1
    set "S_NAME_!STEP_COUNT!=%%A"
    set "S_PATH_!STEP_COUNT!=%%B"
    set "S_DEF_!STEP_COUNT!=%%C"
    set "S_STOP_!STEP_COUNT!=%%D"
    set "S_DESC_!STEP_COUNT!=%%E"
    if "%%C"=="1" set "STEP_DEFAULT=!STEP_DEFAULT!!STEP_COUNT!,"
)
if %STEP_COUNT%==0 (
    echo   SKIP: install-steps.cfg has no step.
    exit /b 0
)

echo   Available steps:
for /l %%I in (1,1,!STEP_COUNT!) do (
    set "MARK= "
    if "!S_DEF_%%I!"=="1" set "MARK=*"
    echo     !MARK! %%I. !S_NAME_%%I!  [!S_PATH_%%I!]  !S_DESC_%%I!
)
echo   * = selected by default
if defined STEP_DEFAULT set "STEP_DEFAULT=!STEP_DEFAULT:~0,-1!"
if not defined STEP_DEFAULT set "STEP_DEFAULT=none"
set "SEL="
set /p "SEL=  Steps to run (comma separated, 0 = none) [default !STEP_DEFAULT!]: "
if not defined SEL set "SEL=!STEP_DEFAULT!"
if /i "!SEL!"=="none" set "SEL=0"
if "!SEL!"=="0" (
    echo   SKIP: no step selected.
    exit /b 0
)
set "SEL=!SEL:,= !"
for %%I in (!SEL!) do set "RUN_%%I=1"

set /a STEP_RUN=0
for /l %%I in (1,1,!STEP_COUNT!) do (
    if defined RUN_%%I call :RUN_ONE_STEP %%I
    if defined STEP_FATAL exit /b 0
)
if %STEP_RUN%==0 echo   WARN no valid step number entered, nothing run.
exit /b 0

:RUN_ONE_STEP
set "SI=%~1"
set "SNAME=!S_NAME_%SI%!"
set "SPATH=!S_PATH_%SI%!"
set "SSTOP=!S_STOP_%SI%!"
set /a STEP_RUN+=1
echo.
echo   --- !SNAME!  [!SPATH!] ---
if not exist "%APP_HOME%\%SPATH%" (
    echo   FAIL script not found: %APP_HOME%\%SPATH%
    set "STEP_FAIL=1"
    if "!SSTOP!"=="1" set "STEP_FATAL=1"
    exit /b 0
)
call "%APP_HOME%\%SPATH%" auto
set "RC=!errorlevel!"
if "!RC!"=="0" (
    echo   OK   !SNAME!
    exit /b 0
)
echo   FAIL !SNAME! exit=!RC!
set "STEP_FAIL=1"
if "!SSTOP!"=="1" set "STEP_FATAL=1"
exit /b 0
