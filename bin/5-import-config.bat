@echo off
rem =====================================================================
rem  Push every conf\nacos\*.yaml into Nacos as a config.
rem  File name = dataId, e.g.  svc01-prod.yaml
rem  Run this AFTER infrastructure is up (bin\2-start-infra.bat).
rem  Namespace must exist first, with ID equal to NACOS_NAMESPACE.
rem =====================================================================
setlocal enabledelayedexpansion
call "%~dp0..\conf\env.bat"
title Import Nacos configs

set "CURL=%APP_HOME%\runtime\curl\curl.exe"
if not exist "%CURL%" set "CURL=curl.exe"
set "META=%APP_HOME%\conf\nacos\nacos-meta.cfg"

echo.
echo ===== Import conf\nacos\*.yaml to Nacos =====
echo   Nacos  : http://%NACOS_ADDR%/nacos
echo   Group  : %NACOS_GROUP%
echo   Tenant : %NACOS_NAMESPACE%

netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   Nacos is not running. Start it first: bin\2-start-infra.bat
    pause
    exit /b 1
)

if not exist "%APP_HOME%\conf\nacos" goto :NO_FILE

set /a CNT=0
for %%E in (yaml yml properties) do (
    if exist "%APP_HOME%\conf\nacos\*.%%E" (
        for %%F in ("%APP_HOME%\conf\nacos\*.%%E") do set /a CNT+=1
    )
)
if %CNT%==0 goto :NO_FILE

set "FAILCNT=0"
for %%E in (yaml yml properties) do (
    if exist "%APP_HOME%\conf\nacos\*.%%E" (
        for %%F in ("%APP_HOME%\conf\nacos\*.%%E") do (
            set "CFGTYPE=yaml"
            if /i "%%~xF"==".properties" set "CFGTYPE=properties"
            set "DATAID=%%~nxF"
            set "GRP=%NACOS_GROUP%"
            set "TEN=%NACOS_NAMESPACE%"
            if exist "%META%" (
                for /f "usebackq eol=# tokens=1-4 delims=|" %%A in ("%META%") do (
                    if /i "%%A"=="%%~nxF" (
                        if not "%%B"=="" set "DATAID=%%B"
                        if not "%%C"=="" set "GRP=%%C"
                        if not "%%D"=="" set "TEN=%%D"
                    )
                )
            )
            echo   publish %%~nxF ... [dataId=!DATAID! type=!CFGTYPE!]
            "%CURL%" -s -f -m 20 -X POST "http://%NACOS_ADDR%/nacos/v1/cs/configs" -d "dataId=!DATAID!" -d "group=!GRP!" -d "tenant=!TEN!" -d "type=!CFGTYPE!" --data-urlencode "content@%%~fF" >nul 2>&1
            if errorlevel 1 (echo     FAIL & set /a FAILCNT+=1) else (echo     OK)
        )
    )
)
echo.
echo   %CNT% file(s) processed, %FAILCNT% failed.
echo   Verify in console: http://%NACOS_ADDR%/nacos
if defined NACOS_USER echo   NOTE: auth is enabled. If publish failed, import via Nacos console instead.
if /i not "%~1"=="auto" pause
if not "%FAILCNT%"=="0" (
    echo   FAIL some configs were not published
    exit /b 1
)
exit /b 0

:NO_FILE
echo   No yaml found in conf\nacos\
echo   1) Read existing configs from Nacos first:
echo      Setup.exe - Run control page - "Read Nacos"
echo   2) Or put files into conf\nacos\, named like svc01-prod.yaml
pause
exit /b 0
