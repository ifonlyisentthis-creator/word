const config = window.AFTERWORD_VIEWER_CONFIG || {
  supabaseUrl: "YOUR_SUPABASE_URL",
  supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
  audioBucket: "vault-audio",
};

const entryInput = document.getElementById("entry-id");
const keyInput = document.getElementById("security-key");
const unlockButton = document.getElementById("unlock");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const resultTitle = document.getElementById("result-title");
const resultBody = document.getElementById("result-body");
const resultActions = document.getElementById("result-actions");

let currentObjectUrl = null;

const params = new URLSearchParams(window.location.search);
const entryParam = params.get("entry") || params.get("id");
if (entryParam) entryInput.value = entryParam;
if (params.has("key")) {
  params.delete("key");
  const query = params.toString();
  const sanitizedUrl = query
    ? `${window.location.pathname}?${query}`
    : window.location.pathname;
  window.history.replaceState(null, "", sanitizedUrl);
}

function setStatus(message, type = "") {
  statusEl.textContent = message;
  statusEl.className = `status ${type}`.trim();
}

function normalizeBase64(input) {
  let normalized = input.trim();
  normalized = normalized.replace(/-/g, "+").replace(/_/g, "/");
  const pad = normalized.length % 4;
  if (pad) {
    normalized += "=".repeat(4 - pad);
  }
  return normalized;
}

function base64ToBytes(value) {
  const normalized = normalizeBase64(value);
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeSecretBox(encoded) {
  const parts = encoded.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid encrypted payload.");
  }
  return {
    nonce: base64ToBytes(parts[0]),
    cipherText: base64ToBytes(parts[1]),
    tag: base64ToBytes(parts[2]),
  };
}

async function decryptPayload(encoded, keyBytes) {
  const { nonce, cipherText, tag } = decodeSecretBox(encoded);
  const combined = new Uint8Array(cipherText.length + tag.length);
  combined.set(cipherText, 0);
  combined.set(tag, cipherText.length);

  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "AES-GCM" },
    false,
    ["decrypt"]
  );

  const decrypted = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      tagLength: tag.length * 8,
    },
    key,
    combined
  );

  return new Uint8Array(decrypted);
}

function clearResult() {
  resultEl.classList.add("hidden");
  resultTitle.textContent = "";
  resultBody.innerHTML = "";
  resultActions.innerHTML = "";
  if (currentObjectUrl) {
    URL.revokeObjectURL(currentObjectUrl);
    currentObjectUrl = null;
  }
}

function createDownloadButton(label, blob, filename) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.addEventListener("click", () => {
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 200);
  });
  return button;
}

async function unlock() {
  clearResult();
  if (!window.supabase) {
    setStatus("Supabase client not loaded.", "error");
    return;
  }

  const entryId = entryInput.value.trim();
  const keyValue = keyInput.value.trim();
  if (!entryId || !keyValue) {
    setStatus("Enter both the entry ID and security key.", "error");
    return;
  }

  if (
    config.supabaseUrl.includes("YOUR_SUPABASE_URL") ||
    config.supabaseAnonKey.includes("YOUR_SUPABASE_ANON_KEY")
  ) {
    setStatus("Viewer is not configured with Supabase credentials.", "error");
    return;
  }

  setStatus("Unlocking vault…");
  unlockButton.disabled = true;

  try {
    const keyBytes = base64ToBytes(keyValue);
    const client = supabase.createClient(
      config.supabaseUrl,
      config.supabaseAnonKey
    );

    const { data: entry, error } = await client
      .from("vault_entries")
      .select(
        "id,title,data_type,payload_encrypted,audio_file_path,audio_duration_seconds,status"
      )
      .eq("id", entryId)
      .maybeSingle();

    if (error || !entry) {
      throw new Error("Entry not found or unavailable.");
    }

    if (entry.status && entry.status !== "sent") {
      throw new Error("This message is not available yet.");
    }

    resultTitle.textContent = entry.title || "Untitled";

    if (entry.data_type === "audio") {
      if (!entry.audio_file_path) {
        throw new Error("Audio file is missing.");
      }
      const { data: audioBlob, error: audioError } = await client.storage
        .from(config.audioBucket)
        .download(entry.audio_file_path);

      if (audioError || !audioBlob) {
        throw new Error("Unable to download audio.");
      }

      const encryptedText = await audioBlob.text();
      const decryptedBytes = await decryptPayload(encryptedText, keyBytes);
      const audio = document.createElement("audio");
      audio.controls = true;
      const decryptedBlob = new Blob([decryptedBytes], { type: "audio/m4a" });
      currentObjectUrl = URL.createObjectURL(decryptedBlob);
      audio.src = currentObjectUrl;
      resultBody.appendChild(audio);

      resultActions.appendChild(
        createDownloadButton("Download audio", decryptedBlob, "afterword.m4a")
      );
    } else {
      const decryptedBytes = await decryptPayload(
        entry.payload_encrypted,
        keyBytes
      );
      const decoded = new TextDecoder().decode(decryptedBytes);
      const text = document.createElement("pre");
      text.textContent = decoded;
      resultBody.appendChild(text);

      const textBlob = new Blob([decoded], { type: "text/plain" });
      resultActions.appendChild(
        createDownloadButton("Download .txt", textBlob, "afterword.txt")
      );
    }

    resultEl.classList.remove("hidden");
    setStatus("Vault unlocked.", "success");
  } catch (error) {
    setStatus(error.message || "Unable to unlock vault.", "error");
  } finally {
    unlockButton.disabled = false;
  }
}

unlockButton.addEventListener("click", unlock);
