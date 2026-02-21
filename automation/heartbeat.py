import base64

import hashlib

import hmac

import html as html_mod

import json

import os

import random

import re

import sys

import time

from datetime import datetime, timedelta, timezone

from dataclasses import dataclass



import requests

from google.auth.transport.requests import Request as GoogleAuthRequest

from google.oauth2 import service_account

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from supabase import create_client



AUDIO_BUCKET = "vault-audio"

PAID_STATUSES = {"pro", "lifetime", "premium"}

WARNING_WINDOW = timedelta(days=1)

PUSH_66_REMAINING_FRACTION = 0.66

PUSH_33_REMAINING_FRACTION = 0.33

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

PAGE_SIZE = 1000

PROFILE_BATCH_SIZE = 200

PROFILE_SELECT_FIELDS = (
    "id,email,sender_name,status,subscription_status,last_check_in,timer_days,"
    "hmac_key_encrypted,warning_sent_at,push_66_sent_at,push_33_sent_at,"
    "selected_theme,selected_soul_fire,created_at"
)

REQUEST_TIMEOUT_SECONDS = 30

HTTP_RETRY_DELAYS_SECONDS = (1, 3, 8)

STALE_SENDING_LOCK_MINUTES = 30

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

MAX_RUNTIME_SECONDS = 5.5 * 3600  # 5h30m — exit gracefully before GH Actions 6h limit


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


def iter_rows(query_builder, page_size: int = PAGE_SIZE):
    """Yield paginated rows in batches to avoid loading huge result sets at once."""
    offset = 0
    while True:
        response = query_builder.range(offset, offset + page_size - 1).execute()
        batch = response.data or []
        if not batch:
            break
        yield batch
        if len(batch) < page_size:
            break
        offset += page_size


def iter_active_profiles(client, page_size: int = PROFILE_BATCH_SIZE):
    """Yield active profiles via keyset pagination to avoid offset-skip issues.

    Heartbeat mutates profile.status while processing users. Offset pagination can
    skip rows when the filtered set shrinks mid-run. Keyset pagination on `id`
    remains stable under those updates.
    """
    last_seen_id: str | None = None
    while True:
        query = (
            client.table("profiles")
            .select(PROFILE_SELECT_FIELDS)
            .eq("status", "active")
            .order("id")
            .limit(page_size)
        )
        if last_seen_id is not None:
            query = query.gt("id", last_seen_id)
        response = query.execute()
        batch = response.data or []
        if not batch:
            break
        yield batch
        last_seen_id = str(batch[-1]["id"])





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

    parsed = datetime.fromisoformat(value)

    if parsed.tzinfo is None:

        return parsed.replace(tzinfo=timezone.utc)

    return parsed.astimezone(timezone.utc)


@dataclass(frozen=True)
class TimerState:

    last_check_in: datetime

    deadline: datetime

    total_seconds: int

    remaining_seconds: int

    remaining_fraction: float

    push_66_at: datetime

    push_33_at: datetime

    email_24h_at: datetime


def _normalize_timer_days(timer_days: int | str | None) -> int:

    try:

        parsed = int(timer_days or 0)

    except Exception:  # noqa: BLE001

        parsed = 0

    return max(1, parsed)


def _compute_trigger_from_remaining(

    *,

    last_check_in: datetime,

    total_seconds: int,

    remaining_fraction: float,

) -> datetime:

    elapsed_fraction = 1.0 - remaining_fraction

    elapsed_seconds = max(0.0, min(1.0, elapsed_fraction)) * total_seconds

    return last_check_in + timedelta(seconds=elapsed_seconds)


def build_timer_state(last_check_in: datetime, timer_days: int | str | None, now: datetime) -> TimerState:

    normalized_days = _normalize_timer_days(timer_days)

    total_seconds = normalized_days * 86400

    deadline = last_check_in + timedelta(seconds=total_seconds)

    remaining_seconds = max(int((deadline - now).total_seconds()), 0)

    remaining_fraction = remaining_seconds / total_seconds if total_seconds > 0 else 0.0

    push_66_at = _compute_trigger_from_remaining(

        last_check_in=last_check_in,

        total_seconds=total_seconds,

        remaining_fraction=PUSH_66_REMAINING_FRACTION,

    )

    push_33_at = _compute_trigger_from_remaining(

        last_check_in=last_check_in,

        total_seconds=total_seconds,

        remaining_fraction=PUSH_33_REMAINING_FRACTION,

    )

    email_24h_at = deadline - WARNING_WINDOW

    if email_24h_at < last_check_in:

        email_24h_at = last_check_in

    return TimerState(

        last_check_in=last_check_in,

        deadline=deadline,

        total_seconds=total_seconds,

        remaining_seconds=remaining_seconds,

        remaining_fraction=remaining_fraction,

        push_66_at=push_66_at,

        push_33_at=push_33_at,

        email_24h_at=email_24h_at,

    )


def _already_marked_in_cycle(sent_at: datetime | None, last_check_in: datetime) -> bool:

    return bool(sent_at and sent_at >= last_check_in)


def should_send_push_66(profile: dict, timer_state: TimerState, now: datetime) -> bool:

    if now < timer_state.push_66_at:

        return False

    push_66_sent = parse_iso(profile.get("push_66_sent_at"))

    return not _already_marked_in_cycle(push_66_sent, timer_state.last_check_in)


def should_send_push_33(profile: dict, timer_state: TimerState, now: datetime) -> bool:

    if now < timer_state.push_33_at:

        return False

    push_33_sent = parse_iso(profile.get("push_33_sent_at"))

    return not _already_marked_in_cycle(push_33_sent, timer_state.last_check_in)


