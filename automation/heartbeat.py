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
    "selected_theme,selected_soul_fire,created_at,downgrade_email_pending,app_mode"
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

# Free-tier themes and soul fires (used in multiple downgrade checks)
FREE_THEMES = frozenset({"oledVoid", "midnightFrost", "shadowRose", None})
FREE_SOUL_FIRES = frozenset({"etherealOrb", "goldenPulse", "nebulaHeart", None})

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

    notification: dict = {"title": title, "body": body}

    payload: dict = {

        "message": {

            "token": fcm_token,

            "notification": notification,

        }

    }

    if data:

        payload["message"]["data"] = data

    # Android notification tag prevents device-side collapsing between
    # different push types (66%, 33%, warning, executed).
    tag = (data or {}).get("type") or "afterword"
    payload["message"]["android"] = {
        "notification": {"tag": tag},
    }



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
    push_stage: str = "warning",
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
        data={"type": push_stage},
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





def _fragment_security_key(key: str) -> tuple[str, str]:
    """Break a Base64 key into 3 chunks separated by spaces.

    Disguises the continuous high-entropy string as a standard reference
    code, lowering heuristic risk scores in email spam filters that flag
    contiguous Base64 strings as obfuscated payloads.

    Returns (plain_text, html_text) with double-space and &nbsp; separators.
    """
    n = len(key)
    third = n // 3
    r = n % 3
    c1 = third + (1 if r > 0 else 0)
    c2 = c1 + third + (1 if r > 1 else 0)
    parts = [key[:c1], key[c1:c2], key[c2:]]
    return (
        "  ".join(parts),
        "&nbsp;&nbsp;".join(html_mod.escape(p) for p in parts),
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
    """Build the Resend email payload for a beneficiary unlock email.

    Structured to land in the Primary inbox:
    - Simple <div dir="ltr"> HTML mimicking a native Gmail client message
    - No styled buttons, dark headers, or marketing layout
    - Key fragmented into 3 chunks to avoid Base64 pattern detection
    - No List-Unsubscribe header (this is a 1-to-1 delivery, not bulk)
    - Plain text and HTML in exact parity
    - Title excluded from body to avoid triggering content filters
    """
    formatted_from = _format_from_address(from_email)
    safe_sender = html_mod.escape(sender_name)
    safe_link = html_mod.escape(viewer_link)
    key_plain, key_html = _fragment_security_key(security_key)

    subject = f"A personal message from {sender_name}"

    text = (
        "Hi,\n\n"
        f"{sender_name} asked me to ensure you received this message.\n\n"
        "They prepared a private digital vault for you via our service, "
        "which they scheduled for delivery at this specific time. Per their "
        "instructions, the file has been secured, and no one else has "
        "access to it.\n\n"
        "You can view their message here:\n"
        f"{viewer_link}\n\n"
        "To unlock it, you will need the unique access sequence "
        "they generated for you:\n\n"
        f"  {key_plain}\n\n"
        "Please keep this sequence safe. For your privacy, this is an "
        "automated delivery and this inbox is not monitored for replies.\n\n"
        "Take care,\n\n"
        "The Afterword Team\n"
        "https://afterword-app.com"
    )

    html = (
        '<div dir="ltr">'
        '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;'
        'color:#222222;line-height:1.5">'
        '<p>Hi,</p>'
        f'<p>{safe_sender} asked me to ensure you received this message.</p>'
        '<p>They prepared a private digital vault for you via our service, '
        'which they scheduled for delivery at this specific time. Per their '
        'instructions, the file has been secured, and no one else has '
        'access to it.</p>'
        f'<p>You can view their message here:<br>'
        f'<a href="{safe_link}" style="color:#1155cc;text-decoration:underline">'
        f'{safe_link}</a></p>'
        '<p>To unlock it, you will need the unique access sequence '
        'they generated for you:</p>'
        "<p style=\"font-family:'Courier New',Courier,monospace;"
        'background-color:#f8f9fa;padding:12px;border-radius:4px;'
        'display:inline-block;letter-spacing:1px;'
        f'margin-top:5px;margin-bottom:5px">'
        f'{key_html}</p>'
        '<p>Please keep this sequence safe. For your privacy, this is an '
        'automated delivery and this inbox is not monitored for replies.</p>'
        '<p>Take care,</p>'
        '<p>The Afterword Team<br>'
        '<a href="https://afterword-app.com" style="color:#1155cc;'
        'text-decoration:none">https://afterword-app.com</a></p>'
        '</div></div>'
    )

    return {
        "from": formatted_from,
        "to": [recipient_email],
        "subject": subject,
        "text": text,
        "html": html,
        "headers": {},
    }


def build_zk_unlock_email_payload(
    recipient_email: str,
    entry_id: str,
    sender_name: str,
    entry_title: str,
    viewer_link: str,
    from_email: str,
) -> dict:
    """Build email payload for a zero-knowledge vault entry.

    Same deliverability-optimized format as build_unlock_email_payload but
    WITHOUT the security key. The sender chose self-managed key mode, so the
    beneficiary must obtain the key directly from the sender.
    """
    formatted_from = _format_from_address(from_email)
    safe_sender = html_mod.escape(sender_name)
    safe_link = html_mod.escape(viewer_link)

    subject = f"A personal message from {sender_name}"

    text = (
        "Hi,\n\n"
        f"{sender_name} asked me to ensure you received this message.\n\n"
        "They prepared a private digital vault for you via our service, "
        "which they scheduled for delivery at this specific time. Per their "
        "instructions, the file has been secured with a self-managed access "
        "sequence that only they control.\n\n"
        "You can view their message here:\n"
        f"{viewer_link}\n\n"
        "To unlock it, you will need the unique access sequence "
        "they generated. Please contact them or check any instructions "
        "they may have left for you.\n\n"
        "For your privacy, this is an automated delivery and this inbox "
        "is not monitored for replies.\n\n"
        "Take care,\n\n"
        "The Afterword Team\n"
        "https://afterword-app.com"
    )

    html = (
        '<div dir="ltr">'
        '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;'
        'color:#222222;line-height:1.5">'
        '<p>Hi,</p>'
        f'<p>{safe_sender} asked me to ensure you received this message.</p>'
        '<p>They prepared a private digital vault for you via our service, '
        'which they scheduled for delivery at this specific time. Per their '
        'instructions, the file has been secured with a self-managed access '
        'sequence that only they control.</p>'
        f'<p>You can view their message here:<br>'
        f'<a href="{safe_link}" style="color:#1155cc;text-decoration:underline">'
        f'{safe_link}</a></p>'
        '<p>To unlock it, you will need the unique access sequence '
        'they generated. Please contact them or check any instructions '
        'they may have left for you.</p>'
        '<p>For your privacy, this is an automated delivery and this inbox '
        'is not monitored for replies.</p>'
        '<p>Take care,</p>'
        '<p>The Afterword Team<br>'
        '<a href="https://afterword-app.com" style="color:#1155cc;'
        'text-decoration:none">https://afterword-app.com</a></p>'
        '</div></div>'
    )

    return {
        "from": formatted_from,
        "to": [recipient_email],
        "subject": subject,
        "text": text,
        "html": html,
        "headers": {},
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

    if not response.data:
        return False

    # Double-guard: verify the write actually persisted (triggers can silently revert)
    verify = client.table("vault_entries").select("status").eq("id", entry_id).execute()
    if not verify.data or verify.data[0].get("status") != "sending":
        print(f"CRITICAL: claim_entry_for_sending write was silently reverted for {entry_id} — trigger or DB issue")
        return False
    return True





def release_entry_lock(client, entry_id: str) -> None:

    client.table("vault_entries").update({"status": "active"}).eq(

        "id", entry_id

    ).eq("status", "sending").execute()


def mark_entry_sent(client, entry_id: str, sent_at: datetime) -> bool:

    response = client.table("vault_entries").update(

        {"status": "sent", "sent_at": sent_at.isoformat()}

    ).eq("id", entry_id).eq("status", "sending").execute()

    if not response.data:
        return False

    # Double-guard: verify the write actually persisted (triggers can silently revert)
    verify = client.table("vault_entries").select("status").eq("id", entry_id).execute()
    if not verify.data or verify.data[0].get("status") != "sent":
        print(f"CRITICAL: mark_entry_sent write was silently reverted for {entry_id} — trigger or DB issue")
        return False
    return True


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
                }).eq("id", uid).eq("status", "inactive").execute()
                healed_2 += 1
        if healed_2:
            print(f"Healed {healed_2} orphaned inactive profiles (no protocol_executed_at)")
    except Exception as exc:  # noqa: BLE001
        print(f"Guard 2 (orphaned inactive) failed: {exc}")

    # Guard 3: Expired grace periods are handled by cleanup_sent_entries
    # which runs at the end of main(). No separate startup sweep needed.


