@echo off
rem =====================================================================
rem  Build a portable node package for distributed service deployment.
rem  Usage:
rem    make-node.bat <host>       build nodes\node-<host>.zip for one host
rem    make-node.bat all          build packages for every remote host in apps.cfg
rem  apps.cfg host column = service node IP/hostname (empty = local machine)
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Build service node package

set "MODE=%~1"
if "%MODE%"=="" goto :USAGE

set "OUT_ROOT=%APP_HOME%\nodes"
if not exist "%OUT_ROOT%" mkdir "%OUT_ROOT%" >nul 2>&1

if /i "%MODE%"=="all" goto :ALL
call :BUILD "%MODE%"
if errorlevel 1 exit /b 1
goto :DONE

:ALL
set "SELF_HOST=%DEPLOY_HOST%"
if /i "%SELF_HOST%"=="localhost" set "SELF_HOST=127.0.0.1"
if not exist "%APP_HOME%\conf\service-hosts.cfg" goto :NO_HOSTS
set "HOSTS_FILE=%TEMP%\make-node-hosts-%RANDOM%.txt"
type nul > "%HOSTS_FILE%"
for /f "usebackq eol=# tokens=1,2 delims=|" %%A in ("%APP_HOME%\conf\service-hosts.cfg") do (
    set "H=%%~B"
    if defined H (
        if /i "!H!"=="localhost" set "H=127.0.0.1"
        if /i not "!H!"=="!SELF_HOST!" (
            findstr /i /x /c:"!H!" "%HOSTS_FILE%" >nul 2>&1
            if errorlevel 1 >>"%HOSTS_FILE%" echo !H!
        )
    )
)
set /a HOST_COUNT=0
set "NODE_FAIL="
for /f "usebackq tokens=*" %%H in ("%HOSTS_FILE%") do (
    set /a HOST_COUNT+=1
    call :BUILD "%%H"
    if errorlevel 1 set "NODE_FAIL=1"
)
del "%HOSTS_FILE%" >nul 2>&1
if %HOST_COUNT%==0 (
    echo   No remote hosts found in conf\apps.cfg.
    echo   Fill the 7th column ^(host^) in the service list, save, then retry.
    exit /b 1
)
goto :DONE

rem ---------------------------------------------------------------
rem  BUILD %1 = node host
rem ---------------------------------------------------------------
:BUILD
set "NODE_HOST=%~1"
if "%NODE_HOST%"=="" exit /b 1
set "NODE_SAFE=%NODE_HOST%"
set "NODE_SAFE=%NODE_SAFE::=_%"
set "NODE_SAFE=%NODE_SAFE:\=_%"
set "NODE_SAFE=%NODE_SAFE:/=_%"
set "OUT=%OUT_ROOT%\node-%NODE_SAFE%"
set "ZIP=%OUT_ROOT%\node-%NODE_SAFE%.zip"

echo.
echo ============================================================
echo   Node host : %NODE_HOST%
echo   Output    : %OUT%
echo ============================================================

echo "%OUT%" | findstr /i /c:"\nodes\node-" >nul
if errorlevel 1 (
    echo   UNSAFE output path, abort.
    exit /b 1
)
if exist "%OUT%" rd /s /q "%OUT%"
mkdir "%OUT%\apps" >nul 2>&1
mkdir "%OUT%\bin" >nul 2>&1
mkdir "%OUT%\conf" >nul 2>&1
mkdir "%OUT%\logs" >nul 2>&1
mkdir "%OUT%\data" >nul 2>&1
mkdir "%OUT%\runtime" >nul 2>&1

rem ---------- copy conf and scripts ----------
xcopy /E /I /Y /Q "%APP_HOME%\conf" "%OUT%\conf" >nul
copy /Y "%APP_HOME%\bin\3-start-apps.bat" "%OUT%\bin\" >nul
copy /Y "%APP_HOME%\bin\8-service.bat" "%OUT%\bin\" >nul
copy /Y "%APP_HOME%\bin\4-status.bat" "%OUT%\bin\" >nul
copy /Y "%APP_HOME%\bin\9-stop-all.bat" "%OUT%\bin\" >nul
if exist "%APP_HOME%\runtime\curl" xcopy /E /I /Y /Q "%APP_HOME%\runtime\curl" "%OUT%\runtime\curl" >nul

> "%OUT%\start-node.bat" echo @echo off
>>"%OUT%\start-node.bat" echo call "%%~dp0bin\3-start-apps.bat"
> "%OUT%\stop-node.bat" echo @echo off
>>"%OUT%\stop-node.bat" echo call "%%~dp0bin\9-stop-all.bat"
> "%OUT%\status-node.bat" echo @echo off
>>"%OUT%\status-node.bat" echo call "%%~dp0bin\4-status.bat"

