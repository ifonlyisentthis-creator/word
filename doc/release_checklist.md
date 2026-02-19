# Afterword Release Checklist (Staging -> Production)

## 1) Pre-deploy

- Confirm `flutter analyze` passes.
- Confirm `flutter test` passes.
- Confirm `python -m unittest discover automation/tests -v` passes.
- Confirm `python -m py_compile automation/heartbeat.py` passes.
- Confirm secrets are present in Supabase/CI:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SERVER_SECRET`
  - `REVENUECAT_API_SECRET`
  - `REVENUECAT_ENTITLEMENT_ID`
  - `RESEND_API_KEY`
  - `RESEND_FROM_EMAIL`
  - `VIEWER_BASE_URL`
  - `FIREBASE_SERVICE_ACCOUNT_JSON`

## 2) SQL migrations (idempotent order)

1. `supabase/v35_downgrade_and_cleanup.sql`
2. `supabase/v36_theme_preferences_alignment.sql`
3. `supabase/v37_account_deletion_rpc.sql`

## 3) Staging validation

- Sign-up/login flow works (Google + Supabase).
- Verify subscription sync via `verify-subscription` function.
- Free/pro/lifetime theme + soul-fire gating works.
- Create/update/delete text entry path works.
- Create/update/delete audio entry path works.
- Protocol execution path works (send and destroy).
- Grace period state and viewer access behave as expected.
- Account deletion removes auth identity and user data.

## 4) Canary rollout

- Deploy app to a small internal cohort first.
- Monitor error rate, auth failures, payment sync failures, and push delivery failures for 30-60 minutes.
- If stable, continue phased rollout.

## 5) Rollback plan

- Mobile app: roll back to previous stable release in stores.
- Backend functions: redeploy previous function revisions.
- SQL rollback:
  - `REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM authenticated;`
  - `DROP FUNCTION IF EXISTS public.delete_my_account();`
- If needed, disable new CI workflow temporarily by removing it from default branch.

## 6) Post-deploy verification

- Verify one live free account flow and one premium account flow.
- Trigger heartbeat manually and inspect logs.
- Verify a push device token refresh and one warning notification path.
- Verify one account deletion end-to-end.
