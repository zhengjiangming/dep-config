@echo off
setlocal
call "%~dp0..\conf\env.bat"
title First-time init
echo.
echo ===== First-time init (run once) =====

rem ---------- MySQL ----------
if exist "%DATA_DIR%\mysql" (
    echo   [SKIP] MySQL data dir already exists
) else (
    echo   [INIT] MySQL data dir ...
    "%MYSQL_HOME%\bin\mysqld.exe" --defaults-file="%MYSQL_HOME%\my.ini" --initialize-insecure --console
)

rem ---------- PostgreSQL ----------
if exist "%DATA_DIR%\pg" (
    echo   [SKIP] PostgreSQL data dir already exists
) else (
    echo   [INIT] PostgreSQL data dir ...
    "%PG_HOME%\bin\initdb.exe" -D "%DATA_DIR%\pg" -U postgres -E UTF8 --locale=C
)

rem ---------- Other data dirs ----------
if not exist "%MINIO_DATA_DIR%" mkdir "%MINIO_DATA_DIR%"
if not exist "%DATA_DIR%\rocketmq" mkdir "%DATA_DIR%\rocketmq"
if not exist "%GEOSERVER_DATA_DIR%" mkdir "%GEOSERVER_DATA_DIR%"

echo.
echo Done. MySQL root has no password at first boot, run once:
echo   %MYSQL_HOME%\bin\mysql.exe -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%MYSQL_PWD%';"
echo Then run bin\2-start-infra.bat and bin\3-start-apps.bat
pause
exit /b 0
