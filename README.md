# Afterword

A secure, time-locked digital vault. Create encrypted messages and audio recordings that are delivered to designated recipients — or permanently erased — when your check-in timer expires.

## Architecture

- **Flutter** (Android-first) mobile client
- **Supabase** — database, auth, storage, Edge Functions
- **Heartbeat script** (`automation/heartbeat.py`) — daily cron for timer expiry, notifications, subscription enforcement, bot cleanup
- **Viewer** (`viewer/`) — static web page for recipients to decrypt messages client-side

## Timer Tiers

| Tier | Timer Range | Vault Limit | Features |
|------|-------------|-------------|----------|
| Free | 30 days (fixed) | 3 text | Push notifications |
| Pro Monthly/Yearly | 7–365 days | Unlimited text | Custom timer, Protocol Zero (erase mode), email warning |
| Lifetime | 7–3650 days | Unlimited text + 10 min audio | All Pro features, all themes & styles |

## Encryption Flow

1. Client encrypts content with a locally-generated key
2. Key is wrapped with a server-managed secret for delivery
3. On timer expiry, server retrieves the delivery key and emails it to the recipient
4. Recipient decrypts content entirely in their browser — key never returns to the server

## Subscription Handling

- **Refund (Pro)**: Immediately revert to free tier (timer → 30 days, themes → default). Keep all vault entries.
- **Refund (Lifetime)**: Same as Pro, plus delete audio vault entries.
- **Non-renewal**: Same reversion at end of billing period.
- **All cases**: Notification email sent to user. Timer restarts fresh at 30 days.

## Bot Prevention

Accounts with zero activity (no check-ins, no vaults, no history) are automatically deleted after 90 days.

## Key Rules

- **Timer resets only on**: Soul Fire check-in, timer adjustment, or account deletion
- **Timer only runs if** at least one vault entry exists
- **Each vault entry is independent**: separate recipient, separate encryption, separate delivery
- **Limits auto-reset** after grace period data deletion (count-based enforcement)

## Run (dev)

```powershell
flutter run --dart-define=SUPABASE_URL="..." --dart-define=SUPABASE_ANON_KEY="..." --dart-define=REVENUECAT_API_KEY="..." --dart-define=GOOGLE_WEB_CLIENT_ID="..."
```

## SQL

Run `supabase/v35_downgrade_and_cleanup.sql` in the SQL Editor for subscription downgrade support.
