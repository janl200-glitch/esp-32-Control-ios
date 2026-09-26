# ESP32 Control Center for iPhone

A SwiftUI iPhone app for controlling and monitoring the ESP32 web server.

## App name
The iOS Home Screen name is **ESP32 Control**.

## App icon
The project includes the generated ESP32/Wi-Fi neon icon in `ESP32ControlCenter/Assets.xcassets/AppIcon.appiconset`.

## Build with GitHub Actions
1. Upload the complete project to a GitHub repository.
2. Open **Actions**.
3. Run **Build unsigned iOS app**.
4. Download the `ESP32ControlCenter-iOS-unsigned` artifact.
5. Sign the resulting IPA with your signing service/certificate.

The app uses the ESP32 HTTP API implemented by the supplied server code.
