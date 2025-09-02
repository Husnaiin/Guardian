#!/bin/bash

# Guardian Drone Controller - Quick Setup Script
# This script helps you set up and run the Flutter app and Pi backend

echo "🔥 Guardian Drone Controller - Quick Setup"
echo "==========================================="

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first:"
    echo "   https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -n 1)"

# Check Flutter doctor
echo ""
echo "🔍 Running Flutter doctor..."
flutter doctor

# Get Flutter dependencies
echo ""
echo "📦 Getting Flutter dependencies..."
flutter pub get

if [ $? -eq 0 ]; then
    echo "✅ Dependencies installed successfully"
else
    echo "❌ Failed to install dependencies"
    exit 1
fi

# Check for connected devices
echo ""
echo "📱 Checking for connected devices..."
flutter devices

# Ask user what they want to do
echo ""
echo "What would you like to do?"
echo "1) Run Flutter app on connected device"
echo "2) Set up Raspberry Pi backend"
echo "3) Both"
echo "4) Exit"
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        echo ""
        echo "🚀 Running Flutter app..."
        flutter run
        ;;
    2)
        echo ""
        echo "🥧 Setting up Raspberry Pi backend..."
        if [ -d "pi_backend" ]; then
            cd pi_backend
            echo "Installing Python dependencies..."
            pip3 install -r requirements.txt
            echo ""
            echo "✅ Backend setup complete!"
            echo "To run the backend:"
            echo "   cd pi_backend"
            echo "   python3 drone_controller.py"
        else
            echo "❌ pi_backend directory not found"
        fi
        ;;
    3)
        echo ""
        echo "🥧 Setting up Raspberry Pi backend..."
        if [ -d "pi_backend" ]; then
            cd pi_backend
            pip3 install -r requirements.txt
            cd ..
            echo "✅ Backend setup complete!"
        fi
        echo ""
        echo "🚀 Running Flutter app..."
        flutter run
        ;;
    4)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "🎉 Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. If running on Pi: Start the backend with 'python3 pi_backend/drone_controller.py'"
echo "2. Open the app on your device"
echo "3. Enter your Raspberry Pi's IP address (find it with: hostname -I)"
echo "4. Tap 'Connect' and start controlling your drone!"
echo ""
echo "🔗 For more help, check the README.md file" 