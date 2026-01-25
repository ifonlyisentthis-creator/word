# Afterword Heartbeat Automation

This script runs daily to enforce the Afterword protocol:

1. **Warning (Day 29)**: Paid users with non-empty vaults receive a final email.
2. **Execution (Day 30+)**: Expired entries are sent (Send) or deleted (Destroy).
3. **Cleanup (Day 8 post-send)**: Sent items older than 7 days are deleted and profiles archived.

## Requirements

- Python 3.11+
- Install dependencies:
  ```bash
  pip install -r automation/requirements.txt
  ```

## Environment Variables

Set these in GitHub Actions secrets or your shell:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SERVER_SECRET` (matches the Flutter `SERVER_SECRET`)
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL` (e.g., `Afterword <noreply@afterword-app.com>`)
- `VIEWER_BASE_URL` (e.g., `https://view.afterword-app.com`)

## Run Locally

```bash
python automation/heartbeat.py
```

## Notes

- The script only unlocks entries with valid HMAC signatures.
- Destroy-mode entries are deleted immediately on expiration.
- Sent entries remain available for 7 days, then are purged.
