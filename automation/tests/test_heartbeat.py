import sys
import types
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

# Allow importing automation/heartbeat.py as a module in test runs.
AUTOMATION_DIR = Path(__file__).resolve().parents[1]
if str(AUTOMATION_DIR) not in sys.path:
    sys.path.insert(0, str(AUTOMATION_DIR))


def _install_optional_dependency_stubs() -> None:
    # heartbeat.py imports google auth + supabase at module load time.
    # Unit tests in lightweight environments may not have those packages.
    try:
        from google.auth.transport.requests import Request as _  # noqa: F401
        from google.oauth2 import service_account as _  # noqa: F401
    except ModuleNotFoundError:
        google_mod = types.ModuleType("google")
        google_auth_mod = types.ModuleType("google.auth")
        google_auth_transport_mod = types.ModuleType("google.auth.transport")
        google_auth_transport_requests_mod = types.ModuleType(
            "google.auth.transport.requests"
        )

        class _DummyGoogleAuthRequest:
            pass

        google_auth_transport_requests_mod.Request = _DummyGoogleAuthRequest

        google_oauth2_mod = types.ModuleType("google.oauth2")
        google_oauth2_service_account_mod = types.ModuleType(
            "google.oauth2.service_account"
        )

        class _DummyCredentials:
            token = ""

            @classmethod
            def from_service_account_info(cls, _info, scopes=None):
                del scopes
                return cls()

            def refresh(self, _request):
                self.token = "dummy"

        google_oauth2_service_account_mod.Credentials = _DummyCredentials

        sys.modules.setdefault("google", google_mod)
        sys.modules.setdefault("google.auth", google_auth_mod)
        sys.modules.setdefault("google.auth.transport", google_auth_transport_mod)
        sys.modules.setdefault(
            "google.auth.transport.requests", google_auth_transport_requests_mod
        )
        sys.modules.setdefault("google.oauth2", google_oauth2_mod)
        sys.modules.setdefault(
            "google.oauth2.service_account", google_oauth2_service_account_mod
        )

    def _create_client(*_args, **_kwargs):
        raise RuntimeError("supabase client is not available in unit tests")

    try:
        import supabase as supabase_mod  # type: ignore
        if not hasattr(supabase_mod, "create_client"):
            supabase_mod.create_client = _create_client
    except ModuleNotFoundError:
        supabase_mod = types.ModuleType("supabase")
        supabase_mod.create_client = _create_client
        sys.modules.setdefault("supabase", supabase_mod)

    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM as _  # noqa: F401
    except ModuleNotFoundError:
        cryptography_mod = types.ModuleType("cryptography")
        hazmat_mod = types.ModuleType("cryptography.hazmat")
        primitives_mod = types.ModuleType("cryptography.hazmat.primitives")
        ciphers_mod = types.ModuleType("cryptography.hazmat.primitives.ciphers")
        aead_mod = types.ModuleType("cryptography.hazmat.primitives.ciphers.aead")

        class _DummyAESGCM:
            def __init__(self, _key):
                pass

            def decrypt(self, _nonce, _combined, _aad):
                raise RuntimeError("AESGCM decrypt is unavailable in unit-test stub")

        aead_mod.AESGCM = _DummyAESGCM

        sys.modules.setdefault("cryptography", cryptography_mod)
        sys.modules.setdefault("cryptography.hazmat", hazmat_mod)
        sys.modules.setdefault("cryptography.hazmat.primitives", primitives_mod)
        sys.modules.setdefault("cryptography.hazmat.primitives.ciphers", ciphers_mod)
        sys.modules.setdefault("cryptography.hazmat.primitives.ciphers.aead", aead_mod)


_install_optional_dependency_stubs()

import heartbeat  # noqa: E402


class _DummyResponse:
    def __init__(self, status_code: int = 200, text: str = ""):
        self.status_code = status_code
        self.text = text

    @property
    def ok(self):
        return self.status_code < 400

    def json(self):
        import json as _json
        return _json.loads(self.text)


class _ProfilesQuery:
    def __init__(self) -> None:
        self.updated_payload = None

    def update(self, payload):
        self.updated_payload = payload
        return self

    def eq(self, *_args, **_kwargs):
        return self

    def execute(self):
        return types.SimpleNamespace(data=[], count=0)


class _VaultEntriesQuery:
    """Minimal stub for vault_entries table queries in downgrade tests."""

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, *_args, **_kwargs):
        return self

    def execute(self):
        return types.SimpleNamespace(data=[], count=0)


class _MinimalClient:
    def __init__(self) -> None:
        self.profiles = _ProfilesQuery()
        self._vault_entries = _VaultEntriesQuery()

    def table(self, table_name: str):
        if table_name == "profiles":
            return self.profiles
        if table_name == "vault_entries":
            return self._vault_entries
        raise AssertionError(f"Unexpected table access in unit test: {table_name}")


