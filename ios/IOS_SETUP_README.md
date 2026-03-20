# iOS Setup Guide — Afterword

Everything possible has been pre-configured. The items below require **manual action** on a Mac with Xcode.

---

## 1. Firebase iOS App (GoogleService-Info.plist)

The file `Runner/GoogleService-Info.plist` is a **placeholder**. Replace it:

1. Go to [Firebase Console](https://console.firebase.google.com/) → your project → Project Settings → General
2. Click **Add app** → iOS
3. Bundle ID: `com.afterword.afterword`
4. Download `GoogleService-Info.plist`
5. Replace `ios/Runner/GoogleService-Info.plist` with the downloaded file
6. In Xcode: drag `GoogleService-Info.plist` into the Runner group (if not already listed)

## 2. Google Sign-In Reversed Client ID

After downloading the real `GoogleService-Info.plist`:

1. Open it and find the `REVERSED_CLIENT_ID` value (e.g. `com.googleusercontent.apps.123456-abc`)
2. In `Runner/Info.plist`, replace `PLACEHOLDER-REVERSED-CLIENT-ID` with that value

## 3. APNs Key (Push Notifications)

Push notifications require an APNs authentication key:

1. Go to [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) → Keys → Create
2. Enable **Apple Push Notifications service (APNs)**
3. Download the `.p8` key file
4. Upload it to Firebase Console → Project Settings → Cloud Messaging → iOS app → APNs Authentication Key

## 4. Code Signing (Xcode)

Open `ios/Runner.xcworkspace` in Xcode:

1. Select the **Runner** target → Signing & Capabilities
2. Set your **Team** (Apple Developer account)
3. Xcode will auto-manage provisioning profiles
4. Verify the Bundle Identifier is `com.afterword.afterword`

## 5. Verify Files in Xcode Project

All files are already referenced in `project.pbxproj`. After opening the workspace,
verify they appear in the Runner group in the Xcode project navigator:

- `GoogleService-Info.plist` (included in Copy Bundle Resources build phase)
- `Runner.entitlements` (referenced by Debug build config)
- `Release.entitlements` (referenced by Release + Profile build configs)

## 6. Run Pod Install

On a Mac, from the `ios/` directory:

```bash
cd ios
pod install
```

This generates `Podfile.lock` and the `Pods/` directory. Both are gitignored.

## 7. RevenueCat iOS Setup

RevenueCat should work automatically via `purchases_flutter`. Ensure:

1. Your App Store Connect app is created with Bundle ID `com.afterword.afterword`
2. In RevenueCat dashboard, add the iOS app with the correct Bundle ID
3. Upload your App Store Connect API key to RevenueCat
4. **IMPORTANT:** The iOS build uses a different RevenueCat API key than Android.
   Pass the Apple API key via `--dart-define=REVENUECAT_API_KEY=appl_XXXXX`

## 8. iOS Build Command

All runtime config is passed via `--dart-define`. Example iOS build:

```bash
flutter build ios \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=REVENUECAT_API_KEY=appl_your_ios_key \
  --dart-define=GOOGLE_WEB_CLIENT_ID=394982150671-qcapj1t19e19p4bunm448t5cf51lp8m9.apps.googleusercontent.com
```

The `GOOGLE_WEB_CLIENT_ID` is the same web (type 3) OAuth client ID used on Android.

## 9. App Store Connect

1. Create the app in App Store Connect with Bundle ID `com.afterword.afterword`
2. Set up your app listing (screenshots, description, etc.)
3. Configure In-App Purchases / Subscriptions matching RevenueCat products

---

## Pre-configured (no action needed)

| Feature | Status |
|---------|--------|
| Info.plist permissions (Mic, Face ID) | ✅ Done |
| URL schemes (afterword://, Google Sign-In) | ✅ Done (placeholder for Google) |
| Background modes (remote-notification) | ✅ Done |
| Push entitlements (dev + production) | ✅ Done |
| Keychain entitlements (flutter_secure_storage) | ✅ Done |
| AppDelegate (Firebase init + APNs forwarding) | ✅ Done |
| Podfile (platform 14.0, Firebase) | ✅ Done |
| Deployment target (iOS 14.0) | ✅ Done |
| Launch screen (black background) | ✅ Done |
| Splash screen (flutter_native_splash) | ✅ Done |
| Push service (iOS DarwinNotificationDetails) | ✅ Done |
| App icons | ✅ Already present |
| GoogleService-Info.plist in Xcode project | ✅ Referenced in pbxproj |
| Entitlements in Xcode project | ✅ Referenced in pbxproj |
| Platform-aware subscription URLs | ✅ Done (App Store on iOS) |
