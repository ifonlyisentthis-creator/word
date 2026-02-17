import base64

import hashlib

import hmac

import html as html_mod

import json

import os

import sys

import time

from datetime import datetime, timedelta, timezone



import requests

from google.auth.transport.requests import Request as GoogleAuthRequest

from google.oauth2 import service_account

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from supabase import create_client



AUDIO_BUCKET = "vault-audio"

PAID_STATUSES = {"pro", "lifetime", "premium"}

WARNING_WINDOW = timedelta(days=1)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

PAGE_SIZE = 1000


def fetch_all_rows(query_builder) -> list[dict]:
    """Paginate through a Supabase query to fetch all matching rows.

    Supabase PostgREST caps responses at ~1000 rows by default.
    This helper fetches in PAGE_SIZE batches using .range() until
    a batch returns fewer rows than the page size.

    Usage:
        rows = fetch_all_rows(
            client.table("profiles")
            .select("id,email,...")
            .eq("status", "active")
        )
    """
    all_rows: list[dict] = []
    offset = 0
    while True:
        response = query_builder.range(offset, offset + PAGE_SIZE - 1).execute()
        batch = response.data or []
        all_rows.extend(batch)
        if len(batch) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    return all_rows





def get_env(name: str, default: str | None = None) -> str:

    value = os.getenv(name, default)

    if value is None or value == "":

        raise RuntimeError(f"Missing required environment variable: {name}")

    return value





def parse_iso(value: str | None) -> datetime | None:

    if not value:

        return None

    if value.endswith("Z"):

        value = value.replace("Z", "+00:00")

    return datetime.fromisoformat(value)





def decode_secret_box(encoded: str) -> tuple[bytes, bytes, bytes]:

    parts = encoded.split(".")

    if len(parts) != 3:

        raise ValueError("Invalid encrypted payload format.")

    nonce = base64.b64decode(parts[0])

    cipher_text = base64.b64decode(parts[1])

    mac = base64.b64decode(parts[2])

    return nonce, cipher_text, mac





def decrypt_with_server_secret(encoded: str, server_secret: str) -> bytes:

    nonce, cipher_text, mac = decode_secret_box(encoded)

    key = hashlib.sha256(server_secret.encode("utf-8")).digest()

    aes = AESGCM(key)

    combined = cipher_text + mac

    return aes.decrypt(nonce, combined, None)





def extract_server_ciphertext(value: str) -> str:

    if not value:

        return value

    try:

        decoded = json.loads(value)

    except Exception:  # noqa: BLE001

        return value



    if isinstance(decoded, dict):

        server = decoded.get("server")

        if isinstance(server, str) and server:

            return server

    return value





def compute_hmac_signature(message: str, key_bytes: bytes) -> str:

    digest = hmac.new(key_bytes, message.encode("utf-8"), hashlib.sha256).digest()

    return base64.b64encode(digest).decode("utf-8")





def is_paid(subscription_status: str | None) -> bool:

    if not subscription_status:

        return False

    return subscription_status.lower() in PAID_STATUSES





def build_viewer_link(base_url: str, entry_id: str) -> str:

    return f"{base_url.rstrip('/')}/?entry={entry_id}"





def send_email(api_key: str, from_email: str, to_email: str, subject: str, text: str, html: str) -> None:

    response = requests.post(

        "https://api.resend.com/emails",

        headers={

            "Authorization": f"Bearer {api_key}",

            "Content-Type": "application/json",

        },

        json={

            "from": from_email,

            "to": [to_email],

            "subject": subject,

            "text": text,

            "html": html,

        },

        timeout=30,

    )

    if response.status_code >= 400:

        raise RuntimeError(f"Resend error: {response.status_code} {response.text}")





