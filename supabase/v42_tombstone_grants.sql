-- ============================================================================
-- SQL #42 — Grant service_role access to vault_entry_tombstones
-- ============================================================================
-- Problem: heartbeat.py uses service_role key to INSERT tombstones before
-- deleting sent vault entries. Without this grant, the tombstone insert
-- fails silently and the tombstone-before-delete guard prevents deletion.
-- ============================================================================

-- service_role needs INSERT (create tombstones) and DELETE (cleanup)
GRANT INSERT, DELETE ON TABLE vault_entry_tombstones TO service_role;

-- Belt-and-suspenders: also grant SELECT so queries work
GRANT SELECT ON TABLE vault_entry_tombstones TO service_role;
