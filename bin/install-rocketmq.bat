@echo off
setlocal
rem  register RocketMQ (NameServer + Broker, standalone single node) as
rem  auto-start Windows services via the WinSW wrapper. Broker depends on
rem  NameServer so boot order is guaranteed.
rem  idempotent + refreshable: re-run after changing deploy parameters.
rem  needs admin rights; on failure the start scripts still launch
rem  mqnamesrv.cmd/mqbroker.cmd directly, so this step is not fatal.
call "%~dp0..\conf\env.bat"
if errorlevel 1 exit /b 1

set "WSW_DIR=%APP_HOME%\tools\winsw"
if not exist "%WSW_DIR%\WinSW-x64.exe" (
    echo   [SKIP] WinSW wrapper not found: %WSW_DIR%\WinSW-x64.exe
    exit /b 0
)
if not exist "%ROCKETMQ_HOME%\bin\mqnamesrv.cmd" (
    echo   [SKIP] mqnamesrv.cmd not found: %ROCKETMQ_HOME%\bin\mqnamesrv.cmd
    exit /b 0
)
if not exist "%WSW_DIR%" mkdir "%WSW_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

rem  the broker reads this rendered config; produce it at install time too
call "%~dp0_lib.bat" render-mq
if errorlevel 1 (
    echo   [WARN] cannot render broker config from %MQ_BROKER_CNF%
    exit /b 0
)

rem ---------- NameServer ----------
call :REFRESH_WSV "%WSW_DIR%\rocketmq-namesrv.exe" rocketmq-namesrv
copy /y "%WSW_DIR%\WinSW-x64.exe" "%WSW_DIR%\rocketmq-namesrv.exe" >nul 2>&1
(
    echo ^<service^>
    echo   ^<id^>rocketmq-namesrv^</id^>
    echo   ^<name^>rocketmq-namesrv^</name^>
    echo   ^<description^>bat_application RocketMQ NameServer^</description^>
    echo   ^<executable^>cmd.exe^</executable^>
    echo   ^<arguments^>/c mqnamesrv.cmd^</arguments^>
    echo   ^<workingdirectory^>%ROCKETMQ_HOME%\bin^</workingdirectory^>
    echo   ^<env name="ROCKETMQ_HOME" value="%ROCKETMQ_HOME%"/^>
) > "%WSW_DIR%\rocketmq-namesrv.xml"
if defined JAVA_HOME (
    echo   ^<env name="JAVA_HOME" value="%JAVA_HOME%"/^>>> "%WSW_DIR%\rocketmq-namesrv.xml"
)
(
    echo   ^<startmode^>Automatic^</startmode^>
    echo   ^<logpath^>%LOG_DIR%^</logpath^>
    echo   ^<log mode="roll-by-size"^>
    echo     ^<sizeThreshold^>10240^</sizeThreshold^>
    echo     ^<keepFiles^>4^</keepFiles^>
    echo   ^</log^>
    echo ^</service^>
) >> "%WSW_DIR%\rocketmq-namesrv.xml"

"%WSW_DIR%\rocketmq-namesrv.exe" install >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register RocketMQ service rocketmq-namesrv ^(needs admin^)
    exit /b 0
)
echo   [ OK ] RocketMQ NameServer service registered: rocketmq-namesrv, auto start

rem ---------- Broker ----------
call :REFRESH_WSV "%WSW_DIR%\rocketmq-broker.exe" rocketmq-broker
copy /y "%WSW_DIR%\WinSW-x64.exe" "%WSW_DIR%\rocketmq-broker.exe" >nul 2>&1
(
    echo ^<service^>
    echo   ^<id^>rocketmq-broker^</id^>
    echo   ^<name^>rocketmq-broker^</name^>
    echo   ^<description^>bat_application RocketMQ Broker^</description^>
    echo   ^<executable^>cmd.exe^</executable^>
    echo   ^<arguments^>/c mqbroker.cmd -n %MQ_HOST%:%PORT_MQ_NAMESRV% -c "%MQ_BROKER_RUN_CNF%"^</arguments^>
    echo   ^<workingdirectory^>%ROCKETMQ_HOME%\bin^</workingdirectory^>
    echo   ^<env name="ROCKETMQ_HOME" value="%ROCKETMQ_HOME%"/^>
) > "%WSW_DIR%\rocketmq-broker.xml"
if defined JAVA_HOME (
    echo   ^<env name="JAVA_HOME" value="%JAVA_HOME%"/^>>> "%WSW_DIR%\rocketmq-broker.xml"
)
(
    echo   ^<startmode^>Automatic^</startmode^>
    echo   ^<logpath^>%LOG_DIR%^</logpath^>
    echo   ^<log mode="roll-by-size"^>
    echo     ^<sizeThreshold^>10240^</sizeThreshold^>
    echo     ^<keepFiles^>4^</keepFiles^>
    echo   ^</log^>
    echo ^</service^>
) >> "%WSW_DIR%\rocketmq-broker.xml"

"%WSW_DIR%\rocketmq-broker.exe" install >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register RocketMQ service rocketmq-broker ^(needs admin^)
    exit /b 0
)
sc config rocketmq-broker depend= rocketmq-namesrv >nul 2>&1
echo   [ OK ] RocketMQ Broker service registered: rocketmq-broker, auto start, depends on rocketmq-namesrv
exit /b 0

rem ---------- stop + uninstall an existing WinSW service so it can be
rem  re-registered with fresh XML config. %1 = wrapper exe, %2 = service id.
rem  a RUNNING service must be fully stopped first, otherwise uninstall
rem  leaves it half-deleted and the next install fails with 1073 ----------
:REFRESH_WSV
sc query "%~2" >nul 2>&1
if errorlevel 1 exit /b 0
echo   [UPD ] existing %~2 found, stopping and refreshing config
"%~1" stop >nul 2>&1
set /a RW_N=0
:RW_WAIT
sc query "%~2" 2>nul | findstr /c:"STOPPED" >nul 2>&1
if not errorlevel 1 goto :RW_STOPPED
set /a RW_N+=1
if %RW_N% GEQ 30 goto :RW_STOPPED
ping -n 2 127.0.0.1 >nul
goto :RW_WAIT
:RW_STOPPED
"%~1" uninstall >nul 2>&1
ping -n 2 127.0.0.1 >nul
exit /b 0