def should_send_24h_warning_email(profile: dict, timer_state: TimerState, now: datetime) -> bool:

    if now < timer_state.email_24h_at:

        return False

    if not is_paid(profile.get("subscription_status")):

        return False

    warning_sent_at = parse_iso(profile.get("warning_sent_at"))

    return not _already_marked_in_cycle(warning_sent_at, timer_state.last_check_in)





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


def _is_retryable_http_status(status_code: int) -> bool:

    return status_code in (408, 425, 429, 500, 502, 503, 504)


def _post_json_with_retries(
    url: str,
    *,
    headers: dict[str, str],
    payload: dict,
    idempotency_key: str | None = None,
    timeout: int = REQUEST_TIMEOUT_SECONDS,
) -> requests.Response:

    request_headers = dict(headers)
    if idempotency_key:
        request_headers["Idempotency-Key"] = idempotency_key

    for attempt in range(len(HTTP_RETRY_DELAYS_SECONDS) + 1):

        try:

            response = requests.post(

                url,

                headers=request_headers,

                json=payload,

                timeout=timeout,

            )

        except requests.RequestException as exc:

            if attempt < len(HTTP_RETRY_DELAYS_SECONDS):

                base_delay = HTTP_RETRY_DELAYS_SECONDS[attempt]
                delay = base_delay + random.uniform(0, base_delay * 0.25)

                print(

                    f"HTTP request failed ({exc}); retrying in {delay}s "

                    f"[{attempt + 1}/{len(HTTP_RETRY_DELAYS_SECONDS) + 1}]"

                )

                time.sleep(delay)

                continue

            raise

        if (

            _is_retryable_http_status(response.status_code)

            and attempt < len(HTTP_RETRY_DELAYS_SECONDS)

        ):

            base_delay = HTTP_RETRY_DELAYS_SECONDS[attempt]
            delay = base_delay + random.uniform(0, base_delay * 0.25)

            print(

                f"HTTP {response.status_code} retry in {delay}s "

                f"[{attempt + 1}/{len(HTTP_RETRY_DELAYS_SECONDS) + 1}]"

            )

            time.sleep(delay)

            continue

        return response

    raise RuntimeError("Unreachable retry state")





def _format_from_address(from_email: str) -> str:
    """Ensure from address has a display name for deliverability."""
    if "<" in from_email:
        return from_email  # Already formatted as 'Name <email>'
    return f"Afterword <{from_email}>"


def wrap_email_html(body_html: str) -> str:
    """Wrap bare email body HTML in a proper email document structure.

    Adds DOCTYPE, html/head/body tags, responsive container, and
    CAN-SPAM compliant footer. Critical for email deliverability —
    bare <p> tags without structure trigger spam filters.
    """
    return (
        '<!DOCTYPE html>'
        '<html lang="en" xmlns="http://www.w3.org/1999/xhtml">'
        '<head>'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '<title>Afterword</title>'
        '</head>'
        '<body style="margin:0;padding:0;background-color:#f7f7f7;'
        'font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;'
        'font-size:15px;line-height:1.6;color:#1a1a1a">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'style="background-color:#f7f7f7">'
        '<tr><td align="center" style="padding:32px 16px">'
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'style="max-width:560px;background-color:#ffffff;'
        'border-radius:8px;overflow:hidden">'
        # Header bar
        '<tr><td style="background-color:#0f0f0f;padding:20px 32px">'
        '<span style="color:#ffffff;font-size:18px;font-weight:600;'
        'letter-spacing:0.5px">Afterword</span>'
        '</td></tr>'
        # Body content
        '<tr><td style="padding:28px 32px">'
        f'{body_html}'
        '</td></tr>'
        # Footer
        '<tr><td style="padding:20px 32px;border-top:1px solid #e5e5e5;'
        'background-color:#fafafa">'
        '<p style="margin:0;font-size:12px;color:#999999;line-height:1.5">'
        'This is an automated message from Afterword, a time-locked digital vault app. '
        'You are receiving this because you have an Afterword account or '
        'someone designated you as a recipient.</p>'
        '<p style="margin:8px 0 0;font-size:12px;color:#999999">'
        'Afterword &middot; afterword-app.com</p>'
        '</td></tr>'
        '</table>'
        '</td></tr></table>'
        '</body></html>'
    )


def send_email(
    api_key: str,
    from_email: str,
    to_email: str,
    subject: str,
    text: str,
    html: str,
    *,
    idempotency_key: str | None = None,
) -> None:

    formatted_from = _format_from_address(from_email)
    wrapped_html = wrap_email_html(html)

    payload: dict = {
        "from": formatted_from,
        "to": [to_email],
        "subject": subject,
        "text": text,
        "html": wrapped_html,
        "headers": {
            "List-Unsubscribe": "<mailto:afterword.app@gmail.com?subject=Unsubscribe>",
        },
    }

    response = _post_json_with_retries(

        "https://api.resend.com/emails",

        headers={

            "Authorization": f"Bearer {api_key}",

            "Content-Type": "application/json",

        },

        payload=payload,

        idempotency_key=idempotency_key,

    )

    if response.status_code >= 400:

        raise RuntimeError(f"Resend error: {response.status_code} {response.text}")





