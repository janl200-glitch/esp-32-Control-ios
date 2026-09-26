# ESP32 Control Center iPhone App

Native SwiftUI app for the provided ESP32 Ultimate Control Center firmware.

## Included
- Login using the existing `/login` endpoint and ESP32SESSION cookie
- Dashboard: RAM, LittleFS, flash, CPU, RSSI, uptime
- LittleFS file browser
- File editor and delete
- Multipart file upload
- Visitor analytics
- Logs
- Server settings
- Admin password change
- ESP32 restart
- LittleFS format

## First use
1. Open `ESP32ControlCenter.xcodeproj` in Xcode on a Mac.
2. Select your Apple developer team under Signing & Capabilities.
3. Select your iPhone as the run destination.
4. Build and run.
5. Enter the ESP32 address. The firmware's optional static address is `192.168.178.67`, but DHCP may assign another address because `USE_STATIC_IP` is currently `false`.
6. Enter the admin password configured by the ESP32 setup wizard.

The project includes local-network permission and allows HTTP because the supplied firmware currently uses HTTP on port 80.

Security note: do not expose this HTTP admin interface directly to the public internet without adding HTTPS/VPN/reverse-proxy protection.
