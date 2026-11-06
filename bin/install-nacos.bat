@echo off
setlocal
rem  register Nacos (standalone single node) as an auto-start Windows service
rem  via the WinSW wrapper.
rem  idempotent + refreshable: re-run after changing deploy parameters.
rem  needs admin rights; on failure the start scripts still launch
rem  startup.cmd directly, so this step is not fatal.
call "%~dp0..\conf\env.bat"
if errorlevel 1 exit /b 1

set "WSW_DIR=%APP_HOME%\tools\winsw"
if not exist "%WSW_DIR%\WinSW-x64.exe" (
    echo   [SKIP] WinSW wrapper not found: %WSW_DIR%\WinSW-x64.exe
    exit /b 0
)
if not exist "%NACOS_HOME%\bin\startup.cmd" (
    echo   [SKIP] startup.cmd not found: %NACOS_HOME%\bin\startup.cmd
    exit /b 0
)
if not exist "%WSW_DIR%" mkdir "%WSW_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

rem  refresh: if the service already exists, stop + uninstall the old wrapper
rem  first so updated paths take effect
call :REFRESH_WSV "%WSW_DIR%\nacos.exe" nacos
copy /y "%WSW_DIR%\WinSW-x64.exe" "%WSW_DIR%\nacos.exe" >nul 2>&1
(
    echo ^<service^>
    echo   ^<id^>nacos^</id^>
    echo   ^<name^>nacos^</name^>
    echo   ^<description^>bat_application Nacos registry, standalone mode^</description^>
    echo   ^<executable^>cmd.exe^</executable^>
    echo   ^<arguments^>/c startup.cmd -m standalone^</arguments^>
    echo   ^<workingdirectory^>%NACOS_HOME%\bin^</workingdirectory^>
    echo   ^<env name="NACOS_HOME" value="%NACOS_HOME%"/^>
) > "%WSW_DIR%\nacos.xml"
if defined JAVA_HOME (
    echo   ^<env name="JAVA_HOME" value="%JAVA_HOME%"/^>>> "%WSW_DIR%\nacos.xml"
)
(
    echo   ^<startmode^>Automatic^</startmode^>
    echo   ^<logpath^>%LOG_DIR%^</logpath^>
    echo   ^<log mode="roll-by-size"^>
    echo     ^<sizeThreshold^>10240^</sizeThreshold^>
    echo     ^<keepFiles^>4^</keepFiles^>
    echo   ^</log^>
    echo ^</service^>
) >> "%WSW_DIR%\nacos.xml"

"%WSW_DIR%\nacos.exe" install >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register Nacos service nacos ^(needs admin^)
    echo          start scripts will launch startup.cmd directly instead
    exit /b 0
)
echo   [ OK ] Nacos service registered: nacos, auto start, standalone mode
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
