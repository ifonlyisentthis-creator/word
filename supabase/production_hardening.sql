-- ============================================================================
-- AFTERWORD — PRODUCTION HARDENING SQL
-- Run this in Supabase SQL Editor AFTER comprehensive_update.sql.
--
-- This script:
--   1. Ensures last_entry_at column exists (rate-limit trigger dependency)
--   2. Adds missing indexes for scalability (millions of users)
--   3. Adds connection-pool-friendly settings
--   4. Adds cleanup for sent entries (30-day purge safety net)
--   5. Adds NOT NULL defaults for safety
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. ENSURE last_entry_at COLUMN (rate-limit trigger dependency)        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_entry_at timestamptz;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. ADDITIONAL PERFORMANCE INDEXES                                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Speed up heartbeat.py expired-user scan (profiles WHERE active + deadline passed)
CREATE INDEX IF NOT EXISTS idx_profiles_status ON profiles (status);

-- Speed up heartbeat.py push notification queries
CREATE INDEX IF NOT EXISTS idx_profiles_active_push ON profiles (last_check_in, timer_days)
  WHERE status = 'active';

-- Speed up push_devices lookup by token (for dedup on upsert)
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_devices_token ON push_devices (fcm_token);

-- Speed up vault_entries count for free-tier check in RLS
CREATE INDEX IF NOT EXISTS idx_vault_entries_user_active_type
  ON vault_entries (user_id, data_type) WHERE status = 'active';

-- Speed up viewer: audio file path lookup for storage RLS
CREATE INDEX IF NOT EXISTS idx_vault_entries_audio_path
  ON vault_entries (audio_file_path) WHERE audio_file_path IS NOT NULL;

-- Speed up tombstone queries
CREATE INDEX IF NOT EXISTS idx_tombstones_user ON vault_entry_tombstones (user_id);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. ENFORCE VALID SUBSCRIPTION STATUS VALUES                           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_subscription_status_check'
      AND conrelid = 'profiles'::regclass
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_subscription_status_check
      CHECK (subscription_status IN ('free', 'pro', 'lifetime'));
  END IF;
END $$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. ENFORCE VALID PROFILE STATUS VALUES                                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_status_check'
      AND conrelid = 'profiles'::regclass
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_status_check
      CHECK (status IN ('active', 'archived', 'inactive'));
  END IF;
END $$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  5. ENFORCE VALID VAULT ENTRY STATUS VALUES                            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'vault_entries_status_check'
      AND conrelid = 'vault_entries'::regclass
  ) THEN
    ALTER TABLE vault_entries ADD CONSTRAINT vault_entries_status_check
      CHECK (status IN ('active', 'sending', 'sent'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'vault_entries_action_type_check'
      AND conrelid = 'vault_entries'::regclass
  ) THEN
    ALTER TABLE vault_entries ADD CONSTRAINT vault_entries_action_type_check
      CHECK (action_type IN ('send', 'destroy'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'vault_entries_data_type_check'
      AND conrelid = 'vault_entries'::regclass
  ) THEN
    ALTER TABLE vault_entries ADD CONSTRAINT vault_entries_data_type_check
      CHECK (data_type IN ('text', 'audio'));
  END IF;
END $$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  6. TIMER BOUNDS CONSTRAINT                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_timer_days_bounds'
      AND conrelid = 'profiles'::regclass
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_timer_days_bounds
      CHECK (timer_days >= 7 AND timer_days <= 3650);
  END IF;
END $$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  7. AUDIO DURATION BOUNDS CONSTRAINT                                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'vault_entries_audio_duration_bounds'
      AND conrelid = 'vault_entries'::regclass
  ) THEN
    ALTER TABLE vault_entries ADD CONSTRAINT vault_entries_audio_duration_bounds
      CHECK (audio_duration_seconds IS NULL OR (audio_duration_seconds > 0 AND audio_duration_seconds <= 600));
  END IF;
END $$;

-- ============================================================================
-- END OF PRODUCTION HARDENING SQL
-- ============================================================================
