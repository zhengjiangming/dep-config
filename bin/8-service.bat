@echo off
rem =====================================================================
rem  Start / stop / restart ONE service from conf\apps.cfg.
rem  Usage: 8-service.bat start|stop|restart <serviceName>
rem  Called by Setup.exe (service list page) or manually.
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
set "CURL=%APP_HOME%\runtime\curl\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"
set "SELF_HOST=%DEPLOY_HOST%"
if /i "%SELF_HOST%"=="localhost" set "SELF_HOST=127.0.0.1"

set "ACTION=%~1"
set "SVC_NAME=%~2"
if "%ACTION%"=="" goto :USAGE
if "%SVC_NAME%"=="" goto :USAGE

set "SVC_JAR="
set "SVC_PORT="
set "SVC_JDK="
set "SVC_JVM="
set "SVC_EXTRA="
set "SVC_HOST="
for /f "usebackq eol=# tokens=1,2,3,4,5,6 delims=|" %%A in ("%APP_HOME%\conf\apps.cfg") do (
    if /i "%%~A"=="%SVC_NAME%" (
        set "SVC_JAR=%APP_HOME%\%%~B"
        set "SVC_PORT=%%~C"
        set "SVC_JDK=%%~D"
        set "SVC_JVM=%%~E"
        set "SVC_EXTRA=%%~F"
        set "SVC_HOST="
        if exist "%APP_HOME%\conf\service-hosts.cfg" (
            for /f "usebackq eol=# tokens=1,2 delims=|" %%X in ("%APP_HOME%\conf\service-hosts.cfg") do (
                if /i "%%X"=="%SVC_NAME%" set "SVC_HOST=%%Y"
            )
        )
    )
)
if not defined SVC_JAR goto :NOT_FOUND
if /i "!SVC_HOST!"=="localhost" set "SVC_HOST=127.0.0.1"
if defined SVC_HOST if /i not "!SVC_HOST!"=="%SELF_HOST%" (
    echo   [REMOTE] %SVC_NAME% runs on !SVC_HOST!, start it on that machine
    exit /b 1
)
if not defined SVC_JDK set "SVC_JDK=%INFRA_JDK%"
set "SVC_JAVA="
if "%SVC_JDK%"=="17" set "SVC_JAVA=%JDK17_HOME%\bin\java.exe"
if "%SVC_JDK%"=="21" set "SVC_JAVA=%JDK21_HOME%\bin\java.exe"
if not defined SVC_JAVA goto :BAD_JDK

if /i "%ACTION%"=="start" goto :DO_START
if /i "%ACTION%"=="stop" goto :DO_STOP
if /i "%ACTION%"=="restart" goto :DO_RESTART
goto :USAGE

:DO_RESTART
echo   [STOP] %SVC_NAME% port=%SVC_PORT%
call :KILLPORT %SVC_PORT%
ping -n 2 127.0.0.1 >nul
goto :DO_START

:DO_STOP
echo   [STOP] %SVC_NAME% port=%SVC_PORT%
call :KILLPORT %SVC_PORT%
exit /b 0

:DO_START
"%CURL%" -s -f -m 3 "http://%NACOS_ADDR%/nacos/v1/console/health/liveness" >nul 2>&1
if errorlevel 1 echo   WARN Nacos not reachable at %NACOS_ADDR%
if not exist "%SVC_JAR%" (
    echo   FAIL jar not found: %SVC_JAR%
    exit /b 1
)
echo   [START] %SVC_NAME% port=%SVC_PORT% jdk=%SVC_JDK%
start "%SVC_NAME%" /D "%APP_HOME%" /MIN cmd /c "%SVC_JAVA% %JVM_BASE% %APP_OPTS% %NACOS_OPTS% %SVC_JVM% -jar %SVC_JAR% %SVC_EXTRA% >> %LOG_DIR%\%SVC_NAME%.log 2>&1"
call :WAITPORT %SVC_PORT% 180 "%SVC_NAME%"
exit /b %errorlevel%

:USAGE
echo Usage: 8-service.bat start^|stop^|restart ^<serviceName^>
exit /b 1

:NOT_FOUND
echo   FAIL service not found in conf\apps.cfg: %SVC_NAME%
exit /b 1

:BAD_JDK
echo   FAIL bad jdk tag "%SVC_JDK%" for %SVC_NAME%, use 17 or 21
exit /b 1

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
    echo   FAIL %~3 port %~1 timeout, check %LOG_DIR%\%~3.log
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :WAITPORT_LOOP

rem  %1 = port. Only kill processes belonging to this deployment, so a port
rem  taken by IIS / another Java app is never force-killed by accident.
:KILLPORT
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do call :KILLPID %%P %~1
exit /b 0

:KILLPID
set "KP_IMG="
for /f "tokens=1 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul') do set "KP_IMG=%%~I"
if not defined KP_IMG exit /b 0
set "KP_OK="
for %%I in (java.exe javaw.exe nginx.exe mysqld.exe postgres.exe redis-server.exe minio.exe) do if /i "!KP_IMG!"=="%%I" set "KP_OK=1"
if not defined KP_OK (
    echo   [SKIP] port %~2 is held by !KP_IMG! ^(PID %~1^), not a deployment process
    exit /b 0
)
taskkill /F /PID %~1 >nul 2>&1
exit /b 0
