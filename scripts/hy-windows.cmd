@echo off
setlocal
set "HYDROGEN_ROOT=%~dp0.."
if /I "%~1"=="update-check" goto maintenance
if /I "%~1"=="update" goto maintenance
if /I "%~1"=="uninstall" goto maintenance
if /I "%~1"=="remove" goto maintenance
if "%~1"=="--version" (
  for /f "tokens=1,2,3" %%A in ('type "%HYDROGEN_ROOT%\BUILD-INFO.txt"') do if /I "%%A %%B"=="Hydrogen release:" echo Hydrogen %%C
  exit /b 0
)
"%HYDROGEN_ROOT%\libexec\hy-core.exe" %*
exit /b %ERRORLEVEL%
:maintenance
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HYDROGEN_ROOT%\libexec\hy-maintenance.ps1" -EntryPath "%~f0" %*
exit /b %ERRORLEVEL%
