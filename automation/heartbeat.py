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
    "selected_theme,selected_soul_fire,created_at,downgrade_email_pending"
)

REQUEST_TIMEOUT_SECONDS = 30

HTTP_RETRY_DELAYS_SECONDS = (1, 3, 8)

STALE_SENDING_LOCK_MINUTES = 30

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

MAX_RUNTIME_SECONDS = 5.5 * 3600  # 5h30m — exit gracefully before GH Actions 6h limit

RESEND_INTER_CHUNK_DELAY = 0.15  # seconds between batch chunks to respect rate limits

REVENUECAT_ENTITLEMENT_ID = "AfterWord Pro"

RC_VERIFY_RATE_LIMIT_DELAY = 1.1  # seconds between RC API calls — RC V1 limit is ~60 req/min
RC_429_BACKOFF_SECONDS = 30       # pause when RC returns 429 (rate limited)

_HTTP_SESSION: requests.Session | None = None
_resend_quota_exhausted = False  # set True when Resend daily limit (100/day free) is hit


def _mark_resend_quota_exhausted(response: "requests.Response") -> bool:
    """Check if a Resend response indicates the daily quota is exhausted.

    When the free-tier limit (100 emails/day) is reached, Resend returns 429.
    We detect this and set a module flag so all subsequent sends in the same
    run short-circuit immediately instead of wasting retries.  Pending flags
    (downgrade_email_pending, entry locks) ensure delivery next heartbeat run.
    """
    global _resend_quota_exhausted
    if response.status_code == 429:
        _resend_quota_exhausted = True
        print("Resend rate/quota limit hit — skipping remaining emails this run")
        return True
    return False


