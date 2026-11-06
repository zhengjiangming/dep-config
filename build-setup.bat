@echo off
rem =====================================================================
rem  Build the GUI installer / manager: Setup.exe (package root).
rem  Requires .NET Framework 4.x (csc.exe is bundled with Windows).
rem  Sources: installer\Program.cs, installer\ConfigStore.cs, installer\MainForm.cs
rem =====================================================================
setlocal
cd /d "%~dp0"

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" goto :NO_CSC
if not exist "installer\Program.cs" goto :NO_SRC

echo Compiling with %CSC% ...
set "ICON=installer\app.ico"
if not exist "%ICON%" (
    echo Generating app icon ...
    "%CSC%" /nologo /target:exe /out:makeicon.exe installer\MakeIcon.cs
    if errorlevel 1 goto :FAIL
    makeicon.exe "%ICON%"
    if errorlevel 1 goto :FAIL
)
rem  the manifest makes the tool ask for administrator rights: stop / firewall /
rem  taskkill must run elevated to touch services started by another account
"%CSC%" /nologo /target:winexe /win32icon:%ICON% /win32manifest:"installer\Setup.exe.manifest" /out:Setup.exe /r:System.Windows.Forms.dll /r:System.Drawing.dll installer\Program.cs installer\ConfigStore.cs installer\Theme.cs installer\MainForm.cs
if errorlevel 1 goto :FAIL

echo.
echo Built: %CD%\Setup.exe
echo Run it to install, edit configs and control services.
pause
exit /b 0

:NO_CSC
echo .NET Framework 4.x csc.exe not found. Install .NET Framework 4.x first.
pause
exit /b 1

:NO_SRC
echo installer\Program.cs not found, run this from the package root.
pause
exit /b 1

:FAIL
echo.
echo Build failed. Fix the compile errors above.
pause
exit /b 1
