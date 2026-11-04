@echo off
setlocal
call "%~dp0..\conf\env.bat"
title Reload Nginx
if not exist "%NGINX_HOME%\nginx.exe" (
    echo nginx not found: %NGINX_HOME%
    exit /b 1
)
if not exist "%NGINX_CONF%" (
    echo nginx.conf not found: %NGINX_CONF%
    exit /b 1
)
echo Reloading Nginx with %NGINX_CONF% ...
"%NGINX_HOME%\nginx.exe" -p "%NGINX_HOME%" -c "%NGINX_CONF%" -s reload
if errorlevel 1 (
    echo Reload failed. Start Nginx first with bin\2-start-infra.bat
    exit /b 1
)
echo OK
exit /b 0
