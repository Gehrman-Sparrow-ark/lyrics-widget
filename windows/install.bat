@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "LW_NONINTERACTIVE="
if /I "%~1"=="--no-autostart" set "LW_NONINTERACTIVE=1"
if not "%~1"=="" if not defined LW_NONINTERACTIVE goto usage
if not "%~2"=="" goto usage

pushd "%~dp0" || goto directory_error
set "LW_ROOT=%~dp0"
set "LW_PY=.venv\Scripts\python.exe"
set "PYCHECK=import sys, sysconfig; sys.exit(not (sys.implementation.name == 'cpython' and sys.version_info[:2] in ((3, 11), (3, 12)) and sysconfig.get_platform() == 'win-amd64'))"

if exist "%LW_PY%" goto check_venv
if exist ".venv" goto invalid_venv
where py >nul 2>&1 || goto no_python
py -3.12 -I -c "%PYCHECK%" >nul 2>&1
if not errorlevel 1 goto py312
py -3.11 -I -c "%PYCHECK%" >nul 2>&1
if errorlevel 1 goto no_python
set "LW_VERSION=-3.11"
goto create_venv

:py312
set "LW_VERSION=-3.12"

:create_venv
py %LW_VERSION% -I -m venv ".venv"
if errorlevel 1 goto failed

:check_venv
"%LW_PY%" -I -c "%PYCHECK%" >nul 2>&1 || goto invalid_venv
"%LW_PY%" -I -c "import sys; sys.exit(sys.prefix == sys.base_prefix)" >nul 2>&1 || goto invalid_venv
if not exist ".venv\Scripts\pythonw.exe" goto invalid_venv
rem Repair a compatible virtual environment left without pip.
"%LW_PY%" -I -m pip --version >nul 2>&1
if not errorlevel 1 goto install_dependencies
echo pip is missing or unusable. Repairing pip in .venv...
"%LW_PY%" -I -m ensurepip --upgrade
if errorlevel 1 goto no_pip
"%LW_PY%" -I -m pip --version >nul 2>&1
if errorlevel 1 goto no_pip

:install_dependencies
"%LW_PY%" -I -m pip --isolated --disable-pip-version-check install --require-hashes --only-binary=:all: -r requirements.txt
if errorlevel 1 goto failed
"%LW_PY%" -I -m pip --isolated --disable-pip-version-check check
if errorlevel 1 goto failed
"%LW_PY%" -I -c "from PySide6 import QtCore, QtGui, QtQml, QtWidgets; from winrt.windows.media.control import GlobalSystemMediaTransportControlsSessionManager"
if errorlevel 1 goto failed

if defined LW_NONINTERACTIVE goto installed
echo.
choice /C YN /N /M "Start Lyrics Widget automatically with Windows? [Y/N] "
if errorlevel 3 goto autostart_error
if errorlevel 2 goto installed
if not errorlevel 1 goto installed
call :create_autostart
if errorlevel 1 goto autostart_error
echo Verified Startup shortcut.

:installed
echo.
echo Dependencies installed in .venv. Start Lyrics Widget with run.bat.
popd
if not defined LW_NONINTERACTIVE pause
exit /b 0

:create_autostart
powershell -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; $root=[IO.Path]::GetFullPath($env:LW_ROOT); $drive=New-Object System.IO.DriveInfo ([IO.Path]::GetPathRoot($root)); if ($drive.DriveType -ne 'Fixed') { throw 'Autostart requires a folder on a local fixed drive.' }; $startup=[Environment]::GetFolderPath('Startup'); if (-not $startup -or -not (Test-Path -LiteralPath $startup -PathType Container)) { throw 'Could not locate the Startup folder.' }; $launcher=Join-Path $root '.venv\Scripts\pythonw.exe'; $widget=Join-Path $root 'lyricswidget.py'; if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or -not (Test-Path -LiteralPath $widget -PathType Leaf)) { throw 'Widget or launcher is missing.' }; $argument=[string][char]34+$widget+[char]34; $link=Join-Path $startup 'Lyrics Widget.lnk'; $shell=New-Object -ComObject WScript.Shell; $shortcut=$shell.CreateShortcut($link); $shortcut.TargetPath=$launcher; $shortcut.Arguments=$argument; $shortcut.WorkingDirectory=$root; $shortcut.WindowStyle=7; $shortcut.Save(); if (-not (Test-Path -LiteralPath $link -PathType Leaf)) { throw 'Shortcut was not saved.' }; $actual=$shell.CreateShortcut($link); if ($actual.TargetPath -ne $launcher -or $actual.Arguments -ne $argument -or $actual.WorkingDirectory.TrimEnd([char]92) -ne $root.TrimEnd([char]92)) { throw 'Saved shortcut does not match this installation.' }"
exit /b %ERRORLEVEL%

:autostart_error
echo Dependencies installed, but autostart could not be verified. Run run.bat manually.
popd
pause
exit /b 2

:no_python
echo Install 64-bit CPython 3.11 or 3.12 with the Python launcher from https://www.python.org/downloads/ and retry.
goto failed

:invalid_venv
echo This folder has an incompatible or incomplete .venv. Rename it and rerun install.bat.
goto failed

:no_pip
echo Python could not install pip into .venv.
echo Run the python.org installer for Python 3.12 or 3.11, choose Modify and make sure pip is ticked.
echo Then rename .venv to .venv-broken and run install.bat again.
goto failed

:directory_error
echo Could not open the extracted widget folder.
if not defined LW_NONINTERACTIVE pause
exit /b 1

:usage
echo Usage: install.bat [--no-autostart]
exit /b 2

:failed
echo Install failed. See the error above.
popd
if not defined LW_NONINTERACTIVE pause
exit /b 1
