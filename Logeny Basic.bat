@echo off
echo Starting Logeny Basic...
echo.

REM --- Set the R_LIBS_USER environment variable (important for R to find libraries) ---
set "R_LIBS_USER=%USERPROFILE%\R\win-library\4.5"
echo [DEBUG] Setting R_LIBS_USER to: "%R_LIBS_USER%"

REM --- Check for R in system PATH (again, in case it wasn't there before) ---
echo Checking for R...
where Rscript
if %errorlevel% neq 0 (
    echo [ERROR] R not found in your system's PATH.
    echo        Please run Logeny_Install.bat first to ensure R is set up correctly.
    pause
    exit /b 1
)
echo [DEBUG] Found R in system PATH.

REM --- Check if app.R exists ---
if not exist "app.R" (
    echo [ERROR] The app.R file does not exist in the current directory.
    echo         Please ensure app.R is in the same directory as this .bat file.
    pause
    exit /b 1
)
echo [DEBUG] app.R file exists.

REM --- Run the Shiny app using Rscript ---
echo [DEBUG] Attempting to run the Shiny app with:
echo         Rscript: Rscript
echo         Command: -e "shiny::runApp('./', launch.browser = TRUE, host = '127.0.0.1')"
Rscript -e "shiny::runApp('./', launch.browser = TRUE, host = '127.0.0.1')"

echo [DEBUG] Shiny app command executed. Checking for potential errors...
if %errorlevel% neq 0 (
    echo [ERROR] The R script execution returned an error.
    echo        Please check your R installation and app.R code.
    pause
    exit /b 1
) else (
    echo [DEBUG] Shiny app should be starting...
)

echo.
echo Logeny Basic started. The application should open in your default web browser.
pause
exit /b 0