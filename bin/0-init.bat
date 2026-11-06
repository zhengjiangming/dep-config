@echo off
setlocal
call "%~dp0..\conf\env.bat"
title First-time init
echo.
echo ===== First-time init (run once) =====

rem ---------- data / log roots (created once here, not on every env.bat load) ----------
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

set "INIT_FAIL="

rem ---------- MySQL ----------
if not exist "%MYSQL_CNF%" (
    echo   [FAIL] MySQL config not found: %MYSQL_CNF%
    set "INIT_FAIL=1"
) else if exist "%MYSQL_DATA_DIR%\mysql" (
    echo   [SKIP] MySQL data dir already initialized: %MYSQL_DATA_DIR%
) else (
    rem  the folder may exist after a failed init; initializing into a non-empty
    rem  datadir fails, so report it instead of silently skipping
    set "MYSQL_PARTIAL="
    if exist "%MYSQL_DATA_DIR%" for /f "delims=" %%F in ('dir /b /a "%MYSQL_DATA_DIR%" 2^>nul') do set "MYSQL_PARTIAL=1"
    if defined MYSQL_PARTIAL (
        echo   [FAIL] MySQL data dir exists but is not initialized: %MYSQL_DATA_DIR%
        echo          Delete or move it away, then re-run bin\0-init.bat
        set "INIT_FAIL=1"
    ) else (
        echo   [INIT] MySQL data dir: %MYSQL_DATA_DIR%
        "%MYSQL_HOME%\bin\mysqld.exe" --defaults-file="%MYSQL_CNF%" --datadir="%MYSQL_DATA_DIR%" --initialize-insecure --console
        if errorlevel 1 (
            echo   [FAIL] MySQL init failed
            set "INIT_FAIL=1"
        ) else (
            echo   [ OK ] MySQL data dir ready
        )
    )
)

rem ---------- register the MySQL Windows service ----------
rem  so the start scripts can net start it (no console window)
if exist "%MYSQL_HOME%\bin\mysqld.exe" if exist "%MYSQL_CNF%" call :REGISTER_MYSQL_SERVICE

rem ---------- PostgreSQL ----------
if exist "%PG_DATA_DIR%\PG_VERSION" (
    echo   [SKIP] PostgreSQL data dir already initialized: %PG_DATA_DIR%
) else (
    set "PG_PARTIAL="
    if exist "%PG_DATA_DIR%" for /f "delims=" %%F in ('dir /b /a "%PG_DATA_DIR%" 2^>nul') do set "PG_PARTIAL=1"
    if defined PG_PARTIAL (
        echo   [FAIL] PostgreSQL data dir exists but is not initialized: %PG_DATA_DIR%
        echo          Delete or move it away, then re-run bin\0-init.bat
        set "INIT_FAIL=1"
    ) else (
        echo   [INIT] PostgreSQL data dir: %PG_DATA_DIR%
        "%PG_HOME%\bin\initdb.exe" -D "%PG_DATA_DIR%" -U %PG_USER% -E UTF8 --locale=C
        if errorlevel 1 (
            echo   [FAIL] PostgreSQL init failed
            set "INIT_FAIL=1"
        ) else (
            echo   [ OK ] PostgreSQL data dir ready
        )
    )
)

rem ---------- Other data dirs ----------
if not exist "%MINIO_DATA_DIR%" mkdir "%MINIO_DATA_DIR%"
if not exist "%MQ_DATA_DIR%" mkdir "%MQ_DATA_DIR%"
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"

if defined INIT_FAIL (
    echo.
    echo Init failed. Fix the errors above, delete the partially created data dir, then retry.
    if /i not "%~1"=="auto" pause
    exit /b 1
)

echo.
if defined MYSQL_PWD (
    echo Done. MySQL root is passwordless now; MYSQL_PWD is applied automatically on first start.
    echo   manual: %MYSQL_HOME%\bin\mysql.exe -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%MYSQL_PWD%';"
) else (
    echo Done. MYSQL_PWD is empty, MySQL root stays without a password.
)
echo Then run bin\2-start-infra.bat and bin\3-start-apps.bat
if /i not "%~1"=="auto" pause
exit /b 0

rem  register the bundled MySQL as a Windows service so the start scripts can
rem  net start it (no console window). Needs admin rights; on failure the start
rem  scripts fall back to launching mysqld.exe directly, so this is not fatal.
rem  The service stores the exact parameters the direct start would use, so it
rem  does not depend on the bundled my.ini content.
:REGISTER_MYSQL_SERVICE
if not defined MYSQL_SERVICE_NAME set "MYSQL_SERVICE_NAME=batapp-mysql"
sc query "%MYSQL_SERVICE_NAME%" >nul 2>&1
if not errorlevel 1 (
    echo   [SKIP] MySQL service already registered: %MYSQL_SERVICE_NAME%
    exit /b 0
)
"%MYSQL_HOME%\bin\mysqld.exe" --install "%MYSQL_SERVICE_NAME%" --defaults-file="%MYSQL_CNF%" --datadir="%MYSQL_DATA_DIR%" --port=%MYSQL_PORT% >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register MySQL service %MYSQL_SERVICE_NAME% ^(needs admin^)
    echo          start scripts will launch mysqld.exe directly instead
    exit /b 0
)
echo   [ OK ] MySQL service registered: %MYSQL_SERVICE_NAME%
exit /b 0