rem ---------- filter apps.cfg and copy jars ----------
> "%OUT%\conf\apps.cfg" echo # name^|jar^|port^|jdk^|jvm opts^|extra args
>>"%OUT%\conf\apps.cfg" echo # jdk: 17 or 21; order matters
>>"%OUT%\conf\apps.cfg" echo # host mapping is in conf\service-hosts.cfg
set /a SVC_COUNT=0
set "NEED17="
set "NEED21="
set "NODE_ERROR="
rem reset per host: otherwise a previous node's JDK choice leaks into the next one
set "NODE_INFRA_JDK="
for /f "usebackq eol=# tokens=1,2,3,4,5,6 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do (
    set "SVC_HOST="
    if exist "%APP_HOME%\conf\service-hosts.cfg" (
        for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do (
            if /i "%%X"=="%%~A" set "SVC_HOST=%%Y"
        )
    )
    if /i "!SVC_HOST!"=="%NODE_HOST%" (
        set "SVC_NAME=%%~A"
        set "SVC_JAR=%%~B"
        set "SVC_JDK=%%~D"
        if "%%~D"=="" set "SVC_JDK=17"
        if "!SVC_JDK!"=="21" (set "NEED21=1") else (set "NEED17=1")
        set /a SVC_COUNT+=1
        echo   copy !SVC_NAME!  !SVC_JAR!
        if not exist "%APP_HOME%\!SVC_JAR!" (
            echo   MISSING jar !SVC_JAR!
            set "NODE_ERROR=1"
        ) else (
            for %%P in ("%OUT%\!SVC_JAR!") do if not exist "%%~dpP" mkdir "%%~dpP" >nul 2>&1
            xcopy /Y /Q "%APP_HOME%\!SVC_JAR!" "%OUT%\!SVC_JAR!" >nul
            >>"%OUT%\conf\apps.cfg" echo %%A^|%%B^|%%C^|%%D^|%%E^|%%F
        )
    )
)
if defined NODE_ERROR (
    echo   Package aborted: some jars are missing.
    rd /s /q "%OUT%"
    exit /b 1
)
if %SVC_COUNT%==0 (
    echo   No services assigned to host %NODE_HOST%.
    echo   Fill the host column in Setup.exe service list and save, retry.
    rd /s /q "%OUT%"
    exit /b 1
)

rem ---------- copy required JDKs ----------
if defined NEED17 (
    if not exist "%JDK17_HOME%\bin\java.exe" (
        echo   MISSING JDK17 at %JDK17_HOME%
        exit /b 1
    )
    echo   copy JDK17 ...
    xcopy /E /I /Y /Q "%JDK17_HOME%" "%OUT%\runtime\jdk17" >nul
    set "NODE_INFRA_JDK=17"
)
if defined NEED21 (
    if not exist "%JDK21_HOME%\bin\java.exe" (
        echo   MISSING JDK21 at %JDK21_HOME%
        exit /b 1
    )
    echo   copy JDK21 ...
    xcopy /E /I /Y /Q "%JDK21_HOME%" "%OUT%\runtime\jdk21" >nul
    if not defined NODE_INFRA_JDK set "NODE_INFRA_JDK=21"
)
if not defined NODE_INFRA_JDK set "NODE_INFRA_JDK=%INFRA_JDK%"

rem ---------- node-specific overrides ----------
>>"%OUT%\conf\deploy.properties" echo.
>>"%OUT%\conf\deploy.properties" echo # ===== generated by make-node.bat =====
>>"%OUT%\conf\deploy.properties" echo DEPLOY_HOST=%NODE_HOST%
>>"%OUT%\conf\deploy.properties" echo INFRA_JDK=%NODE_INFRA_JDK%
>>"%OUT%\conf\deploy.properties" echo NACOS_HOST=%NACOS_HOST%
>>"%OUT%\conf\deploy.properties" echo NACOS_PORT=%NACOS_PORT%
>>"%OUT%\conf\deploy.properties" echo NACOS_NAMESPACE=%NACOS_NAMESPACE%
>>"%OUT%\conf\deploy.properties" echo NACOS_GROUP=%NACOS_GROUP%
>>"%OUT%\conf\deploy.properties" echo NACOS_PROFILE=%NACOS_PROFILE%
>>"%OUT%\conf\deploy.properties" echo MYSQL_HOST=%MYSQL_HOST%
>>"%OUT%\conf\deploy.properties" echo PG_HOST=%PG_HOST%
>>"%OUT%\conf\deploy.properties" echo REDIS_HOST=%REDIS_HOST%
>>"%OUT%\conf\deploy.properties" echo MINIO_HOST=%MINIO_HOST%
>>"%OUT%\conf\deploy.properties" echo MQ_HOST=%MQ_HOST%
>>"%OUT%\conf\deploy.properties" echo GEOSERVER_HOST=%GEOSERVER_HOST%
>>"%OUT%\conf\deploy.properties" echo NGINX_HOST=%NGINX_HOST%
>>"%OUT%\conf\deploy.properties" echo START_MYSQL=0
>>"%OUT%\conf\deploy.properties" echo START_PG=0
>>"%OUT%\conf\deploy.properties" echo START_REDIS=0
>>"%OUT%\conf\deploy.properties" echo START_MINIO=0
>>"%OUT%\conf\deploy.properties" echo START_MQ=0
>>"%OUT%\conf\deploy.properties" echo START_NACOS=0
>>"%OUT%\conf\deploy.properties" echo START_GEOSERVER=0
>>"%OUT%\conf\deploy.properties" echo START_NGINX=0

rem ---------- zip ----------
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
where tar >nul 2>&1
if not errorlevel 1 (
    tar -a -c -f "%ZIP%" -C "%OUT_ROOT%" "node-%NODE_SAFE%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
)
if exist "%ZIP%" (
    echo   OK  %SVC_COUNT% service^(s^) -^> %ZIP%
) else (
    echo   WARN zip not created, folder is available: %OUT%
)
exit /b 0

:DONE
echo.
if defined NODE_FAIL (
    echo Done with errors. Node packages: %OUT_ROOT%
    exit /b 1
)
echo Done. Node packages: %OUT_ROOT%
exit /b 0

:NO_HOSTS
echo   conf\service-hosts.cfg not found.
echo   Fill the host column in Setup.exe service list and save first.
exit /b 1

:USAGE
echo Usage:
echo   make-node.bat ^<host^>    build one node package
echo   make-node.bat all       build packages for all remote hosts
echo.
echo Host mapping is in conf\service-hosts.cfg, edited by Setup.exe service list.
exit /b 1