def _try_send_tampering_notification(
    client,
    profile: dict,
    resend_key: str,
    from_email: str,
    decryption_failures: int,
    now: datetime,
) -> None:
    """Best-effort email to user when AES-GCM decryption fails on their entries.

    This indicates genuine data corruption or tampering — NOT a simple HMAC key
    rotation.  AES-GCM is authenticated encryption; if the ciphertext or tag was
    modified, decryption raises an error.  This is the only scenario where we
    alert the user.
    """
    uid = profile.get("id", "?")
    email = profile.get("email")
    sender_name = profile.get("sender_name") or "Afterword"
    if not email:
        return

    subject = "Afterword — Important Security Notice"
    text = (
        f"Hi {sender_name},\n\n"
        f"Our system detected that {decryption_failures} vault "
        f"{'entry has' if decryption_failures == 1 else 'entries have'} "
        f"data that could not be verified.\n\n"
        f"This may indicate data corruption.  The affected "
        f"{'entry was' if decryption_failures == 1 else 'entries were'} "
        f"preserved and will not be sent until the issue is resolved.\n\n"
        f"If you recently restored your account on a new device, "
        f"please open the app and re-save any affected entries. "
        f"If you did not make changes, please contact support.\n\n"
        f"— The Afterword Team"
    )
    html = (
        f"<p>Hi {sender_name},</p>"
        f"<p>Our system detected that <strong>{decryption_failures}</strong> vault "
        f"{'entry has' if decryption_failures == 1 else 'entries have'} "
        f"data that could not be verified.</p>"
        f"<p>This may indicate data corruption. The affected "
        f"{'entry was' if decryption_failures == 1 else 'entries were'} "
        f"preserved and will not be sent until the issue is resolved.</p>"
        f"<p>If you recently restored your account on a new device, "
        f"please open the app and re-save any affected entries. "
        f"If you did not make changes, please contact support.</p>"
        f"<p>— The Afterword Team</p>"
    )
    try:
        send_email(
            resend_key, from_email, email, subject, text, html,
            idempotency_key=f"tamper-{uid}-{now.date().isoformat()}",
            preheader="Important security notice about your Afterword vault.",
        )
        print(f"User {uid}: sent tampering notification email")
    except Exception as exc:  # noqa: BLE001
        print(f"User {uid}: failed to send tampering notification: {exc}")


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
        and (e.get("entry_mode") or "standard") != "recurring"
    )

    sender_name = profile.get("sender_name") or "Afterword"
    user_id = profile.get("id", "?")

    hmac_key_encrypted = profile.get("hmac_key_encrypted")
    hmac_key_bytes = None
    if hmac_key_encrypted:
        try:
            hmac_key_bytes = decrypt_with_server_secret(hmac_key_encrypted, server_secret)
        except Exception as exc:  # noqa: BLE001
            print(f"WARNING: Failed to decrypt HMAC key for user {user_id}: {exc} — delivery will proceed without HMAC check")
    elif input_send_count > 0:
        print(f"WARNING: User {user_id} has {input_send_count} send entries but hmac_key_encrypted is NULL — delivery will proceed without HMAC check")

    # Counters for post-loop integrity summary
    hmac_mismatches = 0
    decryption_failures = 0

    # ── Phase 1: Process destroy entries immediately, prepare send entries ──
    # Each prepared send is (entry_id, entry_title, recipient, viewer_link, security_key, email_payload)
    prepared_sends: list[tuple[str, str, str, str, str, dict]] = []

    for entry in entries:
        # Skip recurring (Forever Letters) — never consumed by timer expiry
        if (entry.get("entry_mode") or "standard") == "recurring":
            continue
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

            # ── HMAC integrity check (advisory, NOT a delivery gate) ──
            # AES-GCM authenticated encryption is the authoritative tamper
            # check — if the ciphertext was modified, decryption fails.
            # HMAC mismatches are most often caused by legitimate HMAC key
            # rotation (device change, app reinstall, secure-storage wipe)
            # and must NOT block delivery.
            hmac_ok = False
            if hmac_key_bytes is not None:
                recipient_encrypted = entry.get("recipient_email_encrypted") or ""
                signature_message = f"{entry.get('payload_encrypted')}|{recipient_encrypted}"
                expected_signature = compute_hmac_signature(signature_message, hmac_key_bytes)
                hmac_ok = expected_signature == entry.get("hmac_signature")
                if not hmac_ok:
                    hmac_mismatches += 1
            else:
                recipient_encrypted = entry.get("recipient_email_encrypted") or ""

            if not recipient_encrypted:
                print(f"CRITICAL: Empty recipient for send entry {entry_id} user {user_id} — entry preserved")
                release_entry_lock(client, entry_id)
                continue

            # Step 1: Decrypt recipient email (AES-GCM — authoritative integrity check)
            try:
                recipient_ciphertext = extract_server_ciphertext(recipient_encrypted)
                recipient_email = decrypt_with_server_secret(
                    recipient_ciphertext, server_secret
                ).decode("utf-8").strip()
            except Exception as dec_exc:  # noqa: BLE001
                print(f"CRITICAL: Failed to decrypt recipient for send entry {entry_id} user {user_id}: {dec_exc}")
                decryption_failures += 1
                release_entry_lock(client, entry_id)
                continue

            if not _EMAIL_RE.match(recipient_email):
                print(f"CRITICAL: Invalid recipient email format for send entry {entry_id} user {user_id} — entry preserved")
                release_entry_lock(client, entry_id)
                continue

            # Step 2: Decrypt data key or handle ZK entry
            is_zk = entry.get("is_zero_knowledge", False)
            viewer_link = build_viewer_link(viewer_base_url, entry_id)
            entry_title = entry.get("title") or "Untitled"

            if is_zk:
                # Zero-knowledge: server never has the data key.
                # Send email WITHOUT the security key.
                security_key = None
                email_payload = build_zk_unlock_email_payload(
                    recipient_email, entry_id, sender_name, entry_title,
                    viewer_link, from_email,
                )
            else:
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
                    decryption_failures += 1
                    release_entry_lock(client, entry_id)
                    continue

                security_key = base64.b64encode(data_key_bytes).decode("utf-8")
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

    # ── Post-loop integrity summary ──
    if hmac_mismatches > 0 and decryption_failures == 0:
        # All decryptions succeeded → data was NOT tampered, just key rotation.
        print(
            f"HMAC-INFO: User {user_id}: {hmac_mismatches} HMAC mismatch(es) "
            f"but all AES-GCM decryptions succeeded — likely HMAC key rotation "
            f"(device change / app reinstall). Entries delivered normally."
        )
    elif decryption_failures > 0:
        # AES-GCM decryption failed → genuine corruption or tampering.
        print(
            f"CRITICAL: User {user_id}: {decryption_failures} entry decryption "
            f"failure(s) detected — possible data corruption or tampering. "
            f"HMAC mismatches: {hmac_mismatches}."
        )
        _try_send_tampering_notification(
            client=client,
            profile=profile,
            resend_key=resend_key,
            from_email=from_email,
            decryption_failures=decryption_failures,
            now=now,
        )

    return had_send, input_send_count


