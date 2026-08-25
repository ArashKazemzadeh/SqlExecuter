@echo off
setlocal EnableDelayedExpansion

:: ==========================================
:: SQL Server 2022 Optimized Script Runner
:: ==========================================

:MAIN_LOOP
echo.
echo ===================================================
echo   SQL Server 2022 Batch Script Executor
echo ===================================================
echo.

set /p SERVER=Enter SQL SERVER NAME (e.g., . or localhost or SERVER\INSTANCE): 
if "%SERVER%"=="" (
    echo Server name cannot be empty.
    goto MAIN_LOOP
)

:: --- Authentication Selection ---
set AUTH_TYPE=Y
set /p AUTH_TYPE=Use Windows Authentication? (Y=default, N for SQL Login): 
if /I "%AUTH_TYPE%"=="N" (
    set /p SQL_USER=Enter SQL Login: 
    set /p SQL_PASS=Enter SQL Password: 
    set AUTH_PARAMS=-U "%SQL_USER%" -P "%SQL_PASS%"
) else (
    set AUTH_PARAMS=-E
)

echo.
set /p DBNAME=Enter DATABASE NAME (type 'exit' to quit): 
if /I "%DBNAME%"=="exit" goto :EOF

echo.

:: Check database existence 
:: -C : TrustServerCertificate (Crucial for SQL 2022 TLS/Encryption defaults)
sqlcmd -S "%SERVER%" -d master %AUTH_PARAMS% -C -b -Q "IF DB_ID(N'%DBNAME%') IS NULL RAISERROR('DB_NOT_FOUND',16,1)" >nul 2>&1

if errorlevel 1 (
    echo.
    echo ERROR: Database "%DBNAME%" does NOT exist on server "%SERVER%".
    echo.
    goto MAIN_LOOP
)

set /p FOLDER=Enter SCRIPTS FOLDER PATH (example: C:\SqlScripts): 
if "%FOLDER%"=="" (
    echo Folder path cannot be empty.
    goto MAIN_LOOP
)

if not exist "%FOLDER%" (
    echo Folder not found: %FOLDER%
    goto MAIN_LOOP
)

set FAILED_LIST=%TEMP%\sql_failed_%RANDOM%.txt
set STILL_FAILED=%TEMP%\sql_still_failed_%RANDOM%.txt
if exist "%FAILED_LIST%" del "%FAILED_LIST%"
if exist "%STILL_FAILED%" del "%STILL_FAILED%"

echo.
echo ===== Running SQL scripts on %SERVER%\%DBNAME% =====

:: -C : Trust Server Certificate (Prevents TLS 1.2/1.3 handshake failures in 2022)
:: -t 0 : No query timeout (Prevents long scripts from failing)
:: -I  : Enables QUOTED_IDENTIFIER (Best practice for SQL scripts)

for %%F in ("%FOLDER%\*.sql") do (
    echo RUN %%F
    sqlcmd -S "%SERVER%" -d "%DBNAME%" %AUTH_PARAMS% -C -t 0 -i "%%F" -I
    if errorlevel 1 (
        echo ERROR %%F
        echo %%F>>"%FAILED_LIST%"
    )
)

if not exist "%FAILED_LIST%" (
    echo.
    echo All scripts executed successfully.
    goto END_RUN
)

echo.
echo ===== Re-running failed scripts =====

:: Fix for time formatting (e.g., changing 9:05:00 to 09:05:00)
set LOGFILE=%FOLDER%\sql_errors_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.txt
set LOGFILE=%LOGFILE: =0%

for /f "usebackq delims=" %%F in ("%FAILED_LIST%") do (
    echo RUN (retry) %%F
    sqlcmd -S "%SERVER%" -d "%DBNAME%" %AUTH_PARAMS% -C -t 0 -i "%%F" -I > "%TEMP%\sql_output.txt" 2>&1
    if errorlevel 1 (
        echo ERROR (retry) %%F
        echo %%F>>"%STILL_FAILED%"

        echo ==================================================================================>>"%LOGFILE%"
        echo FILE: %%F>>"%LOGFILE%"
        echo DATE: %DATE% %TIME%>>"%LOGFILE%"
        echo SERVER: %SERVER%>>"%LOGFILE%"
        echo DB:     %DBNAME%>>"%LOGFILE%"
        echo OUTPUT:>>"%LOGFILE%"
        type "%TEMP%\sql_output.txt">>"%LOGFILE%"
    )
)

if exist "%STILL_FAILED%" (
    echo.
    echo Some scripts still failed.
    echo Errors saved to:
    echo %LOGFILE%
) else (
    echo.
    echo All previously failed scripts succeeded on retry.
)

:END_RUN
echo.
pause
goto MAIN_LOOP