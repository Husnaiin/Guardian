@echo off
REM Guardian Drone Controller - Quick Setup Script (Windows)
REM This script helps you set up and run the Flutter app and Pi backend

echo 🔥 Guardian Drone Controller - Quick Setup
echo ===========================================

REM Check if Flutter is installed
flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Flutter is not installed. Please install Flutter first:
    echo    https://docs.flutter.dev/get-started/install
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('flutter --version') do (
    echo ✅ Flutter found: %%i
    goto :break
)
:break

echo.
echo 🔍 Running Flutter doctor...
flutter doctor

echo.
echo 📦 Getting Flutter dependencies...
flutter pub get

if %errorlevel% equ 0 (
    echo ✅ Dependencies installed successfully
) else (
    echo ❌ Failed to install dependencies
    pause
    exit /b 1
)

echo.
echo 📱 Checking for connected devices...
flutter devices

echo.
echo What would you like to do?
echo 1) Run Flutter app on connected device
echo 2) Set up Raspberry Pi backend
echo 3) Both
echo 4) Exit
set /p choice=Enter your choice (1-4): 

if "%choice%"=="1" (
    echo.
    echo 🚀 Running Flutter app...
    flutter run
) else if "%choice%"=="2" (
    echo.
    echo 🥧 Setting up Raspberry Pi backend...
    if exist "pi_backend" (
        cd pi_backend
        echo Installing Python dependencies...
        pip3 install -r requirements.txt
        echo.
        echo ✅ Backend setup complete!
        echo To run the backend:
        echo    cd pi_backend
        echo    python3 drone_controller.py
        cd ..
    ) else (
        echo ❌ pi_backend directory not found
    )
) else if "%choice%"=="3" (
    echo.
    echo 🥧 Setting up Raspberry Pi backend...
    if exist "pi_backend" (
        cd pi_backend
        pip3 install -r requirements.txt
        cd ..
        echo ✅ Backend setup complete!
    )
    echo.
    echo 🚀 Running Flutter app...
    flutter run
) else if "%choice%"=="4" (
    echo 👋 Goodbye!
    exit /b 0
) else (
    echo ❌ Invalid choice
    pause
    exit /b 1
)

echo.
echo 🎉 Setup complete!
echo.
echo 📋 Next steps:
echo 1. If running on Pi: Start the backend with 'python3 pi_backend/drone_controller.py'
echo 2. Open the app on your device
echo 3. Enter your Raspberry Pi's IP address (find it with: hostname -I)
echo 4. Tap 'Connect' and start controlling your drone!
echo.
echo 🔗 For more help, check the README.md file
pause 