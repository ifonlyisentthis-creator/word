# Afterword — Mega Update Progress Notes

## Items to implement (20 total)

### 1. Security Audit + Remove "Zero Knowledge" → "Time-Locked Encryption"
- **Encryption flow confirmed correct**: heartbeat.py decrypts server-layer only (data_key_encrypted) to get raw key → emails to beneficiary → viewer/app.js decrypts content client-side in browser → key never sent back to server
- **"Zero Knowledge" found in**: privacy_policy_screen.dart (section 2 heading), terms_screen.dart (section 2 "zero-knowledge encrypted legacy vault"), viewer/app.js line 148 ("Zero-Knowledge security protocols"), how_it_works_screen.dart mentions encryption but no "zero knowledge", viewer/index.html (no direct mention)
- **Replace with**: "Time-Locked Encryption" or "Managed Encryption"

### 2. UI Polish — Skeleton Loader + Theme Flicker
- Timer card CLS: home_screen.dart _TimerCard rebuilds after data fetch → need skeleton/fixed height
- Theme flicker: ThemeProvider starts with oledVoid default → syncFromProfile called in HomeController.initialize() which is AFTER UI is visible → soul fire flashes purple before user's theme loads
- Fix: Load theme preference from SharedPreferences/local storage during splash phase BEFORE runApp

### 3. Limit Reset After Grace Period
- Currently cleanup_sent_entries() creates tombstones, deletes entries, archives profiles
- Need: After grace period deletion, reset vault limits (free gets 3 back, lifetime gets 10min audio back)
- Already partially handled: limits are based on COUNT of active entries, so when entries are deleted, count goes to 0 automatically
- Audio time bank: enforce_audio_time_bank() counts active audio entries — when deleted, sum=0, so 10min is available again ✓
- Free 3-vault limit: RLS counts active text entries < 3 — when deleted, count=0, so 3 slots open ✓
- **VERDICT**: Limits auto-reset because they're COUNT-based, not cumulative. No code change needed, just verify.

### 4. History Section SQL
- vault_entry_tombstones table EXISTS (SQL #13/17)
- tombstones_select_own policy EXISTS
- history_screen.dart reads from vault_entries (sent) + vault_entry_tombstones
- **VERDICT**: SQL is already there. ✓

### 5. Bot Account Cleanup — 90-day Zero Activity
- Need new logic: delete accounts with ZERO activity after 90 days
- Activity = soul fire check-in, vault creation, any interaction
- Indicators of activity: last_check_in differs from created_at, vault_entries exist, vault_entry_tombstones exist
- Must NOT delete: users whose timer expired and data was deleted (they have tombstones or had entries)
- Add to heartbeat.py OR as a new pg_cron function

### 6. Website/Privacy/Terms — Store-Friendly Language
- Remove: "death", "I'm gone", "die", "dead", tech stack names (Supabase, RevenueCat, Firebase, AES-256, etc.)
- Add: abuse/harassment/threats disclaimer, responsibility on user
- Use: "if you become unavailable", "unable to check in", "in your absence"

### 7. Vault Form Consent Checkbox
- Add mandatory checkbox in VaultEntrySheet before save
- Text: authorization for good use + authorization that vault items get sent based on timer

### 8. Timer Reset Conditions
- Timer ONLY resets on: (a) timer adjustment (increase/decrease), (b) soul fire button check-in, (c) account deletion (vaults deleted = no timer)
- NOT on: logout, inactivity, app open, anything else
- Currently: update_check_in RPC resets last_check_in — called from manualCheckIn (soul fire) and updateTimerDays
- Verify: logout doesn't call update_check_in ✓, autoCheckIn just fetches profile ✓

### 9. Timer Only Runs If ≥1 Vault Exists
- Already implemented: heartbeat.py skips users with no active entries (has_entries check)
- homeController._scheduleReminders cancels notifications if no vault entries
- **VERDICT**: Already correct ✓

### 10. Subscription Handling — MASSIVE
- Part 1A: Pro refund → immediately revert to free (timer=30, themes=default, keep all vaults, can't add >3)
- Part 1B: Lifetime refund → same as 1A but also delete audio vaults immediately
- Part 2: Non-renewal (monthly/yearly) → same as refund but detected on next heartbeat cycle
- All cases: send email notification to user
- Implementation: heartbeat.py needs new PASS for subscription downgrade detection
- RevenueCat webhook (verify-subscription Edge Function) handles real-time status changes

### 11. One Timer Per User, Multiple Vaults Different Beneficiaries
- Already correct: profiles has ONE timer (last_check_in + timer_days), vault_entries has per-entry recipient_email_encrypted
- **VERDICT**: Already correct ✓

### 12. Zero-Grouping Architecture
- Each vault+beneficiary is unique — no grouping
- Already correct: each vault_entry has its own id, own recipient_email_encrypted, own data_key_encrypted
- viewer/app.js fetches by entry ID — can only see that one entry
- Even same beneficiary gets separate emails with separate entry IDs
- **VERDICT**: Already correct ✓ — architecture is inherently per-entry isolated

### 13. Fresh Account After Grace Period — Limits Reset
- Same as #3 — limits auto-reset because COUNT-based ✓

### 14-20: Implementation, SQL, setup, edge cases, update pages, triple-check, push
