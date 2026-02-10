-- ============================================================
-- Storage RLS policies for the vault-audio bucket.
-- Run this once in the Supabase SQL Editor (Dashboard → SQL).
-- ============================================================

-- 1. Make sure the bucket exists (idempotent).
INSERT INTO storage.buckets (id, name, public)
VALUES ('vault-audio', 'vault-audio', false)
ON CONFLICT (id) DO NOTHING;

-- 2. Allow authenticated users to INSERT into their own folder.
--    Path pattern: {user_id}/{entry_id}.enc
CREATE POLICY "vault_audio_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 3. Allow authenticated users to SELECT (download) their own files.
CREATE POLICY "vault_audio_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 4. Allow authenticated users to UPDATE their own files (needed for upsert).
CREATE POLICY "vault_audio_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 5. Allow authenticated users to DELETE their own files.
CREATE POLICY "vault_audio_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
