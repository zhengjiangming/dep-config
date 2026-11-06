@echo off
rem =====================================================================
rem  Start / stop / restart ONE service from conf\apps.cfg.
rem  Usage: 8-service.bat start|stop|restart <serviceName>
rem  Called by Setup.exe (service list page) or manually.
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
set "CURL=%CURL_EXE%"
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
if not exist "%APP_HOME%\conf\apps.cfg" (
    echo   FAIL conf\apps.cfg not found
    exit /b 1
)
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
rem  starting on top of a still-listening port would only produce a bind error
if errorlevel 1 (
    echo   FAIL %SVC_NAME% could not be stopped, restart aborted
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :DO_START

:DO_STOP
echo   [STOP] %SVC_NAME% port=%SVC_PORT%
call :KILLPORT %SVC_PORT%
if errorlevel 1 exit /b 1
exit /b 0

:DO_START
rem  this action writes logs, create the folder on demand (env.bat stays read-only)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
"%CURL%" -s -f -m %HTTP_TIMEOUT_SEC% "http://%NACOS_ADDR%/nacos/v1/console/health/liveness" >nul 2>&1
if errorlevel 1 echo   WARN Nacos not reachable at %NACOS_ADDR%
if not exist "%SVC_JAR%" (
    echo   FAIL jar not found: %SVC_JAR%
    exit /b 1
)
call :VALIDPORT "%SVC_PORT%"
if errorlevel 1 (
    echo   FAIL bad port "%SVC_PORT%" for %SVC_NAME%, fix conf\apps.cfg
    exit /b 1
)
rem  端口被其他程序占用时必须失败退出，否则 WAITPORT 会把别人的监听误报成启动成功
call :PORTSKIP "%SVC_PORT%" "%SVC_NAME%" "java.exe javaw.exe"
if errorlevel 2 exit /b 1
if errorlevel 1 (
    echo   OK   %SVC_NAME% already running on port %SVC_PORT%
    exit /b 0
)
echo   [START] %SVC_NAME% port=%SVC_PORT% jdk=%SVC_JDK%
start "%SVC_NAME%" /D "%APP_HOME%" /MIN cmd /c ""%SVC_JAVA%" %JVM_BASE% %APP_OPTS% %NACOS_OPTS% %SVC_JVM% -jar %SVC_JAR% %SVC_EXTRA% >> "%LOG_DIR%\%SVC_NAME%.log" 2>&1"
call :WAITPORT %SVC_PORT% %WAIT_APP_SEC% "%SVC_NAME%"
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
    echo   FAIL %~3 port %~1 timeout, check %LOG_DIR%\%~3.log
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :WAITPORT_LOOP

rem ---------- port helpers ----------
:VALIDPORT
if "%~1"=="" exit /b 1
for /f "delims=0123456789" %%A in ("%~1") do exit /b 1
if %~1 LEQ 0 exit /b 1
if %~1 GTR 65535 exit /b 1
exit /b 0

rem  %1 port, %2 service, %3 expected process image(s)
rem  exit 0 = free, 1 = already running by this deployment, 2 = held by another program
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
    echo   FAIL %~2 port %~1 is held by another program, PID:!PS_FOREIGN!
    echo          expected %~3, stop that program or change the port in conf\apps.cfg
    exit /b 2
)
echo   [SKIP] %~2 port %~1 already listening, assume it is running
exit /b 1

:PORTIMAGE
set "PI_IMG="
for /f "tokens=1 delims=," %%I in ('tasklist /FI "PID eq %~1" /FO CSV /NH 2^>nul ^| findstr /v /b /c:"INFO:"') do set "PI_IMG=%%~I"
if not defined PI_IMG exit /b 1
for %%I in (%~2) do if /i "!PI_IMG!"=="%%~I" exit /b 0
exit /b 1

rem  %1 = port. Only kill processes belonging to this deployment, so a port
rem  taken by IIS / another Java app is never force-killed by accident.
:KILLPORT
set "KPL_FAIL="
rem  a dual stack listener reports the same PID twice, only kill it once
set "KPL_SEEN="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do call :KILLPID %%P %~1
if defined KPL_FAIL exit /b 1
exit /b 0

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
