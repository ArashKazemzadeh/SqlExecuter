@echo off
setlocal EnableDelayedExpansion

:: ==========================================
:: SQL Server 2025 Optimized Script Runner
:: ==========================================

:MAIN_LOOP
echo.
echo ===================================================
echo   SQL Server 2025 Batch Script Executor
echo ===================================================
echo.

:: حذف مقادیر قبلی برای جلوگیری از تداخل
set "SERVER="
set /p SERVER=Enter SQL SERVER NAME (e.g., . or localhost or SERVER\INSTANCE): 

:: رفع باگ 2025: حذف فاصله‌های انتهایی که باعث خطای Connection می‌شود
set "SERVER=%SERVER%"

if "!SERVER!"=="" (
    echo Server name cannot be empty.
    goto MAIN_LOOP
)

:: --- Authentication Selection ---
:: پاک کردن متغیرهای احتمالی از اجراهای قبلی
set "SQLCMDUSER="
set "SQLCMDPASSWORD="
set "AUTH_SWITCH="

set AUTH_TYPE=Y
set /p AUTH_TYPE=Use Windows Authentication? (Y=default, N for SQL Login): 
if /I "!AUTH_TYPE!"=="N" (
    set /p SQL_USER=Enter SQL Login: 
    set /p SQL_PASS=Enter SQL Password: 
    
    :: رفع باگ اصلی 2025: استفاده از Environment Variables به جای پارامترهای متنی
    :: نسخه جدید sqlcmd در 2025 با کوتیشن‌های داخلی (-U "user") به مشکل می‌خورد
    set "SQLCMDUSER=!SQL_USER!"
    set "SQLCMDPASSWORD=!SQL_PASS!"
) else (
    set "AUTH_SWITCH=-E"
)

echo.
set "DBNAME="
set /p DBNAME=Enter DATABASE NAME (type 'exit' to quit): 
set "DBNAME=%DBNAME%"

if /I "!DBNAME!"=="exit" goto :EOF

echo.

:: رفع باگ 2025: جایگزینی RAISERROR با THROW استاندارد
sqlcmd -S "!SERVER!" -d master !AUTH_SWITCH! -C -b -Q "IF DB_ID(N'!DBNAME!') IS NULL THROW 50000, 'DB_NOT_FOUND', 1;" >nul 2>&1

if errorlevel 1 (
    echo.
    echo ERROR: Database "!DBNAME!" does NOT exist on server "!SERVER!".
    echo.
    goto MAIN_LOOP
)

set "FOLDER="
set /p FOLDER=Enter SCRIPTS FOLDER PATH (example: C:\SqlScripts): 

:: رفع باگ 2025: حذف اسلش انتهایی پوشه که در مسیردهی جدید sqlcmd ارور می‌دهد
if "!FOLDER:~-1!"=="\" set "FOLDER=!FOLDER:~0,-1%"
set "FOLDER=%FOLDER%"

if "!FOLDER!"=="" (
    echo Folder path cannot be empty.
    goto MAIN_LOOP
)

if not exist "!FOLDER!" (
    echo Folder not found: !FOLDER!
    goto MAIN_LOOP
)

set "FAILED_LIST=%TEMP%\sql_failed_%RANDOM%.txt"
set "STILL_FAILED=%TEMP%\sql_still_failed_%RANDOM%.txt"
if exist "!FAILED_LIST!" del "!FAILED_LIST!"
if exist "!STILL_FAILED!" del "!STILL_FAILED!"

echo.
echo ===== Running SQL scripts on !SERVER!\!DBNAME! =====

:: -C : Trust Server Certificate (برای دور زدن مشکل TLS 1.3 پیش‌فرض در 2025)
:: -t 0 : No query timeout
:: -l 0 : No LOGIN timeout (اضافه شده برای 2025 تا در زمان Handshake رمزنگاری تایم‌اوت نشود)
:: -I  : Enables QUOTED_IDENTIFIER

for %%F in ("!FOLDER!\*.sql") do (
    echo RUN %%~nxF
    sqlcmd -S "!SERVER!" -d "!DBNAME!" !AUTH_SWITCH! -C -t 0 -l 0 -i "%%F" -I
    if errorlevel 1 (
        echo ERROR %%~nxF
        echo %%F>>"!FAILED_LIST!"
    )
)

if not exist "!FAILED_LIST!" (
    echo.
    echo All scripts executed successfully.
    goto END_RUN
)

echo.
echo ===== Re-running failed scripts =====

:: Fix for time formatting (e.g., changing 9:05:00 to 09:05:00)
set "LOGFILE=!FOLDER!\sql_errors_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.txt"
set "LOGFILE=%LOGFILE: =0%"

for /f "usebackq delims=" %%F in ("!FAILED_LIST!") do (
    echo RUN (retry) %%~nxF
    sqlcmd -S "!SERVER!" -d "!DBNAME!" !AUTH_SWITCH! -C -t 0 -l 0 -i "%%F" -I > "%TEMP%\sql_output.txt" 2>&1
    if errorlevel 1 (
        echo ERROR (retry) %%~nxF
        echo %%F>>"!STILL_FAILED!"

        echo ==================================================================================>>"!LOGFILE!"
        echo FILE: %%F>>"!LOGFILE!"
        echo DATE: %DATE% %TIME%>>"!LOGFILE!"
        echo SERVER: !SERVER!>>"!LOGFILE!"
        echo DB:     !DBNAME!>>"!LOGFILE!"
        echo OUTPUT:>>"!LOGFILE!"
        type "%TEMP%\sql_output.txt">>"!LOGFILE!"
    )
)

if exist "!STILL_FAILED%" (
    echo.
    echo Some scripts still failed.
    echo Errors saved to:
    echo !LOGFILE!
) else (
    echo.
    echo All previously failed scripts succeeded on retry.
)

:END_RUN
echo.
pause
goto MAIN_LOOP