def send_warning_email(profile: dict, deadline: datetime, resend_key: str, from_email: str) -> None:

    email = profile.get("email")

    if not email:

        return

    sender_name = profile.get("sender_name") or "Afterword"

    deadline_text = deadline.strftime("%b %d, %Y")

    subject = "Afterword warning: check in now"

    text = (

        f"Hi {sender_name},\n\n"

        f"Your Afterword timer expires on {deadline_text}. Open the app to check in "

        "and keep your vault secure.\n\n"

        "If you are safe, open Afterword today to reset your timer."

    )

    safe_name = html_mod.escape(sender_name)

    html = (

        f"<p>Hi {safe_name},</p>"

        f"<p>Your Afterword timer expires on <strong>{deadline_text}</strong>. "

        "Open the app to check in and keep your vault secure.</p>"

        "<p>If you are safe, open Afterword today to reset your timer.</p>"

    )

    send_email(resend_key, from_email, email, subject, text, html)





def get_fcm_access_token(service_account_info: dict) -> str:

    credentials = service_account.Credentials.from_service_account_info(

        service_account_info,

        scopes=[FCM_SCOPE],

    )

    request = GoogleAuthRequest()

    credentials.refresh(request)

    if not credentials.token:

        raise RuntimeError("Unable to mint FCM access token")

    return credentials.token





def send_push_v1(

    project_id: str,

    access_token: str,

    fcm_token: str,

    title: str,

    body: str,

    data: dict[str, str] | None = None,

) -> requests.Response:

    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    payload: dict = {

        "message": {

            "token": fcm_token,

            "notification": {"title": title, "body": body},

        }

    }

    if data:

        payload["message"]["data"] = data



    return requests.post(

        url,

        headers={

            "Authorization": f"Bearer {access_token}",

            "Content-Type": "application/json",

        },

        json=payload,

        timeout=30,

    )





def build_fcm_context(firebase_sa_json: str) -> dict | None:
    """Parse Firebase SA JSON and mint an access token once per heartbeat run."""
    if not firebase_sa_json:
        return None
    try:
        sa_info = json.loads(firebase_sa_json)
    except Exception as exc:  # noqa: BLE001
        print(f"Invalid FIREBASE_SERVICE_ACCOUNT_JSON: {exc}")
        return None
    project_id = sa_info.get("project_id")
    if not project_id:
        print("FIREBASE_SERVICE_ACCOUNT_JSON missing project_id")
        return None
    try:
        access_token = get_fcm_access_token(sa_info)
    except Exception as exc:  # noqa: BLE001
        print(f"Failed to mint FCM access token: {exc}")
        return None
    return {"project_id": project_id, "access_token": access_token}


