@echo off
rem =====================================================================
rem  Open the configured inbound TCP ports in Windows Firewall.
rem  Usage: 10-firewall.bat [auto]   (auto = no pause)
rem  Rule name comes from FIREWALL_RULE_NAME (default bat_application).
rem =====================================================================
setlocal
call "%~dp0..\conf\env.bat"
title Firewall rules
set "NO_PAUSE="
if /i "%~1"=="auto" set "NO_PAUSE=1"

set "PLIST=%PORT_MYSQL%,%PORT_PG%,%PORT_REDIS%,%PORT_MINIO%,%PORT_MINIO_CONSOLE%,%PORT_MQ_NAMESRV%,%PORT_MQ_BROKER%,%PORT_MQ_VIP%,%PORT_MQ_HA%,%PORT_NACOS%,%PORT_NACOS_CLUSTER%,%PORT_NACOS_CLUSTER2%,%PORT_GEOSERVER%,%PORT_NGINX%"

echo.
echo ===== Windows Firewall =====
echo   Rule  : %FIREWALL_RULE_NAME%
echo   Ports : %PLIST%

rem deleting the old rule first would leave the host with no rule at all when the
rem "add" that follows fails (not elevated), so check the rights up front
fltmc filters >nul 2>&1
if errorlevel 1 (
    echo   WARN not running as administrator, existing firewall rule left untouched.
    echo        Right-click this script and choose "Run as administrator".
    if not defined NO_PAUSE pause
    exit /b 1
)

rem drop the previous rule of the same name so re-running never duplicates it
netsh advfirewall firewall delete rule name="%FIREWALL_RULE_NAME%" >nul 2>&1
netsh advfirewall firewall add rule name="%FIREWALL_RULE_NAME%" dir=in action=allow protocol=TCP localport=%PLIST% >nul 2>&1
if errorlevel 1 (
    echo   WARN firewall rule not added. Right-click this script and choose "Run as administrator".
    if not defined NO_PAUSE pause
    exit /b 1
)

echo   OK   TCP ports opened.
if not defined NO_PAUSE pause
exit /b 0
