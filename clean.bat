@echo off
flutter clean
rmdir /s /q .dart_tool
rmdir /s /q build
flutter pub get
pause
