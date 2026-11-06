@echo off
setlocal
rem  register MinIO as an auto-start Windows service via the WinSW wrapper
rem  (minio.exe has no native SCM support, see tools\winsw).
rem  idempotent + refreshable: re-run after changing deploy parameters.
rem  needs admin rights; on failure the start scripts still launch minio.exe
rem  directly, so this step is not fatal.
call "%~dp0..\conf\env.bat"
if errorlevel 1 exit /b 1

set "WSW_DIR=%APP_HOME%\tools\winsw"
if not exist "%WSW_DIR%\WinSW-x64.exe" (
    echo   [SKIP] WinSW wrapper not found: %WSW_DIR%\WinSW-x64.exe
    exit /b 0
)
if not exist "%MINIO_HOME%\minio.exe" (
    echo   [SKIP] minio.exe not found: %MINIO_HOME%\minio.exe
    exit /b 0
)
if not exist "%MINIO_DATA_DIR%" mkdir "%MINIO_DATA_DIR%" >nul 2>&1
if not exist "%WSW_DIR%" mkdir "%WSW_DIR%" >nul 2>&1

rem  refresh: if the service already exists, stop + uninstall the old wrapper
rem  first so updated paths/ports/credentials take effect
call :REFRESH_WSV "%WSW_DIR%\minio.exe" minio

copy /y "%WSW_DIR%\WinSW-x64.exe" "%WSW_DIR%\minio.exe" >nul 2>&1
(
    echo ^<service^>
    echo   ^<id^>minio^</id^>
    echo   ^<name^>minio^</name^>
    echo   ^<description^>bat_application MinIO object storage^</description^>
    echo   ^<executable^>%MINIO_HOME%\minio.exe^</executable^>
    echo   ^<arguments^>server "%MINIO_DATA_DIR%" --address ":%PORT_MINIO%" --console-address ":%PORT_MINIO_CONSOLE%"^</arguments^>
    echo   ^<workingdirectory^>%MINIO_HOME%^</workingdirectory^>
    echo   ^<env name="MINIO_ROOT_USER" value="%MINIO_USER%"/^>
    echo   ^<env name="MINIO_ROOT_PASSWORD" value="%MINIO_PWD%"/^>
    echo   ^<env name="MINIO_ACCESS_KEY" value="%MINIO_USER%"/^>
    echo   ^<env name="MINIO_SECRET_KEY" value="%MINIO_PWD%"/^>
    echo   ^<startmode^>Automatic^</startmode^>
    echo   ^<logpath^>%LOG_DIR%^</logpath^>
    echo   ^<log mode="roll-by-size"^>
    echo     ^<sizeThreshold^>10240^</sizeThreshold^>
    echo     ^<keepFiles^>4^</keepFiles^>
    echo   ^</log^>
    echo ^</service^>
) > "%WSW_DIR%\minio.xml"

"%WSW_DIR%\minio.exe" install >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register MinIO service minio ^(needs admin^)
    echo          start scripts will launch minio.exe directly instead
    exit /b 0
)
echo   [ OK ] MinIO service registered: minio, auto start
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