def process_scheduled_entries(
    client,
    profile: dict,
    entries: list[dict],
    server_secret: str,
    resend_key: str,
    from_email: str,
    viewer_base_url: str,
    now: datetime,
) -> int:
    """Process scheduled vault entries whose scheduled_at has arrived.

    Time Capsule mode: each entry has its own scheduled_at date. When that
    date passes, the entry is delivered. No global timer, no push notifications.

    Per-entry grace: after delivery, grace_until = now + 30 days (beneficiary
    gets a full 30 days from actual delivery, not from the scheduled date).

    Returns the number of entries successfully sent.
    """
    sender_name = profile.get("sender_name") or "Afterword"
    user_id = str(profile.get("id", "?"))
    sent_count = 0

    # Counters for post-loop integrity summary (parity with process_expired_entries)
    hmac_mismatches = 0
    decryption_failures = 0

    # Filter to entries whose scheduled_at has arrived
    due_entries = []
    for entry in entries:
        # Skip recurring (Forever Letters) — handled by process_recurring_entries
        if (entry.get("entry_mode") or "standard") == "recurring":
            continue
        scheduled_at_str = entry.get("scheduled_at")
        if not scheduled_at_str:
            continue
        scheduled_at = parse_iso(scheduled_at_str)
        if scheduled_at is not None and scheduled_at <= now:
            due_entries.append(entry)

    if not due_entries:
        return 0

    hmac_key_encrypted = profile.get("hmac_key_encrypted")
    hmac_key_bytes = None
    if hmac_key_encrypted:
        try:
            hmac_key_bytes = decrypt_with_server_secret(hmac_key_encrypted, server_secret)
        except Exception as exc:  # noqa: BLE001
            print(f"WARNING: Failed to decrypt HMAC key for scheduled user {user_id}: {exc}")

    prepared_sends: list[tuple[str, str, str, str, str | None, dict]] = []

    for entry in due_entries:
        entry_id = entry.get("id", "unknown")
        try:
            if not claim_entry_for_sending(client, entry_id):
                continue

            action = (entry.get("action_type") or "send").lower()

            if action == "destroy":
                entry_title = entry.get("title") or "Untitled"
                delete_entry(client, entry)
                continue

            # Decrypt recipient email
            recipient_encrypted = entry.get("recipient_email_encrypted") or ""

            # ── HMAC integrity check (advisory, NOT a delivery gate) ──
            # Mirrors process_expired_entries: AES-GCM is the authoritative
            # tamper check; HMAC mismatches are usually key rotation.
            if hmac_key_bytes is not None:
                signature_message = f"{entry.get('payload_encrypted')}|{recipient_encrypted}"
                expected_signature = compute_hmac_signature(signature_message, hmac_key_bytes)
                hmac_ok = expected_signature == entry.get("hmac_signature")
                if not hmac_ok:
                    hmac_mismatches += 1

            if not recipient_encrypted:
                print(f"CRITICAL: Empty recipient for scheduled entry {entry_id} user {user_id}")
                release_entry_lock(client, entry_id)
                continue

            try:
                recipient_ciphertext = extract_server_ciphertext(recipient_encrypted)
                recipient_email = decrypt_with_server_secret(
                    recipient_ciphertext, server_secret
                ).decode("utf-8").strip()
            except Exception as dec_exc:  # noqa: BLE001
                print(f"CRITICAL: Failed to decrypt recipient for scheduled entry {entry_id}: {dec_exc}")
                decryption_failures += 1
                release_entry_lock(client, entry_id)
                continue

            if not _EMAIL_RE.match(recipient_email):
                print(f"CRITICAL: Invalid recipient email format for scheduled entry {entry_id}")
                release_entry_lock(client, entry_id)
                continue

            # Decrypt data key or handle ZK
            is_zk = entry.get("is_zero_knowledge", False)
            viewer_link = build_viewer_link(viewer_base_url, entry_id)
            entry_title = entry.get("title") or "Untitled"

            if is_zk:
                security_key = None
                email_payload = build_zk_unlock_email_payload(
                    recipient_email, entry_id, sender_name, entry_title,
                    viewer_link, from_email,
                )
            else:
                data_key_encrypted = entry.get("data_key_encrypted")
                if not data_key_encrypted:
                    print(f"CRITICAL: Missing data_key for scheduled entry {entry_id}")
                    release_entry_lock(client, entry_id)
                    continue

                try:
                    data_key_ciphertext = extract_server_ciphertext(data_key_encrypted)
                    data_key_bytes = decrypt_with_server_secret(data_key_ciphertext, server_secret)
                except Exception as dk_exc:  # noqa: BLE001
                    print(f"CRITICAL: Failed to decrypt data_key for scheduled entry {entry_id}: {dk_exc}")
                    decryption_failures += 1
                    release_entry_lock(client, entry_id)
                    continue

                security_key = base64.b64encode(data_key_bytes).decode("utf-8")
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
            print(f"SEND FAILED (prepare) scheduled entry {entry_id} user {user_id}: {exc}")

    # Send prepared emails in batches
    if prepared_sends:
        all_entry_ids = [eid for eid, _, _, _, _, _ in prepared_sends]
        entry_hash = hashlib.md5(
            "|".join(sorted(all_entry_ids)).encode()
        ).hexdigest()[:16]
        idem_base = f"scheduled-batch-{user_id}-{entry_hash}"

        total_chunks = (len(prepared_sends) + RESEND_BATCH_LIMIT - 1) // RESEND_BATCH_LIMIT
        print(f"User {user_id} (scheduled): sending {len(prepared_sends)} emails in {total_chunks} chunk(s)")

        for chunk_start in range(0, len(prepared_sends), RESEND_BATCH_LIMIT):
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
                print(f"CHUNK {chunk_idx} FAILED for scheduled user {user_id}: {chunk_exc}")
                for eid in all_entry_ids[chunk_start:]:
                    try:
                        release_entry_lock(client, eid)
                    except Exception:  # noqa: BLE001
                        pass
                break

            # Mark entries as sent with per-entry grace_until
            for entry_id, entry_title, *_ in chunk:
                marked = False
                for _mark_attempt in range(3):
                    try:
                        if mark_entry_sent(client, entry_id, now):
                            # Set per-entry grace_until = now + 30 days
                            grace_until = (now + timedelta(days=30)).isoformat()
                            gu_ok = False
                            for _gu_attempt in range(3):
                                try:
                                    client.table("vault_entries").update({
                                        "grace_until": grace_until,
                                    }).eq("id", entry_id).execute()
                                    # Double-guard: verify grace_until persisted
                                    verify = client.table("vault_entries").select("grace_until").eq("id", entry_id).execute()
                                    if verify.data and verify.data[0].get("grace_until"):
                                        gu_ok = True
                                        break
                                    else:
                                        print(f"WARNING: grace_until write silently reverted for {entry_id} (attempt {_gu_attempt + 1})")
                                except Exception:  # noqa: BLE001
                                    if _gu_attempt < 2:
                                        time.sleep(0.5)
                            if not gu_ok:
                                # Email already sent — do NOT revert to active.
                                # Reverting would cause duplicate emails on next run.
                                # Missing grace_until just means the entry won't
                                # auto-cleanup, which is far safer than re-sending.
                                print(f"WARNING: grace_until failed for scheduled entry {entry_id}, keeping status=sent (no revert)")
                            marked = True
                            break
                    except Exception as mark_exc:  # noqa: BLE001
                        if _mark_attempt == 2:
                            print(f"Failed to mark scheduled entry {entry_id} as sent: {mark_exc}")
                    if _mark_attempt < 2:
                        time.sleep(1)
                if marked:
                    sent_count += 1

            if chunk_start + RESEND_BATCH_LIMIT < len(prepared_sends):
                time.sleep(RESEND_INTER_CHUNK_DELAY)

    if sent_count > 0:
        try:
            client.table("profiles").update({
                "had_vault_activity": True,
            }).eq("id", user_id).execute()
        except Exception:  # noqa: BLE001
            pass
        print(f"User {user_id} (scheduled): {sent_count} entries delivered")

    # ── Post-loop integrity summary (parity with process_expired_entries) ──
    if hmac_mismatches > 0 and decryption_failures == 0:
        print(
            f"HMAC-INFO: User {user_id} (scheduled): {hmac_mismatches} HMAC "
            f"mismatch(es) but all AES-GCM decryptions succeeded — likely "
            f"HMAC key rotation (device change / app reinstall). "
            f"Entries delivered normally."
        )
    elif decryption_failures > 0:
        print(
            f"CRITICAL: User {user_id} (scheduled): {decryption_failures} "
            f"entry decryption failure(s) detected — possible data "
            f"corruption or tampering. HMAC mismatches: {hmac_mismatches}."
        )
        _try_send_tampering_notification(
            client=client,
            profile=profile,
            resend_key=resend_key,
            from_email=from_email,
            decryption_failures=decryption_failures,
            now=now,
        )

    return sent_count


