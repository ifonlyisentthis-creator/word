import base64
import hashlib
import hmac
import os
import sys
from datetime import datetime, timedelta, timezone

import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from supabase import create_client

AUDIO_BUCKET = "vault-audio"
PAID_STATUSES = {"pro", "lifetime", "premium"}
WARNING_WINDOW = timedelta(days=1)


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
    html = (
        f"<p>Hi {sender_name},</p>"
        f"<p>Your Afterword timer expires on <strong>{deadline_text}</strong>. "
        "Open the app to check in and keep your vault secure.</p>"
        "<p>If you are safe, open Afterword today to reset your timer.</p>"
    )
    send_email(resend_key, from_email, email, subject, text, html)


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
        f"{sender_name} left you a secure message in Afterword.\n\n"
        f"Title: {entry_title}\n"
        f"Security Key: {security_key}\n"
        f"Open: {viewer_link}\n\n"
        "The key decrypts the message in your browser.\n\n"
        "Important: This secure transmission expires 30 days after delivery."
    )
    html = (
        f"<p><strong>{sender_name}</strong> left you a secure message in Afterword.</p>"
        f"<p><strong>Title:</strong> {entry_title}</p>"
        f"<p><strong>Security Key:</strong> {security_key}</p>"
        f"<p><a href=\"{viewer_link}\">Open the secure message</a></p>"
        "<p>The key decrypts the message in your browser.</p>"
        "<p><strong>Important:</strong> This secure transmission expires 30 days after delivery.</p>"
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
    now: datetime,
) -> None:
    sender_name = profile.get("sender_name") or "Afterword"
    hmac_key_encrypted = profile.get("hmac_key_encrypted")
    hmac_key_bytes = (
        decrypt_with_server_secret(hmac_key_encrypted, server_secret)
        if hmac_key_encrypted
        else None
    )

    for entry in entries:
        action = (entry.get("action_type") or "send").lower()
        if action == "destroy":
            delete_entry(client, entry)
            continue

        if not claim_entry_for_sending(client, entry["id"]):
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

        recipient_email = decrypt_with_server_secret(
            recipient_encrypted, server_secret
        ).decode("utf-8")
        data_key_encrypted = entry.get("data_key_encrypted")
        if not data_key_encrypted:
            delete_entry(client, entry)
            continue

        data_key_bytes = decrypt_with_server_secret(data_key_encrypted, server_secret)
        security_key = base64.b64encode(data_key_bytes).decode("utf-8")
        viewer_link = build_viewer_link(viewer_base_url, entry["id"])
        entry_title = entry.get("title") or "Untitled"
        try:
            send_unlock_email(
                recipient_email,
                sender_name,
                entry_title,
                viewer_link,
                security_key,
                resend_key,
                from_email,
            )

            client.table("vault_entries").update(
                {"status": "sent", "sent_at": now.isoformat()}
            ).eq("id", entry["id"]).execute()
        except Exception as exc:  # noqa: BLE001
            release_entry_lock(client, entry["id"])
            print(f"Failed to send entry {entry['id']}: {exc}")


def cleanup_sent_entries(client) -> None:
    client.rpc("cleanup_sent_entries", {}).execute()


def main() -> int:
    supabase_url = get_env("SUPABASE_URL")
    supabase_key = get_env("SUPABASE_SERVICE_ROLE_KEY")
    server_secret = get_env("SERVER_SECRET")
    resend_key = get_env("RESEND_API_KEY")
    from_email = get_env("RESEND_FROM_EMAIL")
    viewer_base_url = get_env("VIEWER_BASE_URL")

    client = create_client(supabase_url, supabase_key)
    now = datetime.now(timezone.utc)

    profiles_response = (
        client.table("profiles")
        .select(
            "id,email,sender_name,status,subscription_status,last_check_in,timer_days,"
            "hmac_key_encrypted,warning_sent_at"
        )
        .execute()
    )
    profiles = profiles_response.data or []

    entries_response = (
        client.table("vault_entries")
        .select(
            "id,user_id,title,action_type,data_type,status,payload_encrypted,recipient_email_encrypted,data_key_encrypted,hmac_signature,audio_file_path"
        )
        .eq("status", "active")
        .execute()
    )
    entries = entries_response.data or []
    entries_by_user: dict[str, list[dict]] = {}
    for entry in entries:
        entries_by_user.setdefault(entry["user_id"], []).append(entry)

    for profile in profiles:
        user_id = profile["id"]
        last_check_in = parse_iso(profile.get("last_check_in"))
        timer_days = int(profile.get("timer_days") or 30)
        if last_check_in is None:
            continue

        deadline = last_check_in + timedelta(days=timer_days)
        remaining = deadline - now
        active_entries = entries_by_user.get(user_id, [])
        has_entries = len(active_entries) > 0

        if remaining.total_seconds() <= 0:
            if has_entries:
                process_expired_entries(
                    client,
                    profile,
                    active_entries,
                    server_secret,
                    resend_key,
                    from_email,
                    viewer_base_url,
                    now,
                )
            if (profile.get("status") or "").lower() != "archived":
                mark_profile_status(client, user_id, "inactive")
            continue

        if remaining <= WARNING_WINDOW and is_paid(profile.get("subscription_status")):
            warning_sent_at = parse_iso(profile.get("warning_sent_at"))
            already_warned = bool(
                warning_sent_at and last_check_in and warning_sent_at >= last_check_in
            )
            if has_entries and not already_warned:
                send_warning_email(profile, deadline, resend_key, from_email)
                mark_warning_sent(client, user_id, now)

    cleanup_sent_entries(client)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"Heartbeat failed: {exc}")
        sys.exit(1)
