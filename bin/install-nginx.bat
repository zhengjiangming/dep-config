@echo off
setlocal
rem  register Nginx as an auto-start Windows service via the WinSW wrapper
rem  (nginx.exe has no native SCM support, see tools\winsw).
rem  idempotent + refreshable: re-run after changing deploy parameters.
rem  needs admin rights; on failure the start scripts still launch nginx.exe
rem  directly, so this step is not fatal.
call "%~dp0..\conf\env.bat"
if errorlevel 1 exit /b 1

set "WSW_DIR=%APP_HOME%\tools\winsw"
if not exist "%WSW_DIR%\WinSW-x64.exe" (
    echo   [SKIP] WinSW wrapper not found: %WSW_DIR%\WinSW-x64.exe
    exit /b 0
)
if not exist "%NGINX_HOME%\nginx.exe" (
    echo   [SKIP] nginx.exe not found: %NGINX_HOME%\nginx.exe
    exit /b 0
)
if not exist "%NGINX_HOME%\logs" mkdir "%NGINX_HOME%\logs" >nul 2>&1
if not exist "%NGINX_HOME%\temp" mkdir "%NGINX_HOME%\temp" >nul 2>&1
if not exist "%NGINX_CONF%" (
    echo   [SKIP] nginx.conf not found: %NGINX_CONF%
    exit /b 0
)

rem  render the effective nginx config first so the service references a
rem  fresh %NGINX_RUN_CNF%
call "%~dp0_lib.bat" render-nginx
if errorlevel 1 (
    echo   [SKIP] cannot render nginx.conf placeholders
    exit /b 0
)

call :REFRESH_WSV "%WSW_DIR%\nginx.exe" "%NGINX_SERVICE_NAME%"

copy /y "%WSW_DIR%\WinSW-x64.exe" "%WSW_DIR%\nginx.exe" >nul 2>&1
(
    echo ^<service^>
    echo   ^<id^>%NGINX_SERVICE_NAME%^</id^>
    echo   ^<name^>%NGINX_SERVICE_NAME%^</name^>
    echo   ^<description^>bat_application Nginx reverse proxy^</description^>
    echo   ^<executable^>%NGINX_HOME%\nginx.exe^</executable^>
    echo   ^<arguments^>-p "%NGINX_HOME%" -c "%NGINX_RUN_CNF%"^</arguments^>
    echo   ^<workingdirectory^>%NGINX_HOME%^</workingdirectory^>
    echo   ^<startmode^>Automatic^</startmode^>
    echo   ^<logpath^>%LOG_DIR%^</logpath^>
    echo   ^<log mode="roll-by-size"^>
    echo     ^<sizeThreshold^>10240^</sizeThreshold^>
    echo     ^<keepFiles^>4^</keepFiles^>
    echo   ^</log^>
    echo ^</service^>
) > "%WSW_DIR%\nginx.xml"

"%WSW_DIR%\nginx.exe" install >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register Nginx service %NGINX_SERVICE_NAME% ^(needs admin^)
    echo          start scripts will launch nginx.exe directly instead
    exit /b 0
)
echo   [ OK ] Nginx service registered: %NGINX_SERVICE_NAME%, auto start
exit /b 0

rem ---------- stop + uninstall an existing WinSW service so it can be
rem  re-registered with fresh XML config. %1 = wrapper exe, %2 = service id.
rem  a RUNNING service must be fully stopped first, otherwise uninstall
rem  leaves it half-deleted and the next install fails with 1073 ----------
:REFRESH_WSV
sc query %~2 >nul 2>&1
if errorlevel 1 exit /b 0
echo   [UPD ] existing %~2 found, stopping and refreshing config
"%~1" stop >nul 2>&1
set /a RW_N=0
:RW_WAIT
sc query %~2 2>nul | findstr /c:"STOPPED" >nul 2>&1
if not errorlevel 1 goto :RW_STOPPED
set /a RW_N+=1
if %RW_N% GEQ 30 goto :RW_STOPPED
ping -n 2 127.0.0.1 >nul
goto :RW_WAIT
:RW_STOPPED
"%~1" uninstall >nul 2>&1
ping -n 2 127.0.0.1 >nul
exit /b 0