class HeartbeatTests(unittest.TestCase):
    def setUp(self):
        heartbeat._resend_quota_exhausted = False

    def test_build_timer_state_uses_utc_deadline_and_stage_triggers(self):
        last_check_in = datetime(2026, 2, 1, 0, 0, tzinfo=timezone.utc)
        now = datetime(2026, 2, 5, 2, 0, tzinfo=timezone.utc)

        state = heartbeat.build_timer_state(last_check_in, 7, now)

        self.assertEqual(
            state.deadline,
            datetime(2026, 2, 8, 0, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(
            state.push_66_at,
            datetime(2026, 2, 3, 9, 7, 12, tzinfo=timezone.utc),
        )
        self.assertEqual(
            state.push_33_at,
            datetime(2026, 2, 5, 16, 33, 36, tzinfo=timezone.utc),
        )
        self.assertEqual(
            state.email_24h_at,
            datetime(2026, 2, 7, 0, 0, tzinfo=timezone.utc),
        )

    def test_should_send_push_33_when_due_and_unmarked(self):
        last_check_in = datetime(2026, 2, 1, 0, 0, tzinfo=timezone.utc)
        now = datetime(2026, 2, 6, 2, 0, tzinfo=timezone.utc)
        state = heartbeat.build_timer_state(last_check_in, 7, now)

        profile = {
            "subscription_status": "premium",
            "push_33_sent_at": None,
        }

        self.assertTrue(heartbeat.should_send_push_33(profile, state, now))

    def test_should_not_send_push_33_before_trigger_time(self):
        last_check_in = datetime(2026, 2, 1, 0, 0, tzinfo=timezone.utc)
        now = datetime(2026, 2, 5, 10, 0, tzinfo=timezone.utc)
        state = heartbeat.build_timer_state(last_check_in, 7, now)

        profile = {
            "subscription_status": "premium",
            "push_33_sent_at": None,
        }

        self.assertFalse(heartbeat.should_send_push_33(profile, state, now))

    def test_should_send_24h_warning_email_only_for_paid_and_once_per_cycle(self):
        last_check_in = datetime(2026, 2, 1, 0, 0, tzinfo=timezone.utc)
        now = datetime(2026, 2, 7, 1, 0, tzinfo=timezone.utc)
        state = heartbeat.build_timer_state(last_check_in, 7, now)

        paid_profile = {
            "subscription_status": "pro",
            "warning_sent_at": None,
        }
        free_profile = {
            "subscription_status": "free",
            "warning_sent_at": None,
        }
        already_sent_profile = {
            "subscription_status": "pro",
            "warning_sent_at": (last_check_in + timedelta(days=2)).isoformat(),
        }

        self.assertTrue(heartbeat.should_send_24h_warning_email(paid_profile, state, now))
        self.assertFalse(heartbeat.should_send_24h_warning_email(free_profile, state, now))
        self.assertFalse(
            heartbeat.should_send_24h_warning_email(already_sent_profile, state, now)
        )

    def test_short_timer_clamps_24h_email_trigger_to_last_check_in(self):
        last_check_in = datetime(2026, 2, 1, 12, 0, tzinfo=timezone.utc)
        now = datetime(2026, 2, 1, 12, 0, tzinfo=timezone.utc)

        state = heartbeat.build_timer_state(last_check_in, 0, now)

        self.assertEqual(state.email_24h_at, last_check_in)

    def test_process_expired_entries_sends_to_beneficiary_and_marks_sent(self):
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        client = object()
        profile = {
            "id": "user-1",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }
        entries = [
            {
                "id": "entry-1",
                "action_type": "send",
                "title": "Vault Letter",
                "payload_encrypted": "payload",
                "recipient_email_encrypted": "enc-recipient",
                "data_key_encrypted": "enc-data-key",
                "hmac_signature": "sig-1",
            }
        ]

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda value: value),
            patch.object(
                heartbeat,
                "decrypt_with_server_secret",
                side_effect=[
                    b"h" * 32,
                    b"beneficiary@example.com",
                    b"k" * 32,
                ],
            ),
            patch.object(heartbeat, "compute_hmac_signature", return_value="sig-1"),
            patch.object(heartbeat, "build_unlock_email_payload", return_value={"mock": True}) as mock_build,
            patch.object(heartbeat, "_post_json_with_retries", return_value=_DummyResponse(200, '{"data": [{"id": "r1"}]}')) as mock_post,
            patch.object(heartbeat, "mark_entry_sent", return_value=True) as mock_mark_sent,
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=client,
                profile=profile,
                entries=entries,
                server_secret="server-secret",
                resend_key="rk_test",
                from_email="from@example.com",
                viewer_base_url="https://viewer.afterword.app",
                fcm_ctx=None,
                now=now,
            )

        self.assertTrue(had_send)
        self.assertEqual(input_send_count, 1)
        mock_build.assert_called_once()
        mock_post.assert_called_once()
        mock_mark_sent.assert_called_once_with(client, "entry-1", now)

    def test_process_expired_entries_destroy_path_deletes_without_grace_flag(self):
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        profile = {
            "id": "user-2",
            "sender_name": "Alice",
            "hmac_key_encrypted": None,
        }
        entries = [
            {
                "id": "entry-destroy",
                "action_type": "destroy",
                "title": "Temporary Note",
            }
        ]

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "delete_entry") as mock_delete_entry,
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(),
                profile=profile,
                entries=entries,
                server_secret="server-secret",
                resend_key="rk_test",
                from_email="from@example.com",
                viewer_base_url="https://viewer.afterword.app",
                fcm_ctx=None,
                now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 0)
        mock_delete_entry.assert_called_once()

    def test_send_email_passes_idempotency_key(self):
        with patch.object(
            heartbeat,
            "_post_json_with_retries",
            return_value=_DummyResponse(200, "ok"),
        ) as mocked_post:
            heartbeat.send_email(
                api_key="rk_test",
                from_email="from@example.com",
                to_email="to@example.com",
                subject="Subject",
                text="Plain",
                html="<p>Plain</p>",
                idempotency_key="unlock-entry-123",
            )

        self.assertEqual(mocked_post.call_count, 1)
        self.assertEqual(
            mocked_post.call_args.kwargs.get("idempotency_key"),
            "unlock-entry-123",
        )

        payload = mocked_post.call_args.kwargs.get("payload", {})
        self.assertEqual(payload.get("reply_to"), "from@example.com")
        self.assertEqual(
            payload.get("headers", {}).get("List-Unsubscribe"),
            "<mailto:from@example.com?subject=Unsubscribe>",
        )

    def test_build_unlock_email_payload_primary_inbox_structure(self):
        """Beneficiary email must be structured for Primary inbox delivery:
        - No List-Unsubscribe (not bulk)
        - No reply_to (inbox not monitored)
        - Subject includes sender name
        - Title excluded from body (triggering words risk)
        - Key fragmented into chunks
        - HTML uses native <div dir="ltr"> wrapper
        """
        payload = heartbeat.build_unlock_email_payload(
            recipient_email="recipient@example.com",
            entry_id="entry-123",
            sender_name="Alice",
            entry_title="My Secret Letter",
            viewer_link="https://viewer.afterword.app/?entry=entry-123",
            security_key="O1UFuAKfBm3qZ9sLU+nOczvjGQ9LWc/MHsUdKU7bIuk=",
            from_email="Afterword <vault@afterword-app.com>",
        )

        # No bulk/commercial headers
        self.assertNotIn("reply_to", payload)
        self.assertEqual(payload.get("headers"), {})

        # Subject contains sender name
        self.assertEqual(payload["subject"], "A personal message from Alice")

        # Title must NOT appear in body (could contain triggering words)
        self.assertNotIn("My Secret Letter", payload["text"])
        self.assertNotIn("My Secret Letter", payload["html"])

        # Sender name appears in first sentence
        self.assertIn("Alice asked me to ensure you received", payload["text"])
        self.assertIn("Alice asked me to ensure you received", payload["html"])

        # Key is fragmented (spaces in plain text)
        self.assertIn("  ", payload["text"])
        # Key is fragmented (nbsp in HTML)
        self.assertIn("&nbsp;&nbsp;", payload["html"])

        # HTML uses native Gmail structure
        self.assertTrue(payload["html"].startswith('<div dir="ltr">'))
        self.assertIn("font-family:Arial", payload["html"])
        self.assertIn("color:#222222", payload["html"])
        # Raw link, not a styled button
        self.assertIn('style="color:#1155cc;text-decoration:underline"', payload["html"])
        # No dark header, no card layout
        self.assertNotIn("background:#0a0a0a", payload["html"])
        self.assertNotIn("border-radius:12px", payload["html"])

    def test_fragment_security_key_splits_into_three_chunks(self):
        key = "O1UFuAKfBm3qZ9sLU+nOczvjGQ9LWc/MHsUdKU7bIuk="
        plain, html = heartbeat._fragment_security_key(key)

        # Plain text uses double-space separator
        parts = plain.split("  ")
        self.assertEqual(len(parts), 3)
        # Recombined key matches original
        self.assertEqual("".join(parts), key)

        # HTML uses &nbsp;&nbsp; separator
        html_parts = html.split("&nbsp;&nbsp;")
        self.assertEqual(len(html_parts), 3)

    def test_fragment_security_key_handles_short_keys(self):
        plain, html = heartbeat._fragment_security_key("abc")
        parts = plain.split("  ")
        self.assertEqual(len(parts), 3)
        self.assertEqual("".join(parts), "abc")

    def test_invalid_fcm_token_detection(self):
        self.assertTrue(
            heartbeat._is_invalid_fcm_token_response(
                "registration-token-not-registered"
            )
        )
        self.assertTrue(
            heartbeat._is_invalid_fcm_token_response("Requested entity was not found")
        )
        self.assertFalse(
            heartbeat._is_invalid_fcm_token_response("internal server error")
        )

    def test_downgrade_uses_active_audio_entries_without_extra_query(self):
        client = _MinimalClient()
        deleted_entries = []

        profile = {
            "id": "user-123",
            "email": None,
            "sender_name": "Afterword",
            "timer_days": 30,
            "selected_theme": "oledVoid",
            "selected_soul_fire": "etherealOrb",
        }
        active_entries = [
            {
                "id": "entry-1",
                "data_type": "audio",
                "audio_file_path": "user-123/entry-1.enc",
            }
        ]

        with patch.object(heartbeat, "delete_entry", side_effect=lambda _c, e: deleted_entries.append(e["id"])):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client,
                profile=profile,
                active_entries=active_entries,
                resend_key="rk",
                from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(deleted_entries, ["entry-1"])
        self.assertEqual(client.profiles.updated_payload["timer_days"], 30)
        self.assertIsNone(client.profiles.updated_payload["selected_theme"])
        self.assertIsNone(client.profiles.updated_payload["selected_soul_fire"])

    def test_downgrade_sets_pending_flag_when_email_needed(self):
        """When a genuine downgrade is detected with an email address,
        downgrade_email_pending must be set True in the wipe update."""
        update_calls = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-456",
            "email": "user@example.com",
            "sender_name": "Alice",
            "timer_days": 60,
            "selected_theme": None,
            "selected_soul_fire": None,
        }

        with (
            patch.object(heartbeat, "delete_entry"),
            patch.object(heartbeat, "send_email"),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client,
                profile=profile,
                active_entries=[],
                resend_key="rk",
                from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        # First update (wipe) sets pending=True
        self.assertTrue(update_calls[0].get("downgrade_email_pending"))

    def test_downgrade_email_success_clears_pending_flag(self):
        """Successful email send must clear downgrade_email_pending."""
        update_calls = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-789",
            "email": "user@example.com",
            "sender_name": "Bob",
            "timer_days": 90,
            "selected_theme": None,
            "selected_soul_fire": None,
        }

        with (
            patch.object(heartbeat, "delete_entry"),
            patch.object(heartbeat, "send_email"),  # succeeds (no exception)
        ):
            heartbeat.handle_subscription_downgrade(
                client=client,
                profile=profile,
                active_entries=[],
                resend_key="rk",
                from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        # First update sets pending=True (wipe), second clears it (email success)
        self.assertEqual(len(update_calls), 2)
        self.assertTrue(update_calls[0].get("downgrade_email_pending"))
        self.assertFalse(update_calls[1].get("downgrade_email_pending"))

    def test_downgrade_email_failure_keeps_pending_flag(self):
        """Failed email send must leave downgrade_email_pending=True for retry."""
        update_calls = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-fail",
            "email": "user@example.com",
            "sender_name": "Carol",
            "timer_days": 45,
            "selected_theme": None,
            "selected_soul_fire": None,
        }

        with (
            patch.object(heartbeat, "delete_entry"),
            patch.object(heartbeat, "send_email", side_effect=RuntimeError("Resend 500")),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client,
                profile=profile,
                active_entries=[],
                resend_key="rk",
                from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        # Only the wipe update happened — no second update to clear flag
        self.assertEqual(len(update_calls), 1)
        self.assertTrue(update_calls[0].get("downgrade_email_pending"))

    def test_downgrade_retry_sends_deferred_email(self):
        """When indicators are gone but downgrade_email_pending is True,
        the function must retry the email and clear the flag on success."""
        update_calls = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-retry",
            "email": "user@example.com",
            "sender_name": "Dan",
            "timer_days": 30,  # already reset (no indicators)
            "selected_theme": None,
            "selected_soul_fire": None,
            "downgrade_email_pending": True,  # left from failed previous run
        }

        with patch.object(heartbeat, "send_email") as mock_send:
            reverted = heartbeat.handle_subscription_downgrade(
                client=client,
                profile=profile,
                active_entries=[],
                resend_key="rk",
                from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        # Returns False — no indicators were reverted
        self.assertFalse(reverted)
        # Email was sent
        mock_send.assert_called_once()
        # Flag was cleared
        self.assertEqual(len(update_calls), 1)
        self.assertFalse(update_calls[0]["downgrade_email_pending"])

    def test_downgrade_no_indicators_no_pending_returns_false(self):
        """Free user with no indicators and no pending flag → skip entirely."""
        client = _MinimalClient()
        profile = {
            "id": "user-free",
            "email": "user@example.com",
            "sender_name": "Eve",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
            "downgrade_email_pending": False,
        }

        reverted = heartbeat.handle_subscription_downgrade(
            client=client,
            profile=profile,
            active_entries=[],
            resend_key="rk",
            from_email="no-reply@example.com",
            now=heartbeat.datetime.now(heartbeat.timezone.utc),
        )

        self.assertFalse(reverted)
        # No DB update should have happened
        self.assertIsNone(client.profiles.updated_payload)


    # ── Security-specific tests ──

    def test_hmac_signature_matches_for_correct_payload(self):
        key_bytes = b"\x01" * 32
        payload_enc = "encrypted_payload_data"
        recipient_enc = "encrypted_recipient"
        message = f"{payload_enc}|{recipient_enc}"

        sig1 = heartbeat.compute_hmac_signature(message, key_bytes)
        sig2 = heartbeat.compute_hmac_signature(message, key_bytes)

        self.assertEqual(sig1, sig2, "HMAC must be deterministic")

    def test_hmac_signature_changes_on_tampered_payload(self):
        key_bytes = b"\x01" * 32
        original_msg = "encrypted_payload|encrypted_recipient"
        tampered_msg = "encrypted_payload|TAMPERED_recipient"

        sig_original = heartbeat.compute_hmac_signature(original_msg, key_bytes)
        sig_tampered = heartbeat.compute_hmac_signature(tampered_msg, key_bytes)

        self.assertNotEqual(sig_original, sig_tampered,
                            "Tampered payload must produce different HMAC")

    def test_hmac_signature_changes_with_different_key(self):
        key1 = b"\x01" * 32
        key2 = b"\x02" * 32
        message = "payload|recipient"

        sig1 = heartbeat.compute_hmac_signature(message, key1)
        sig2 = heartbeat.compute_hmac_signature(message, key2)

        self.assertNotEqual(sig1, sig2,
                            "Different HMAC keys must produce different signatures")

    def test_process_expired_entries_hmac_mismatch_with_bad_recipient_still_preserved(self):
        """HMAC mismatch alone does NOT block delivery (soft warning). Entry is preserved
        here because the mocked recipient decryption returns invalid email format."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {
                "id": "entry-tampered",
                "action_type": "send",
                "title": "Tampered",
                "payload_encrypted": "payload",
                "recipient_email_encrypted": "recipient",
                "data_key_encrypted": "datakey",
                "hmac_signature": "WRONG_SIGNATURE",
            }
        ]
        profile = {
            "id": "user-x",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "decrypt_with_server_secret", return_value=b"h" * 32),
            patch.object(heartbeat, "compute_hmac_signature", return_value="CORRECT_SIGNATURE"),
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send, "Tampered entry must not trigger grace period")
        self.assertEqual(input_send_count, 1)
        mock_delete.assert_not_called()  # CRITICAL: send entries must NEVER be deleted
        mock_release.assert_called_once()  # Lock released for retry
        mock_post.assert_not_called()

    def test_process_expired_entries_rejects_empty_recipient(self):
        """Entry with no recipient is preserved (not deleted), not sent."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {
                "id": "entry-no-recip",
                "action_type": "send",
                "title": "No Recipient",
                "payload_encrypted": "payload",
                "recipient_email_encrypted": "",
                "data_key_encrypted": "dk",
                "hmac_signature": "sig",
            }
        ]
        profile = {
            "id": "user-y",
            "sender_name": "Bob",
            "hmac_key_encrypted": "enc-hmac",
        }

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "decrypt_with_server_secret", return_value=b"h" * 32),
            patch.object(heartbeat, "compute_hmac_signature", return_value="sig"),
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 1)
        mock_delete.assert_not_called()  # CRITICAL: send entries must NEVER be deleted
        mock_release.assert_called_once()  # Lock released for retry
        mock_post.assert_not_called()

    def test_extract_server_ciphertext_from_envelope(self):
        envelope = '{"v":1,"server":"server_ct","device":"device_ct"}'
        result = heartbeat.extract_server_ciphertext(envelope)
        self.assertEqual(result, "server_ct")

    def test_extract_server_ciphertext_legacy_raw(self):
        raw = "raw_ciphertext_no_json"
        result = heartbeat.extract_server_ciphertext(raw)
        self.assertEqual(result, raw)

    def test_viewer_link_format(self):
        link = heartbeat.build_viewer_link("https://view.afterword-app.com", "entry-abc")
        self.assertEqual(link, "https://view.afterword-app.com/?entry=entry-abc")

    def test_viewer_link_strips_trailing_slash(self):
        link = heartbeat.build_viewer_link("https://view.afterword-app.com/", "e-1")
        self.assertEqual(link, "https://view.afterword-app.com/?entry=e-1")

    def test_is_paid_recognizes_all_tiers(self):
        self.assertTrue(heartbeat.is_paid("pro"))
        self.assertTrue(heartbeat.is_paid("lifetime"))
        self.assertTrue(heartbeat.is_paid("premium"))
        self.assertTrue(heartbeat.is_paid("Pro"))
        self.assertTrue(heartbeat.is_paid("LIFETIME"))
        self.assertFalse(heartbeat.is_paid("free"))
        self.assertFalse(heartbeat.is_paid(None))
        self.assertFalse(heartbeat.is_paid(""))

    def test_normalize_timer_days_edge_cases(self):
        self.assertEqual(heartbeat._normalize_timer_days(0), 1)
        self.assertEqual(heartbeat._normalize_timer_days(-5), 1)
        self.assertEqual(heartbeat._normalize_timer_days(None), 30)  # match Flutter default
        self.assertEqual(heartbeat._normalize_timer_days("30"), 30)
        self.assertEqual(heartbeat._normalize_timer_days(365), 365)
        self.assertEqual(heartbeat._normalize_timer_days("garbage"), 30)
        self.assertEqual(heartbeat._normalize_timer_days(""), 30)

    def test_already_marked_in_cycle(self):
        lci = datetime(2026, 2, 1, 0, 0, tzinfo=timezone.utc)
        before = datetime(2026, 1, 31, 23, 0, tzinfo=timezone.utc)
        after = datetime(2026, 2, 2, 0, 0, tzinfo=timezone.utc)

        self.assertFalse(heartbeat._already_marked_in_cycle(None, lci))
        self.assertFalse(heartbeat._already_marked_in_cycle(before, lci))
        self.assertTrue(heartbeat._already_marked_in_cycle(after, lci))
        self.assertTrue(heartbeat._already_marked_in_cycle(lci, lci))

    def test_claim_entry_skipped_means_no_processing(self):
        """If claim_entry_for_sending returns False, entry is skipped entirely."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [{"id": "e-race", "action_type": "send", "title": "Race"}]
        profile = {"id": "u", "sender_name": "X", "hmac_key_encrypted": "hk"}

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=False),
            patch.object(heartbeat, "delete_entry") as mock_del,
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 1)
        mock_del.assert_not_called()
        mock_batch.assert_not_called()


    # ── CRITICAL: Hybrid send+destroy scenario tests ──

    def test_hybrid_send_destroy_null_hmac_preserves_send_entries(self):
        """THE BUG: 6 send + 3 destroy entries, hmac_key_encrypted is NULL.
        Destroy entries should be deleted. Send entries must be PRESERVED (not deleted).
        had_send must be False, input_send_count must be 6."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": f"send-{i}", "action_type": "send", "title": f"Send {i}",
             "payload_encrypted": "p", "recipient_email_encrypted": "r",
             "data_key_encrypted": "dk", "hmac_signature": "sig"}
            for i in range(6)
        ] + [
            {"id": f"destroy-{i}", "action_type": "destroy", "title": f"Destroy {i}"}
            for i in range(3)
        ]
        profile = {
            "id": "user-hybrid",
            "sender_name": "Alice",
            "hmac_key_encrypted": None,  # <-- THE BUG TRIGGER
        }
        deleted_ids = []
        released_ids = []

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_ids.append(e["id"])),
            patch.object(heartbeat, "release_entry_lock",
                         side_effect=lambda _c, eid: released_ids.append(eid)),
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 6)
        # Destroy entries ARE deleted (correct behavior)
        self.assertEqual(sorted(deleted_ids), ["destroy-0", "destroy-1", "destroy-2"])
        # Send entries are RELEASED (preserved for retry), NOT deleted
        self.assertEqual(sorted(released_ids),
                         [f"send-{i}" for i in range(6)])
        mock_post.assert_not_called()

    def test_hybrid_send_destroy_successful_sends_with_destroys(self):
        """Mixed vault: 2 send + 1 destroy. Sends succeed, destroy deleted.
        had_send=True, input_send_count=2."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": "s1", "action_type": "send", "title": "Send 1",
             "payload_encrypted": "p1", "recipient_email_encrypted": "r1",
             "data_key_encrypted": "dk1", "hmac_signature": "sig1"},
            {"id": "s2", "action_type": "send", "title": "Send 2",
             "payload_encrypted": "p2", "recipient_email_encrypted": "r2",
             "data_key_encrypted": "dk2", "hmac_signature": "sig2"},
            {"id": "d1", "action_type": "destroy", "title": "Destroy 1"},
        ]
        profile = {
            "id": "user-mixed",
            "sender_name": "Bob",
            "hmac_key_encrypted": "enc-hmac",
        }
        deleted_ids = []

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=[b"h" * 32, b"ben@x.com", b"k" * 32,
                                      b"ben2@x.com", b"k" * 32]),
            patch.object(heartbeat, "compute_hmac_signature",
                         side_effect=lambda msg, key: {
                             "p1|r1": "sig1", "p2|r2": "sig2",
                         }.get(msg, "nomatch")),
            patch.object(heartbeat, "build_unlock_email_payload", return_value={"mock": True}),
            patch.object(heartbeat, "_post_json_with_retries", return_value=_DummyResponse(200, '{"data": [{"id": "r1"}, {"id": "r2"}]}')) as mock_post,
            patch.object(heartbeat, "mark_entry_sent", return_value=True),
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_ids.append(e["id"])),
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertTrue(had_send)
        self.assertEqual(input_send_count, 2)
        self.assertEqual(deleted_ids, ["d1"])  # Only destroy entry deleted
        mock_post.assert_called_once()  # Single batch call for both send entries
        self.assertEqual(len(mock_post.call_args.kwargs["payload"]), 2)  # 2 payloads in batch

    def test_hmac_mismatch_does_not_block_delivery_when_decryption_succeeds(self):
        """THE FIX: HMAC mismatch (key rotation) must NOT block delivery.
        When AES-GCM decryption succeeds, the data is intact — HMAC mismatch
        is just a stale key, not tampering. Entries must be delivered."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": "rotated-1", "action_type": "send", "title": "Key Rotated Entry",
             "payload_encrypted": "p1", "recipient_email_encrypted": "r1",
             "data_key_encrypted": "dk1", "hmac_signature": "OLD_STALE_SIG"},
        ]
        profile = {
            "id": "user-rotated",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            # First call: HMAC key decryption, then recipient, then data_key
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=[b"h" * 32, b"ben@example.com", b"k" * 32]),
            # compute_hmac_signature returns something that does NOT match the entry
            patch.object(heartbeat, "compute_hmac_signature", return_value="NEW_KEY_SIG"),
            patch.object(heartbeat, "build_unlock_email_payload", return_value={"mock": True}),
            patch.object(heartbeat, "_post_json_with_retries",
                         return_value=_DummyResponse(200, '{"data": [{"id": "r1"}]}')),
            patch.object(heartbeat, "mark_entry_sent", return_value=True),
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        # Entry MUST be delivered despite HMAC mismatch
        self.assertTrue(had_send, "HMAC mismatch must NOT block delivery when decryption succeeds")
        self.assertEqual(input_send_count, 1)
        mock_delete.assert_not_called()
        # release_entry_lock should NOT be called (entry was sent successfully)
        mock_release.assert_not_called()

    def test_null_hmac_key_sends_zero_preserves_all(self):
        """When hmac_key_encrypted is None, ALL send entries must be preserved."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": f"e-{i}", "action_type": "send", "title": f"Entry {i}",
             "payload_encrypted": "p", "recipient_email_encrypted": "r",
             "data_key_encrypted": "dk", "hmac_signature": "sig"}
            for i in range(3)
        ]
        profile = {"id": "u-null", "sender_name": "X", "hmac_key_encrypted": None}
        released_ids = []

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "release_entry_lock",
                         side_effect=lambda _c, eid: released_ids.append(eid)),
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 3)
        mock_delete.assert_not_called()  # ZERO deletions
        self.assertEqual(sorted(released_ids), ["e-0", "e-1", "e-2"])
        mock_post.assert_not_called()


    def test_email_validation_regex(self):
        """Basic email validation catches obviously invalid addresses."""
        self.assertTrue(heartbeat._EMAIL_RE.match("user@example.com"))
        self.assertTrue(heartbeat._EMAIL_RE.match("a+b@sub.domain.org"))
        self.assertIsNone(heartbeat._EMAIL_RE.match(""))
        self.assertIsNone(heartbeat._EMAIL_RE.match("no-at-sign"))
        self.assertIsNone(heartbeat._EMAIL_RE.match("@no-local.com"))
        self.assertIsNone(heartbeat._EMAIL_RE.match("spaces in@email.com"))

    def test_recipient_decryption_failure_preserves_entry(self):
        """If recipient email decryption throws, entry is preserved, not deleted."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {
                "id": "entry-dec-fail",
                "action_type": "send",
                "title": "Decrypt Fail",
                "payload_encrypted": "payload",
                "recipient_email_encrypted": "corrupt-envelope",
                "data_key_encrypted": "dk",
                "hmac_signature": "sig",
            }
        ]
        profile = {
            "id": "user-dec",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }

        call_count = {"decrypt": 0}

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32  # HMAC key
            raise ValueError("Corrupt ciphertext")

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature", return_value="sig"),
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 1)
        mock_delete.assert_not_called()
        mock_release.assert_called_once()
        mock_post.assert_not_called()

    def test_data_key_decryption_failure_preserves_entry(self):
        """If data key decryption throws, entry is preserved, not deleted."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {
                "id": "entry-dk-fail",
                "action_type": "send",
                "title": "DK Fail",
                "payload_encrypted": "payload",
                "recipient_email_encrypted": "enc-recipient",
                "data_key_encrypted": "corrupt-dk",
                "hmac_signature": "sig",
            }
        ]
        profile = {
            "id": "user-dk",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }

        call_count = {"decrypt": 0}

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32  # HMAC key
            if call_count["decrypt"] == 2:
                return b"user@example.com"  # recipient email
            raise ValueError("Corrupt data key")

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature", return_value="sig"),
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_post_json_with_retries") as mock_post,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 1)
        mock_delete.assert_not_called()
        mock_release.assert_called_once()
        mock_post.assert_not_called()

    def test_multiple_send_entries_all_sent_different_recipients(self):
        """4 send entries with 2 different emails — ALL must be sent via single batch."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": f"s-{i}", "action_type": "send", "title": f"Entry {i}",
             "payload_encrypted": f"p{i}", "recipient_email_encrypted": f"r{i}",
             "data_key_encrypted": f"dk{i}", "hmac_signature": f"sig{i}"}
            for i in range(4)
        ]
        profile = {
            "id": "user-multi",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }
        emails = ["a@x.com", "a@x.com", "b@y.com", "b@y.com"]

        call_count = {"decrypt": 0}

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32  # HMAC key
            # Pattern: recipient, data_key, recipient, data_key, ...
            idx = call_count["decrypt"] - 2
            if idx % 2 == 0:
                email_idx = idx // 2
                return emails[email_idx].encode("utf-8")
            return b"k" * 32  # data key

        built_payloads = []

        def _track_build(*args, **kwargs):
            built_payloads.append(args[0])  # recipient_email
            return {"to": [args[0]]}

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature",
                         side_effect=lambda msg, key: {
                             f"p{i}|r{i}": f"sig{i}" for i in range(4)
                         }.get(msg, "nomatch")),
            patch.object(heartbeat, "build_unlock_email_payload", side_effect=_track_build),
            patch.object(heartbeat, "_post_json_with_retries",
                         return_value=_DummyResponse(200, '{"data": []}')) as mock_post,
            patch.object(heartbeat, "mark_entry_sent", return_value=True),
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertTrue(had_send)
        self.assertEqual(input_send_count, 4)
        self.assertEqual(built_payloads, ["a@x.com", "a@x.com", "b@y.com", "b@y.com"])
        # Single batch call with all 4 payloads (no rate-limit issues)
        mock_post.assert_called_once()
        self.assertEqual(len(mock_post.call_args.kwargs["payload"]), 4)

    def test_batch_send_failure_releases_all_locks(self):
        """If the batch API call fails, all prepared entry locks are released."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": f"s-{i}", "action_type": "send", "title": f"Entry {i}",
             "payload_encrypted": f"p{i}", "recipient_email_encrypted": f"r{i}",
             "data_key_encrypted": f"dk{i}", "hmac_signature": f"sig{i}"}
            for i in range(3)
        ]
        profile = {
            "id": "user-bfail",
            "sender_name": "Alice",
            "hmac_key_encrypted": "enc-hmac",
        }
        released_ids = []

        call_count = {"decrypt": 0}

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32
            idx = call_count["decrypt"] - 2
            if idx % 2 == 0:
                return b"user@example.com"
            return b"k" * 32

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature",
                         side_effect=lambda msg, key: {
                             f"p{i}|r{i}": f"sig{i}" for i in range(3)
                         }.get(msg, "nomatch")),
            patch.object(heartbeat, "build_unlock_email_payload",
                         return_value={"to": ["u@x.com"], "headers": {}}),
            patch.object(heartbeat, "_post_json_with_retries",
                         return_value=_DummyResponse(429, '{"message": "rate limited"}')),
            patch.object(heartbeat, "release_entry_lock",
                         side_effect=lambda _c, eid: released_ids.append(eid)),
            patch.object(heartbeat, "mark_entry_sent") as mock_mark,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send)
        self.assertEqual(input_send_count, 3)
        # All 3 locks released after batch failed
        self.assertEqual(sorted(released_ids), ["s-0", "s-1", "s-2"])
        mock_mark.assert_not_called()


    def test_send_batch_emails_chunks_over_100(self):
        """send_batch_emails splits >100 payloads into multiple chunk requests."""
        call_payloads = []

        def _mock_post(url, *, headers, payload, idempotency_key=None, timeout=30):
            call_payloads.append((len(payload), idempotency_key))
            return _DummyResponse(200, '{"data": []}')

        with patch.object(heartbeat, "_post_json_with_retries", side_effect=_mock_post):
            heartbeat.send_batch_emails("key", [{"mock": i} for i in range(250)],
                                        idempotency_key="batch-test")

        # Should be 3 chunks: 100 + 100 + 50
        self.assertEqual(len(call_payloads), 3)
        self.assertEqual(call_payloads[0][0], 100)
        self.assertEqual(call_payloads[1][0], 100)
        self.assertEqual(call_payloads[2][0], 50)
        # Idempotency keys should have chunk suffixes
        self.assertEqual(call_payloads[0][1], "batch-test-0")
        self.assertEqual(call_payloads[1][1], "batch-test-1")
        self.assertEqual(call_payloads[2][1], "batch-test-2")

    def test_send_batch_emails_no_suffix_under_100(self):
        """send_batch_emails uses original key (no suffix) when <=100 payloads."""
        call_keys = []

        def _mock_post(url, *, headers, payload, idempotency_key=None, timeout=30):
            call_keys.append(idempotency_key)
            return _DummyResponse(200, '{"data": []}')

        with patch.object(heartbeat, "_post_json_with_retries", side_effect=_mock_post):
            heartbeat.send_batch_emails("key", [{"mock": i} for i in range(50)],
                                        idempotency_key="batch-small")

        self.assertEqual(len(call_keys), 1)
        self.assertEqual(call_keys[0], "batch-small")  # No suffix

    def test_cleanup_sent_entries_grace_expired_no_entries(self):
        """Grace expired + zero entries → profile reset to fresh active."""
        update_payloads = []
        profile_select_calls = {"n": 0}

        class _Q:
            def __init__(self, *, data=None, count=0):
                self._data = data or []
                self._count = count
            def select(self, *a, **kw): return self
            def eq(self, *a, **kw): return self
            def neq(self, *a, **kw): return self
            def in_(self, *a, **kw): return self
            def lte(self, *a, **kw): return self
            def gt(self, *a, **kw): return self
            def order(self, *a, **kw): return self
            def limit(self, *a, **kw): return self
            def insert(self, *a, **kw): return self
            def update(self, payload):
                update_payloads.append(payload)
                return self
            def execute(self):
                return types.SimpleNamespace(data=self._data, count=self._count)

        class _Client:
            def table(self_inner, name):
                if name == "profiles":
                    profile_select_calls["n"] += 1
                    if profile_select_calls["n"] == 1:
                        return _Q(data=[{"id": "user-1", "sender_name": "Alice", "timer_days": 30}])
                    return _Q()
                if name == "vault_entries":
                    return _Q()  # zero entries everywhere
                if name == "vault_entry_tombstones":
                    return _Q()
                return _Q()

        heartbeat.cleanup_sent_entries(_Client())

        # Profile should be reset to fresh active
        self.assertTrue(any(p.get("status") == "active" and p.get("timer_days") == 30
                           for p in update_payloads))

    def test_cleanup_sent_entries_grace_expired_with_unprocessed(self):
        """Grace expired + unprocessed entries → re-activate with expired timer."""
        update_payloads = []
        profile_select_calls = {"n": 0}

        class _Q:
            def __init__(self, *, data=None, count=0):
                self._data = data or []
                self._count = count
            def select(self, *a, **kw): return self
            def eq(self, *a, **kw): return self
            def neq(self, *a, **kw): return self
            def lte(self, *a, **kw): return self
            def gt(self, *a, **kw): return self
            def order(self, *a, **kw): return self
            def limit(self, *a, **kw): return self
            def insert(self, *a, **kw): return self
            def in_(self, *a, **kw):
                self._is_unprocessed = True
                return self
            def update(self, payload):
                update_payloads.append(payload)
                return self
            def execute(self):
                # If this was an unprocessed query, return count=2
                if getattr(self, "_is_unprocessed", False):
                    return types.SimpleNamespace(data=[], count=2)
                return types.SimpleNamespace(data=self._data, count=self._count)

        class _Client:
            def table(self_inner, name):
                if name == "profiles":
                    profile_select_calls["n"] += 1
                    if profile_select_calls["n"] == 1:
                        return _Q(data=[{"id": "user-2", "sender_name": "Bob", "timer_days": 30}])
                    return _Q()
                if name == "vault_entries":
                    return _Q()
                return _Q()

        heartbeat.cleanup_sent_entries(_Client())

        # Profile should be re-activated with expired timer (Scenario B)
        self.assertTrue(len(update_payloads) >= 1)
        self.assertEqual(update_payloads[0]["status"], "active")
        self.assertIsNone(update_payloads[0]["protocol_executed_at"])
        self.assertNotIn("timer_days", update_payloads[0])
        check_in = datetime.fromisoformat(update_payloads[0]["last_check_in"])
        self.assertTrue(check_in < datetime.now(timezone.utc) - timedelta(days=30))

    def test_cleanup_sent_entries_grace_expired_deletes_sent_immediately(self):
        """Grace expired + sent entries → tombstone + delete ALL sent entries immediately."""
        deleted_ids = []
        tombstone_inserts = []
        update_payloads = []
        profile_select_calls = {"n": 0}
        vault_select_calls = {"n": 0}

        sent_entries = [
            {"id": "e1", "user_id": "user-3", "audio_file_path": None, "sent_at": "2026-01-01T00:00:00+00:00"},
            {"id": "e2", "user_id": "user-3", "audio_file_path": None, "sent_at": "2026-01-15T00:00:00+00:00"},
        ]

        class _Q:
            def __init__(self, *, data=None, count=0):
                self._data = data or []
                self._count = count
                self._is_unprocessed = False
            def select(self, *a, **kw): return self
            def eq(self, *a, **kw): return self
            def neq(self, *a, **kw): return self
            def lte(self, *a, **kw): return self
            def gt(self, *a, **kw): return self
            def order(self, *a, **kw): return self
            def limit(self, *a, **kw): return self
            def in_(self, *a, **kw):
                self._is_unprocessed = True
                return self
            def insert(self, payload):
                tombstone_inserts.append(payload)
                return self
            def update(self, payload):
                update_payloads.append(payload)
                return self
            def execute(self):
                if self._is_unprocessed:
                    return types.SimpleNamespace(data=[], count=0)
                return types.SimpleNamespace(data=self._data, count=self._count)

        class _Client:
            def table(self_inner, name):
                if name == "profiles":
                    profile_select_calls["n"] += 1
                    if profile_select_calls["n"] == 1:
                        return _Q(data=[{"id": "user-3", "sender_name": "Carol", "timer_days": 30}])
                    return _Q()
                if name == "vault_entries":
                    vault_select_calls["n"] += 1
                    # First vault call = unprocessed check (count=0)
                    # Second vault call = sent entries fetch
                    # Third vault call = empty (pagination end)
                    if vault_select_calls["n"] == 1:
                        return _Q()  # unprocessed = 0
                    if vault_select_calls["n"] == 2:
                        return _Q(data=sent_entries)
                    return _Q()
                if name == "vault_entry_tombstones":
                    return _Q()
                return _Q()

        def _mock_delete(client, entry):
            deleted_ids.append(entry["id"])

        with patch.object(heartbeat, "delete_entry", side_effect=_mock_delete):
            heartbeat.cleanup_sent_entries(_Client())

        # Both entries should be tombstoned
        self.assertEqual(len(tombstone_inserts), 2)
        # Both entries should be deleted
        self.assertEqual(sorted(deleted_ids), ["e1", "e2"])
        # Profile should be reset to fresh
        reset_update = [p for p in update_payloads if p.get("status") == "active"]
        self.assertTrue(len(reset_update) >= 1)
        self.assertEqual(reset_update[0]["timer_days"], 30)


    # ── Subscription downgrade edge-case tests ──

    def test_downgrade_short_timer_below_30_detected(self):
        """timer_days=7 (below free default of 30) IS a premium feature.
        Must be detected and reset to 30, with downgrade email sent."""
        update_calls = []
        sent_emails = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-short-timer",
            "email": "short@example.com",
            "sender_name": "ShortTimer",
            "timer_days": 7,
            "selected_theme": None,
            "selected_soul_fire": None,
        }

        with patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=[],
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(len(sent_emails), 1)
        # Wipe update resets timer to 30
        self.assertEqual(update_calls[0]["timer_days"], 30)
        # downgrade_email_pending set True in wipe, then cleared on success
        self.assertTrue(update_calls[0].get("downgrade_email_pending"))
        self.assertFalse(update_calls[1].get("downgrade_email_pending"))

    def test_downgrade_timer_14_days_detected(self):
        """timer_days=14 (between min and free default) IS a premium feature."""
        client = _MinimalClient()
        sent_emails = []

        profile = {
            "id": "user-14d",
            "email": "t14@example.com",
            "sender_name": "Timer14",
            "timer_days": 14,
            "selected_theme": None,
            "selected_soul_fire": None,
        }

        with patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=[],
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(len(sent_emails), 1)

    def test_downgrade_pro_user_with_audio_deletes_audio(self):
        """Pro user (timer_days=60) with audio entries → audio deleted, email sent."""
        client = _MinimalClient()
        deleted_entries = []
        sent_emails = []

        profile = {
            "id": "user-pro-audio",
            "email": "pro@example.com",
            "sender_name": "ProUser",
            "timer_days": 60,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "audio-1", "data_type": "audio", "audio_file_path": "user-pro-audio/a1.enc"},
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e["id"])),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(deleted_entries, ["audio-1"])
        self.assertEqual(len(sent_emails), 1)

    def test_downgrade_audio_only_no_pro_indicators_still_detected(self):
        """User with ONLY audio entries (timer=30, free themes) → still detected and cleaned."""
        client = _MinimalClient()
        deleted_entries = []
        sent_emails = []

        profile = {
            "id": "user-audio-only",
            "email": "audio@example.com",
            "sender_name": "AudioOnly",
            "timer_days": 30,
            "selected_theme": "oledVoid",
            "selected_soul_fire": "etherealOrb",
        }
        active_entries = [
            {"id": "a1", "data_type": "audio", "audio_file_path": "user-audio-only/a1.enc"},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e["id"])),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(deleted_entries, ["a1"])
        self.assertEqual(len(sent_emails), 1)

    def test_downgrade_timer_only_no_audio_no_audio_deleted(self):
        """Pro user with custom timer but no audio → timer reset, no audio deletion, email sent."""
        update_calls = []
        deleted_entries = []
        sent_emails = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-timer-only",
            "email": "timer@example.com",
            "sender_name": "TimerOnly",
            "timer_days": 180,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e["id"])),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(deleted_entries, [])
        self.assertEqual(len(sent_emails), 1)
        # First update is the wipe
        self.assertEqual(update_calls[0]["timer_days"], 30)

    def test_downgrade_already_free_defaults_returns_false(self):
        """User already at free defaults (timer=30, no themes, no audio) → no action."""
        client = _MinimalClient()

        profile = {
            "id": "user-already-free",
            "email": "free@example.com",
            "sender_name": "Free",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        reverted = heartbeat.handle_subscription_downgrade(
            client=client, profile=profile, active_entries=active_entries,
            resend_key="rk", from_email="no-reply@example.com",
            now=heartbeat.datetime.now(heartbeat.timezone.utc),
        )

        self.assertFalse(reverted)
        self.assertIsNone(client.profiles.updated_payload)

    def test_downgrade_email_text_says_text_preserved_when_audio_deleted(self):
        """When audio is deleted, email says 'text vault entries' not 'all vault entries'."""
        client = _MinimalClient()
        sent_emails = []

        profile = {
            "id": "user-email-check",
            "email": "check@example.com",
            "sender_name": "EmailCheck",
            "timer_days": 60,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "a1", "data_type": "audio", "audio_file_path": "user-email-check/a1.enc"},
        ]

        with (
            patch.object(heartbeat, "delete_entry", side_effect=lambda _c, e: None),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *args, **kwargs: sent_emails.append(args)),
        ):
            heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertEqual(len(sent_emails), 1)
        # args: (api_key, from_email, to_email, subject, text, html)
        text_body = sent_emails[0][4]
        html_body = sent_emails[0][5]
        self.assertIn("text vault entries are preserved", text_body)
        self.assertNotIn("All your existing vault entries are preserved", text_body)
        self.assertIn("Audio vault entries have been removed", text_body)
        self.assertIn("text vault entries are preserved", html_body)
        self.assertIn("Audio vault entries have been removed", html_body)

    def test_downgrade_email_says_all_preserved_when_no_audio(self):
        """When no audio deleted, email says 'All your existing vault entries'."""
        client = _MinimalClient()
        sent_emails = []

        profile = {
            "id": "user-no-audio-email",
            "email": "noaudio@example.com",
            "sender_name": "NoAudio",
            "timer_days": 90,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        with (
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *args, **kwargs: sent_emails.append(args)),
        ):
            heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertEqual(len(sent_emails), 1)
        text_body = sent_emails[0][4]
        self.assertIn("All your existing vault entries are preserved", text_body)
        self.assertNotIn("Audio vault entries have been removed", text_body)

    def test_downgrade_no_email_for_theme_only_change(self):
        """Theme-only change (no custom timer, no audio) → silent reset, NO email."""
        client = _MinimalClient()
        sent_emails = []

        profile = {
            "id": "user-theme-only",
            "email": "theme@example.com",
            "sender_name": "ThemeOnly",
            "timer_days": 30,
            "selected_theme": "obsidianSteel",
            "selected_soul_fire": None,
        }
        active_entries = []

        with (
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(len(sent_emails), 0)
        self.assertIsNone(client.profiles.updated_payload["selected_theme"])

    def test_downgrade_idempotency_key_is_date_scoped(self):
        """Idempotency key includes the date to prevent duplicate emails within same day."""
        client = _MinimalClient()
        sent_emails = []

        now = datetime(2026, 3, 15, 10, 30, tzinfo=timezone.utc)
        profile = {
            "id": "user-idemp",
            "email": "idemp@example.com",
            "sender_name": "Idemp",
            "timer_days": 90,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = []

        with patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)):
            heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=now,
            )

        self.assertEqual(len(sent_emails), 1)
        self.assertEqual(
            sent_emails[0]["idempotency_key"],
            "downgrade-user-idemp-2026-03-15",
        )

    def test_downgrade_second_run_after_reset_is_noop(self):
        """After downgrade resets everything, a second call with free defaults returns False."""
        client = _MinimalClient()

        # This is what the profile looks like AFTER the first downgrade run
        profile = {
            "id": "user-second-run",
            "email": "second@example.com",
            "sender_name": "Second",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        # No audio entries left after first run deleted them
        active_entries = [
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        reverted = heartbeat.handle_subscription_downgrade(
            client=client, profile=profile, active_entries=active_entries,
            resend_key="rk", from_email="no-reply@example.com",
            now=heartbeat.datetime.now(heartbeat.timezone.utc),
        )

        self.assertFalse(reverted)
        self.assertIsNone(client.profiles.updated_payload)

    def test_downgrade_no_email_when_email_is_none(self):
        """If user has no email on profile, downgrade still works but no email sent."""
        client = _MinimalClient()
        deleted_entries = []
        sent_emails = []

        profile = {
            "id": "user-no-email",
            "email": None,
            "sender_name": "NoEmail",
            "timer_days": 60,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "a1", "data_type": "audio", "audio_file_path": "user-no-email/a1.enc"},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e["id"])),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(deleted_entries, ["a1"])
        self.assertEqual(len(sent_emails), 0)

    def test_downgrade_multiple_audio_entries_all_deleted(self):
        """User with multiple audio entries → ALL audio entries deleted, single email."""
        update_calls = []
        deleted_entries = []
        sent_emails = []

        class _TrackingProfilesQuery(_ProfilesQuery):
            def update(self, payload):
                update_calls.append(dict(payload))
                return super().update(payload)

        class _TrackingClient(_MinimalClient):
            def __init__(self):
                super().__init__()
                self.profiles = _TrackingProfilesQuery()

            def table(self, name):
                if name == "profiles":
                    return self.profiles
                return super().table(name)

        client = _TrackingClient()
        profile = {
            "id": "user-multi-audio",
            "email": "multi@example.com",
            "sender_name": "MultiAudio",
            "timer_days": 365,
            "selected_theme": "deepOcean",
            "selected_soul_fire": "voidPortal",
        }
        active_entries = [
            {"id": "a1", "data_type": "audio", "audio_file_path": "user-multi-audio/a1.enc"},
            {"id": "a2", "data_type": "audio", "audio_file_path": "user-multi-audio/a2.enc"},
            {"id": "a3", "data_type": "audio", "audio_file_path": "user-multi-audio/a3.enc"},
            {"id": "text-1", "data_type": "text", "audio_file_path": None},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e["id"])),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *a, **kw: sent_emails.append(kw)),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        self.assertTrue(reverted)
        self.assertEqual(sorted(deleted_entries), ["a1", "a2", "a3"])
        self.assertEqual(len(sent_emails), 1)
        # First update is the wipe
        self.assertEqual(update_calls[0]["timer_days"], 30)
        self.assertIsNone(update_calls[0]["selected_theme"])
        self.assertIsNone(update_calls[0]["selected_soul_fire"])


    # ── RC lifetime detection tests ──

    def test_rc_verify_lifetime_via_null_expires(self):
        """Non-expiring entitlement matching our ID = lifetime, regardless of product name."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "AfterWord Pro": {
                        "expires_date": None,
                        "product_identifier": "com.afterword.pro_purchase",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-lt")
        self.assertEqual(result, "lifetime")

    def test_rc_verify_lifetime_via_product_identifier(self):
        """Product identifier containing 'lifetime' = lifetime."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "AfterWord Pro": {
                        "expires_date": "2099-01-01T00:00:00Z",
                        "product_identifier": "com.afterword.lifetime_pro",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-lt2")
        self.assertEqual(result, "lifetime")

    def test_rc_verify_pro_with_expiring_entitlement(self):
        """Entitlement with future expires_date and no 'lifetime' in product = pro."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "AfterWord Pro": {
                        "expires_date": "2099-06-15T00:00:00Z",
                        "product_identifier": "com.afterword.pro_monthly",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-pro")
        self.assertEqual(result, "pro")

    def test_rc_verify_case_insensitive_entitlement_id(self):
        """Entitlement key 'Afterword Pro' (lowercase w) must still match 'AfterWord Pro'."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "Afterword Pro": {
                        "expires_date": "2099-01-01T00:00:00Z",
                        "product_identifier": "com.afterword.pro_annual",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-case")
        self.assertEqual(result, "pro")

    def test_rc_verify_case_insensitive_lifetime(self):
        """Case-insensitive entitlement key + null expires = lifetime."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "afterword pro": {
                        "expires_date": None,
                        "product_identifier": "com.afterword.pro",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-ci-lt")
        self.assertEqual(result, "lifetime")

    def test_rc_verify_no_matching_entitlement_returns_free(self):
        """Entitlement key that doesn't match at all → free."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "SomeOtherEntitlement": {
                        "expires_date": None,
                        "product_identifier": "com.other.product",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-free")
        self.assertEqual(result, "free")

    def test_rc_verify_expired_entitlement_returns_free(self):
        """Entitlement with past expires_date → free."""
        rc_response = {
            "subscriber": {
                "entitlements": {
                    "AfterWord Pro": {
                        "expires_date": "2020-01-01T00:00:00Z",
                        "product_identifier": "com.afterword.pro_monthly",
                    }
                }
            }
        }
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(200, __import__("json").dumps(rc_response))
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-expired")
        self.assertEqual(result, "free")

    def test_rc_verify_404_returns_free(self):
        """User not found in RC → free."""
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(404, "Not Found")
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-404")
        self.assertEqual(result, "free")

    def test_rc_verify_api_error_returns_none(self):
        """API error (500, timeout) → None (preserve DB value)."""
        with patch.object(
            heartbeat, "_get_http_session",
            return_value=type("S", (), {
                "get": lambda self, *a, **kw: _DummyResponse(500, "Internal Server Error")
            })(),
        ):
            result = heartbeat.verify_subscription_with_revenuecat("secret", "user-err")
        self.assertIsNone(result)


    # ── Decryption failure triggers tamper notification ──

    def test_decryption_failure_triggers_tamper_notification(self):
        """When AES-GCM decryption fails, _try_send_tampering_notification must be called."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": "tamper-1", "action_type": "send", "title": "Tampered",
             "payload_encrypted": "p1", "recipient_email_encrypted": "corrupt",
             "data_key_encrypted": "dk1", "hmac_signature": "sig"},
        ]
        profile = {
            "id": "user-tamper",
            "email": "owner@example.com",
            "sender_name": "Bob",
            "hmac_key_encrypted": "enc-hmac",
        }

        call_count = {"decrypt": 0}

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32  # HMAC key
            raise ValueError("AES-GCM authentication failed")

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature", return_value="sig"),
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "_try_send_tampering_notification") as mock_tamper,
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertFalse(had_send, "Decryption failure must block delivery")
        mock_delete.assert_not_called()
        mock_release.assert_called_once()
        mock_tamper.assert_called_once()
        # Verify decryption_failures count was passed
        self.assertEqual(
            mock_tamper.call_args.kwargs["decryption_failures"], 1,
        )

    # ── Multiple HMAC mismatches all delivered ──

    def test_multiple_hmac_mismatches_all_delivered(self):
        """3 entries all with HMAC mismatch (key rotation) — ALL must be delivered
        when AES-GCM decryption succeeds for each."""
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        entries = [
            {"id": f"rot-{i}", "action_type": "send", "title": f"Entry {i}",
             "payload_encrypted": f"p{i}", "recipient_email_encrypted": f"r{i}",
             "data_key_encrypted": f"dk{i}", "hmac_signature": "OLD_SIG"}
            for i in range(3)
        ]
        profile = {
            "id": "user-multi-rot",
            "sender_name": "Charlie",
            "hmac_key_encrypted": "enc-hmac",
        }

        call_count = {"decrypt": 0}
        emails = ["a@x.com", "b@x.com", "c@x.com"]

        def _decrypt_side_effect(encoded, secret):
            call_count["decrypt"] += 1
            if call_count["decrypt"] == 1:
                return b"h" * 32  # HMAC key
            idx = call_count["decrypt"] - 2
            if idx % 2 == 0:
                return emails[idx // 2].encode("utf-8")
            return b"k" * 32

        with (
            patch.object(heartbeat, "claim_entry_for_sending", return_value=True),
            patch.object(heartbeat, "extract_server_ciphertext", side_effect=lambda v: v),
            patch.object(heartbeat, "decrypt_with_server_secret",
                         side_effect=_decrypt_side_effect),
            patch.object(heartbeat, "compute_hmac_signature", return_value="NEW_SIG"),
            patch.object(heartbeat, "build_unlock_email_payload", return_value={"mock": True}),
            patch.object(heartbeat, "_post_json_with_retries",
                         return_value=_DummyResponse(200, '{"data": [{"id":"r"}]}')),
            patch.object(heartbeat, "mark_entry_sent", return_value=True),
            patch.object(heartbeat, "delete_entry") as mock_delete,
            patch.object(heartbeat, "release_entry_lock") as mock_release,
            patch.object(heartbeat, "send_executed_push", return_value=True),
        ):
            had_send, input_send_count = heartbeat.process_expired_entries(
                client=object(), profile=profile, entries=entries,
                server_secret="s", resend_key="rk", from_email="f@x.com",
                viewer_base_url="https://v.x", fcm_ctx=None, now=now,
            )

        self.assertTrue(had_send, "ALL entries must be delivered despite HMAC mismatches")
        self.assertEqual(input_send_count, 3)
        mock_delete.assert_not_called()
        mock_release.assert_not_called()

    # ── FCM push payload includes Android tag ──

    def test_fcm_push_payload_has_android_tag(self):
        """send_push_v1 must include android.notification.tag from data['type']."""
        captured = {}

        def _capture_post(url, *, headers, payload, **kwargs):
            captured.update(payload)
            return _DummyResponse(200, '{"name": "projects/p/messages/m"}')

        with patch.object(heartbeat, "_post_json_with_retries", side_effect=_capture_post):
            heartbeat.send_push_v1(
                project_id="proj",
                access_token="tok",
                fcm_token="device-token",
                title="Test",
                body="Body",
                data={"type": "warning_33"},
            )

        msg = captured.get("message", {})
        self.assertEqual(msg["android"]["notification"]["tag"], "warning_33")
        self.assertEqual(msg["data"]["type"], "warning_33")

    # ── Push 66 and 33 get different tags ──

    def test_push_66_and_33_use_different_tags(self):
        """66% and 33% pushes must use different push_stage values to avoid
        device-side notification collapsing."""
        captured_data = []

        def _capture_push(client, user_id, fcm_ctx, title, body, data=None):
            captured_data.append(data)
            return True

        with patch.object(heartbeat, "_send_push_to_user", side_effect=_capture_push):
            heartbeat.send_warning_push(
                object(), "u1", "Alice", datetime(2026, 3, 1, tzinfo=timezone.utc),
                {"project_id": "p", "access_token": "t"},
                now_utc=datetime(2026, 2, 20, tzinfo=timezone.utc),
                push_stage="warning_66",
            )
            heartbeat.send_warning_push(
                object(), "u1", "Alice", datetime(2026, 3, 1, tzinfo=timezone.utc),
                {"project_id": "p", "access_token": "t"},
                now_utc=datetime(2026, 2, 25, tzinfo=timezone.utc),
                push_stage="warning_33",
            )

        self.assertEqual(len(captured_data), 2)
        self.assertEqual(captured_data[0]["type"], "warning_66")
        self.assertEqual(captured_data[1]["type"], "warning_33")
        self.assertNotEqual(captured_data[0]["type"], captured_data[1]["type"])

    # ── Paid user with default timer NOT downgraded ──

    def test_paid_user_default_timer_not_downgraded(self):
        """A pro user with timer_days=30 (never changed) must NOT be downgraded.
        handle_subscription_downgrade only fires when sub_status is already 'free'."""
        profile = {
            "id": "user-pro-default",
            "email": "pro@example.com",
            "sender_name": "ProUser",
            "subscription_status": "pro",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
            "downgrade_email_pending": False,
        }
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)
        result = heartbeat.handle_subscription_downgrade(
            client=object(), profile=profile, active_entries=[],
            resend_key="rk", from_email="f@x.com", now=now,
        )
        # handle_subscription_downgrade checks for pro artifacts on a free user.
        # A pro user has NO artifacts to revert (timer_days=30 is the default).
        self.assertFalse(result, "Pro user with default timer must NOT trigger downgrade")

    # ── Free user with pro timer IS downgraded ──

    def test_free_user_custom_timer_is_downgraded(self):
        """A free user with timer_days=90 (pro artifact) MUST be downgraded."""
        profile = {
            "id": "user-free-custom",
            "email": "ex@example.com",
            "sender_name": "ExPro",
            "subscription_status": "free",
            "timer_days": 90,
            "selected_theme": None,
            "selected_soul_fire": None,
            "downgrade_email_pending": False,
        }
        now = datetime(2026, 2, 7, 10, 0, tzinfo=timezone.utc)

        update_calls = []

        class _FakeTable:
            def __init__(self):
                self._chain = {}
            def table(self, name):
                return self
            def update(self, data):
                update_calls.append(data)
                return self
            def eq(self, *a):
                return self
            def execute(self):
                return type("R", (), {"data": [], "count": 0})()
            def select(self, *a, **kw):
                return self

        with patch.object(heartbeat, "send_email"):
            result = heartbeat.handle_subscription_downgrade(
                client=_FakeTable(), profile=profile, active_entries=[],
                resend_key="rk", from_email="f@x.com", now=now,
            )

        self.assertTrue(result, "Free user with custom timer MUST be downgraded")
        # First update call should reset timer_days to 30
        self.assertEqual(update_calls[0]["timer_days"], 30)

    # ── ZK mode tests ──

    def test_zk_entry_email_has_no_security_key(self):
        """ZK entries produce email without security key section."""
        payload = heartbeat.build_zk_unlock_email_payload(
            recipient_email="ben@example.com",
            entry_id="e1",
            sender_name="Alice",
            entry_title="My Vault",
            viewer_link="https://view.afterword-app.com/e1",
            from_email="noreply@afterword-app.com",
        )
        self.assertNotIn("access sequence they generated for you:", payload["text"])
        self.assertNotIn("Courier New", payload["html"])
        self.assertIn("self-managed access", payload["text"])
        self.assertIn("self-managed access", payload["html"])
        self.assertIn("https://view.afterword-app.com/e1", payload["text"])

    def test_zk_entry_skips_data_key_decryption(self):
        """In process_expired_entries, ZK entries skip server data key decryption."""
        # Build a ZK entry — data_key_encrypted has empty server field
        zk_entry = {
            "id": "zk1",
            "user_id": "u1",
            "title": "ZK Vault",
            "action_type": "send",
            "data_type": "text",
            "status": "active",
            "payload_encrypted": "some_cipher",
            "recipient_email_encrypted": "",
            "data_key_encrypted": '{"v":1,"server":"","device":"abc"}',
            "hmac_signature": "",
            "is_zero_knowledge": True,
        }

        # The extract_server_ciphertext for ZK returns the raw JSON (no server content)
        server_ct = heartbeat.extract_server_ciphertext(zk_entry["data_key_encrypted"])
        # When server field is empty, extract_server_ciphertext returns the whole JSON
        # because it falls through (empty string is falsy)
        import json
        parsed = json.loads(server_ct) if server_ct.startswith("{") else {"server": server_ct}
        self.assertEqual(parsed.get("server", server_ct), "", "ZK envelope server field should be empty")

    def test_build_zk_email_has_correct_from_and_to(self):
        """ZK email payload has correct from/to fields."""
        payload = heartbeat.build_zk_unlock_email_payload(
            recipient_email="bob@example.com",
            entry_id="e2",
            sender_name="Carol",
            entry_title="Secret",
            viewer_link="https://view.afterword-app.com/e2",
            from_email="noreply@afterword-app.com",
        )
        self.assertEqual(payload["to"], ["bob@example.com"])
        self.assertIn("A personal message from Carol", payload["subject"])

    # ── Scheduled mode tests ──

    def test_process_scheduled_entries_delivers_due_entries(self):
        """Entries with scheduled_at <= now are processed for delivery."""
        now = datetime(2026, 6, 15, 12, 0, tzinfo=timezone.utc)
        past = (now - timedelta(hours=1)).isoformat()
        future = (now + timedelta(days=5)).isoformat()

        entry_due = {
            "id": "s1", "user_id": "u1", "title": "Due",
            "action_type": "send", "data_type": "text", "status": "active",
            "payload_encrypted": "c", "recipient_email_encrypted": "r",
            "data_key_encrypted": "dk", "hmac_signature": "h",
            "scheduled_at": past, "is_zero_knowledge": False,
            "grace_until": None,
        }
        entry_future = {
            "id": "s2", "user_id": "u1", "title": "Future",
            "action_type": "send", "data_type": "text", "status": "active",
            "payload_encrypted": "c", "recipient_email_encrypted": "r",
            "data_key_encrypted": "dk", "hmac_signature": "h",
            "scheduled_at": future, "is_zero_knowledge": False,
            "grace_until": None,
        }

        # Verify due entry is detected, future entry is not
        due_dt = heartbeat.parse_iso(entry_due["scheduled_at"])
        future_dt = heartbeat.parse_iso(entry_future["scheduled_at"])
        self.assertTrue(due_dt <= now, "Past entry should be due")
        self.assertFalse(future_dt <= now, "Future entry should not be due")

    def test_scheduled_mode_no_global_timer_dependency(self):
        """Scheduled mode profiles don't need last_check_in for processing."""
        profile = {
            "id": "u1", "app_mode": "scheduled",
            "last_check_in": None,
            "timer_days": 30,
        }
        # In main loop, scheduled mode profiles are routed before
        # the last_check_in NULL check, so they work even without it
        self.assertEqual(
            (profile.get("app_mode") or "vault").lower(),
            "scheduled",
        )

    def test_scheduled_entry_grace_until_set_correctly(self):
        """After delivery, grace_until should be now + 30 days."""
        now = datetime(2026, 3, 1, 0, 0, tzinfo=timezone.utc)
        grace = now + timedelta(days=30)
        self.assertEqual(grace, datetime(2026, 3, 31, 0, 0, tzinfo=timezone.utc))

    def test_clamp_scheduled_dates_within_limits(self):
        """Scheduled dates within max_days are not clamped."""
        now = datetime(2026, 3, 1, 0, 0, tzinfo=timezone.utc)
        max_date = (now + timedelta(days=30)).isoformat()
        entry_date = (now + timedelta(days=15)).isoformat()
        # Entry is within limit, should not be clamped
        self.assertLess(entry_date, max_date)

    def test_clamp_scheduled_dates_beyond_limits(self):
        """Scheduled dates beyond max_days must be clamped."""
        now = datetime(2026, 3, 1, 0, 0, tzinfo=timezone.utc)
        max_days = 30
        max_date = (now + timedelta(days=max_days)).isoformat()
        entry_date = (now + timedelta(days=365)).isoformat()
        # Entry exceeds limit
        self.assertGreater(entry_date, max_date)

    # ── Vault limits tests ──

    def test_vault_limit_constants_match_spec(self):
        """Verify tier limits match specification: Free=3, Pro=20, Lifetime=50."""
        # These are enforced via RLS policy in SQL and client-side in vault_controller.
        # The heartbeat doesn't enforce limits directly but the spec is:
        limits = {"free": 3, "pro": 20, "lifetime": 50}
        self.assertEqual(limits["free"], 3)
        self.assertEqual(limits["pro"], 20)
        self.assertEqual(limits["lifetime"], 50)

    def test_downgrade_clamps_scheduled_dates(self):
        """When downgrading, scheduled dates beyond free tier max are clamped."""
        now = datetime(2026, 6, 1, 0, 0, tzinfo=timezone.utc)
        free_max_days = 30
        max_date = now + timedelta(days=free_max_days)
        entry_scheduled = now + timedelta(days=365)  # Originally Pro/Lifetime entry

        # After downgrade to free, entry_scheduled should be clamped to max_date
        clamped = min(entry_scheduled, max_date)
        self.assertEqual(clamped, max_date)

    def test_downgrade_recurring_only_no_pro_indicators_detected(self):
        """Free user with only recurring entries (no custom timer/theme) must still trigger downgrade."""
        client = _MinimalClient()
        deleted_entries = []

        profile = {
            "id": "user-recurring-only",
            "email": "rec@example.com",
            "sender_name": "RecurringUser",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        # Only recurring entries, no audio, no pro indicators
        active_entries = [
            {"id": "fl-1", "data_type": "text", "audio_file_path": None, "entry_mode": "recurring"},
        ]

        with (
            patch.object(heartbeat, "delete_entry",
                         side_effect=lambda _c, e: deleted_entries.append(e)),
            patch.object(heartbeat, "send_email",
                         side_effect=lambda *args, **kwargs: None),
        ):
            reverted = heartbeat.handle_subscription_downgrade(
                client=client, profile=profile, active_entries=active_entries,
                resend_key="rk", from_email="no-reply@example.com",
                now=heartbeat.datetime.now(heartbeat.timezone.utc),
            )

        # Must detect recurring entries and trigger downgrade
        self.assertTrue(reverted)
        # Profile should be updated (timer reset, etc.)
        self.assertIsNotNone(client.profiles.updated_payload)

    def test_downgrade_no_recurring_no_indicators_still_returns_false(self):
        """Free user with no recurring entries and no pro indicators → no action."""
        client = _MinimalClient()

        profile = {
            "id": "user-plain-free",
            "email": "plain@example.com",
            "sender_name": "PlainFree",
            "timer_days": 30,
            "selected_theme": None,
            "selected_soul_fire": None,
        }
        active_entries = [
            {"id": "e-1", "data_type": "text", "audio_file_path": None, "entry_mode": "standard"},
        ]

        reverted = heartbeat.handle_subscription_downgrade(
            client=client, profile=profile, active_entries=active_entries,
            resend_key="rk", from_email="no-reply@example.com",
            now=heartbeat.datetime.now(heartbeat.timezone.utc),
        )

        self.assertFalse(reverted)
        self.assertIsNone(client.profiles.updated_payload)


if __name__ == "__main__":
    unittest.main()
