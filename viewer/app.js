const config = window.AFTERWORD_VIEWER_CONFIG || {};
const audioBucket = config.audioBucket || "vault-audio";

let _supabaseClient = null;
function getClient() {
  if (_supabaseClient) return _supabaseClient;
  const url = config.supabaseUrl || "";
  const key = config.supabaseAnonKey || "";
  if (!url || !key || url.includes("YOUR_") || key.includes("YOUR_")) {
    return null;
  }
  _supabaseClient = supabase.createClient(url, key);
  return _supabaseClient;
}

const entryInput = document.getElementById("entry-id");
const keyInput = document.getElementById("security-key");
const unlockButton = document.getElementById("unlock");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const resultTitle = document.getElementById("result-title");
const resultBody = document.getElementById("result-body");
const resultActions = document.getElementById("result-actions");

let currentObjectUrl = null;
let lastSenderName = null;

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

function renderExpiredMessage(senderName) {
  resultTitle.textContent = "Message Unavailable";
  resultBody.innerHTML = "";
  resultActions.innerHTML = "";

  const intro = document.createElement("p");
  intro.textContent = "This secure transmission has expired.";

  const detail = document.createElement("p");
  const sender = senderName || "the sender";
  detail.textContent = `You are trying to access a secured message from ${sender}.`;

  const policy = document.createElement("p");
  policy.textContent =
    "To protect the sender's privacy and security, all data in this vault was configured to permanently auto-erase 30 days after delivery.";

  const finality = document.createElement("p");
  finality.textContent =
    "That time window has passed. In accordance with our time-locked security protocols, the encryption keys have been removed and the data has been permanently erased from our servers. It cannot be recovered by anyone, including our support team.";

  const rule = document.createElement("hr");

  resultBody.appendChild(intro);
  resultBody.appendChild(detail);
  resultBody.appendChild(policy);
  resultBody.appendChild(finality);
  resultBody.appendChild(rule);

  resultEl.classList.remove("hidden");
}

async function unlock() {
  clearResult();

  const entryId = entryInput.value.trim();
  const keyValue = keyInput.value.trim();

  if (!entryId) {
    setStatus("Please enter the Entry ID from your email.", "error");
    return;
  }

  const client = getClient();
  if (!client) {
    setStatus("This viewer is temporarily unavailable. Please try again later.", "error");
    return;
  }

  setStatus("Unlocking vault…");
  unlockButton.disabled = true;

  try {
    const { data: entryStatus, error: statusError } = await client.rpc(
      "viewer_entry_status",
      { entry_id: entryId }
    );

    if (statusError) {
      throw new Error("could_not_verify");
    }

    if (entryStatus?.state === "expired") {
      renderExpiredMessage(entryStatus.sender_name);
      setStatus("This transmission has expired.", "error");
      return;
    }

    if (entryStatus?.state === "unavailable") {
      throw new Error("unavailable");
    }

    lastSenderName = entryStatus?.sender_name || null;

    if (!keyValue) {
      setStatus("Please enter the Security Key from your email.", "error");
      return;
    }

    let keyBytes;
    try {
      keyBytes = base64ToBytes(keyValue);
    } catch (_) {
      throw new Error("invalid_key_format");
    }

    const { data: entry, error } = await client
      .from("vault_entries")
      .select(
        "id,title,data_type,payload_encrypted,audio_file_path,audio_duration_seconds,status"
      )
      .eq("id", entryId)
      .maybeSingle();

    if (error || !entry) {
      throw new Error("not_found");
    }

    if (entry.status && entry.status !== "sent") {
      throw new Error("unavailable");
    }

    resultTitle.textContent = entry.title || "Untitled";

    // Show sender metadata
    const metaEl = document.getElementById("result-meta");
    if (metaEl) {
      const parts = [];
      if (lastSenderName) parts.push(`From ${lastSenderName}`);
      if (entry.data_type === "audio") parts.push("Audio message");
      metaEl.textContent = parts.join(" · ") || "";
    }

    if (entry.data_type === "audio") {
      if (!entry.audio_file_path) {
        throw new Error("audio_missing");
      }
      const { data: audioBlob, error: audioError } = await client.storage
        .from(audioBucket)
        .download(entry.audio_file_path);

      if (audioError || !audioBlob) {
        throw new Error("audio_missing");
      }

      let decryptedBytes;
      try {
        const encryptedText = await audioBlob.text();
        decryptedBytes = await decryptPayload(encryptedText, keyBytes);
      } catch (_) {
        throw new Error("decrypt_failed");
      }

      const audio = document.createElement("audio");
      audio.controls = true;
      const decryptedBlob = new Blob([decryptedBytes], { type: "audio/m4a" });
      currentObjectUrl = URL.createObjectURL(decryptedBlob);
      audio.src = currentObjectUrl;
      resultBody.appendChild(audio);

      resultActions.appendChild(
        createDownloadButton("Download Audio", decryptedBlob, "afterword.m4a")
      );
    } else {
      let decoded;
      try {
        const decryptedBytes = await decryptPayload(
          entry.payload_encrypted,
          keyBytes
        );
        decoded = new TextDecoder().decode(decryptedBytes);
      } catch (_) {
        throw new Error("decrypt_failed");
      }

      const text = document.createElement("pre");
      text.textContent = decoded;
      resultBody.appendChild(text);

      const textBlob = new Blob([decoded], { type: "text/plain" });
      resultActions.appendChild(
        createDownloadButton("Download Text", textBlob, "afterword.txt")
      );
    }

    resultEl.classList.remove("hidden");
    setStatus("Vault unlocked.", "success");
    if (typeof window._orbPulseVerified === 'function') window._orbPulseVerified();
  } catch (error) {
    const msg = error.message || "";
    const friendly = {
      could_not_verify: "Unable to verify this entry. Please check the Entry ID and try again.",
      invalid_key_format: "The security key format is invalid. Please copy the full key from your email.",
      audio_missing: "The audio file for this entry could not be found.",
      decrypt_failed: "Unable to decrypt this message. Please make sure you entered the correct Security Key from your email.",
      not_found: "No entry found with this ID. Please check the Entry ID from your email.",
      unavailable: "This entry is not yet available for viewing. It may still be processing.",
    };
    setStatus(friendly[msg] || "Something went wrong. Please check your Entry ID and Security Key and try again.", "error");
  } finally {
    unlockButton.disabled = false;
  }
}

unlockButton.addEventListener("click", unlock);
entryInput.addEventListener("keydown", (e) => { if (e.key === "Enter") unlock(); });
keyInput.addEventListener("keydown", (e) => { if (e.key === "Enter") unlock(); });