def send_warning_email(
    profile: dict,
    deadline: datetime,
    resend_key: str,
    from_email: str,
    *,
    remaining_fraction: float = 0.0,
) -> None:

    email = profile.get("email")

    if not email:

        return

    sender_name = profile.get("sender_name") or "Afterword"

    deadline_text = deadline.strftime("%b %d, %Y at %I:%M %p UTC")

    # Contextual urgency based on remaining fraction
    if remaining_fraction <= 0.10:
        urgency_line = "Your vault is about to execute."
        subject = f"URGENT: Afterword timer expires {deadline.strftime('%b %d')}"
    elif remaining_fraction <= 0.33:
        urgency_line = "Your timer is running critically low."
        subject = f"Afterword warning: timer expires {deadline.strftime('%b %d')}"
    elif remaining_fraction <= 0.66:
        urgency_line = "Your timer is past the halfway mark."
        subject = f"Afterword reminder: check in before {deadline.strftime('%b %d')}"
    else:
        urgency_line = "This is an automated check-in reminder."
        subject = "Afterword reminder: check in now"

    text = (
        f"Hi {sender_name},\n\n"
        f"{urgency_line}\n\n"
        f"Your Afterword timer expires on {deadline_text}.\n"
        "Open the app to check in and keep your vault secure.\n\n"
        "If you are safe, open Afterword today to reset your timer.\n\n"
        "— The Afterword Team\n\n"
        "Afterword is a time-locked digital vault app. You are receiving this email "
        "because you have an active Afterword account with vault entries."
    )

    safe_name = html_mod.escape(sender_name)

    html = (
        f'<p style="margin:0 0 16px">Hi {safe_name},</p>'
        f'<p style="margin:0 0 16px">{urgency_line}</p>'
        f'<p style="margin:0 0 16px">Your Afterword timer expires on '
        f'<strong>{deadline_text}</strong>. '
        'Open the app to check in and keep your vault secure.</p>'
        '<p style="margin:0 0 24px">If you are safe, open Afterword today to reset your timer.</p>'
        '<p style="margin:0;color:#666666;font-size:13px">&mdash; The Afterword Team</p>'
    )

    idempotency_key = f"warning-{profile.get('id', 'unknown')}-{deadline.date().isoformat()}"
    send_email(
        resend_key,
        from_email,
        email,
        subject,
        text,
        html,
        idempotency_key=idempotency_key,
    )





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



    return _post_json_with_retries(

        url,

        headers={

            "Authorization": f"Bearer {access_token}",

            "Content-Type": "application/json",

        },

        payload=payload,

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
    return {
        "project_id": project_id,
        "access_token": access_token,
        "service_account_info": sa_info,
    }


def refresh_fcm_access_token(fcm_ctx: dict) -> bool:

    sa_info = fcm_ctx.get("service_account_info")

    if not isinstance(sa_info, dict):

        return False

    try:

        fcm_ctx["access_token"] = get_fcm_access_token(sa_info)

        return True

    except Exception as exc:  # noqa: BLE001

        print(f"Failed to refresh FCM access token: {exc}")

        return False


def _is_invalid_fcm_token_response(response_text: str) -> bool:

    lowered = response_text.lower()

    return (

        "unregistered" in lowered

        or "registration-token-not-registered" in lowered

        or "invalid registration token" in lowered

        or "requested entity was not found" in lowered

    )


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
    tokens = list(
        dict.fromkeys(
            str(row.get("fcm_token")).strip()
            for row in rows
            if row.get("fcm_token")
        )
    )
    if not tokens:
        print(f"No FCM tokens for user {user_id}, push skipped")
        return False

    sent = False
    for token in tokens:
        try:
            response = send_push_v1(
                project_id=fcm_ctx["project_id"],
                access_token=fcm_ctx["access_token"],
                fcm_token=token,
                title=title,
                body=body,
                data=data,
            )
        except requests.RequestException as exc:
            print(f"Push request failed for user {user_id}: {exc}")
            continue

        if response.status_code in (401, 403) and refresh_fcm_access_token(fcm_ctx):
            try:
                response = send_push_v1(
                    project_id=fcm_ctx["project_id"],
                    access_token=fcm_ctx["access_token"],
                    fcm_token=token,
                    title=title,
                    body=body,
                    data=data,
                )
            except requests.RequestException as exc:
                print(f"Push retry failed for user {user_id}: {exc}")
                continue

        if response.status_code >= 400:
            text = response.text or ""
            if _is_invalid_fcm_token_response(text):
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
    *,
    now_utc: datetime | None = None,
    remaining_fraction: float = 1.0,
) -> bool:
    """Returns True if push was actually delivered to at least one device."""
    if fcm_ctx is None:
        return False
    # Compute human-friendly remaining time (timezone-safe because it's relative)
    now = now_utc or datetime.now(timezone.utc)
    remaining = deadline - now
    total_hours = max(0, remaining.total_seconds() / 3600)
    total_days = remaining.days

    if total_hours < 1:
        time_left = "less than 1 hour"
    elif total_hours < 24:
        h = int(total_hours)
        time_left = f"~{h} hour{'s' if h != 1 else ''}"
    elif total_days < 2:
        time_left = "~1 day"
    else:
        time_left = f"~{total_days} days"

    # Format deadline in a human-friendly way
    deadline_str = deadline.strftime("%b %d, %Y at %I:%M %p UTC")

    if remaining_fraction <= 0.10:
        urgency = f"Only {time_left} left — your vault executes {deadline_str}."
    elif remaining_fraction <= 0.33:
        urgency = f"{time_left} remaining. Timer expires {deadline_str}."
    else:
        urgency = f"{time_left} remaining. Deadline: {deadline_str}."

    return _send_push_to_user(
        client, user_id, fcm_ctx,
        title="Afterword — check in now",
        body=f"Hi {sender_name}, {urgency} Open the app to check in.",
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





def build_unlock_email_payload(
    recipient_email: str,
    entry_id: str,
    sender_name: str,
    entry_title: str,
    viewer_link: str,
    security_key: str,
    from_email: str,
) -> dict:
    """Build the Resend email payload dict for a single unlock email.

    Returns a dict suitable for both the single send and batch endpoints.
    """
    formatted_from = _format_from_address(from_email)
    subject = f"Message from {sender_name}"

    text = (
        f"{sender_name} left you a secure message using Afterword, "
        "a time-locked digital vault app.\n\n"
        f"Title: {entry_title}\n\n"
        "To view this message, open the link below and paste your "
        "security key when prompted.\n\n"
        f"Viewer: {viewer_link}\n\n"
        f"Security Key: {security_key}\n\n"
        "How it works:\n"
        "1. Open the viewer link above in your browser\n"
        "2. Paste the security key into the key field\n"
        "3. Your message will be decrypted locally in your browser\n\n"
        "The security key is never sent to our servers. Do not share "
        "it — anyone with this key can read the message.\n\n"
        "This message will be available for 30 days, after which it "
        "will be permanently and automatically erased.\n\n"
        "If you do not recognize the sender, you may safely ignore "
        "this email.\n\n"
        "— The Afterword Team"
    )

    safe_sender = html_mod.escape(sender_name)
    safe_title = html_mod.escape(entry_title)
    safe_link = html_mod.escape(viewer_link)

    body_html = (
        f'<p style="margin:0 0 16px"><strong>{safe_sender}</strong> left you a secure '
        'message using Afterword, a time-locked digital vault app.</p>'

        f'<p style="margin:0 0 8px"><strong>Title:</strong> {safe_title}</p>'

        '<table role="presentation" cellpadding="0" cellspacing="0" '
        'style="margin:20px 0"><tr><td>'
        f'<a href="{safe_link}" style="display:inline-block;background-color:#0f0f0f;'
        'color:#ffffff;font-size:15px;font-weight:600;padding:12px 28px;'
        'border-radius:6px;text-decoration:none" target="_blank">'
        'Open Secure Message</a>'
        '</td></tr></table>'

        '<p style="margin:0 0 8px"><strong>Your Security Key:</strong></p>'
        '<p style="margin:0 0 16px;background-color:#f4f4f4;padding:12px 16px;'
        'border-radius:6px;font-family:Consolas,Monaco,Courier New,monospace;'
        f'font-size:13px;word-break:break-all;line-height:1.5">{security_key}</p>'

        '<p style="margin:0 0 16px"><strong>How to view your message:</strong></p>'
        '<ol style="margin:0 0 16px;padding-left:20px;color:#333333">'
        '<li style="margin-bottom:6px">Click the button above to open the secure viewer</li>'
        '<li style="margin-bottom:6px">Copy and paste the security key into the key field</li>'
        '<li style="margin-bottom:6px">Your message will be decrypted privately in your browser</li>'
        '</ol>'

        '<p style="margin:0 0 16px;color:#666666;font-size:13px">'
        '<em>The security key is never sent to our servers. Do not share '
        'it — anyone with this key can read the message.</em></p>'

        '<hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0">'

        '<p style="margin:0 0 8px;color:#888888;font-size:12px">'
        'This message will be available for 30 days after delivery, after which '
        'it will be permanently and automatically erased.</p>'
        '<p style="margin:0;color:#888888;font-size:12px">'
        'If you do not recognize the sender, you may safely ignore this email.</p>'
    )

    return {
        "from": formatted_from,
        "to": [recipient_email],
        "subject": subject,
        "text": text,
        "html": wrap_email_html(body_html),
        "headers": {
            "List-Unsubscribe": "<mailto:afterword.app@gmail.com?subject=Unsubscribe>",
        },
    }


def send_unlock_email(
    recipient_email: str,
    entry_id: str,
    sender_name: str,
    entry_title: str,
    viewer_link: str,
    security_key: str,
    resend_key: str,
    from_email: str,
) -> None:
    """Send a single unlock email.  Kept for backward compatibility / simple cases."""
    payload = build_unlock_email_payload(
        recipient_email, entry_id, sender_name, entry_title,
        viewer_link, security_key, from_email,
    )
    response = _post_json_with_retries(
        "https://api.resend.com/emails",
        headers={
            "Authorization": f"Bearer {resend_key}",
            "Content-Type": "application/json",
        },
        payload=payload,
        idempotency_key=f"unlock-{entry_id}",
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Resend error: {response.status_code} {response.text}")


RESEND_BATCH_LIMIT = 100


def send_batch_emails(
    api_key: str,
    payloads: list[dict],
    *,
    idempotency_key: str | None = None,
) -> list[dict]:
    """Send emails via the Resend batch endpoint, chunking if >100.

    Resend limits batch requests to 100 emails each.  This function
    automatically splits larger lists into sequential chunk requests,
    appending a chunk index to the idempotency key for uniqueness.

    Returns a flat list of ``{"id": "..."}`` dicts on success.
    Raises RuntimeError on the first chunk that fails (already-sent
    chunks are NOT rolled back — those emails are delivered).
    """
    if not payloads:
        return []

    all_results: list[dict] = []
    for chunk_idx in range(0, len(payloads), RESEND_BATCH_LIMIT):
        chunk = payloads[chunk_idx : chunk_idx + RESEND_BATCH_LIMIT]
        chunk_key = None
        if idempotency_key:
            chunk_key = (
                idempotency_key
                if len(payloads) <= RESEND_BATCH_LIMIT
                else f"{idempotency_key}-{chunk_idx // RESEND_BATCH_LIMIT}"
            )

        response = _post_json_with_retries(
            "https://api.resend.com/emails/batch",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            payload=chunk,
            idempotency_key=chunk_key,
        )

        if response.status_code >= 400:
            raise RuntimeError(
                f"Resend batch error (chunk {chunk_idx // RESEND_BATCH_LIMIT}): "
                f"{response.status_code} {response.text}"
            )

        data = response.json()
        chunk_results = data.get("data", data) if isinstance(data, dict) else data
        all_results.extend(chunk_results if isinstance(chunk_results, list) else [])

    return all_results





def delete_entry(client, entry: dict) -> None:

    audio_path = entry.get("audio_file_path")

    client.table("vault_entries").delete().eq("id", entry["id"]).execute()

    if audio_path:

        try:

            client.storage.from_(AUDIO_BUCKET).remove([audio_path])

        except Exception as exc:  # noqa: BLE001

            print(f"Failed to delete audio object '{audio_path}' for entry {entry.get('id', '?')}: {exc}")





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

    ).eq("status", "sending").execute()


def mark_entry_sent(client, entry_id: str, sent_at: datetime) -> bool:

    response = client.table("vault_entries").update(

        {"status": "sent", "sent_at": sent_at.isoformat()}

    ).eq("id", entry_id).eq("status", "sending").execute()

    return bool(response.data)


def requeue_stale_sending_entries(client, now: datetime) -> int:

    cutoff = (now - timedelta(minutes=STALE_SENDING_LOCK_MINUTES)).isoformat()

    try:

        response = client.table("vault_entries").update({"status": "active"}).eq(

            "status", "sending"

        ).lt("updated_at", cutoff).execute()

        count = len(response.data or [])

        if count:

            print(f"Recovered {count} stale sending locks")

        return count

    except Exception as exc:  # noqa: BLE001

        print(f"Failed to recover stale sending locks: {exc}")

        return 0





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
) -> tuple[bool, int]:
    """Process expired vault entries using batch email sending.

    Three-phase approach for send entries:
      Phase 1 – Validate & prepare: claim lock, HMAC check, decrypt, build payload
      Phase 2 – Batch send: one Resend API call for ALL emails (avoids rate limits)
      Phase 3 – Finalise: mark entries as sent, send push notifications

    Returns (had_send, input_send_count):
      - had_send: True if any 'send' entries were successfully emailed
      - input_send_count: number of send-type entries in the input
    """
    had_send = False
    input_send_count = sum(
        1 for e in entries
        if (e.get("action_type") or "send").lower() != "destroy"
    )

    sender_name = profile.get("sender_name") or "Afterword"
    user_id = profile.get("id", "?")

    hmac_key_encrypted = profile.get("hmac_key_encrypted")
    hmac_key_bytes = None
    if hmac_key_encrypted:
        try:
            hmac_key_bytes = decrypt_with_server_secret(hmac_key_encrypted, server_secret)
        except Exception as exc:  # noqa: BLE001
            print(f"CRITICAL: Failed to decrypt HMAC key for user {user_id}: {exc}")
    elif input_send_count > 0:
        print(f"CRITICAL: User {user_id} has {input_send_count} send entries but hmac_key_encrypted is NULL in profile")

    # ── Phase 1: Process destroy entries immediately, prepare send entries ──
    # Each prepared send is (entry_id, entry_title, email_payload_dict)
    prepared_sends: list[tuple[str, str, dict]] = []

    for entry in entries:
        entry_id = entry.get("id", "unknown")
        try:
            if not claim_entry_for_sending(client, entry_id):
                continue

            action = (entry.get("action_type") or "send").lower()

            if action == "destroy":
                entry_title = entry.get("title") or "Untitled"
                try:
                    send_executed_push(
                        client, profile["id"], entry_id, entry_title,
                        fcm_ctx, action="destroy",
                    )
                except Exception:  # noqa: BLE001
                    pass
                delete_entry(client, entry)
                continue

            # ── SEND entry validation ──
            # SAFETY: NEVER delete a send entry on validation failure.
            # Release the lock so it stays in the DB for retry next cycle.

            if hmac_key_bytes is None:
                print(f"CRITICAL: Skipping send entry {entry_id} — HMAC key unavailable for user {user_id}")
                release_entry_lock(client, entry_id)
                continue

            recipient_encrypted = entry.get("recipient_email_encrypted") or ""
            signature_message = f"{entry.get('payload_encrypted')}|{recipient_encrypted}"
            expected_signature = compute_hmac_signature(signature_message, hmac_key_bytes)

            if expected_signature != entry.get("hmac_signature"):
                print(f"CRITICAL: HMAC mismatch for send entry {entry_id} user {user_id} — entry preserved for investigation")
                release_entry_lock(client, entry_id)
                continue

            if not recipient_encrypted:
                print(f"CRITICAL: Empty recipient for send entry {entry_id} user {user_id} — entry preserved")
                release_entry_lock(client, entry_id)
                continue

            # Step 1: Decrypt recipient email
            try:
                recipient_ciphertext = extract_server_ciphertext(recipient_encrypted)
                recipient_email = decrypt_with_server_secret(
                    recipient_ciphertext, server_secret
                ).decode("utf-8").strip()
            except Exception as dec_exc:  # noqa: BLE001
                print(f"CRITICAL: Failed to decrypt recipient for send entry {entry_id} user {user_id}: {dec_exc}")
                release_entry_lock(client, entry_id)
                continue

            if not _EMAIL_RE.match(recipient_email):
                print(f"CRITICAL: Invalid recipient email format for send entry {entry_id} user {user_id}: '{recipient_email}' — entry preserved")
                release_entry_lock(client, entry_id)
                continue

            # Step 2: Decrypt data key
            data_key_encrypted = entry.get("data_key_encrypted")
            if not data_key_encrypted:
                print(f"CRITICAL: Missing data_key_encrypted for send entry {entry_id} user {user_id} — entry preserved")
                release_entry_lock(client, entry_id)
                continue

            try:
                data_key_ciphertext = extract_server_ciphertext(data_key_encrypted)
                data_key_bytes = decrypt_with_server_secret(data_key_ciphertext, server_secret)
            except Exception as dk_exc:  # noqa: BLE001
                print(f"CRITICAL: Failed to decrypt data_key for send entry {entry_id} user {user_id}: {dk_exc}")
                release_entry_lock(client, entry_id)
                continue

            security_key = base64.b64encode(data_key_bytes).decode("utf-8")
            viewer_link = build_viewer_link(viewer_base_url, entry_id)
            entry_title = entry.get("title") or "Untitled"

            email_payload = build_unlock_email_payload(
                recipient_email, entry_id, sender_name, entry_title,
                viewer_link, security_key, from_email,
            )
            prepared_sends.append((entry_id, entry_title, email_payload))

        except Exception as exc:  # noqa: BLE001
            try:
                release_entry_lock(client, entry_id)
            except Exception:  # noqa: BLE001
                pass
            print(f"SEND FAILED (prepare) entry {entry_id} user {user_id}: {type(exc).__name__}: {exc}")

    # ── Phase 2: Batch-send all prepared emails in a single API call ──
    if prepared_sends:
        batch_payloads = [p for _, _, p in prepared_sends]
        batch_entry_ids = [eid for eid, _, _ in prepared_sends]
        batch_idem_key = f"unlock-batch-{user_id}-{int(now.timestamp())}"

        try:
            print(f"User {user_id}: sending batch of {len(batch_payloads)} emails")
            send_batch_emails(resend_key, batch_payloads, idempotency_key=batch_idem_key)

            # ── Phase 3: Mark all entries as sent + push notifications ──
            for entry_id, entry_title, _ in prepared_sends:
                try:
                    if not mark_entry_sent(client, entry_id, now):
                        print(f"WARNING: mark_entry_sent returned False for {entry_id}, retrying")
                        mark_entry_sent(client, entry_id, now)
                except Exception as mark_exc:  # noqa: BLE001
                    print(f"Failed to mark entry {entry_id} as sent: {mark_exc}")
                had_send = True
                try:
                    send_executed_push(
                        client, profile["id"], entry_id, entry_title, fcm_ctx,
                    )
                except Exception as push_exc:  # noqa: BLE001
                    print(f"Push executed failed for entry {entry_id}: {push_exc}")

        except Exception as batch_exc:  # noqa: BLE001
            print(f"BATCH SEND FAILED for user {user_id} ({len(batch_payloads)} emails): "
                  f"{type(batch_exc).__name__}: {batch_exc}")
            # Release all locks so entries can be retried next cycle
            for eid in batch_entry_ids:
                try:
                    release_entry_lock(client, eid)
                except Exception:  # noqa: BLE001
                    pass

    return had_send, input_send_count




