@echo off
echo Starting Logeny Installation...
echo.

REM --- Set the R_LIBS_USER environment variable ---
set "R_LIBS_USER=%USERPROFILE%\R\win-library\4.5"
echo [DEBUG] Setting R_LIBS_USER to: "%R_LIBS_USER%"

REM --- Check for R in system PATH ---
echo Checking for R...
where Rscript
if %errorlevel% neq 0 (
    echo [ERROR] R not found in your system's PATH.
    echo        Please install R from https://www.r-project.org/
    echo        and ensure it is added to your system's PATH.
    pause
    exit /b 1
)
echo [DEBUG] Found R in system PATH.

REM --- Run install_packages.R ---
echo Running install_packages.R to install necessary R and Python packages...
Rscript "Logeny\install_packages.R"
if %errorlevel% neq 0 (
    echo [ERROR] Failed during package installation. Please check the output above for details.
    echo        Logeny Basic cannot start without these packages.
    pause
    exit /b 1
)
echo [DEBUG] Package installation completed successfully.

echo.
echo Installation complete. You can now run Logeny Basic by executing "Logeny Basic.bat".
pause
exit /b 0