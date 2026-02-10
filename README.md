# Afterword

Flutter (Android-first) client for Afterword.

## Timer tiers

- **Free**
  - Fixed at **30 days**
- **Pro**
  - Range: **7–365 days**
- **Lifetime ($99.99)**
  - Range: **7–3650 days (10 years)**
  - Use case: **Time Capsule** (children/legacy)
  - If duration **> 365 days**, show this warning:
    - `⚠️ NOTE: This is a Time Capsule setting. Beneficiaries will NOT receive this until the full duration passes, even if you stop checking in tomorrow.`

## Run (dev)

```powershell
flutter run --dart-define=SUPABASE_URL="https://abxduxfiwhsjsqicrbru.supabase.co" --dart-define=SUPABASE_ANON_KEY="(your anon key)" --dart-define=REVENUECAT_API_KEY="(your revenuecat key)" --dart-define=GOOGLE_WEB_CLIENT_ID="394982150671-qcapj1t19e19p4bunm448t5cf51lp8m9.apps.googleusercontent.com"
```