def cleanup_sent_entries(client) -> None:

    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    now_iso = datetime.now(timezone.utc).isoformat()

    # Paginate sent entries to avoid loading millions into memory
    user_ids: set[str] = set()
    sender_names: dict[str, str] = {}

    for batch in iter_rows(
        client.table("vault_entries")
        .select("id,user_id,audio_file_path,sent_at")
        .eq("status", "sent")
        .lt("sent_at", cutoff)
        .order("id"),
    ):
        # Batch-fetch sender_names for any new user_ids in this batch
        new_uids = {str(e["user_id"]) for e in batch} - set(sender_names.keys())
        if new_uids:
            try:
                profiles_resp = (
                    client.table("profiles")
                    .select("id,sender_name")
                    .in_("id", list(new_uids))
                    .execute()
                )
                for p in (profiles_resp.data or []):
                    sender_names[str(p["id"])] = p.get("sender_name") or "Afterword"
            except Exception:  # noqa: BLE001
                pass
            for uid in new_uids:
                sender_names.setdefault(uid, "Afterword")

        for entry in batch:
            user_ids.add(str(entry["user_id"]))

            # Create tombstone BEFORE deleting (preserves History tab data)
            try:
                client.table("vault_entry_tombstones").insert({
                    "vault_entry_id": entry["id"],
                    "user_id": entry["user_id"],
                    "sender_name": sender_names.get(str(entry["user_id"]), "Afterword"),
                    "sent_at": entry.get("sent_at"),
                    "expired_at": now_iso,
                }).execute()
            except Exception:  # noqa: BLE001
                # Tombstone insert may fail on duplicate PK if already exists — safe to skip
                pass

            # Delete entry (storage files + DB row)
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

    # ── Sweep: reset inactive profiles whose grace period expired ──
    # Handles edge case where all sent entries were already cleaned up
    # (or never existed) but the profile is still stuck as 'inactive'.
    _reset_expired_grace_profiles(client, cutoff, now_iso)


