@echo off
setlocal EnableExtensions DisableDelayedExpansion
pushd "%~dp0" || goto directory_error
if not exist ".venv\Scripts\python.exe" goto no_venv
".venv\Scripts\python.exe" "lyricswidget.py" %*
set "LW_EXIT=%ERRORLEVEL%"
popd
if "%LW_EXIT%"=="0" exit /b 0
echo Lyrics Widget exited with code %LW_EXIT%. Check the console above and the log:
echo "%LOCALAPPDATA%\lyrics-widget\lyrics-widget.log"
pause
exit /b %LW_EXIT%

:no_venv
echo Run install.bat from the extracted widget folder first.
popd
pause
exit /b 1

:directory_error
echo Could not open the extracted widget folder.
pause
exit /b 1
