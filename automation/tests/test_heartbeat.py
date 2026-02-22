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


class _MinimalClient:
    def __init__(self) -> None:
        self.profiles = _ProfilesQuery()

    def table(self, table_name: str):
        if table_name == "profiles":
            return self.profiles
        raise AssertionError(f"Unexpected table access in unit test: {table_name}")


class HeartbeatTests(unittest.TestCase):
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
            patch.object(heartbeat, "send_batch_emails", return_value=[{"id": "r1"}]) as mock_batch,
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
        mock_batch.assert_called_once()
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

    def test_process_expired_entries_rejects_tampered_hmac(self):
        """Entry with wrong HMAC signature is preserved (not deleted), not sent."""
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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()

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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()

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
        self.assertEqual(heartbeat._normalize_timer_days(None), 1)
        self.assertEqual(heartbeat._normalize_timer_days("30"), 30)
        self.assertEqual(heartbeat._normalize_timer_days(365), 365)

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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()

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
            patch.object(heartbeat, "send_batch_emails", return_value=[{"id": "r1"}, {"id": "r2"}]) as mock_batch,
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
        mock_batch.assert_called_once()  # Single batch call for both send entries
        self.assertEqual(len(mock_batch.call_args[0][1]), 2)  # 2 payloads in batch

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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()


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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()

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
            patch.object(heartbeat, "send_batch_emails") as mock_batch,
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
        mock_batch.assert_not_called()

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
            patch.object(heartbeat, "send_batch_emails",
                         return_value=[{"id": f"r{i}"} for i in range(4)]) as mock_batch,
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
        mock_batch.assert_called_once()
        self.assertEqual(len(mock_batch.call_args[0][1]), 4)

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
            patch.object(heartbeat, "send_batch_emails",
                         side_effect=RuntimeError("Resend batch error: 429")),
            patch.object(heartbeat, "send_unlock_email",
                         side_effect=RuntimeError("Individual send also failed")),
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
        # All 3 locks released after both batch AND individual fallback failed
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


if __name__ == "__main__":
    unittest.main()
