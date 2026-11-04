@echo off
rem =====================================================================
rem  Assemble components into the package layout before packing.
rem
rem  Only entries EXPLICITLY configured in conf\components.properties
rem  are copied (system environment variables are ignored here).
rem    JDK17_HOME / JDK21_HOME          -> runtime\jdk17 / jdk21
rem    MYSQL_HOME ... GEOSERVER_HOME    -> infra\<component>
rem    APPS_DIR                          -> apps\
rem    ENGINE_JAR                        -> engine\qrule.jar
rem
rem  Then run pack.bat to build the zip.
rem =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
call "conf\env.bat"

echo.
echo ===== Assemble components into package layout =====
echo   APP_HOME = %APP_HOME%
echo   Copying only entries configured in conf\components.properties
set "FAIL="

rem ---------- read raw values from components.properties ----------
set "SRC_JDK17="
set "SRC_JDK21="
set "SRC_MYSQL="
set "SRC_PG="
set "SRC_REDIS="
set "SRC_ROCKETMQ="
set "SRC_MINIO="
set "SRC_NACOS="
set "SRC_GEOSERVER="
set "SRC_NGINX="
set "SRC_APPS="
set "SRC_ENGINE="
if not exist "%APP_HOME%\conf\components.properties" goto :CFG_DONE
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%APP_HOME%\conf\components.properties") do (
    if /i "%%A"=="JDK17_HOME" set "SRC_JDK17=%%B"
    if /i "%%A"=="JDK21_HOME" set "SRC_JDK21=%%B"
    if /i "%%A"=="MYSQL_HOME" set "SRC_MYSQL=%%B"
    if /i "%%A"=="PG_HOME" set "SRC_PG=%%B"
    if /i "%%A"=="REDIS_HOME" set "SRC_REDIS=%%B"
    if /i "%%A"=="ROCKETMQ_HOME" set "SRC_ROCKETMQ=%%B"
    if /i "%%A"=="MINIO_HOME" set "SRC_MINIO=%%B"
    if /i "%%A"=="NACOS_HOME" set "SRC_NACOS=%%B"
    if /i "%%A"=="GEOSERVER_HOME" set "SRC_GEOSERVER=%%B"
    if /i "%%A"=="NGINX_HOME" set "SRC_NGINX=%%B"
    if /i "%%A"=="APPS_DIR" set "SRC_APPS=%%B"
    if /i "%%A"=="ENGINE_JAR" set "SRC_ENGINE=%%B"
)
:CFG_DONE

if defined SRC_JDK17 call :COPYDIR "JDK17"      "%SRC_JDK17%"      "%APP_HOME%\runtime\jdk17"
if defined SRC_JDK21 call :COPYDIR "JDK21"      "%SRC_JDK21%"      "%APP_HOME%\runtime\jdk21"
if defined SRC_MYSQL call :COPYDIR "MySQL"      "%SRC_MYSQL%"      "%APP_HOME%\infra\mysql"
if defined SRC_PG call :COPYDIR "PostgreSQL"    "%SRC_PG%"         "%APP_HOME%\infra\postgres"
if defined SRC_REDIS call :COPYDIR "Redis"      "%SRC_REDIS%"      "%APP_HOME%\infra\redis"
if defined SRC_ROCKETMQ call :COPYDIR "RocketMQ" "%SRC_ROCKETMQ%"  "%APP_HOME%\infra\rocketmq"
if defined SRC_MINIO call :COPYDIR "MinIO"      "%SRC_MINIO%"      "%APP_HOME%\infra\minio"
if defined SRC_NACOS call :COPYDIR "Nacos"      "%SRC_NACOS%"      "%APP_HOME%\infra\nacos"
if defined SRC_GEOSERVER call :COPYDIR "GeoServer" "%SRC_GEOSERVER%" "%APP_HOME%\infra\geoserver"
if defined SRC_NGINX call :COPYDIR "Nginx" "%SRC_NGINX%" "%APP_HOME%\infra\nginx"
if defined SRC_APPS call :COPYDIR "Apps"        "%SRC_APPS%"       "%APP_HOME%\apps"

rem ---------- single jar: engine ----------
if not defined SRC_ENGINE goto :ENGINE_DONE
set "E=%SRC_ENGINE%"
if "!E:~-1!"=="\" set "E=!E:~0,-1!"
if /i "!E!"=="%APP_HOME%\engine\qrule.jar" (
    echo   SKIP  qrule.jar  already inside package
    goto :ENGINE_DONE
)
if not exist "!E!" (
    echo   MISS  qrule.jar  source not found: !E!
    set "FAIL=1"
    goto :ENGINE_DONE
)
if not exist "%APP_HOME%\engine" mkdir "%APP_HOME%\engine"
echo   COPY  qrule.jar  !E!  to  %APP_HOME%\engine\qrule.jar
copy /y "!E!" "%APP_HOME%\engine\qrule.jar" >nul
:ENGINE_DONE

echo.
if defined FAIL (
    echo Assemble finished with problems. Fix the MISS items above, then run again.
    pause
    exit /b 1
)
echo Assemble finished. Next: pack.bat
pause
exit /b 0

rem ---------- copy a component dir into the package ----------
:COPYDIR
set "S=%~2"
set "T=%~3"
if "!S:~-1!"=="\" set "S=!S:~0,-1!"
if "!T:~-1!"=="\" set "T=!T:~0,-1!"
if /i "!S!"=="!T!" (
    echo   SKIP  %~1  already inside package
    exit /b 0
)
if not exist "!S!" (
    echo   MISS  %~1  source not found: !S!
    set "FAIL=1"
    exit /b 0
)
echo   COPY  %~1  !S!  to  !T!
robocopy "!S!" "!T!" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
    echo   FAIL  %~1  robocopy error
    set "FAIL=1"
)
exit /b 0