def _reset_expired_grace_profiles(client, cutoff: str, now_iso: str) -> None:
    """Find inactive profiles with expired grace and reset them to active."""
    last_seen_id: str | None = None
    while True:
        query = (
            client.table("profiles")
            .select("id")
            .eq("status", "inactive")
            .lt("protocol_executed_at", cutoff)
            .order("id")
            .limit(200)
        )
        if last_seen_id is not None:
            query = query.gt("id", last_seen_id)
        response = query.execute()
        batch = response.data or []
        if not batch:
            break
        last_seen_id = str(batch[-1]["id"])

        for profile in batch:
            uid = str(profile["id"])
            try:
                # Only reset if user has zero remaining vault entries
                remaining = (
                    client.table("vault_entries")
                    .select("id", count="exact")
                    .eq("user_id", uid)
                    .execute()
                )
                if (remaining.count or 0) > 0:
                    continue

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
                print(f"User {uid}: expired grace period reset (no remaining entries)")
            except Exception:  # noqa: BLE001
                print(f"Failed to reset expired grace profile {uid}")


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

    # Keyset-paginate candidate profiles to avoid loading millions into memory
    last_seen_id: str | None = None
    while True:
        query = (
            client.table("profiles")
            .select("id,email,created_at,last_check_in,had_vault_activity")
            .eq("status", "active")
            .lt("created_at", cutoff)
            .order("id")
            .limit(PROFILE_BATCH_SIZE)
        )
        if last_seen_id is not None:
            query = query.gt("id", last_seen_id)
        response = query.execute()
        candidates = response.data or []
        if not candidates:
            break
        last_seen_id = str(candidates[-1]["id"])

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
    active_entries: list[dict],
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
    FREE_THEMES = {"oledVoid", "midnightFrost", "shadowRose"}
    FREE_SOUL_FIRES = {"etherealOrb", "goldenPulse", "nebulaHeart"}
    has_custom_theme = selected_theme is not None and selected_theme not in FREE_THEMES
    has_custom_soul_fire = selected_soul_fire is not None and selected_soul_fire not in FREE_SOUL_FIRES

    active_audio_entries = [
        entry
        for entry in active_entries
        if (entry.get("data_type") or "").lower() == "audio"
    ]
    has_audio = bool(active_audio_entries)
    audio_entries: list[dict] = []

    # Only query for audio if there are other pro/lifetime indicators.
    # This avoids a DB query for every always-free user at scale.
    has_pro_indicators = has_custom_timer or has_custom_theme or has_custom_soul_fire
    if not has_audio and (has_pro_indicators or (selected_soul_fire in ("toxicCore", "crystalAscend"))):
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
        if active_audio_entries:
            audio_entries = active_audio_entries
        else:
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

    # 3. Send notification email ONLY for genuine downgrades.
    # Strong indicators: timer > 30 (impossible without pro) or audio entries
    # (impossible without lifetime). Theme/soul_fire alone are weak signals
    # that can arise from bugs or testing — silently reset, no email.
    is_genuine_downgrade = has_custom_timer or has_audio
    if email and is_genuine_downgrade:
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
            "- Your timer has been reset to the default 30 days\n"
            "- Custom themes and styles have been reset to defaults\n"
            "- All your existing vault entries are preserved\n"
            f"{'- Audio vault entries have been removed (Lifetime feature)' if was_lifetime and audio_entries else ''}"
            "\n\n"
            "You can continue using Afterword on the free tier, or "
            "resubscribe at any time to restore premium features.\n\n"
            "— The Afterword Team\n\n"
            "Afterword is a time-locked digital vault app. You are receiving "
            "this email because you have an Afterword account."
        )
        safe_name = html_mod.escape(sender_name)
        audio_li = (
            '<li style="margin-bottom:6px">Audio vault entries have been removed (Lifetime feature)</li>'
            if was_lifetime and audio_entries else ''
        )
        html = (
            f'<p style="margin:0 0 16px">Hi {safe_name},</p>'
            f'<p style="margin:0 0 16px">Your Afterword subscription has been updated due to a {reason}. '
            'Your account has been reverted to the free tier.</p>'
            '<p style="margin:0 0 8px"><strong>What this means:</strong></p>'
            '<ul style="margin:0 0 16px;padding-left:20px;color:#333333">'
            '<li style="margin-bottom:6px">Your timer has been reset to the default 30 days</li>'
            '<li style="margin-bottom:6px">Custom themes and styles have been reset to defaults</li>'
            '<li style="margin-bottom:6px">All your existing vault entries are preserved</li>'
            f'{audio_li}'
            '</ul>'
            '<p style="margin:0 0 24px">You can continue using Afterword on the free tier, or '
            'resubscribe at any time to restore premium features.</p>'
            '<p style="margin:0;color:#666666;font-size:13px">&mdash; The Afterword Team</p>'
        )
        try:
            send_email(
                resend_key,
                from_email,
                email,
                subject,
                text,
                html,
                idempotency_key=f"downgrade-{uid}-{now.date().isoformat()}",
            )
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
    fcm_token_minted_at = now  # track when FCM token was last refreshed

    requeue_stale_sending_entries(client, now)



    processed_profiles = 0

    processed_entries = 0

    start_time = time.monotonic()

    for profile_batch in iter_active_profiles(client):

      # Runtime guard: exit gracefully before GH Actions kills the job
      elapsed = time.monotonic() - start_time
      if elapsed > MAX_RUNTIME_SECONDS:
          print(f"Runtime limit reached ({elapsed:.0f}s). Exiting gracefully — "
                f"remaining users will be processed next run.")
          break

      # Proactively refresh FCM token every 45 min to avoid expiry during long runs
      if fcm_ctx is not None:
          fcm_elapsed = (datetime.now(timezone.utc) - fcm_token_minted_at).total_seconds()
          if fcm_elapsed > 2700:  # 45 minutes
              if refresh_fcm_access_token(fcm_ctx):
                  fcm_token_minted_at = datetime.now(timezone.utc)
                  print("Proactively refreshed FCM access token")

      batch_user_ids = [str(p["id"]) for p in profile_batch if p.get("id")]

      batch_entries_by_user: dict[str, list[dict]] = {}

      if batch_user_ids:

        batch_entries = fetch_all_rows(

            client.table("vault_entries")

            .select(

                "id,user_id,title,action_type,data_type,status,payload_encrypted,recipient_email_encrypted,data_key_encrypted,hmac_signature,audio_file_path"

            )

            .eq("status", "active")

            .in_("user_id", batch_user_ids)

            .order("id")

        )

        processed_entries += len(batch_entries)

        for entry in batch_entries:

            batch_entries_by_user.setdefault(str(entry["user_id"]), []).append(entry)

      for profile in profile_batch:

        processed_profiles += 1

        try:

          user_id = str(profile["id"])

          last_check_in = parse_iso(profile.get("last_check_in"))

          if last_check_in is None:

              continue



          timer_state = build_timer_state(last_check_in, profile.get("timer_days"), now)

          deadline = timer_state.deadline

          active_entries = batch_entries_by_user.get(user_id, [])

          has_entries = len(active_entries) > 0

          sender_name = profile.get("sender_name") or "Afterword"
          sub_status = (profile.get("subscription_status") or "free").lower()

          # ── PASS 0: Subscription downgrade → revert to free tier ──
          if sub_status == "free":
              try:
                  reverted = handle_subscription_downgrade(
                      client, profile, active_entries, resend_key, from_email, now,
                  )
                  if reverted:
                      # Profile was modified in DB (timer reset, theme cleared).
                      # In-memory profile dict is now stale — skip remaining passes.
                      # Next heartbeat cycle will use the fresh values.
                      continue
              except Exception as exc:  # noqa: BLE001
                  print(f"Subscription downgrade handling failed for {user_id}: {exc}")

          # ── PASS 1: Timer expired → execute protocol ──

          if timer_state.remaining_seconds <= 0:

              if not has_entries:
                  # Empty vault = timer has no effect. Do NOT mark inactive.
                  # User stays active; timer just sits expired until they add entries.
                  continue

              had_send, input_send_count = process_expired_entries(

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
              elif input_send_count > 0:
                  # SAFETY INVARIANT: There were send entries in the input but
                  # none were successfully sent AND none are pending in DB.
                  # This means they were lost (catastrophic bug). Do NOT reset
                  # to fresh — keep active so the issue is visible.
                  print(
                      f"CRITICAL: User {user_id}: {input_send_count} send entries existed "
                      f"but 0 were sent and 0 are pending. Data may have been lost. "
                      f"Keeping active for investigation — NOT resetting."
                  )
              else:
                  # Truly destroy-only → no grace needed, reset to fresh immediately
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

          if should_send_push_66(profile, timer_state, now):

              push_sent = False

              try:

                  push_sent = send_warning_push(

                      client,

                      user_id,

                      sender_name,

                      deadline,

                      fcm_ctx,

                      now_utc=now,

                      remaining_fraction=timer_state.remaining_fraction,

                  )

              except Exception as exc:  # noqa: BLE001

                  print(f"Push 66% warning failed for user {user_id}: {exc}")

              if push_sent:

                  client.table("profiles").update(

                      {"push_66_sent_at": now.isoformat()}

                  ).eq("id", user_id).execute()



          # ── PASS 3: Push #2 at 33% remaining (ALL users) ──

          if should_send_push_33(profile, timer_state, now):

              push_sent = False

              try:

                  push_sent = send_warning_push(

                      client,

                      user_id,

                      sender_name,

                      deadline,

                      fcm_ctx,

                      now_utc=now,

                      remaining_fraction=timer_state.remaining_fraction,

                  )

              except Exception as exc:  # noqa: BLE001

                  print(f"Push 33% warning failed for user {user_id}: {exc}")

              if push_sent:

                  client.table("profiles").update(

                      {"push_33_sent_at": now.isoformat()}

                  ).eq("id", user_id).execute()



          # ── PASS 4: Email at 24h before expiry (PAID users only) ──

          if should_send_24h_warning_email(profile, timer_state, now):

              try:

                  send_warning_email(
                      profile,
                      deadline,
                      resend_key,
                      from_email,
                      remaining_fraction=timer_state.remaining_fraction,
                  )

                  mark_warning_sent(client, user_id, now)

              except Exception as exc:  # noqa: BLE001

                  print(f"Warning email failed for user {user_id}: {exc}")



        except Exception as exc:  # noqa: BLE001
            print(f"Processing failed for user {profile.get('id', '?')}: {exc}")

    print(f"Active profiles processed: {processed_profiles}")

    print(f"Active entries processed: {processed_entries}")

    try:
        cleanup_sent_entries(client)
    except Exception as exc:  # noqa: BLE001
        print(f"cleanup_sent_entries failed: {exc}")

    try:
        cleanup_bot_accounts(client, now)
    except Exception as exc:  # noqa: BLE001
        print(f"cleanup_bot_accounts failed: {exc}")

    return 0


def is_transient_error_message(message: str) -> bool:

    lowered = message.lower()

    return any(

        token in lowered

        for token in (

            "500",

            "502",

            "503",

            "504",

            "429",

            "connectionerror",

            "timeout",

            "temporar",

            "network",

        )

    )





if __name__ == "__main__":

    _RETRY_DELAYS = [15, 45]

    for _attempt in range(3):

        try:

            sys.exit(main())

        except Exception as exc:  # noqa: BLE001

            _err = str(exc)

            _transient = is_transient_error_message(_err)

            if _transient and _attempt < 2:

                print(f"Transient error (attempt {_attempt + 1}/3), retrying in {_RETRY_DELAYS[_attempt]}s: {exc}")

                time.sleep(_RETRY_DELAYS[_attempt])

            else:

                print(f"Heartbeat failed: {exc}")

                sys.exit(1)