def _get_http_session() -> requests.Session:
    global _HTTP_SESSION
    if _HTTP_SESSION is None:
        _HTTP_SESSION = requests.Session()
    return _HTTP_SESSION


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

    if timer_days is None:
        return 30  # match Flutter default — users who never checked in get 30 days

    try:

        parsed = int(timer_days)

    except (ValueError, TypeError):  # noqa: BLE001

        return 30

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

            response = _get_http_session().post(

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


def _extract_email_address(address: str) -> str:
    """Extract raw email address from either 'Name <email>' or 'email'."""
    raw = (address or "").strip()
    if "<" in raw and ">" in raw:
        start = raw.find("<") + 1
        end = raw.find(">", start)
        if end > start:
            return raw[start:end].strip()
    return raw


def wrap_email_html(
    body_html: str,
    *,
    unsubscribe_email: str,
    preheader: str = "",
) -> str:
    """Wrap email body HTML in a premium card layout with dark header.

    Args:
        preheader: Hidden text that appears in inbox preview but not in the
            rendered email. Feeding Gmail's AI a conversational snippet
            dramatically reduces Promotions/Spam classification.
    """
    preheader_block = ""
    if preheader:
        safe_preheader = html_mod.escape(preheader)
        preheader_block = (
            f'<div style="display:none;font-size:1px;color:#f0f0f0;'
            f'line-height:1px;max-height:0px;max-width:0px;opacity:0;'
            f'overflow:hidden">{safe_preheader}'
            '&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;'
            '&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;'
            '&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;'
            '</div>'
        )
    conversational_footer = (
        '<p style="margin:24px 0 0;color:#9a9a9a;font-size:12px;line-height:1.6">'
        'Afterword is a time-locked digital vault app that securely stores '
        'your encrypted messages and delivers them to people you choose. '
        'You are receiving this email because you have an Afterword account. '
        'If you have any questions, simply reply to this email and a real '
        'person will get back to you.</p>'
    )
    return (
        '<!DOCTYPE html>'
        '<html lang="en">'
        '<head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
        '</head>'
        '<body style="margin:0;padding:0;background-color:#f0f0f0;'
        'font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,'
        'Helvetica,Arial,sans-serif">'
        f'{preheader_block}'
        '<div style="max-width:560px;margin:32px auto;background:#ffffff;'
        'border-radius:12px;overflow:hidden">'
        '<div style="background:#0a0a0a;padding:24px 32px">'
        '<span style="color:#ffffff;font-size:22px;font-weight:700;'
        'letter-spacing:0.3px">Afterword</span>'
        '</div>'
        '<div style="padding:28px 32px;font-size:15px;line-height:1.7;'
        'color:#1a1a1a">'
        f'{body_html}'
        f'{conversational_footer}'
        '</div>'
        '<div style="padding:16px 32px 20px;border-top:1px solid #eee;'
        'font-size:11px;color:#999999;line-height:1.5">'
        'Afterword &middot; afterword-app.com<br>'
        f'<a href="mailto:{unsubscribe_email}?subject=Unsubscribe" '
        'style="color:#999999;text-decoration:underline">Unsubscribe</a>'
        '</div>'
        '</div>'
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
    preheader: str = "",
) -> None:
    if _resend_quota_exhausted:
        raise RuntimeError("Resend daily quota exhausted — email deferred to next run")

    formatted_from = _format_from_address(from_email)
    reply_to_email = _extract_email_address(from_email)
    wrapped_html = wrap_email_html(
        html, unsubscribe_email=reply_to_email, preheader=preheader,
    )

    payload: dict = {
        "from": formatted_from,
        "to": [to_email],
        "subject": subject,
        "text": text,
        "html": wrapped_html,
        "reply_to": reply_to_email,
        "headers": {
            "List-Unsubscribe": f"<mailto:{reply_to_email}?subject=Unsubscribe>",
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
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
        _mark_resend_quota_exhausted(response)
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
        "because you have an active Afterword account with vault entries.\n\n"
        "To unsubscribe, reply to this email with subject 'Unsubscribe'."
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
        preheader=f"Hi {sender_name}, your Afterword timer needs attention — check in to keep your vault secure.",
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
        f"Hi,\n\n"
        f"{sender_name} assigned you as a beneficiary on Afterword, "
        "a secure, time-locked digital vault app. "
        "Because their check-in timer expired, the following message "
        "has been automatically released to you.\n\n"
        f"Title: {entry_title}\n\n"
        "To view this message, open the link below and paste your "
        "security key when prompted.\n\n"
        f"Viewer: {viewer_link}\n\n"
        f"Security Key: {security_key}\n\n"
        "How it works:\n"
        "1. Open the viewer link above in your browser\n"
        "2. Paste the security key into the key field\n"
        "3. Your message will be decrypted locally in your browser\n\n"
        "Note: If this email landed in Spam or Promotions, please move "
        "it to your Primary inbox. This helps your email provider learn "
        "that messages from Afterword are important.\n\n"
        "The security key is never sent to our servers. Do not share "
        "it — anyone with this key can read the message.\n\n"
        "This message will be available for 30 days, after which it "
        "will be permanently and automatically erased.\n\n"
        "If you do not recognize the sender, you may safely ignore "
        "this email.\n\n"
        "— The Afterword Team\n\n"
        "To unsubscribe, reply to this email with subject 'Unsubscribe'."
    )

    safe_sender = html_mod.escape(sender_name)
    safe_title = html_mod.escape(entry_title)
    safe_link = html_mod.escape(viewer_link)

    body_html = (
        f'<p style="margin:0 0 12px">Hi,</p>'
        f'<p style="margin:0 0 18px"><strong>{safe_sender}</strong> assigned you as a '
        'beneficiary on Afterword, a secure, time-locked digital vault app. '
        'Because their check-in timer expired, the following message '
        'has been automatically released to you.</p>'

        f'<p style="margin:0 0 20px"><strong>Title:</strong> {safe_title}</p>'

        f'<a href="{safe_link}" target="_blank" style="display:block;'
        'background:#0a0a0a;color:#ffffff;text-decoration:none;'
        'padding:16px 24px;border-radius:8px;font-size:16px;'
        'font-weight:600;text-align:center;margin:0 0 28px">'
        'Open Secure Message</a>'

        '<p style="margin:0 0 8px;font-weight:700">Your Security Key:</p>'
        '<div style="background:#f5f5f5;border:1px solid #e0e0e0;'
        'border-radius:8px;padding:14px 16px;'
        'font-family:\'Courier New\',monospace;font-size:13px;'
        f'word-break:break-all;margin:0 0 28px;color:#333">{security_key}</div>'

        '<p style="margin:0 0 10px;font-weight:700">How to view your message:</p>'
        '<ol style="margin:0 0 20px;padding-left:20px;font-size:14px;'
        'color:#444;line-height:1.8">'
        '<li>Click the button above to open the secure viewer</li>'
        '<li>Paste the security key into the key field</li>'
        '<li>Your message will be decrypted privately in your browser</li>'
        '</ol>'

        '<p style="margin:0 0 20px;font-size:12px;color:#666;'
        'background:#fafafa;border-radius:6px;padding:12px 14px;'
        'border-left:3px solid #ddd">'
        'If this email landed in Spam or Promotions, please move it to your '
        'Primary inbox. This helps your email provider learn that messages '
        'from Afterword are important.</p>'

        '<p style="margin:0 0 12px;color:#888;font-size:12px;font-style:italic">'
        'The security key is never sent to our servers. Do not share it '
        '&mdash; anyone with this key can read the message.</p>'

        '<p style="margin:0;color:#888;font-size:12px">'
        'This message will be available for 30 days, after which it '
        'will be permanently erased. '
        'If you do not recognize the sender, you may safely ignore this email.</p>'
    )

    reply_to_email = _extract_email_address(from_email)

    return {
        "from": formatted_from,
        "to": [recipient_email],
        "subject": subject,
        "text": text,
        "html": wrap_email_html(
            body_html,
            unsubscribe_email=reply_to_email,
            preheader=f"{sender_name} assigned you as a beneficiary. A secure message has been released to you.",
        ),
        "reply_to": reply_to_email,
        "headers": {
            "List-Unsubscribe": f"<mailto:{reply_to_email}?subject=Unsubscribe>",
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
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
    if _resend_quota_exhausted:
        raise RuntimeError("Resend daily quota exhausted — email deferred to next run")
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
        _mark_resend_quota_exhausted(response)
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
    if _resend_quota_exhausted:
        raise RuntimeError("Resend daily quota exhausted — batch deferred to next run")

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
            _mark_resend_quota_exhausted(response)
            raise RuntimeError(
                f"Resend batch error (chunk {chunk_idx // RESEND_BATCH_LIMIT}): "
                f"{response.status_code} {response.text}"
            )

        data = response.json()
        chunk_results = data.get("data", data) if isinstance(data, dict) else data
        all_results.extend(chunk_results if isinstance(chunk_results, list) else [])

        # Throttle between chunks to respect Resend rate limits
        if chunk_idx + RESEND_BATCH_LIMIT < len(payloads):
            time.sleep(RESEND_INTER_CHUNK_DELAY)

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





def heal_inconsistent_profiles(client, now: datetime) -> None:
    """Detect and fix inconsistent profile states at startup.

    Guards against stuck states that could otherwise persist forever:
      1. Active profile with protocol_executed_at set → stale field, clear it.
      2. Inactive profile WITHOUT protocol_executed_at → orphaned inactive, reset.
    """
    now_iso = now.isoformat()

    # Guard 1: Active profiles with stale protocol_executed_at (keyset-paginated)
    try:
        healed_1 = 0
        last_id_g1: str | None = None
        while True:
            q1 = (
                client.table("profiles")
                .select("id")
                .eq("status", "active")
                .not_.is_("protocol_executed_at", "null")
                .order("id")
                .limit(PROFILE_BATCH_SIZE)
            )
            if last_id_g1 is not None:
                q1 = q1.gt("id", last_id_g1)
            resp1 = q1.execute()
            rows1 = resp1.data or []
            if not rows1:
                break
            last_id_g1 = str(rows1[-1]["id"])
            for row in rows1:
                uid = str(row["id"])
                client.table("profiles").update({
                    "protocol_executed_at": None,
                }).eq("id", uid).eq("status", "active").execute()
                healed_1 += 1
        if healed_1:
            print(f"Healed {healed_1} active profiles with stale protocol_executed_at")
    except Exception as exc:  # noqa: BLE001
        print(f"Guard 1 (stale protocol_executed_at) failed: {exc}")

    # Guard 2: Inactive profiles with NULL protocol_executed_at (keyset-paginated)
    try:
        healed_2 = 0
        last_id_g2: str | None = None
        while True:
            q2 = (
                client.table("profiles")
                .select("id")
                .eq("status", "inactive")
                .is_("protocol_executed_at", "null")
                .order("id")
                .limit(PROFILE_BATCH_SIZE)
            )
            if last_id_g2 is not None:
                q2 = q2.gt("id", last_id_g2)
            resp2 = q2.execute()
            rows2 = resp2.data or []
            if not rows2:
                break
            last_id_g2 = str(rows2[-1]["id"])
            for row in rows2:
                uid = str(row["id"])
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
                healed_2 += 1
        if healed_2:
            print(f"Healed {healed_2} orphaned inactive profiles (no protocol_executed_at)")
    except Exception as exc:  # noqa: BLE001
        print(f"Guard 2 (orphaned inactive) failed: {exc}")

    # Guard 3: Expired grace periods are handled by cleanup_sent_entries
    # which runs at the end of main(). No separate startup sweep needed.


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
    # Each prepared send is (entry_id, entry_title, recipient, viewer_link, security_key, email_payload)
    prepared_sends: list[tuple[str, str, str, str, str, dict]] = []

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
            prepared_sends.append((entry_id, entry_title, recipient_email, viewer_link, security_key, email_payload))

        except Exception as exc:  # noqa: BLE001
            try:
                release_entry_lock(client, entry_id)
            except Exception:  # noqa: BLE001
                pass
            print(f"SEND FAILED (prepare) entry {entry_id} user {user_id}: {type(exc).__name__}: {exc}")

    # ── Phase 2+3: Send in chunks, mark entries as sent after each chunk ──
    # Each chunk is up to RESEND_BATCH_LIMIT (100) emails via Resend batch API.
    # Entries are marked "sent" IMMEDIATELY after their chunk succeeds, so they
    # can never be re-claimed by claim_entry_for_sending on retry.  This
    # eliminates all duplicate-email risk regardless of idempotency key expiry.
    if prepared_sends:
        all_entry_ids = [eid for eid, _, _, _, _, _ in prepared_sends]

        # Stable idempotency key base: hash of sorted entry IDs
        entry_hash = hashlib.md5(
            "|".join(sorted(all_entry_ids)).encode()
        ).hexdigest()[:16]
        idem_base = f"unlock-batch-{user_id}-{entry_hash}"

        total_chunks = (len(prepared_sends) + RESEND_BATCH_LIMIT - 1) // RESEND_BATCH_LIMIT
        print(f"User {user_id}: sending {len(prepared_sends)} emails in {total_chunks} chunk(s)")

        for chunk_start in range(0, len(prepared_sends), RESEND_BATCH_LIMIT):
            # Early bail if Resend quota was hit by a previous chunk / email
            if _resend_quota_exhausted:
                for eid in all_entry_ids[chunk_start:]:
                    try:
                        release_entry_lock(client, eid)
                    except Exception:  # noqa: BLE001
                        pass
                break

            chunk = prepared_sends[chunk_start : chunk_start + RESEND_BATCH_LIMIT]
            chunk_payloads = [p for _, _, _, _, _, p in chunk]
            chunk_idx = chunk_start // RESEND_BATCH_LIMIT
            chunk_key = idem_base if total_chunks == 1 else f"{idem_base}-{chunk_idx}"

            try:
                response = _post_json_with_retries(
                    "https://api.resend.com/emails/batch",
                    headers={
                        "Authorization": f"Bearer {resend_key}",
                        "Content-Type": "application/json",
                    },
                    payload=chunk_payloads,
                    idempotency_key=chunk_key,
                )
                if response.status_code >= 400:
                    _mark_resend_quota_exhausted(response)
                    raise RuntimeError(
                        f"Resend batch error (chunk {chunk_idx}): "
                        f"{response.status_code} {response.text}"
                    )
            except Exception as chunk_exc:  # noqa: BLE001
                print(f"CHUNK {chunk_idx} FAILED for user {user_id}: "
                      f"{type(chunk_exc).__name__}: {chunk_exc}")
                # Release THIS chunk + all remaining chunks for retry next cycle
                for eid in all_entry_ids[chunk_start:]:
                    try:
                        release_entry_lock(client, eid)
                    except Exception:  # noqa: BLE001
                        pass
                break

            # ── Chunk succeeded — mark entries as sent IMMEDIATELY ──
            for entry_id, entry_title, *_ in chunk:
                marked = False
                for _mark_attempt in range(3):
                    try:
                        if mark_entry_sent(client, entry_id, now):
                            marked = True
                            break
                    except Exception as mark_exc:  # noqa: BLE001
                        if _mark_attempt == 2:
                            print(f"Failed to mark entry {entry_id} as sent after 3 attempts: {mark_exc}")
                    if _mark_attempt < 2:
                        time.sleep(1)
                if not marked:
                    print(f"WARNING: Could not mark entry {entry_id} as sent — will be requeued")
                had_send = True
                try:
                    send_executed_push(
                        client, profile["id"], entry_id, entry_title, fcm_ctx,
                    )
                except Exception:  # noqa: BLE001
                    pass

            # Throttle between chunks to respect Resend rate limits
            if chunk_start + RESEND_BATCH_LIMIT < len(prepared_sends):
                time.sleep(RESEND_INTER_CHUNK_DELAY)

    return had_send, input_send_count




def cleanup_sent_entries(client) -> None:
    """Grace-based cleanup: when grace period ends, delete ALL sent entries immediately.

    Flow:
      1. Find profiles with expired grace (inactive + protocol_executed_at <= 30 days ago)
      2. For each profile:
         a) If unprocessed entries exist → re-activate with expired timer for retry
         b) Otherwise → tombstone + delete ALL sent entries → reset profile to fresh
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    now_iso = datetime.now(timezone.utc).isoformat()
    print(f"cleanup_sent_entries: scanning for profiles with expired grace (cutoff={cutoff})")

    total_found = 0
    total_deleted = 0
    total_tombstoned = 0
    reset_count = 0

    last_profile_id: str | None = None
    while True:
        prof_q = (
            client.table("profiles")
            .select("id,sender_name,timer_days")
            .eq("status", "inactive")
            .lte("protocol_executed_at", cutoff)
            .order("id")
            .limit(PROFILE_BATCH_SIZE)
        )
        if last_profile_id is not None:
            prof_q = prof_q.gt("id", last_profile_id)
        prof_resp = prof_q.execute()
        profiles = prof_resp.data or []
        if not profiles:
            break
        last_profile_id = str(profiles[-1]["id"])

        for profile in profiles:
            uid = str(profile["id"])
            sender_name = profile.get("sender_name") or "Afterword"

            try:
                # Check for unprocessed entries (active/sending) — partial failure
                unprocessed = (
                    client.table("vault_entries")
                    .select("id", count="exact")
                    .eq("user_id", uid)
                    .in_("status", ["active", "sending"])
                    .execute()
                )
                unprocessed_count = unprocessed.count or 0

                if unprocessed_count > 0:
                    # Re-activate with expired timer so main loop retries sending
                    timer_days = _normalize_timer_days(profile.get("timer_days"))
                    expired_check_in = (
                        datetime.now(timezone.utc) - timedelta(days=timer_days + 1)
                    ).isoformat()
                    client.table("profiles").update({
                        "status": "active",
                        "last_check_in": expired_check_in,
                        "protocol_executed_at": None,
                        "warning_sent_at": None,
                        "push_66_sent_at": None,
                        "push_33_sent_at": None,
                    }).eq("id", uid).execute()
                    reset_count += 1
                    print(
                        f"User {uid}: grace expired but {unprocessed_count} unprocessed "
                        f"entries remain — re-activated with expired timer for retry"
                    )
                    continue

                # Delete ALL sent entries for this user (grace ended = immediate cleanup)
                last_entry_id: str | None = None
                while True:
                    entry_q = (
                        client.table("vault_entries")
                        .select("id,user_id,audio_file_path,sent_at")
                        .eq("user_id", uid)
                        .eq("status", "sent")
                        .order("id")
                        .limit(PAGE_SIZE)
                    )
                    if last_entry_id is not None:
                        entry_q = entry_q.gt("id", last_entry_id)
                    entry_resp = entry_q.execute()
                    entries = entry_resp.data or []
                    if not entries:
                        break
                    last_entry_id = str(entries[-1]["id"])

                    total_found += len(entries)
                    for entry in entries:
                        # Create tombstone BEFORE deleting (preserves History tab data).
                        # GUARD: Only delete if tombstone recorded or already exists.
                        tombstone_ok = False
                        try:
                            client.table("vault_entry_tombstones").insert({
                                "vault_entry_id": entry["id"],
                                "user_id": entry["user_id"],
                                "sender_name": sender_name,
                                "sent_at": entry.get("sent_at"),
                                "expired_at": now_iso,
                            }).execute()
                            tombstone_ok = True
                            total_tombstoned += 1
                        except Exception as tomb_exc:  # noqa: BLE001
                            if "duplicate" in str(tomb_exc).lower() or "23505" in str(tomb_exc):
                                tombstone_ok = True
                            else:
                                print(f"CRITICAL: Tombstone insert failed for entry {entry.get('id', '?')}: {tomb_exc} — skipping delete to preserve history")

                        if tombstone_ok:
                            try:
                                delete_entry(client, entry)
                                total_deleted += 1
                            except Exception as del_exc:  # noqa: BLE001
                                print(f"Failed to delete sent entry {entry.get('id', '?')}: {del_exc}")

                # SAFETY GUARD: Only reset profile if ALL entries were actually removed.
                # If tombstone/delete failed for any entry, keep inactive for retry.
                remaining_check = (
                    client.table("vault_entries")
                    .select("id", count="exact")
                    .eq("user_id", uid)
                    .execute()
                )
                remaining_count = remaining_check.count or 0
                if remaining_count > 0:
                    print(
                        f"User {uid}: grace expired but {remaining_count} entries "
                        f"still remain after cleanup — keeping inactive for retry"
                    )
                    continue

                # All entries removed — reset profile to fresh active state
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
                reset_count += 1
                print(f"User {uid}: grace period ended, all entries cleaned up, account reset")

            except Exception as exc:  # noqa: BLE001
                print(f"Failed to process expired grace profile {uid}: {type(exc).__name__}: {exc}")

    print(
        f"cleanup_sent_entries: done — "
        f"profiles_reset={reset_count} found={total_found} "
        f"tombstoned={total_tombstoned} deleted={total_deleted}"
    )


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


def _build_downgrade_email(
    sender_name: str,
    had_audio: bool,
    reason: str = "refund or expiration",
) -> tuple[str, str, str]:
    """Build downgrade notification email content.

    Returns (subject, text, html).
    """
    text_preserved_line = (
        "- Your text vault entries are preserved\n"
        if had_audio
        else "- All your existing vault entries are preserved\n"
    )
    text_audio_line = (
        "- Audio vault entries have been removed (requires paid subscription)\n"
        if had_audio
        else ""
    )
    subject = "Afterword — Subscription update"
    text = (
        f"Hi {sender_name},\n\n"
        f"Your Afterword subscription has been updated due to a {reason}. "
        "Your account has been reverted to the free tier.\n\n"
        "What this means:\n"
        "- Your timer has been reset to the default 30 days\n"
        "- Custom themes and styles have been reset to defaults\n"
        f"{text_preserved_line}"
        f"{text_audio_line}"
        "\n\n"
        "You can continue using Afterword on the free tier, or "
        "resubscribe at any time to restore premium features.\n\n"
        "— The Afterword Team\n\n"
        "Afterword is a time-locked digital vault app. You are receiving "
        "this email because you have an Afterword account.\n\n"
        "To unsubscribe, reply to this email with subject 'Unsubscribe'."
    )
    safe_name = html_mod.escape(sender_name)
    html_preserved_li = (
        '<li style="margin-bottom:6px">Your text vault entries are preserved</li>'
        if had_audio
        else '<li style="margin-bottom:6px">All your existing vault entries are preserved</li>'
    )
    html_audio_li = (
        '<li style="margin-bottom:6px">Audio vault entries have been removed (requires paid subscription)</li>'
        if had_audio else ''
    )
    html = (
        f'<p style="margin:0 0 16px">Hi {safe_name},</p>'
        f'<p style="margin:0 0 16px">Your Afterword subscription has been updated due to a {reason}. '
        'Your account has been reverted to the free tier.</p>'
        '<p style="margin:0 0 8px"><strong>What this means:</strong></p>'
        '<ul style="margin:0 0 16px;padding-left:20px;color:#333333">'
        '<li style="margin-bottom:6px">Your timer has been reset to the default 30 days</li>'
        '<li style="margin-bottom:6px">Custom themes and styles have been reset to defaults</li>'
        f'{html_preserved_li}'
        f'{html_audio_li}'
        '</ul>'
        '<p style="margin:0 0 24px">You can continue using Afterword on the free tier, or '
        'resubscribe at any time to restore premium features.</p>'
        '<p style="margin:0;color:#666666;font-size:13px">&mdash; The Afterword Team</p>'
    )
    return subject, text, html


def verify_subscription_with_revenuecat(
    rc_api_secret: str,
    user_id: str,
    entitlement_id: str = REVENUECAT_ENTITLEMENT_ID,
) -> str | None:
    """Query RevenueCat REST API to get the authoritative subscription status.

    Returns 'free', 'pro', or 'lifetime'.  Returns None on API error so the
    caller can fall back to the DB value without incorrectly downgrading.

    This is the server-side safety net: even if the client never syncs and
    the webhook never fires, the heartbeat will catch subscription changes.
    """
    session = _get_http_session()
    url = f"https://api.revenuecat.com/v1/subscribers/{requests.utils.quote(user_id, safe='')}"
    try:
        resp = session.get(
            url,
            headers={
                "Authorization": f"Bearer {rc_api_secret}",
                "Content-Type": "application/json",
            },
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"RC verify failed for {user_id}: {type(exc).__name__}: {exc}")
        return None

    if resp.status_code == 404:
        # User not known to RevenueCat → free
        return "free"

    if resp.status_code == 429:
        # Rate-limited — back off so subsequent calls in this batch succeed
        print(f"RC verify 429 rate-limited for {user_id} — backing off {RC_429_BACKOFF_SECONDS}s")
        time.sleep(RC_429_BACKOFF_SECONDS)
        return None

    if not resp.ok:
        print(f"RC verify HTTP {resp.status_code} for {user_id}: {resp.text[:200]}")
        return None

    try:
        data = resp.json()
    except Exception:  # noqa: BLE001
        return None

    subscriber = data.get("subscriber") or {}
    entitlements_raw = subscriber.get("entitlements") or {}

    now_dt = datetime.now(timezone.utc)
    active_entitlements = []
    for key, ent in entitlements_raw.items():
        if not isinstance(ent, dict):
            continue
        expires = ent.get("expires_date")
        if expires is None:
            active_entitlements.append((key, ent))  # lifetime / non-expiring
        elif isinstance(expires, str):
            try:
                if datetime.fromisoformat(expires.replace("Z", "+00:00")) > now_dt:
                    active_entitlements.append((key, ent))
            except (ValueError, TypeError):
                pass

    has_entitlement = any(k == entitlement_id for k, _ in active_entitlements)
    is_lifetime = any(
        (ent.get("product_identifier") or "").lower().find("lifetime") >= 0
        for _, ent in active_entitlements
    )

    if is_lifetime:
        return "lifetime"
    if has_entitlement:
        return "pro"

    # Log when RC says "free" but the user had entitlements with different keys
    # (helps diagnose entitlement ID mismatches like "AfterWord Pro" vs "Afterword Pro")
    if entitlements_raw:
        ent_keys = list(entitlements_raw.keys())
        print(
            f"RC verify: user {user_id} has entitlements {ent_keys} but none match "
            f"'{entitlement_id}' — returning free"
        )
    return "free"


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

    Uses a ``downgrade_email_pending`` flag to guarantee the notification email
    is eventually delivered even if the first send attempt fails (transient
    network error, Resend rate-limit, etc.).  Previous versions wiped all
    premium indicators *before* attempting the email — if the email failed, the
    next heartbeat run could no longer detect that a downgrade had occurred and
    the email was permanently lost.

    Actions:
      1. Compose email content BEFORE any DB changes (needs current indicators)
      2. Reset timer_days to 30 (free default) — timer restarts fresh
      3. Reset last_check_in to now() — user gets full 30 days
      4. Clear warning timestamps
      5. Reset theme and soul fire to free defaults
      6. Delete all audio vault entries (audio requires pro/lifetime)
      7. Send notification email to user
      8. Clear downgrade_email_pending only on successful send
    """
    uid = profile["id"]
    email = profile.get("email")
    sender_name = profile.get("sender_name") or "Afterword"
    timer_days = int(profile.get("timer_days") or 30)
    downgrade_email_pending = profile.get("downgrade_email_pending", False)

    # Detect if downgrade handling is needed:
    # subscription_status is already 'free' (set by RevenueCat webhook),
    # but timer_days != 30 (custom timer) or custom theme/soul_fire is set
    selected_theme = profile.get("selected_theme")
    selected_soul_fire = profile.get("selected_soul_fire")
    has_custom_timer = timer_days != 30
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

    # Check for audio entries if we have any pro/lifetime indicators, or if
    # active_entries didn't include audio (audio is now pro+lifetime feature).
    has_pro_indicators = has_custom_timer or has_custom_theme or has_custom_soul_fire
    if not has_audio and has_pro_indicators:
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

    # ── Retry path: indicators already wiped by a previous run, but email ──
    # ── was never delivered.  The downgrade_email_pending flag persists    ──
    # ── across runs so we can retry until the email finally goes through. ──
    if not needs_revert and downgrade_email_pending:
        if email:
            subject, text, html = _build_downgrade_email(sender_name, had_audio=False)
            try:
                send_email(
                    resend_key, from_email, email, subject, text, html,
                    idempotency_key=f"downgrade-retry-{uid}-{now.date().isoformat()}",
                    preheader=f"Hi {sender_name}, your Afterword subscription has changed — here is what happened to your account.",
                )
                client.table("profiles").update({
                    "downgrade_email_pending": False,
                }).eq("id", uid).execute()
                print(f"Sent deferred downgrade notification to {uid}")
            except Exception as exc:  # noqa: BLE001
                print(f"Deferred downgrade email still failing for {uid}: {exc}")
        else:
            # No email address — clear the flag so we stop retrying
            client.table("profiles").update({
                "downgrade_email_pending": False,
            }).eq("id", uid).execute()
        return False  # nothing was reverted, don't skip remaining passes

    # Nothing to revert and no pending email → user is already on free tier
    if not needs_revert:
        return False

    # ── Fresh downgrade: compose email BEFORE wiping indicators ──
    # Strong indicators: timer != 30 (impossible without pro) or audio entries
    # (impossible without pro/lifetime). Theme/soul_fire alone are weak signals
    # that can arise from bugs or testing — silently reset, no email.
    is_genuine_downgrade = has_custom_timer or has_audio
    email_needed = bool(email) and is_genuine_downgrade

    email_content: tuple[str, str, str] | None = None
    if email_needed:
        email_content = _build_downgrade_email(
            sender_name, had_audio=has_audio,
        )

    # 1. Reset profile to free defaults
    update_data: dict = {
        "timer_days": 30,
        "last_check_in": now.isoformat(),
        "warning_sent_at": None,
        "push_66_sent_at": None,
        "push_33_sent_at": None,
        "selected_theme": None,
        "selected_soul_fire": None,
    }
    # Mark email as pending — will be cleared only after successful send
    if email_needed:
        update_data["downgrade_email_pending"] = True
    client.table("profiles").update(update_data).eq("id", uid).execute()

    # 2. Delete audio vault entries (audio requires pro/lifetime)
    if has_audio:
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
            print(f"Deleted {len(audio_entries)} audio entries for downgraded user {uid}")

    # 3. Send notification email
    if email_content:
        subject, text, html = email_content
        try:
            send_email(
                resend_key,
                from_email,
                email,
                subject,
                text,
                html,
                idempotency_key=f"downgrade-{uid}-{now.date().isoformat()}",
                preheader=f"Hi {sender_name}, your Afterword subscription has changed — here is what happened to your account.",
            )
            # Email succeeded — clear the pending flag
            client.table("profiles").update({
                "downgrade_email_pending": False,
            }).eq("id", uid).execute()
            print(f"Sent downgrade notification to {uid}")
        except Exception as exc:  # noqa: BLE001
            # Email failed — downgrade_email_pending stays True for retry
            print(f"Failed to send downgrade email to {uid}: {exc} — will retry next run")

    return True


def main() -> int:

    supabase_url = get_env("SUPABASE_URL")

    supabase_key = get_env("SUPABASE_SERVICE_ROLE_KEY")

    server_secret = get_env("SERVER_SECRET")

    resend_key = get_env("RESEND_API_KEY")

    from_email = get_env("RESEND_FROM_EMAIL")

    viewer_base_url = get_env("VIEWER_BASE_URL")

    firebase_sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")

    rc_api_secret = os.getenv("REVENUECAT_API_SECRET", "")
    if not rc_api_secret:
        print("WARNING: REVENUECAT_API_SECRET not set — server-side subscription verification disabled")

    client = create_client(supabase_url, supabase_key)

    now = datetime.now(timezone.utc)

    fcm_ctx = build_fcm_context(firebase_sa_json)
    fcm_token_minted_at = now  # track when FCM token was last refreshed

    requeue_stale_sending_entries(client, now)

    try:
        heal_inconsistent_profiles(client, now)
    except Exception as exc:  # noqa: BLE001
        print(f"heal_inconsistent_profiles failed: {exc}")

    processed_profiles = 0

    processed_entries = 0

    start_time = time.monotonic()

    for profile_batch in iter_active_profiles(client):

      # Refresh `now` each batch so timestamps stay accurate during multi-hour runs
      now = datetime.now(timezone.utc)

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
              print(f"WARN: User {user_id} has NULL last_check_in — skipping (timer cannot be computed)")
              continue



          timer_state = build_timer_state(last_check_in, profile.get("timer_days"), now)

          deadline = timer_state.deadline

          active_entries = batch_entries_by_user.get(user_id, [])

          has_entries = len(active_entries) > 0

          sender_name = profile.get("sender_name") or "Afterword"
          sub_status = (profile.get("subscription_status") or "free").lower()

          # ── PRE-PASS: Server-side RC subscription verification ──
          # Query RevenueCat directly to get authoritative status.
          # This catches upgrades, downgrades, renewals, and cancellations
          # even when the client is logged out, phone destroyed, or webhook failed.
          #
          # SCALABILITY: At ~1.1s per RC call (rate-limited to ~60 req/min),
          # verifying every user is too slow at scale. We only verify users where a mismatch
          # is plausible:
          #   - Paid users → catch cancellations, expirations, refunds
          #   - Free users with pro indicators → catch missed webhook upgrades
          #   - Users with pending downgrade email → confirm still free
          # Free users with NO pro indicators are the vast majority and need no
          # verification — they were never paid or have already been downgraded.
          if rc_api_secret:
              selected_theme = profile.get("selected_theme")
              selected_soul_fire = profile.get("selected_soul_fire")
              _FREE_THEMES = {"oledVoid", "midnightFrost", "shadowRose", None}
              _FREE_SF = {"etherealOrb", "goldenPulse", "nebulaHeart", None}
              has_pro_indicators = (
                  int(profile.get("timer_days") or 30) != 30
                  or selected_theme not in _FREE_THEMES
                  or selected_soul_fire not in _FREE_SF
              )
              needs_rc_verify = (
                  sub_status in PAID_STATUSES  # paid → catch cancellations
                  or has_pro_indicators         # free + pro artifacts → missed webhook
                  or profile.get("downgrade_email_pending")  # pending email → confirm status
              )
              if needs_rc_verify:
                  try:
                      rc_status = verify_subscription_with_revenuecat(
                          rc_api_secret, user_id,
                      )
                      if rc_status is not None and rc_status != sub_status:
                          print(f"RC verify: user {user_id} DB={sub_status} RC={rc_status} — updating DB")
                          try:
                              client.table("profiles").update({
                                  "subscription_status": rc_status,
                              }).eq("id", user_id).execute()
                              sub_status = rc_status
                              profile["subscription_status"] = rc_status
                          except Exception as db_exc:  # noqa: BLE001
                              print(f"Failed to update subscription for {user_id}: {db_exc}")
                      time.sleep(RC_VERIFY_RATE_LIMIT_DELAY)
                  except Exception as rc_exc:  # noqa: BLE001
                      print(f"RC verify error for {user_id}: {rc_exc}")

          # Clear stale downgrade flag when user re-subscribes
          if sub_status in PAID_STATUSES and profile.get("downgrade_email_pending"):
              try:
                  client.table("profiles").update({
                      "downgrade_email_pending": False,
                  }).eq("id", user_id).execute()
              except Exception:  # noqa: BLE001
                  pass

          # ── PASS 1: Timer expired → execute protocol ──
          # IMPORTANT: This MUST run before subscription downgrade (PASS 0).
          # The downgrade handler resets last_check_in and timer_days, which
          # would prevent expired entries from ever being sent.  Entry delivery
          # is the core purpose of the app — it must never be blocked by
          # subscription state changes.

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

          # ── PASS 0: Subscription downgrade → revert to free tier ──
          # Runs AFTER timer-expiry check so that entry delivery is never
          # blocked by a subscription status change.
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

    elapsed_total = time.monotonic() - start_time
    print(
        f"=== Heartbeat complete ===\n"
        f"  Profiles processed: {processed_profiles}\n"
        f"  Active entries seen: {processed_entries}\n"
        f"  Runtime: {elapsed_total:.1f}s"
    )

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

