@echo off
rem =====================================================================
rem  Build the offline package:
rem    release\bat_application_YYYYMMDD.zip
rem
rem  Included together:
rem    runtime\  jdk17 + jdk21 (+ optional vc_redist, curl)
rem    infra\    mysql postgres redis rocketmq minio nacos geoserver
rem    apps\     service jars + mapserver.jar
rem    engine\   qrule.jar
rem    bin\ conf\ + install.bat / start-all.bat / stop-all.bat
rem
rem  Excluded: data\ logs\ release\ conf\deploy.properties *.bak
rem  Uses 7-Zip when available, otherwise Windows built-in tar.exe.
rem  Target machines need neither, and no JDK/DB installation.
rem =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem ---------- required folders ----------
set "MISSING="
call :REQ_DIR "runtime"
call :REQ_DIR "infra"
call :REQ_DIR "apps"
call :REQ_DIR "engine"
call :REQ_DIR "bin"
call :REQ_DIR "conf"

rem ---------- bundled JDKs ----------
if not exist "runtime\jdk17\bin\java.exe" set "MISSING=!MISSING! runtime\jdk17"
if not exist "runtime\jdk21\bin\java.exe" set "MISSING=!MISSING! runtime\jdk21"

rem ---------- middleware ----------
if not exist "infra\mysql\bin\mysqld.exe" set "MISSING=!MISSING! infra\mysql"
if not exist "infra\postgres\bin\pg_ctl.exe" set "MISSING=!MISSING! infra\postgres"
if not exist "infra\redis\redis-server.exe" set "MISSING=!MISSING! infra\redis"
if not exist "infra\rocketmq\bin\mqnamesrv.cmd" set "MISSING=!MISSING! infra\rocketmq"
if not exist "infra\minio\minio.exe" set "MISSING=!MISSING! infra\minio"
if not exist "infra\nacos\bin\startup.cmd" set "MISSING=!MISSING! infra\nacos"
if not exist "infra\geoserver\bin\startup.bat" set "MISSING=!MISSING! infra\geoserver"
if not exist "infra\nginx\nginx.exe" set "MISSING=!MISSING! infra\nginx"

rem ---------- apps / engine ----------
if not exist "engine\qrule.jar" set "MISSING=!MISSING! engine\qrule.jar"
if not exist "conf\apps.cfg" set "MISSING=!MISSING! conf\apps.cfg"
set "JARS=0"
for %%F in ("apps\*.jar") do set /a JARS+=1
if "!JARS!"=="0" set "MISSING=!MISSING! apps\*.jar"

if defined MISSING goto :MISS

rem ---------- output name (locale independent) ----------
set "STAMP=%DATE%"
set "STAMP=%STAMP:/=%"
set "STAMP=%STAMP:-=%"
set "STAMP=%STAMP:.=%"
set "STAMP=%STAMP: =%"
set "STAMP=%STAMP:~-8%"
if not defined STAMP set "STAMP=%RANDOM%"
if not exist "release" mkdir "release"
set "OUT=release\bat_application_%STAMP%.zip"
if exist "%OUT%" del "%OUT%"

rem ---------- optional GUI installer ----------
set "EXTRA="
if exist "Setup.exe" set "EXTRA=Setup.exe"

rem ---------- prefer 7-Zip ----------
where 7z.exe >nul 2>&1
if errorlevel 1 goto :USE_TAR

echo Packing runtime + infra + apps with 7-Zip ...
7z.exe a -tzip -mx=5 "%OUT%" "runtime" "infra" "apps" "engine" "bin" "conf" "install.bat" "start-all.bat" "stop-all.bat" "pack.bat" %EXTRA% -xr!data -xr!logs -xr!release -xr!*.bak -xr!deploy.properties
if errorlevel 1 goto :FAIL
goto :OK

rem ---------- fallback: built-in tar on Win10/11 ----------
:USE_TAR
where tar.exe >nul 2>&1
if errorlevel 1 goto :NOTOOL
echo Packing runtime + infra + apps with built-in tar.exe ...
tar.exe -a -c -f "%OUT%" --exclude "*/data/*" --exclude "*/logs/*" --exclude "*/release/*" --exclude "*/deploy.properties" --exclude "*.bak" "runtime" "infra" "apps" "engine" "bin" "conf" "install.bat" "start-all.bat" "stop-all.bat" "pack.bat" %EXTRA%
if errorlevel 1 goto :FAIL
goto :OK

rem ---------- result ----------
:OK
echo.
echo Package : %OUT%
for %%F in ("%OUT%") do echo Size    : %%~zF bytes
echo Jars    : %JARS% in apps\, 1 in engine\
echo JDKs    : jdk17 + jdk21
echo Included: runtime\ infra\ apps\ engine\ bin\ conf\ + launchers
echo.
echo SHA256  :
certutil -hashfile "%OUT%" SHA256 2>nul | findstr /v ":"
echo.
echo Next: copy the zip to the target machine, extract to D:\bat_application,
echo       then run install.bat there.
pause
exit /b 0

:FAIL
echo.
echo Pack failed. Check the messages above.
pause
exit /b 1

:MISS
echo.
echo Missing or incomplete payload:
echo   !MISSING!
echo Fix these items, then run pack.bat again.
echo If components live outside this folder, set their paths in
echo conf\components.properties and run assemble.bat first.
pause
exit /b 1

:NOTOOL
echo.
echo Neither 7-Zip nor tar.exe is available on this build machine.
echo Install 7-Zip, or compress the folders manually with Explorer.
pause
exit /b 1

rem ---------- helper ----------
:REQ_DIR
if not exist "%~1" set "MISSING=!MISSING! %~1\"
exit /b 0
