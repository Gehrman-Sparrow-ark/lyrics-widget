@echo off
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
    powershell -NoProfile -Command "$ws=New-Object -ComObject WScript.Shell; $l=$ws.CreateShortcut($env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\Startup\Lyrics Widget.lnk'); $l.TargetPath='%~dp0run.bat'; $l.WorkingDirectory='%~dp0'; $l.WindowStyle=7; $l.Save()"
    echo Autostart added.
)
echo.
echo Done. Start the widget with run.bat
pause
