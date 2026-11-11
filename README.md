# Agent Management Flutter app (Android, offline)

## Included
- First-run administrator password setup
- Administrator login
- Add, view, edit and delete agents
- Agent login by agent code and password
- Local SQLite database; no Firebase, internet or account required
- Agent passwords stored as bcrypt hashes, never as readable text
- Admin password hash stored with Android secure storage

## Setup
1. Install Flutter SDK and Android Studio.
2. Run `flutter create agent_management`.
3. Replace the generated `lib/main.dart` with this package's `lib/main.dart`.
4. From the project folder run:

   `flutter pub add sqflite path flutter_secure_storage bcrypt`

5. Run `flutter pub get`.
6. Connect an Android phone with USB debugging enabled, or start an Android emulator.
7. Run `flutter run`.

## Build APK
Run `flutter build apk --release`.
APK location: `build/app/outputs/flutter-apk/app-release.apk`

## First use
1. Open the app and create an administrator password (minimum 8 characters).
2. Select Administrator Login and enter that password.
3. Tap Add agent and enter agent code, agent name and a password (minimum 8 characters).
4. Agents use Agent Login with their own code and password.
5. Tap an agent in the admin list to edit. Leave the password field blank to retain it.

## Important
- The SQLite table contains agentCode, agentName and passwordHash. It does not save the original password.
- The admin password hash is stored separately in Android secure storage.
- This is a single-device offline app. Data is not synchronized with another phone.
- Uninstalling the app or clearing app storage can delete its data. Back up the device before doing so.
- Protect the phone with a strong screen lock and keep Android updated. Rooted or compromised devices can expose local data.
- This is a starter implementation, not an audited enterprise credential vault.
