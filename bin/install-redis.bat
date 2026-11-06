@echo off
setlocal
rem  register the configured Redis as an auto-start Windows service
rem  binPath = redis-server.exe --service-run <REDIS_CNF> --service-name redis-server
rem  needs admin rights; on failure the start scripts still launch
rem  redis-server.exe directly, so this step is not fatal.
call "%~dp0..\conf\env.bat"
if errorlevel 1 exit /b 1

if not exist "%REDIS_HOME%\redis-server.exe" (
    echo   [SKIP] redis-server.exe not found: %REDIS_HOME%\redis-server.exe
    exit /b 0
)
if not exist "%REDIS_CNF%" (
    echo   [SKIP] redis config not found: %REDIS_CNF%
    exit /b 0
)
sc query redis-server >nul 2>&1
if not errorlevel 1 (
    echo   [SKIP] Redis service already registered: redis-server
    exit /b 0
)
"%REDIS_HOME%\redis-server.exe" --service-install "%REDIS_CNF%" --service-name redis-server >nul 2>&1
if errorlevel 1 (
    echo   [WARN] cannot register Redis service redis-server ^(needs admin^)
    echo          start scripts will launch redis-server.exe directly instead
    exit /b 0
)
sc config redis-server start= auto >nul 2>&1
echo   [ OK ] Redis service registered: redis-server, auto start
exit /b 0
