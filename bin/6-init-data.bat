@echo off
rem =====================================================================
rem  Run ONE local init / data-import script.
rem  Usage: 6-init-data.bat <mysql|pg|all> <script> [database]
rem    .sql      import into MySQL and/or PostgreSQL with the bundled clients
rem    .bat/.cmd run as a local data-import hook (MinIO path: %MINIO_DATA_DIR%)
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
if not exist "%MINIO_DATA_DIR%" mkdir "%MINIO_DATA_DIR%" >nul 2>&1

set "TARGET=%~1"
set "SCRIPT=%~2"
set "DBNAME=%~3"

if "%TARGET%"=="" goto :USAGE
if "%SCRIPT%"=="" goto :USAGE
if not exist "%SCRIPT%" (
    echo   FAIL script not found: %SCRIPT%
    exit /b 1
)

set "EXT=%~x2"
set "SCRIPTNAME=%~nx2"
if /i "%EXT%"==".bat" goto :RUN_SCRIPT
if /i "%EXT%"==".cmd" goto :RUN_SCRIPT
if /i "%EXT%"==".sql" goto :SQL
echo   FAIL unsupported script type: %EXT%
exit /b 1

rem ---------- local data-import hook (.bat / .cmd) ----------
:RUN_SCRIPT
echo   [RUN] %SCRIPTNAME%
pushd "%APP_HOME%"
call "%SCRIPT%"
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" (
    echo   FAIL %SCRIPTNAME% exit=%RC%
    exit /b %RC%
)
echo   OK   %SCRIPTNAME%
exit /b 0

rem ---------- SQL import ----------
:SQL
if /i "%TARGET%"=="mysql" goto :MYSQL
if /i "%TARGET%"=="pg" goto :PG
if /i "%TARGET%"=="all" goto :ALL
goto :USAGE

:ALL
call :MYSQL
if errorlevel 1 exit /b 1
call :PG
if errorlevel 1 exit /b 1
exit /b 0

:MYSQL
if not exist "%MYSQL_HOME%\bin\mysql.exe" (
    echo   FAIL mysql client not found: %MYSQL_HOME%\bin\mysql.exe
    exit /b 1
)
echo   [MySQL] %SCRIPTNAME%  db=%DBNAME%
"%MYSQL_HOME%\bin\mysql.exe" --protocol=tcp --host=%MYSQL_HOST% --port=%MYSQL_PORT% --user=%MYSQL_USER% --default-character-set=utf8mb4 %DBNAME% < "%SCRIPT%"
if errorlevel 1 (
    echo   FAIL MySQL import failed: %SCRIPTNAME%
    exit /b 1
)
echo   OK   MySQL import done
exit /b 0

:PG
if not exist "%PG_HOME%\bin\psql.exe" (
    echo   FAIL postgres client not found: %PG_HOME%\bin\psql.exe
    exit /b 1
)
set "PGDB=%DBNAME%"
if not defined PGDB set "PGDB=postgres"
set "PGPASSWORD=%PG_PWD%"
set "PGCLIENTENCODING=UTF8"
echo   [PostgreSQL] %SCRIPTNAME%  db=%PGDB%
"%PG_HOME%\bin\psql.exe" -h %PG_HOST% -p %PG_PORT% -U %PG_USER% -d %PGDB% -v ON_ERROR_STOP=1 -f "%SCRIPT%"
if errorlevel 1 (
    echo   FAIL PostgreSQL import failed: %SCRIPTNAME%
    exit /b 1
)
echo   OK   PostgreSQL import done
exit /b 0

:USAGE
echo Usage: 6-init-data.bat ^<mysql^|pg^|all^> ^<script^> [database]
exit /b 1
