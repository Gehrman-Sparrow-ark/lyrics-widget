@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
    echo Python was not found.
    echo Install Python 3.11 or 3.12 from https://www.python.org/downloads/
    echo and tick "Add python.exe to PATH", then run this file again.
    pause
    exit /b 1
)
py -m pip install -r requirements.txt
if errorlevel 1 (
    echo Install failed, see the messages above.
    pause
    exit /b 1
)
echo.
set /p AUTOSTART=Start Lyrics Widget automatically with Windows? (y/n): 
if /i "%AUTOSTART%"=="y" (
    set "LW_DIR=%~dp0"
    powershell -NoProfile -Command "$ws=New-Object -ComObject WScript.Shell; $l=$ws.CreateShortcut((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Lyrics Widget.lnk')); $l.TargetPath=(Join-Path $env:LW_DIR 'run.bat'); $l.WorkingDirectory=$env:LW_DIR; $l.WindowStyle=7; $l.Save()"
    if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Lyrics Widget.lnk" (
        echo Autostart added.
    ) else (
        echo Could not create the autostart shortcut. Press Win+R, type shell:startup and put a shortcut to run.bat there.
    )
)
echo.
echo Done. Start the widget with run.bat
pause