def _send_push_to_user(
    client,
    user_id: str,
    fcm_ctx: dict,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> bool:
    """Send a push notification to all devices for a user.

    Returns True if at least one push was successfully delivered.
    """
    tokens_response = (
        client.table("push_devices")
        .select("fcm_token")
        .eq("user_id", user_id)
        .execute()
    )
    rows = tokens_response.data or []
    tokens = [row.get("fcm_token") for row in rows if row.get("fcm_token")]
    if not tokens:
        print(f"No FCM tokens for user {user_id}, push skipped")
        return False

    sent = False
    for token in tokens:
        response = send_push_v1(
            project_id=fcm_ctx["project_id"],
            access_token=fcm_ctx["access_token"],
            fcm_token=str(token),
            title=title,
            body=body,
            data=data,
        )
        if response.status_code == 404:
            client.table("push_devices").delete().eq("fcm_token", token).execute()
            continue
        if response.status_code >= 400:
            text = response.text or ""
            if "UNREGISTERED" in text or "registration-token-not-registered" in text:
                client.table("push_devices").delete().eq("fcm_token", token).execute()
                continue
            print(f"Push failed for user {user_id}: {response.status_code} {text}")
            continue
        sent = True
    return sent


def send_warning_push(
    client,
    user_id: str,
    sender_name: str,
    deadline: datetime,
    fcm_ctx: dict | None,
) -> bool:
    """Returns True if push was actually delivered to at least one device."""
    if fcm_ctx is None:
        return False
    deadline_text = deadline.strftime("%b %d, %Y")
    return _send_push_to_user(
        client, user_id, fcm_ctx,
        title="Afterword warning",
        body=f"Hi {sender_name}, your timer expires on {deadline_text}. Open Afterword to check in.",
        data={"type": "warning"},
    )





def send_executed_push(
    client,
    user_id: str,
    entry_id: str,
    entry_title: str,
    fcm_ctx: dict | None,
    *,
    action: str = "send",
) -> bool:
    """Returns True if push was actually delivered to at least one device."""
    if fcm_ctx is None:
        return False
    safe_title = entry_title or "Untitled"
    verb = "destroyed" if action == "destroy" else "sent"
    return _send_push_to_user(
        client, user_id, fcm_ctx,
        title="Afterword executed",
        body=f"Your entry '{safe_title}' was {verb}.",
        data={"type": "executed", "entry_id": entry_id},
    )





def send_unlock_email(

    recipient_email: str,

    sender_name: str,

    entry_title: str,

    viewer_link: str,

    security_key: str,

    resend_key: str,

    from_email: str,

) -> None:

    subject = f"Message from {sender_name}"

    text = (

        f"{sender_name} left you a secure message using Afterword — "

        "a time-locked digital vault.\n\n"

        f"Title: {entry_title}\n\n"

        f"Open: {viewer_link}\n\n"

        f"Security Key: {security_key}\n\n"

        "Paste the security key into the viewer to decrypt the message in "

        "your browser. The key is never sent to our servers.\n\n"

        "Do not share this key — anyone with it can read the message.\n\n"

        "This transmission expires 30 days after delivery.\n\n"

        "If you do not recognize the sender, you may safely ignore this email."

    )

    safe_sender = html_mod.escape(sender_name)

    safe_title = html_mod.escape(entry_title)

    safe_link = html_mod.escape(viewer_link)

    html = (

        f"<p><strong>{safe_sender}</strong> left you a secure message using "

        "Afterword — a time-locked digital vault.</p>"

        f"<p><strong>Title:</strong> {safe_title}</p>"

        f"<p><a href=\"{safe_link}\" style=\"font-size:16px\">Open the secure message</a></p>"

        f"<p><strong>Security Key:</strong><br>"

        f"<code style=\"background:#f4f4f4;padding:6px 10px;border-radius:4px;font-size:13px;word-break:break-all\">{security_key}</code></p>"

        "<p>Paste the security key into the viewer to decrypt the message "

        "in your browser. The key is never sent to our servers.</p>"

        "<p><em>Do not share this key — anyone with it can read the message.</em></p>"

        "<hr>"

        "<p style=\"color:#888;font-size:12px\">This transmission expires 30 days after delivery. "

        "If you do not recognize the sender, you may safely ignore this email.</p>"

    )

    send_email(resend_key, from_email, recipient_email, subject, text, html)





def delete_entry(client, entry: dict) -> None:

    audio_path = entry.get("audio_file_path")

    if audio_path:

        client.storage.from_(AUDIO_BUCKET).remove([audio_path])

    client.table("vault_entries").delete().eq("id", entry["id"]).execute()





def mark_profile_status(client, user_id: str, status: str) -> None:

    client.table("profiles").update({"status": status}).eq("id", user_id).execute()





def mark_warning_sent(client, user_id: str, timestamp: datetime) -> None:

    client.table("profiles").update(

        {"warning_sent_at": timestamp.isoformat()}

    ).eq("id", user_id).execute()





def claim_entry_for_sending(client, entry_id: str) -> bool:

    response = (

        client.table("vault_entries")

        .update({"status": "sending"})

        .eq("id", entry_id)

        .eq("status", "active")

        .execute()

    )

    return bool(response.data)





def release_entry_lock(client, entry_id: str) -> None:

    client.table("vault_entries").update({"status": "active"}).eq(

        "id", entry_id

    ).execute()





def process_expired_entries(

    client,

    profile: dict,

    entries: list[dict],

    server_secret: str,

    resend_key: str,

    from_email: str,

    viewer_base_url: str,

    fcm_ctx: dict | None,

    now: datetime,

) -> bool:
    """Process expired vault entries. Returns True if any 'send' entries were
    processed (grace period needed), False if all entries were destroy-only."""

    had_send = False

    sender_name = profile.get("sender_name") or "Afterword"

    hmac_key_encrypted = profile.get("hmac_key_encrypted")

    hmac_key_bytes = None

    if hmac_key_encrypted:

        try:

            hmac_key_bytes = decrypt_with_server_secret(hmac_key_encrypted, server_secret)

        except Exception as exc:  # noqa: BLE001

            print(f"Failed to decrypt HMAC key for user {profile.get('id', '?')}: {exc}")



    for entry in entries:

        entry_id = entry.get("id", "unknown")

        try:

            action = (entry.get("action_type") or "send").lower()

            if action == "destroy":

                entry_title = entry.get("title") or "Untitled"

                try:
                    send_executed_push(
                        client,
                        profile["id"],
                        entry_id,
                        entry_title,
                        fcm_ctx,
                        action="destroy",
                    )
                except Exception:  # noqa: BLE001
                    pass

                delete_entry(client, entry)

                continue



            if not claim_entry_for_sending(client, entry_id):

                continue



            if hmac_key_bytes is None:

                delete_entry(client, entry)

                continue



            recipient_encrypted = entry.get("recipient_email_encrypted") or ""

            signature_message = f"{entry.get('payload_encrypted')}|{recipient_encrypted}"

            expected_signature = compute_hmac_signature(signature_message, hmac_key_bytes)

            if expected_signature != entry.get("hmac_signature"):

                delete_entry(client, entry)

                continue



            if not recipient_encrypted:

                delete_entry(client, entry)

                continue



            recipient_ciphertext = extract_server_ciphertext(recipient_encrypted)

            recipient_email = decrypt_with_server_secret(

                recipient_ciphertext, server_secret

            ).decode("utf-8")

            data_key_encrypted = entry.get("data_key_encrypted")

            if not data_key_encrypted:

                delete_entry(client, entry)

                continue



            data_key_ciphertext = extract_server_ciphertext(data_key_encrypted)

            data_key_bytes = decrypt_with_server_secret(data_key_ciphertext, server_secret)

            security_key = base64.b64encode(data_key_bytes).decode("utf-8")

            viewer_link = build_viewer_link(viewer_base_url, entry_id)

            entry_title = entry.get("title") or "Untitled"

            send_unlock_email(

                recipient_email,

                sender_name,

                entry_title,

                viewer_link,

                security_key,

                resend_key,

                from_email,

            )



            had_send = True

            client.table("vault_entries").update(

                {"status": "sent", "sent_at": now.isoformat()}

            ).eq("id", entry_id).execute()



            try:

                send_executed_push(

                    client,

                    profile["id"],

                    entry_id,

                    entry_title,

                    fcm_ctx,

                )

            except Exception as exc:  # noqa: BLE001

                print(f"Push executed failed for entry {entry_id}: {exc}")

        except Exception as exc:  # noqa: BLE001

            # Release the sending lock so the entry can be retried next cycle
            try:
                release_entry_lock(client, entry_id)
            except Exception:  # noqa: BLE001
                pass

            print(f"Failed to process entry {entry_id}: {exc}")

    return had_send




def cleanup_sent_entries(client) -> None:

    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    now_iso = datetime.now(timezone.utc).isoformat()

    sent_entries = fetch_all_rows(
        client.table("vault_entries")
        .select("id,user_id,audio_file_path,sent_at")
        .eq("status", "sent")
        .lt("sent_at", cutoff)
    )

    if not sent_entries:
        return

    # Collect user_ids so we can fetch sender_names for tombstones
    user_ids = {e["user_id"] for e in sent_entries}

    # Fetch sender_names for tombstone records
    sender_names: dict[str, str] = {}
    for uid in user_ids:
        try:
            profile_row = (
                client.table("profiles")
                .select("sender_name")
                .eq("id", uid)
                .maybeSingle()
                .execute()
            )
            if profile_row.data:
                sender_names[uid] = profile_row.data.get("sender_name") or "Afterword"
            else:
                sender_names[uid] = "Afterword"
        except Exception:  # noqa: BLE001
            sender_names[uid] = "Afterword"

    # Create tombstones BEFORE deleting (preserves History tab data)
    for entry in sent_entries:
        try:
            client.table("vault_entry_tombstones").insert({
                "vault_entry_id": entry["id"],
                "user_id": entry["user_id"],
                "sender_name": sender_names.get(entry["user_id"], "Afterword"),
                "sent_at": entry.get("sent_at"),
                "expired_at": now_iso,
            }).execute()
        except Exception:  # noqa: BLE001
            # Tombstone insert may fail on duplicate PK if already exists — safe to skip
            pass

    # Now delete the entries (storage files + DB rows)
    for entry in sent_entries:
        try:
            delete_entry(client, entry)
        except Exception:  # noqa: BLE001
            print(f"Failed to delete sent entry {entry.get('id', '?')}")

    # Reset users with zero remaining entries to fresh active state
    for uid in user_ids:
        try:
            remaining = (
                client.table("vault_entries")
                .select("id", count="exact")
                .eq("user_id", uid)
                .execute()
            )
            if (remaining.count or 0) == 0:
                client.table("profiles").update({
                    "status": "active",
                    "timer_days": 30,
                    "last_check_in": now_iso,
                    "protocol_executed_at": None,
                    "warning_sent_at": None,
                    "push_66_sent_at": None,
                    "push_33_sent_at": None,
                    "last_entry_at": None,
                }).eq("id", uid).execute()
                print(f"User {uid}: grace period ended, account reset to fresh state")
        except Exception:  # noqa: BLE001
            print(f"Failed to check/reset user {uid}")


def cleanup_bot_accounts(client, now: datetime) -> None:
    """Delete accounts with ZERO activity after 90 days.

    An account is considered a bot / abandoned if ALL of the following are true:
      - created_at is older than 90 days
      - last_check_in == created_at (never used Soul Fire — timer never reset)
      - had_vault_activity is false (never had entries processed)
      - no vault_entries exist (never created a vault)
      - no vault_entry_tombstones exist (never had executed entries)
      - status is 'active' (not already archived from a prior protocol execution)

    Real users who interacted (Soul Fire, vaults, themes) are never touched.
    Users whose timer expired with 'send' entries have tombstones → safe.
    Users whose timer expired with 'destroy' entries have had_vault_activity → safe.
    """
    cutoff = (now - timedelta(days=90)).isoformat()

    # Find candidate profiles: created > 90 days ago, never checked in after creation
    candidates = fetch_all_rows(
        client.table("profiles")
        .select("id,email,created_at,last_check_in,had_vault_activity")
        .eq("status", "active")
        .lt("created_at", cutoff)
    )

    for profile in candidates:
      try:
        uid = profile["id"]
        created_at = parse_iso(profile.get("created_at"))
        last_check_in = parse_iso(profile.get("last_check_in"))

        if created_at is None or last_check_in is None:
            continue

        # If user ever checked in after account creation, they're real
        # Allow 60 second tolerance for the initial check-in set at creation
        if abs((last_check_in - created_at).total_seconds()) > 60:
            continue

        # If user ever had vault entries processed (destroy or send), they're real
        if profile.get("had_vault_activity"):
            continue

        # Check if they ever had any vault entries
        vault_count = (
            client.table("vault_entries")
            .select("id", count="exact")
            .eq("user_id", uid)
            .execute()
        )
        if (vault_count.count or 0) > 0:
            continue

        # Check if they have tombstones (had entries that were executed + purged)
        tombstone_count = (
            client.table("vault_entry_tombstones")
            .select("vault_entry_id", count="exact")
            .eq("user_id", uid)
            .execute()
        )
        if (tombstone_count.count or 0) > 0:
            continue

        # No activity at all — delete the auth user (cascades to profile + push_devices)
        try:
            client.auth.admin.delete_user(uid)
            print(f"Deleted inactive bot account: {uid}")
        except Exception as exc:  # noqa: BLE001
            print(f"Failed to delete bot account {uid}: {exc}")
      except Exception as exc:  # noqa: BLE001
          print(f"Bot cleanup failed for {profile.get('id', '?')}: {exc}")


def handle_subscription_downgrade(
    client,
    profile: dict,
    resend_key: str,
    from_email: str,
    now: datetime,
) -> bool:
    """Handle a user whose subscription was downgraded (refund or non-renewal).

    Called when RevenueCat has already set subscription_status to 'free' but the
    profile still has pro/lifetime artifacts (custom timer, audio vaults, themes).

    Actions:
      1. Reset timer_days to 30 (free default) — timer restarts fresh
      2. Reset last_check_in to now() — user gets full 30 days
      3. Clear warning timestamps
      4. Reset theme and soul fire to free defaults
      5. If former lifetime user: delete all audio vault entries
      6. Send notification email to user
    """
    uid = profile["id"]
    email = profile.get("email")
    sender_name = profile.get("sender_name") or "Afterword"
    timer_days = int(profile.get("timer_days") or 30)

    # Detect if downgrade handling is needed:
    # subscription_status is already 'free' (set by RevenueCat webhook),
    # but timer_days > 30 or custom theme/soul_fire is set
    selected_theme = profile.get("selected_theme")
    selected_soul_fire = profile.get("selected_soul_fire")
    has_custom_timer = timer_days > 30
    has_custom_theme = selected_theme is not None and selected_theme != "oledVoid"
    has_custom_soul_fire = selected_soul_fire is not None and selected_soul_fire != "etherealOrb"

    # Only query for audio if there are other pro/lifetime indicators.
    # This avoids a DB query for every always-free user at scale.
    has_pro_indicators = has_custom_timer or has_custom_theme or has_custom_soul_fire
    audio_entries: list[dict] = []
    has_audio = False
    if has_pro_indicators or (selected_soul_fire in ("toxicCore", "crystalAscend")):
        try:
            audio_check = (
                client.table("vault_entries")
                .select("id", count="exact")
                .eq("user_id", uid)
                .eq("data_type", "audio")
                .eq("status", "active")
                .execute()
            )
            has_audio = (audio_check.count or 0) > 0
        except Exception:  # noqa: BLE001
            pass

    needs_revert = has_pro_indicators or has_audio

    if not needs_revert:
        return False

    was_lifetime = (
        has_audio
        or (has_custom_soul_fire and selected_soul_fire in ("toxicCore", "crystalAscend"))
    )

    # 1. Reset profile to free defaults
    update_data = {
        "timer_days": 30,
        "last_check_in": now.isoformat(),
        "warning_sent_at": None,
        "push_66_sent_at": None,
        "push_33_sent_at": None,
        "selected_theme": None,
        "selected_soul_fire": None,
    }
    client.table("profiles").update(update_data).eq("id", uid).execute()

    # 2. If former lifetime: delete audio vault entries
    if was_lifetime:
        audio_entries = (
            client.table("vault_entries")
            .select("id,audio_file_path")
            .eq("user_id", uid)
            .eq("data_type", "audio")
            .eq("status", "active")
            .execute()
        ).data or []
        for entry in audio_entries:
            delete_entry(client, entry)
        if audio_entries:
            print(f"Deleted {len(audio_entries)} audio entries for downgraded lifetime user {uid}")

    # 3. Send notification email
    if email:
        reason = "refund or expiration"
        audio_note = ""
        if was_lifetime and audio_entries:
            audio_note = (
                " Audio vault entries have been removed as they require "
                "a Lifetime subscription."
            )

        subject = "Afterword — Subscription update"
        text = (
            f"Hi {sender_name},\n\n"
            f"Your Afterword subscription has been updated due to a {reason}. "
            "Your account has been reverted to the free tier.\n\n"
            "What this means:\n"
            "• Your timer has been reset to the default 30 days\n"
            "• Custom themes and styles have been reset to defaults\n"
            "• All your existing vault entries are preserved\n"
            f"{audio_note}\n\n"
            "You can continue using Afterword on the free tier, or "
            "resubscribe at any time to restore premium features.\n\n"
            "— The Afterword Team"
        )
        safe_name = html_mod.escape(sender_name)
        html = (
            f"<p>Hi {safe_name},</p>"
            f"<p>Your Afterword subscription has been updated due to a {reason}. "
            "Your account has been reverted to the free tier.</p>"
            "<p><strong>What this means:</strong></p>"
            "<ul>"
            "<li>Your timer has been reset to the default 30 days</li>"
            "<li>Custom themes and styles have been reset to defaults</li>"
            "<li>All your existing vault entries are preserved</li>"
            f"{'<li>Audio vault entries have been removed (Lifetime feature)</li>' if was_lifetime and audio_entries else ''}"
            "</ul>"
            "<p>You can continue using Afterword on the free tier, or "
            "resubscribe at any time to restore premium features.</p>"
            "<p>— The Afterword Team</p>"
        )
        try:
            send_email(resend_key, from_email, email, subject, text, html)
            print(f"Sent downgrade notification to {uid}")
        except Exception as exc:  # noqa: BLE001
            print(f"Failed to send downgrade email to {uid}: {exc}")

    return True


def main() -> int:

    supabase_url = get_env("SUPABASE_URL")

    supabase_key = get_env("SUPABASE_SERVICE_ROLE_KEY")

    server_secret = get_env("SERVER_SECRET")

    resend_key = get_env("RESEND_API_KEY")

    from_email = get_env("RESEND_FROM_EMAIL")

    viewer_base_url = get_env("VIEWER_BASE_URL")

    firebase_sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")



    client = create_client(supabase_url, supabase_key)

    now = datetime.now(timezone.utc)

    fcm_ctx = build_fcm_context(firebase_sa_json)



    profiles = fetch_all_rows(

        client.table("profiles")

        .select(

            "id,email,sender_name,status,subscription_status,last_check_in,timer_days,"

            "hmac_key_encrypted,warning_sent_at,push_66_sent_at,push_33_sent_at,"

            "selected_theme,selected_soul_fire,created_at"

        )

        .eq("status", "active")

    )
    print(f"Active profiles: {len(profiles)}")



    entries = fetch_all_rows(

        client.table("vault_entries")

        .select(

            "id,user_id,title,action_type,data_type,status,payload_encrypted,recipient_email_encrypted,data_key_encrypted,hmac_signature,audio_file_path"

        )

        .eq("status", "active")

    )
    print(f"Active entries: {len(entries)}")

    entries_by_user: dict[str, list[dict]] = {}

    for entry in entries:

        entries_by_user.setdefault(entry["user_id"], []).append(entry)



    for profile in profiles:

      try:

        user_id = profile["id"]

        last_check_in = parse_iso(profile.get("last_check_in"))

        timer_days = int(profile.get("timer_days") or 30)

        if last_check_in is None:

            continue



        deadline = last_check_in + timedelta(days=timer_days)

        remaining = deadline - now

        total_seconds = timer_days * 86400

        remaining_seconds = max(remaining.total_seconds(), 0)

        remaining_fraction = remaining_seconds / total_seconds if total_seconds > 0 else 0

        active_entries = entries_by_user.get(user_id, [])

        has_entries = len(active_entries) > 0

        sender_name = profile.get("sender_name") or "Afterword"
        sub_status = (profile.get("subscription_status") or "free").lower()

        # ── PASS 0: Subscription downgrade → revert to free tier ──
        if sub_status == "free":
            try:
                reverted = handle_subscription_downgrade(
                    client, profile, resend_key, from_email, now,
                )
                if reverted:
                    # Profile was modified in DB (timer reset, theme cleared).
                    # In-memory profile dict is now stale — skip remaining passes.
                    # Next heartbeat cycle will use the fresh values.
                    continue
            except Exception as exc:  # noqa: BLE001
                print(f"Subscription downgrade handling failed for {user_id}: {exc}")

        # ── PASS 1: Timer expired → execute protocol ──

        if remaining.total_seconds() <= 0:

            if not has_entries:
                # Empty vault = timer has no effect. Do NOT mark inactive.
                # User stays active; timer just sits expired until they add entries.
                continue

            had_send = process_expired_entries(

                client,

                profile,

                active_entries,

                server_secret,

                resend_key,

                from_email,

                viewer_base_url,

                fcm_ctx,

                now,

            )

            # Mark user as having had vault activity (prevents bot auto-deletion)
            try:
                client.table("profiles").update({
                    "had_vault_activity": True,
                }).eq("id", user_id).execute()
            except Exception:  # noqa: BLE001
                pass

            # Check if any entries still need processing (failed during this run)
            pending = (
                client.table("vault_entries")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .in_("status", ["active", "sending"])
                .execute()
            )
            has_pending = (pending.count or 0) > 0

            if has_pending:
                print(f"User {user_id}: {pending.count} entries still pending, keeping active for retry")
            elif had_send:
                # Send entries exist → enter grace period (beneficiary can download)
                client.table("profiles").update({
                    "status": "inactive",
                    "timer_days": 30,
                    "protocol_executed_at": now.isoformat(),
                    "warning_sent_at": None,
                    "push_66_sent_at": None,
                    "push_33_sent_at": None,
                    "last_entry_at": None,
                }).eq("id", user_id).execute()
                print(f"User {user_id}: protocol executed, grace period started")
            else:
                # Destroy-only → no grace needed, reset to fresh immediately
                client.table("profiles").update({
                    "status": "active",
                    "timer_days": 30,
                    "last_check_in": now.isoformat(),
                    "protocol_executed_at": None,
                    "warning_sent_at": None,
                    "push_66_sent_at": None,
                    "push_33_sent_at": None,
                    "last_entry_at": None,
                }).eq("id", user_id).execute()
                print(f"User {user_id}: destroy-only vault cleared, account reset to fresh")

            continue



        # Skip users with empty vaults — no warnings needed

        if not has_entries:

            continue



        # ── PASS 2: Push #1 at 66% remaining (ALL users) ──

        if remaining_fraction <= 0.66:

            push_66_sent = parse_iso(profile.get("push_66_sent_at"))

            already_sent_66 = bool(

                push_66_sent and last_check_in and push_66_sent >= last_check_in

            )

            if not already_sent_66:

                push_sent = False

                try:

                    push_sent = send_warning_push(

                        client, user_id, sender_name, deadline, fcm_ctx,

                    )

                except Exception as exc:  # noqa: BLE001

                    print(f"Push 66% warning failed for user {user_id}: {exc}")

                if push_sent:

                    client.table("profiles").update(

                        {"push_66_sent_at": now.isoformat()}

                    ).eq("id", user_id).execute()



        # ── PASS 3: Push #2 at 33% remaining (ALL users) ──

        if remaining_fraction <= 0.33:

            push_33_sent = parse_iso(profile.get("push_33_sent_at"))

            already_sent_33 = bool(

                push_33_sent and last_check_in and push_33_sent >= last_check_in

            )

            if not already_sent_33:

                push_sent = False

                try:

                    push_sent = send_warning_push(

                        client, user_id, sender_name, deadline, fcm_ctx,

                    )

                except Exception as exc:  # noqa: BLE001

                    print(f"Push 33% warning failed for user {user_id}: {exc}")

                if push_sent:

                    client.table("profiles").update(

                        {"push_33_sent_at": now.isoformat()}

                    ).eq("id", user_id).execute()



        # ── PASS 4: Email at 24h before expiry (PAID users only) ──

        if remaining <= WARNING_WINDOW and is_paid(profile.get("subscription_status")):

            warning_sent_at = parse_iso(profile.get("warning_sent_at"))

            already_warned = bool(

                warning_sent_at and last_check_in and warning_sent_at >= last_check_in

            )

            if not already_warned:

                try:

                    send_warning_email(profile, deadline, resend_key, from_email)

                    mark_warning_sent(client, user_id, now)

                except Exception as exc:  # noqa: BLE001

                    print(f"Warning email failed for user {user_id}: {exc}")



      except Exception as exc:  # noqa: BLE001
          print(f"Processing failed for user {profile.get('id', '?')}: {exc}")

    try:
        cleanup_sent_entries(client)
    except Exception as exc:  # noqa: BLE001
        print(f"cleanup_sent_entries failed: {exc}")

    try:
        cleanup_bot_accounts(client, now)
    except Exception as exc:  # noqa: BLE001
        print(f"cleanup_bot_accounts failed: {exc}")

    return 0





if __name__ == "__main__":

    _RETRY_DELAYS = [15, 45]

    for _attempt in range(3):

        try:

            sys.exit(main())

        except Exception as exc:  # noqa: BLE001

            _err = str(exc)

            _transient = any(
                c in _err for c in ("500", "502", "503", "504", "ConnectionError", "Timeout")
            )

            if _transient and _attempt < 2:

                print(f"Transient error (attempt {_attempt + 1}/3), retrying in {_RETRY_DELAYS[_attempt]}s: {exc}")

                time.sleep(_RETRY_DELAYS[_attempt])

            else:

                print(f"Heartbeat failed: {exc}")

                sys.exit(1)

