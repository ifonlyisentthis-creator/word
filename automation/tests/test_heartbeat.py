import sys
import types
import unittest
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


if __name__ == "__main__":
    unittest.main()
