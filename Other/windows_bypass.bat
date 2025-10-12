@echo off
echo Windows Setup Bypass Script
echo ==========================
echo.
echo This script will:
echo 1. Create a new user account with admin privileges
echo 2. Disable default accounts
echo 3. Modify registry to skip OOBE
echo 4. Restart the computer
echo.
echo WARNING: This script requires administrator privileges!
echo.

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running with administrator privileges...
) else (
    echo ERROR: This script must be run as administrator!
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo.
echo Creating new user account...
echo Please enter a username for the new account:
set /p NEW_USERNAME=Username: 

if "%NEW_USERNAME%"=="" (
    echo ERROR: Username cannot be empty!
    pause
    exit /b 1
)

echo.
echo Please enter a password for the new account:
set /p NEW_PASSWORD=Password: 

if "%NEW_PASSWORD%"=="" (
    echo ERROR: Password cannot be empty!
    pause
    exit /b 1
)

echo.
echo Creating user account: %NEW_USERNAME%
net user "%NEW_USERNAME%" "%NEW_PASSWORD%" /add
if %errorLevel% neq 0 (
    echo ERROR: Failed to create user account!
    pause
    exit /b 1
)

echo Adding user to administrators group...
net localgroup administrators "%NEW_USERNAME%" /add
if %errorLevel% neq 0 (
    echo ERROR: Failed to add user to administrators group!
    pause
    exit /b 1
)

echo Activating user account...
net user "%NEW_USERNAME%" /active:yes
if %errorLevel% neq 0 (
    echo ERROR: Failed to activate user account!
    pause
    exit /b 1
)

echo Setting account to never expire...
net user "%NEW_USERNAME%" /expires:never
if %errorLevel% neq 0 (
    echo ERROR: Failed to set account expiration!
    pause
    exit /b 1
)

echo.
echo Disabling default accounts...
echo Disabling Administrator account...
net user "Administrator" /active:no

echo Attempting to delete defaultUser0 account...
net user "defaultUser0" /delete 2>nul
if %errorLevel% == 0 (
    echo Successfully deleted defaultUser0 account.
) else (
    echo defaultUser0 account not found or already deleted.
)

echo.
echo Verifying user accounts...
echo Current user accounts:
net user

echo.
echo Modifying registry to skip OOBE...
echo Opening registry editor...

REM Create a temporary registry file
echo Windows Registry Editor Version 5.00 > %temp%\oobe_bypass.reg
echo. >> %temp%\oobe_bypass.reg
echo [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE] >> %temp%\oobe_bypass.reg
echo "SkipMachineOOBE"=dword:00000001 >> %temp%\oobe_bypass.reg

REM Import the registry file
regedit /s %temp%\oobe_bypass.reg
if %errorLevel% neq 0 (
    echo ERROR: Failed to modify registry!
    pause
    exit /b 1
)

REM Clean up temporary registry file
del %temp%\oobe_bypass.reg

echo.
echo Deleting DefaultAccount registry entries...
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v "DefaultAccountAction" /f 2>nul
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v "DefaultAccountSAMName" /f 2>nul
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v "DefaultAccountSID" /f 2>nul

echo.
echo ==========================
echo Setup completed successfully!
echo ==========================
echo.
echo New user account created: %NEW_USERNAME%
echo Default accounts have been disabled/removed
echo Registry has been modified to skip OOBE
echo.
echo The computer will restart in 10 seconds...
echo Press Ctrl+C to cancel the restart.
echo.

timeout /t 10 /nobreak >nul

echo Restarting computer...
shutdown /r /t 0
