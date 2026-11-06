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

set "CURL=%CURL_EXE%"
set "HAS_CURL=1"
if not exist "%CURL%" (
    set "CURL=curl.exe"
    where curl.exe >nul 2>&1
    if errorlevel 1 set "HAS_CURL="
)
if not defined HAS_CURL (
    echo   FAIL curl not found, cannot publish configs from the command line
    echo         Import the yaml files with the Nacos console instead: http://%NACOS_ADDR%/nacos
    if /i not "%~1"=="auto" pause
    exit /b 1
)
set "META=%NACOS_CONF_DIR%\nacos-meta.cfg"

echo.
echo ===== Import conf\nacos\*.yaml to Nacos =====
echo   Nacos  : http://%NACOS_ADDR%/nacos
echo   Group  : %NACOS_GROUP%
echo   Tenant : %NACOS_NAMESPACE%

netstat -ano | findstr /r /c:":%PORT_NACOS% .*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   Nacos is not running. Start it first: bin\2-start-infra.bat
    if /i not "%~1"=="auto" pause
    exit /b 1
)

set "NACOS_TOK="
if defined NACOS_USER (
    call :LOGIN
    if not defined NACOS_TOK (
        echo   FAIL cannot log in to Nacos as "%NACOS_USER%", check NACOS_USER / NACOS_PWD
        if /i not "%~1"=="auto" pause
        exit /b 1
    )
)
set "PUBURL=http://%NACOS_ADDR%/nacos/v1/cs/configs"
if defined NACOS_TOK set "PUBURL=http://%NACOS_ADDR%/nacos/v1/cs/configs?accessToken=!NACOS_TOK!"

if not exist "%NACOS_CONF_DIR%" goto :NO_FILE

set /a CNT=0
for %%E in (yaml yml properties) do (
    if exist "%NACOS_CONF_DIR%\*.%%E" (
        for %%F in ("%NACOS_CONF_DIR%\*.%%E") do set /a CNT+=1
    )
)
if %CNT%==0 goto :NO_FILE

set "FAILCNT=0"
for %%E in (yaml yml properties) do (
    if exist "%NACOS_CONF_DIR%\*.%%E" (
        for %%F in ("%NACOS_CONF_DIR%\*.%%E") do (
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
            "%CURL%" -s -f -m %IMPORT_TIMEOUT_SEC% -X POST "!PUBURL!" --data-urlencode "dataId=!DATAID!" --data-urlencode "group=!GRP!" --data-urlencode "tenant=!TEN!" --data-urlencode "type=!CFGTYPE!" --data-urlencode "content@%%~fF" >nul 2>&1
            if errorlevel 1 (echo     FAIL & set /a FAILCNT+=1) else (echo     OK)
        )
    )
)
echo.
echo   %CNT% file(s) processed, %FAILCNT% failed.
echo   Verify in console: http://%NACOS_ADDR%/nacos
if defined NACOS_USER echo   NOTE: auth is enabled, imported as "%NACOS_USER%".
if /i not "%~1"=="auto" pause
if not "%FAILCNT%"=="0" (
    echo   FAIL some configs were not published
    exit /b 1
)
exit /b 0

:NO_FILE
echo   No yaml found in %NACOS_CONF_DIR%
echo   1) Read existing configs from Nacos first:
echo      Setup.exe - Run control page - "Read Nacos"
echo   2) Or put files into %NACOS_CONF_DIR%, named like svc01-prod.yaml
if /i not "%~1"=="auto" pause
exit /b 0

rem ---------- Nacos login: get accessToken for /nacos/v1/cs/configs ----------
:LOGIN
set "NACOS_TOK="
set "LTMP=%TEMP%\nacos_login.txt"
rem  urlencode the credentials: "&", "+", "%" or space would break plain -d form data
"%CURL%" -s -m %IMPORT_TIMEOUT_SEC% -X POST "http://%NACOS_ADDR%/nacos/v1/auth/login" --data-urlencode "username=%NACOS_USER%" --data-urlencode "password=%NACOS_PWD%" > "%LTMP%" 2>nul
if not exist "%LTMP%" exit /b 0
for /f "usebackq tokens=2 delims=:," %%T in ("%LTMP%") do (
    set "TOK=%%~T"
    set "TOK=!TOK: =!"
    if not defined NACOS_TOK if /i "!TOK:~0,2!"=="ey" set "NACOS_TOK=!TOK!"
)
del "%LTMP%" >nul 2>&1
exit /b 0
