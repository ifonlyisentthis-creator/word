-- v41: Reset timer when first entry is added to an empty vault
--
-- Bug: User creates account → adds entries → deletes all → timer sits expired.
-- A week later they add a new entry, but the timer shows the old last_check_in
-- from the deletion date instead of starting fresh.
--
-- Fix: Server-side trigger on vault_entries INSERT. When the first active entry
-- is inserted into a previously empty vault, reset the timer to a fresh start.
-- This respects the 12h cooldown by only firing on vault empty→non-empty transitions.

CREATE OR REPLACE FUNCTION reset_timer_on_first_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only act on active entries
  IF NEW.status = 'active' THEN
    -- Check if this is the ONLY active entry for this user
    -- (i.e., the vault was empty before this insert)
    IF NOT EXISTS (
      SELECT 1 FROM vault_entries
      WHERE user_id = NEW.user_id
        AND status = 'active'
        AND id != NEW.id
      LIMIT 1
    ) THEN
      -- First entry in an empty vault — reset timer to fresh start.
      -- Only reset if user is in 'active' status (not during grace period).
      UPDATE profiles
      SET last_check_in = now(),
          warning_sent_at = NULL,
          push_66_sent_at = NULL,
          push_33_sent_at = NULL
      WHERE id = NEW.user_id
        AND status = 'active';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if re-running
DROP TRIGGER IF EXISTS trg_reset_timer_on_first_entry ON vault_entries;

CREATE TRIGGER trg_reset_timer_on_first_entry
  AFTER INSERT ON vault_entries
  FOR EACH ROW
  EXECUTE FUNCTION reset_timer_on_first_entry();
