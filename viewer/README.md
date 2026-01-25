# Afterword Secure Viewer

This static viewer decrypts vault entries in the browser. It is meant to be hosted
as a standalone site (e.g., Vercel).

## Configure

Edit `viewer/app.js` and replace the placeholders:

```js
const config = {
  supabaseUrl: "https://YOUR_PROJECT.supabase.co",
  supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
  audioBucket: "vault-audio",
};
```

## Usage

Links should include the entry id as a query param:

```
https://view.afterword-app.com/?entry=<ENTRY_ID>
```

The beneficiary pastes the **Security Key** from the email, clicks **Unlock**,
then can view or download the decrypted text/audio.

## Notes

- Decryption happens locally in the browser.
- The app only unlocks items marked `sent`.
- Audio is downloaded and decrypted to a local blob before playback.
