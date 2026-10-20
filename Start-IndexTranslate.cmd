@echo off
where py >nul 2>nul
if not errorlevel 1 (
    py -3 -I "%~dp0scripts\launch.py"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python 3 was not found. Install Python and enable "Add python.exe to PATH".
    ) else (
        python -I "%~dp0scripts\launch.py"
    )
)
pause
