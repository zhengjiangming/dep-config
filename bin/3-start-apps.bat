@echo off
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Start microservices
set "NO_PAUSE="
if /i "%~1"=="auto" set "NO_PAUSE=1"
set "CURL=%APP_HOME%\runtime\curl\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"
set "SELF_HOST=%DEPLOY_HOST%"
if /i "%SELF_HOST%"=="localhost" set "SELF_HOST=127.0.0.1"

echo.
echo ===== Waiting for Nacos %NACOS_ADDR% =====
call :WAITNACOS 180
if errorlevel 1 (
    echo Nacos not ready, abort. Check NACOS_HOST / NACOS_PORT in conf\deploy.properties.
    if not defined NO_PAUSE pause
    exit /b 1
)

echo.
echo ===== Start services assigned to this host (%DEPLOY_HOST%) =====
set /a N=0
set /a SKIPPED=0
set "FAILED="
set "FAILED_LIST="
for /f "usebackq eol=# tokens=1,2,3,4,5,6 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do (
    set "SVC_NAME=%%~A"
    set "SVC_JAR=%APP_HOME%\%%~B"
    set "SVC_PORT=%%~C"
    set "SVC_JDK=%%~D"
    set "SVC_JVM=%%~E"
    set "SVC_EXTRA=%%~F"
    set "SVC_HOST="
    if exist "%APP_HOME%\conf\service-hosts.cfg" (
        for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do (
            if /i "%%X"=="!SVC_NAME!" set "SVC_HOST=%%Y"
        )
    )
    if /i "!SVC_HOST!"=="localhost" set "SVC_HOST=127.0.0.1"
    set /a N+=1
    if defined SVC_HOST (
        if /i not "!SVC_HOST!"=="%SELF_HOST%" (
            echo   [REMOTE] !SVC_NAME!  host=!SVC_HOST!
            set /a SKIPPED+=1
        ) else (
            call :START_ONE
            if errorlevel 1 (
                set "FAILED=1"
                set "FAILED_LIST=!FAILED_LIST! !SVC_NAME!"
            )
        )
    ) else (
        call :START_ONE
        if errorlevel 1 (
            set "FAILED=1"
            set "FAILED_LIST=!FAILED_LIST! !SVC_NAME!"
        )
    )
)

echo.
echo Total !N! entries, skipped remote !SKIPPED!. Status: bin\4-status.bat   Logs: !LOG_DIR!
if defined FAILED (
    echo.
    echo FAILED:!FAILED_LIST!  check logs in !LOG_DIR!
    if not defined NO_PAUSE pause
    exit /b 1
)
if not defined NO_PAUSE pause
exit /b 0

:START_ONE
if not defined SVC_JDK set "SVC_JDK=%INFRA_JDK%"
set "SVC_JAVA="
if "!SVC_JDK!"=="17" set "SVC_JAVA=!JDK17_HOME!\bin\java.exe"
if "!SVC_JDK!"=="21" set "SVC_JAVA=!JDK21_HOME!\bin\java.exe"
if not defined SVC_JAVA (
    echo   [SKIP] !SVC_NAME!  bad jdk tag "!SVC_JDK!", use 17 or 21
    exit /b 1
)
if not exist "!SVC_JAR!" (
    echo   [MISS] !SVC_NAME!  jar not found: !SVC_JAR!
    exit /b 1
)
echo   [START] !SVC_NAME!  port=!SVC_PORT!  jdk=!SVC_JDK!
start "!SVC_NAME!" /D "%APP_HOME%" /MIN cmd /c "!SVC_JAVA! !JVM_BASE! !APP_OPTS! !NACOS_OPTS! !SVC_JVM! -jar !SVC_JAR! !SVC_EXTRA! >> !LOG_DIR!\!SVC_NAME!.log 2>&1"
call :WAITPORT !SVC_PORT! 180 "!SVC_NAME!"
exit /b %errorlevel%

rem ---------- wait until Nacos HTTP is reachable ----------
:WAITNACOS
set /a WN_N=0
:WAITNACOS_LOOP
"%CURL%" -s -f -m 3 "http://%NACOS_ADDR%/nacos/v1/console/health/liveness" >nul 2>&1
if not errorlevel 1 (
    echo   OK   Nacos %NACOS_ADDR% ready
    exit /b 0
)
set /a WN_N+=1
if %WN_N% GEQ %~1 (
    echo   FAIL Nacos %NACOS_ADDR% not reachable
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :WAITNACOS_LOOP

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