def process_recurring_entries(
    client,
    profile: dict,
    entries: list[dict],
    server_secret: str,
    resend_key: str,
    from_email: str,
    viewer_base_url: str,
    now: datetime,
) -> int:
    """Process recurring (Forever Letters) entries whose annual date has arrived.

    Recurring entries are never marked as 'sent'. Instead, last_sent_year is
    updated so we only send once per calendar year.  Feb 29 entries fire on
    Feb 28 in non-leap years.

    Returns the number of entries successfully sent this run.
    """
    import calendar

    sender_name = profile.get("sender_name") or "Afterword"
    user_id = str(profile.get("id", "?"))
    current_year = now.year
    today_month = now.month
    today_day = now.day
    sent_count = 0
    decryption_failures = 0

    due_entries = []
    for entry in entries:
        if (entry.get("entry_mode") or "standard") != "recurring":
            continue
        scheduled_at_str = entry.get("scheduled_at")
        if not scheduled_at_str:
            continue
        scheduled_at = parse_iso(scheduled_at_str)
        if scheduled_at is None:
            continue

        # Already sent this year?
        last_sent_year = entry.get("last_sent_year")
        if last_sent_year is not None and int(last_sent_year) >= current_year:
            continue

        # If the stored year is in the future, the first delivery isn't due
        # until that year (e.g. user picked Feb 20 next year on March 31).
        if scheduled_at.year > current_year:
            continue

        entry_month = scheduled_at.month
        entry_day = scheduled_at.day

        # Handle Feb 29 in non-leap years: fire on Feb 28
        if entry_month == 2 and entry_day == 29:
            if not calendar.isleap(current_year):
                entry_day = 28

        # Use >= comparison so a missed day (heartbeat outage) still fires
        # on the next run rather than being skipped for the entire year.
        entry_date = (entry_month, entry_day)
        today_date = (today_month, today_day)
        if entry_date <= today_date:
            due_entries.append(entry)

    if not due_entries:
        return 0

    print(f"User {user_id} (recurring): {len(due_entries)} Forever Letter(s) due today")

    for entry in due_entries:
        if _resend_quota_exhausted:
            print(f"Resend quota exhausted, deferring remaining recurring entries for {user_id}")
            break
        entry_id = str(entry.get("id", "?"))
        entry_title = str(entry.get("title", "Untitled"))

        # Optimistic lock: claim entry to prevent concurrent heartbeat instances
        # from double-sending.  Entry is released back to 'active' after send
        # (recurring entries must stay active for next year's delivery).
        if not claim_entry_for_sending(client, entry_id):
            print(f"Skipping recurring entry {entry_id}: already claimed by another instance")
            continue

        try:
            # Decrypt recipient email (same pattern as scheduled entries)
            recipient_encrypted = entry.get("recipient_email_encrypted") or ""
            if not recipient_encrypted:
                print(f"Skipping recurring entry {entry_id}: no recipient")
                continue

            recipient_ciphertext = extract_server_ciphertext(recipient_encrypted)
            try:
                recipient_email = decrypt_with_server_secret(
                    recipient_ciphertext, server_secret
                ).decode("utf-8").strip()
            except Exception as rec_dec_exc:
                decryption_failures += 1
                print(f"CRITICAL: Recipient decryption failed for recurring entry {entry_id}: {rec_dec_exc}")
                continue

            if not _EMAIL_RE.match(recipient_email):
                print(f"Skipping recurring entry {entry_id}: invalid recipient email")
                continue

            viewer_link = build_viewer_link(viewer_base_url, entry_id)

            # Forever Letters cannot use ZK mode — skip if misconfigured
            if entry.get("is_zero_knowledge", False):
                print(f"CRITICAL: Recurring entry {entry_id} has is_zero_knowledge=True — Forever Letters do not support ZK mode, skipping")
                continue

            data_key_encrypted = entry.get("data_key_encrypted")
            if not data_key_encrypted:
                print(f"CRITICAL: Missing data_key for recurring entry {entry_id}")
                continue

            data_key_ciphertext = extract_server_ciphertext(data_key_encrypted)
            try:
                data_key_bytes = decrypt_with_server_secret(data_key_ciphertext, server_secret)
            except Exception as dec_exc:
                decryption_failures += 1
                print(f"CRITICAL: AES-GCM decryption failed for recurring entry {entry_id}: {dec_exc}")
                continue
            security_key = base64.b64encode(data_key_bytes).decode("utf-8")
            email_payload = build_unlock_email_payload(
                recipient_email, entry_id, sender_name, entry_title,
                viewer_link, security_key, from_email,
            )

            # Send via batch API (single-item batch for idempotency key support)
            idem_key = f"recurring-{entry_id}-{current_year}"
            response = _post_json_with_retries(
                "https://api.resend.com/emails/batch",
                headers={
                    "Authorization": f"Bearer {resend_key}",
                    "Content-Type": "application/json",
                },
                payload=[email_payload],
                idempotency_key=idem_key,
            )
            if response.status_code >= 400:
                _mark_resend_quota_exhausted(response)
                raise RuntimeError(
                    f"Resend error for recurring entry {entry_id}: "
                    f"{response.status_code} {response.text}"
                )

            # Update last_sent_year (entry stays active).
            # Retry up to 3 times — if this fails after email was sent,
            # the idempotency key (recurring-{id}-{year}) prevents duplicate
            # emails within 24h, but beyond that window a re-send is possible.
            year_updated = False
            for _yr_attempt in range(3):
                try:
                    client.table("vault_entries").update({
                        "last_sent_year": current_year,
                    }).eq("id", entry_id).execute()
                    # Double-guard: verify the write persisted
                    verify = client.table("vault_entries").select("last_sent_year").eq("id", entry_id).execute()
                    if verify.data and int(verify.data[0].get("last_sent_year", 0)) == current_year:
                        year_updated = True
                        break
                    else:
                        print(f"WARNING: last_sent_year write silently reverted for recurring entry {entry_id} (attempt {_yr_attempt + 1})")
                except Exception as yr_exc:  # noqa: BLE001
                    if _yr_attempt == 2:
                        print(f"WARNING: Failed to update last_sent_year for recurring entry {entry_id} after 3 attempts: {yr_exc}")
                if _yr_attempt < 2:
                    time.sleep(1)

            sent_count += 1
            print(f"Recurring entry {entry_id} ('{entry_title}') sent for year {current_year}{'' if year_updated else ' (last_sent_year update FAILED — may re-send)'}")

        except Exception as exc:  # noqa: BLE001
            print(f"SEND FAILED recurring entry {entry_id} user {user_id}: {exc}")
        finally:
            # Always release the lock — recurring entries must stay 'active'
            # for next year's delivery.  If the entry was deleted (e.g., by a
            # concurrent downgrade), release_entry_lock is a harmless no-op.
            release_entry_lock(client, entry_id)

    # ── Post-loop integrity summary (parity with process_expired/scheduled) ──
    if decryption_failures > 0:
        print(
            f"CRITICAL: User {user_id} (recurring): {decryption_failures} "
            f"entry decryption failure(s) detected — possible data "
            f"corruption or tampering."
        )
        _try_send_tampering_notification(
            client=client,
            profile=profile,
            resend_key=resend_key,
            from_email=from_email,
            decryption_failures=decryption_failures,
            now=now,
        )

    return sent_count


def cleanup_sent_entries(client) -> None:
    """Grace-based cleanup: when grace period ends, delete sent entries.

    Two cleanup paths:
      1. Guardian Vault (global grace): Find profiles with expired grace
         (inactive + protocol_executed_at <= 30 days ago), tombstone + delete
         ALL sent entries, reset profile to fresh.
      2. Time Capsule (per-entry grace): Find individual sent entries where
         grace_until <= now, tombstone + delete each expired entry.
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
                # Exclude recurring (Forever Letters) — they stay active permanently
                unprocessed = (
                    client.table("vault_entries")
                    .select("id", count="exact")
                    .eq("user_id", uid)
                    .in_("status", ["active", "sending"])
                    .neq("entry_mode", "recurring")
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
                        .select("id,user_id,audio_file_path,sent_at,scheduled_at")
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
                                "scheduled_at": entry.get("scheduled_at"),
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

                # SAFETY GUARD: Only reset profile if ALL non-recurring entries were removed.
                # Recurring entries always stay active — exclude them from this check.
                remaining_check = (
                    client.table("vault_entries")
                    .select("id", count="exact")
                    .eq("user_id", uid)
                    .neq("entry_mode", "recurring")
                    .execute()
                )
                remaining_count = remaining_check.count or 0
                if remaining_count > 0:
                    print(
                        f"User {uid}: grace expired but {remaining_count} entries "
                        f"still remain after cleanup — keeping inactive for retry"
                    )
                    continue

                # All entries removed — reset profile to fresh active state.
                # Also clear pro artifacts (themes, soul fire) in case the user
                # was downgraded while inactive.  The main-loop downgrade handler
                # only processes active profiles, so these could have persisted
                # through the entire 30-day grace period.
                client.table("profiles").update({
                    "status": "active",
                    "timer_days": 30,
                    "last_check_in": now_iso,
                    "protocol_executed_at": None,
                    "warning_sent_at": None,
                    "push_66_sent_at": None,
                    "push_33_sent_at": None,
                    "last_entry_at": None,
                    "selected_theme": None,
                    "selected_soul_fire": None,
                    "downgrade_email_pending": False,
                }).eq("id", uid).execute()
                reset_count += 1
                print(f"User {uid}: grace period ended, all entries cleaned up, account reset")

            except Exception as exc:  # noqa: BLE001
                print(f"Failed to process expired grace profile {uid}: {type(exc).__name__}: {exc}")

    print(
        f"cleanup_sent_entries: done (guardian) — "
        f"profiles_reset={reset_count} found={total_found} "
        f"tombstoned={total_tombstoned} deleted={total_deleted}"
    )

    # ── Per-entry grace cleanup (Time Capsule mode) ──
    # Find individual sent entries where grace_until has expired.
    # These are independent of profile status.
    per_entry_deleted = 0
    per_entry_tombstoned = 0
    now_iso_pe = datetime.now(timezone.utc).isoformat()
    last_entry_id_pe: str | None = None
    while True:
        eq = (
            client.table("vault_entries")
            .select("id,user_id,audio_file_path,sent_at,scheduled_at")
            .eq("status", "sent")
            .lte("grace_until", now_iso_pe)
            .order("id")
            .limit(PAGE_SIZE)
        )
        if last_entry_id_pe is not None:
            eq = eq.gt("id", last_entry_id_pe)
        resp = eq.execute()
        entries_pe = resp.data or []
        if not entries_pe:
            break
        last_entry_id_pe = str(entries_pe[-1]["id"])

        for entry in entries_pe:
            eid = entry.get("id", "?")
            uid = entry.get("user_id", "?")
            # Look up sender_name for tombstone
            try:
                prof_resp = (
                    client.table("profiles")
                    .select("sender_name")
                    .eq("id", uid)
                    .limit(1)
                    .execute()
                )
                prof_data = (prof_resp.data or [None])[0]
                s_name = (prof_data.get("sender_name") or "Afterword") if prof_data else "Afterword"
            except Exception:  # noqa: BLE001
                s_name = "Afterword"

            tombstone_ok = False
            try:
                client.table("vault_entry_tombstones").insert({
                    "vault_entry_id": eid,
                    "user_id": uid,
                    "sender_name": s_name,
                    "sent_at": entry.get("sent_at"),
                    "expired_at": now_iso_pe,
                    "scheduled_at": entry.get("scheduled_at"),
                }).execute()
                tombstone_ok = True
                per_entry_tombstoned += 1
            except Exception as tomb_exc:  # noqa: BLE001
                if "duplicate" in str(tomb_exc).lower() or "23505" in str(tomb_exc):
                    tombstone_ok = True
                else:
                    print(f"CRITICAL: Per-entry tombstone failed for {eid}: {tomb_exc}")

            if tombstone_ok:
                try:
                    delete_entry(client, entry)
                    per_entry_deleted += 1
                except Exception as del_exc:  # noqa: BLE001
                    print(f"Failed to delete per-entry grace expired {eid}: {del_exc}")

    if per_entry_deleted > 0 or per_entry_tombstoned > 0:
        print(
            f"cleanup_sent_entries: done (per-entry grace) — "
            f"tombstoned={per_entry_tombstoned} deleted={per_entry_deleted}"
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
    had_recurring: bool = False,
    had_scheduled_clamped: bool = False,
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
    text_recurring_line = (
        "- Forever Letters (recurring annual deliveries) have been removed\n"
        if had_recurring
        else ""
    )
    text_scheduled_line = (
        "- Time Capsule delivery dates beyond 30 days have been moved to within 30 days\n"
        if had_scheduled_clamped
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
        f"{text_recurring_line}"
        f"{text_scheduled_line}"
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
    html_recurring_li = (
        '<li style="margin-bottom:6px">Forever Letters (recurring annual deliveries) have been removed</li>'
        if had_recurring else ''
    )
    html_scheduled_li = (
        '<li style="margin-bottom:6px">Time Capsule delivery dates beyond 30 days have been moved to within 30 days</li>'
        if had_scheduled_clamped else ''
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
        f'{html_recurring_li}'
        f'{html_scheduled_li}'
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

    # Case-insensitive entitlement matching — prevents "AfterWord Pro" vs
    # "Afterword Pro" mismatches that would incorrectly classify paid users as free.
    eid_lower = entitlement_id.lower()
    has_entitlement = any(k.lower() == eid_lower for k, _ in active_entitlements)

    # Log case mismatches so they can be fixed in the RC dashboard
    if has_entitlement:
        exact_match = any(k == entitlement_id for k, _ in active_entitlements)
        if not exact_match:
            matched_key = next(k for k, _ in active_entitlements if k.lower() == eid_lower)
            print(
                f"RC verify: user {user_id} entitlement key case mismatch — "
                f"found '{matched_key}', expected '{entitlement_id}'"
            )

    # Lifetime detection: a non-expiring entitlement matching our ID IS lifetime
    # by RevenueCat definition (subscriptions always have expires_date; only
    # lifetime/non-consumable purchases have expires_date=null).
    # Also check product_identifier as a secondary signal.
    is_lifetime = any(
        (k.lower() == eid_lower and ent.get("expires_date") is None)
        or (ent.get("product_identifier") or "").lower().find("lifetime") >= 0
        for k, ent in active_entitlements
    )

    if is_lifetime:
        return "lifetime"
    if has_entitlement:
        return "pro"

    # Log when RC says "free" but the user had entitlements with different keys
    if entitlements_raw:
        ent_keys = list(entitlements_raw.keys())
        print(
            f"RC verify: user {user_id} has entitlements {ent_keys} but none match "
            f"'{entitlement_id}' (case-insensitive) — returning free"
        )
    return "free"


def _clamp_scheduled_dates(client, user_id: str, max_days: int, now: datetime) -> None:
    """Clamp scheduled_at dates to at most max_days from now for a downgraded user.

    When a Time Capsule user downgrades to free tier, their entries scheduled
    beyond 30 days must be clamped to now + 30 days.
    """
    max_date = (now + timedelta(days=max_days)).isoformat()
    try:
        far_entries = (
            client.table("vault_entries")
            .select("id")
            .eq("user_id", user_id)
            .eq("status", "active")
            .neq("entry_mode", "recurring")
            .not_.is_("scheduled_at", "null")
            .gt("scheduled_at", max_date)
            .execute()
        )
        entries = far_entries.data or []
        if entries:
            clamped_at = max_date
            clamped_grace = (now + timedelta(days=max_days + 30)).isoformat()
            for entry in entries:
                client.table("vault_entries").update({
                    "scheduled_at": clamped_at,
                    "grace_until": clamped_grace,
                }).eq("id", entry["id"]).execute()
            print(f"User {user_id}: clamped {len(entries)} scheduled entries to {max_days} days")
    except Exception as exc:  # noqa: BLE001
        print(f"Failed to clamp scheduled dates for {user_id}: {exc}")


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
    has_custom_theme = selected_theme not in FREE_THEMES
    has_custom_soul_fire = selected_soul_fire not in FREE_SOUL_FIRES

    active_audio_entries = [
        entry
        for entry in active_entries
        if (entry.get("data_type") or "").lower() == "audio"
    ]
    has_audio = bool(active_audio_entries)
    audio_entries: list[dict] = []

    # Detect recurring (Forever Letters) entries
    has_recurring = any(
        (entry.get("entry_mode") or "standard") == "recurring"
        for entry in active_entries
    )

    # Detect scheduled entries beyond free tier max (30 days) that need clamping
    free_max_date = (now + timedelta(days=30)).isoformat()
    has_far_scheduled = False
    try:
        far_check = (
            client.table("vault_entries")
            .select("id", count="exact")
            .eq("user_id", uid)
            .eq("status", "active")
            .neq("entry_mode", "recurring")
            .not_.is_("scheduled_at", "null")
            .gt("scheduled_at", free_max_date)
            .execute()
        )
        has_far_scheduled = (far_check.count or 0) > 0
    except Exception:  # noqa: BLE001
        pass

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

    needs_revert = has_pro_indicators or has_audio or has_recurring or has_far_scheduled

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
    is_genuine_downgrade = has_custom_timer or has_audio or has_recurring or has_far_scheduled
    email_needed = bool(email) and is_genuine_downgrade

    email_content: tuple[str, str, str] | None = None
    if email_needed:
        email_content = _build_downgrade_email(
            sender_name, had_audio=has_audio, had_recurring=has_recurring,
            had_scheduled_clamped=has_far_scheduled,
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

    # 2b. Delete all recurring (Forever Letters) entries — pro/lifetime only feature
    recurring_entries = (
        client.table("vault_entries")
        .select("id,audio_file_path")
        .eq("user_id", uid)
        .eq("entry_mode", "recurring")
        .execute()
    ).data or []
    for entry in recurring_entries:
        delete_entry(client, entry)
    if recurring_entries:
        print(f"Deleted {len(recurring_entries)} recurring (forever letter) entries for downgraded user {uid}")

    # 2c. Clamp scheduled dates beyond free tier max (30 days)
    if has_far_scheduled:
        _clamp_scheduled_dates(client, uid, max_days=30, now=now)

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

    global _resend_quota_exhausted
    _resend_quota_exhausted = False  # Reset for each run/retry

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

                "id,user_id,title,action_type,data_type,status,payload_encrypted,recipient_email_encrypted,data_key_encrypted,hmac_signature,audio_file_path,is_zero_knowledge,scheduled_at,grace_until,entry_mode,last_sent_year"

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

          # ── Scheduled mode (Time Capsule): process per-entry delivery ──
          # No global timer, no push notifications, no warnings.
          app_mode = (profile.get("app_mode") or "vault").lower()
          if app_mode == "scheduled":
              active_entries = batch_entries_by_user.get(user_id, [])
              sub_status = (profile.get("subscription_status") or "free").lower()

              # RC verification for scheduled mode users — same logic as vault mode:
              #   - Paid → catch cancellations
              #   - Free with pro indicators → catch missed webhook upgrades
              #   - Pending downgrade email → confirm still free
              if rc_api_secret:
                  _sc_theme = profile.get("selected_theme")
                  _sc_sf = profile.get("selected_soul_fire")
                  sc_has_pro = (
                      int(profile.get("timer_days") or 30) != 30
                      or _sc_theme not in FREE_THEMES
                      or _sc_sf not in FREE_SOUL_FIRES
                  )
                  sc_needs_rc = (
                      sub_status in PAID_STATUSES
                      or sc_has_pro
                      or profile.get("downgrade_email_pending")
                  )
                  if sc_needs_rc:
                      try:
                          rc_status = verify_subscription_with_revenuecat(rc_api_secret, user_id)
                          if rc_status is not None and rc_status != sub_status:
                              if sub_status in PAID_STATUSES and rc_status == "free":
                                  print(
                                      f"RC DOWNGRADE (scheduled): user {user_id} was {sub_status} "
                                      f"in DB but RC says free — applying downgrade."
                                  )
                              else:
                                  print(f"RC verify (scheduled): user {user_id} DB={sub_status} RC={rc_status} — updating DB")
                              try:
                                  client.table("profiles").update({
                                      "subscription_status": rc_status,
                                  }).eq("id", user_id).execute()
                                  sub_status = rc_status
                                  profile["subscription_status"] = rc_status
                              except Exception as db_exc:  # noqa: BLE001
                                  print(f"Failed to update subscription for scheduled user {user_id}: {db_exc}")
                          time.sleep(RC_VERIFY_RATE_LIMIT_DELAY)
                      except Exception as rc_exc:  # noqa: BLE001
                          print(f"RC verify error for scheduled user {user_id}: {rc_exc}")

              # Clear stale downgrade flag when user re-subscribes
              if sub_status in PAID_STATUSES and profile.get("downgrade_email_pending"):
                  try:
                      client.table("profiles").update({
                          "downgrade_email_pending": False,
                      }).eq("id", user_id).execute()
                      profile["downgrade_email_pending"] = False
                  except Exception:  # noqa: BLE001
                      pass

              # Subscription downgrade for scheduled mode
              if sub_status == "free":
                  try:
                      reverted = handle_subscription_downgrade(
                          client, profile, active_entries, resend_key, from_email, now,
                      )
                      if reverted:
                          continue
                  except Exception as dg_exc:  # noqa: BLE001
                      print(f"Downgrade handling failed for scheduled user {user_id}: {dg_exc}")

              if active_entries:
                  # Process recurring (Forever Letters) FIRST — they are time-critical
                  # (birthdays, anniversaries) and must not be blocked by rate limits
                  # from bulk scheduled entries.
                  try:
                      process_recurring_entries(
                          client, profile, active_entries, server_secret,
                          resend_key, from_email, viewer_base_url, now,
                      )
                  except Exception as exc:  # noqa: BLE001
                      print(f"Recurring processing failed for {user_id}: {exc}")

                  try:
                      process_scheduled_entries(
                          client, profile, active_entries, server_secret,
                          resend_key, from_email, viewer_base_url, now,
                      )
                  except Exception as exc:  # noqa: BLE001
                      print(f"Scheduled processing failed for {user_id}: {exc}")
              continue

          last_check_in = parse_iso(profile.get("last_check_in"))

          if last_check_in is None:
              print(f"WARN: User {user_id} has NULL last_check_in — skipping (timer cannot be computed)")
              continue



          timer_state = build_timer_state(last_check_in, profile.get("timer_days"), now)

          deadline = timer_state.deadline

          active_entries = batch_entries_by_user.get(user_id, [])

          # has_entries excludes recurring — guardian timer logic only cares about standard/scheduled entries
          has_entries = any(
              (e.get("entry_mode") or "standard") != "recurring"
              for e in active_entries
          )

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
              has_pro_indicators = (
                  int(profile.get("timer_days") or 30) != 30
                  or selected_theme not in FREE_THEMES
                  or selected_soul_fire not in FREE_SOUL_FIRES
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
                          # Safety audit: log paid→free transitions prominently
                          if sub_status in PAID_STATUSES and rc_status == "free":
                              print(
                                  f"RC DOWNGRADE: user {user_id} was {sub_status} "
                                  f"in DB but RC says free — applying downgrade. "
                                  f"Pro indicators: timer={profile.get('timer_days')}, "
                                  f"theme={profile.get('selected_theme')}, "
                                  f"soul_fire={profile.get('selected_soul_fire')}"
                              )
                          else:
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
                  # No standard/scheduled entries — timer has no effect. Do NOT mark inactive.
                  # Free users shouldn't keep recurring entries — run downgrade handler
                  # to delete them.  This is safe because has_entries=False means no
                  # standard entries exist, so resetting timer_days/last_check_in
                  # (which the downgrade handler does) cannot block entry delivery.
                  if sub_status == "free" and active_entries:
                      try:
                          reverted = handle_subscription_downgrade(
                              client, profile, active_entries, resend_key, from_email, now,
                          )
                          if reverted:
                              continue
                      except Exception as exc:  # noqa: BLE001
                          print(f"Downgrade handling failed for recurring-only user {user_id}: {exc}")
                  # Still process recurring entries (Forever Letters) if any exist.
                  if active_entries:
                      try:
                          process_recurring_entries(
                              client, profile, active_entries, server_secret,
                              resend_key, from_email, viewer_base_url, now,
                          )
                      except Exception as exc:  # noqa: BLE001
                          print(f"Recurring processing failed for {user_id}: {exc}")
                  continue

              # Process recurring (Forever Letters) FIRST — they are time-critical
              # (birthdays, anniversaries) and must not be blocked by rate limits
              # from bulk guardian entry delivery.
              try:
                  process_recurring_entries(
                      client, profile, active_entries, server_secret,
                      resend_key, from_email, viewer_base_url, now,
                  )
              except Exception as exc:  # noqa: BLE001
                  print(f"Recurring processing failed for guardian user {user_id}: {exc}")

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
              # Exclude recurring entries — they always stay active (Forever Letters)
              pending = (
                  client.table("vault_entries")
                  .select("id", count="exact")
                  .eq("user_id", user_id)
                  .in_("status", ["active", "sending"])
                  .neq("entry_mode", "recurring")
                  .execute()
              )
              has_pending = (pending.count or 0) > 0

              if has_pending:
                  print(f"User {user_id}: {pending.count} entries still pending, keeping active for retry")
              elif had_send:
                  # Send entries exist → enter grace period (beneficiary can download)
                  grace_update: dict = {
                      "status": "inactive",
                      "timer_days": 30,
                      "protocol_executed_at": now.isoformat(),
                      "warning_sent_at": None,
                      "push_66_sent_at": None,
                      "push_33_sent_at": None,
                      "last_entry_at": None,
                  }

                  # ── Inline downgrade: if user is free, clean pro artifacts NOW ──
                  # Without this, the profile sits inactive for 30 days (grace) and
                  # the downgrade handler (PASS 0) never runs because it only
                  # processes active profiles.  Pro themes/soul_fire would persist
                  # during grace and the downgrade email would be delayed 30+ days.
                  if sub_status == "free":
                      sel_t = profile.get("selected_theme")
                      sel_s = profile.get("selected_soul_fire")
                      had_custom_timer_at_start = int(profile.get("timer_days") or 30) != 30
                      had_audio_at_start = any(
                          (e.get("data_type") or "").lower() == "audio"
                          for e in active_entries
                      )
                      had_recurring_at_start = any(
                          (e.get("entry_mode") or "standard") == "recurring"
                          for e in active_entries
                      )
                      # Check for far-scheduled entries (TC entries beyond free 30-day cap)
                      had_far_scheduled_at_start = False
                      try:
                          _fs_max = (now + timedelta(days=30)).isoformat()
                          _fs_check = (
                              client.table("vault_entries")
                              .select("id", count="exact")
                              .eq("user_id", user_id)
                              .eq("status", "active")
                              .neq("entry_mode", "recurring")
                              .not_.is_("scheduled_at", "null")
                              .gt("scheduled_at", _fs_max)
                              .execute()
                          )
                          had_far_scheduled_at_start = (_fs_check.count or 0) > 0
                      except Exception:  # noqa: BLE001
                          pass
                      if sel_t not in FREE_THEMES:
                          grace_update["selected_theme"] = None
                      if sel_s not in FREE_SOUL_FIRES:
                          grace_update["selected_soul_fire"] = None
                      is_genuine_downgrade = had_custom_timer_at_start or had_audio_at_start or had_recurring_at_start or had_far_scheduled_at_start
                      if is_genuine_downgrade:
                          grace_update["downgrade_email_pending"] = True

                  client.table("profiles").update(grace_update).eq("id", user_id).execute()
                  print(f"User {user_id}: protocol executed, grace period started")

                  # ── Inline downgrade: actually delete pro-only entries NOW ──
                  # Without this, audio/recurring entries persist through the 30-day
                  # grace period and trigger a SECOND downgrade email after cleanup.
                  if sub_status == "free":
                      # Delete audio entries
                      if had_audio_at_start:
                          try:
                              _inline_audio = (
                                  client.table("vault_entries")
                                  .select("id,audio_file_path")
                                  .eq("user_id", user_id)
                                  .eq("data_type", "audio")
                                  .eq("status", "active")
                                  .execute()
                              ).data or []
                              for _ae in _inline_audio:
                                  delete_entry(client, _ae)
                              if _inline_audio:
                                  print(f"User {user_id}: inline downgrade deleted {len(_inline_audio)} audio entries")
                          except Exception as _ae_exc:  # noqa: BLE001
                              print(f"User {user_id}: inline audio deletion failed ({_ae_exc}), PASS 0 will retry")

                      # Delete recurring (Forever Letters) entries
                      # No status filter — catch entries in 'sending' too (matches handler)
                      if had_recurring_at_start:
                          try:
                              _inline_recurring = (
                                  client.table("vault_entries")
                                  .select("id,audio_file_path")
                                  .eq("user_id", user_id)
                                  .eq("entry_mode", "recurring")
                                  .execute()
                              ).data or []
                              for _re in _inline_recurring:
                                  delete_entry(client, _re)
                              if _inline_recurring:
                                  print(f"User {user_id}: inline downgrade deleted {len(_inline_recurring)} recurring entries")
                          except Exception as _re_exc:  # noqa: BLE001
                              print(f"User {user_id}: inline recurring deletion failed ({_re_exc}), PASS 0 will retry")

                      # Clamp far-scheduled dates
                      if had_far_scheduled_at_start:
                          try:
                              _clamp_scheduled_dates(client, user_id, max_days=30, now=now)
                          except Exception as _cs_exc:  # noqa: BLE001
                              print(f"User {user_id}: inline scheduled clamp failed ({_cs_exc}), PASS 0 will retry")

                  # Try to send downgrade email inline (best-effort)
                  if sub_status == "free" and grace_update.get("downgrade_email_pending"):
                      _dg_email = profile.get("email")
                      if _dg_email:
                          try:
                              _dg_sub, _dg_txt, _dg_htm = _build_downgrade_email(
                                  sender_name,
                                  had_audio=any(
                                      (e.get("data_type") or "").lower() == "audio"
                                      for e in active_entries
                                  ),
                                  had_recurring=any(
                                      (e.get("entry_mode") or "standard") == "recurring"
                                      for e in active_entries
                                  ),
                                  had_scheduled_clamped=had_far_scheduled_at_start,
                              )
                              send_email(
                                  resend_key, from_email, _dg_email,
                                  _dg_sub, _dg_txt, _dg_htm,
                                  idempotency_key=f"downgrade-{user_id}-{now.date().isoformat()}",
                                  preheader=f"Hi {sender_name}, your Afterword subscription has changed.",
                              )
                              client.table("profiles").update({
                                  "downgrade_email_pending": False,
                              }).eq("id", user_id).execute()
                              print(f"User {user_id}: sent downgrade notification alongside protocol execution")
                          except Exception as _dg_exc:  # noqa: BLE001
                              print(f"User {user_id}: downgrade email deferred ({_dg_exc}), will retry when active")
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
                  # Truly destroy-only → no grace needed, reset to fresh immediately.
                  _destroy_update: dict = {
                      "status": "active",
                      "timer_days": 30,
                      "last_check_in": now.isoformat(),
                      "protocol_executed_at": None,
                      "warning_sent_at": None,
                      "push_66_sent_at": None,
                      "push_33_sent_at": None,
                      "last_entry_at": None,
                      "downgrade_email_pending": False,
                  }
                  # Only clear theme/soul_fire for free users — paid users keep them
                  if sub_status == "free":
                      _destroy_update["selected_theme"] = None
                      _destroy_update["selected_soul_fire"] = None
                  client.table("profiles").update(_destroy_update).eq("id", user_id).execute()
                  print(f"User {user_id}: destroy-only vault cleared, account reset to fresh")

                  # Delete pro-only entries that survive destroy (audio/recurring/far-scheduled)
                  if sub_status == "free":
                      try:
                          _do_audio = (
                              client.table("vault_entries")
                              .select("id,audio_file_path")
                              .eq("user_id", user_id)
                              .eq("data_type", "audio")
                              .eq("status", "active")
                              .execute()
                          ).data or []
                          for _ae in _do_audio:
                              delete_entry(client, _ae)
                          _do_recurring = (
                              client.table("vault_entries")
                              .select("id,audio_file_path")
                              .eq("user_id", user_id)
                              .eq("entry_mode", "recurring")
                              .eq("status", "active")
                              .execute()
                          ).data or []
                          for _re in _do_recurring:
                              delete_entry(client, _re)
                          _clamp_scheduled_dates(client, user_id, max_days=30, now=now)
                          if _do_audio or _do_recurring:
                              print(f"User {user_id}: destroy-only path cleaned {len(_do_audio)} audio + {len(_do_recurring)} recurring entries")
                      except Exception as _do_exc:  # noqa: BLE001
                          print(f"User {user_id}: destroy-only pro cleanup failed ({_do_exc}), PASS 0 will catch on next run")

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
          # But still process recurring entries (Forever Letters) for users with only recurring entries

          has_recurring = any(
              (e.get("entry_mode") or "standard") == "recurring"
              for e in active_entries
          )

          if has_recurring:
              try:
                  process_recurring_entries(
                      client, profile, active_entries, server_secret,
                      resend_key, from_email, viewer_base_url, now,
                  )
              except Exception as exc:  # noqa: BLE001
                  print(f"Recurring processing failed for guardian user {user_id}: {exc}")

          if not has_entries:

              continue

          # ── PASS 1b: Process recurring (Forever Letters) for active-timer users ──
          # Forever Letters fire annually regardless of timer state.
          # (Already handled above for all users including recurring-only)


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

                      push_stage="warning_66",

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

                      push_stage="warning_33",

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

    # ── Post-loop: Forever Letters for inactive (grace-period) profiles ──
    # During Guardian grace, profiles are inactive and skipped by the main
    # loop.  But Forever Letters must still fire on their annual date —
    # a birthday letter shouldn't be delayed 30 days because of grace.
    try:
        now = datetime.now(timezone.utc)
        _grace_last_id: str | None = None
        _grace_recurring_sent = 0
        while True:
            _gq = (
                client.table("profiles")
                .select(PROFILE_SELECT_FIELDS)
                .eq("status", "inactive")
                .order("id")
                .limit(PROFILE_BATCH_SIZE)
            )
            if _grace_last_id is not None:
                _gq = _gq.gt("id", _grace_last_id)
            _grace_batch = _gq.execute().data or []
            if not _grace_batch:
                break
            _grace_user_ids = [str(p["id"]) for p in _grace_batch]
            # Only fetch recurring entries (no need for all entry types)
            _grace_entries = fetch_all_rows(
                client.table("vault_entries")
                .select(
                    "id,user_id,title,action_type,data_type,status,"
                    "payload_encrypted,recipient_email_encrypted,"
                    "data_key_encrypted,hmac_signature,audio_file_path,"
                    "is_zero_knowledge,scheduled_at,grace_until,"
                    "entry_mode,last_sent_year"
                )
                .eq("status", "active")
                .eq("entry_mode", "recurring")
                .in_("user_id", _grace_user_ids)
                .order("id")
            )
            if _grace_entries:
                _ge_by_user: dict[str, list[dict]] = {}
                for _ge in _grace_entries:
                    _ge_by_user.setdefault(str(_ge["user_id"]), []).append(_ge)
                for _gp in _grace_batch:
                    _gp_uid = str(_gp["id"])
                    # Skip free users — their recurring entries should have been
                    # deleted by inline downgrade.  If deletion failed, do NOT
                    # send pro-only content for a free user; PASS 0 will clean up
                    # when the profile reactivates after grace.
                    _gp_sub = (_gp.get("subscription_status") or "free").lower()
                    if _gp_sub == "free":
                        continue
                    _gp_entries = _ge_by_user.get(_gp_uid, [])
                    if not _gp_entries:
                        continue
                    try:
                        _gs = process_recurring_entries(
                            client, _gp, _gp_entries, server_secret,
                            resend_key, from_email, viewer_base_url, now,
                        )
                        _grace_recurring_sent += _gs
                    except Exception as _gr_exc:  # noqa: BLE001
                        print(f"Recurring processing failed for inactive user {_gp_uid}: {_gr_exc}")
            _grace_last_id = str(_grace_batch[-1]["id"])
        if _grace_recurring_sent:
            print(f"Grace-period recurring: sent {_grace_recurring_sent} Forever Letter(s) for inactive profiles")
    except Exception as exc:  # noqa: BLE001
        print(f"Grace-period recurring processing failed: {exc}")

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

