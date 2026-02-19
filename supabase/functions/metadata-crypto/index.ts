const encoder = new TextEncoder();
const decoder = new TextDecoder();

export {};

declare const Deno: {
  env: {
    get(name: string): string | undefined;
  };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

function withCorsHeaders(headers: Headers) {
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Headers", "authorization, x-client-info, apikey, content-type");
  headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

const OUTBOUND_TIMEOUT_MS = 10_000;

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs = OUTBOUND_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function b64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function b64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function deriveServerKey(serverSecret: string): Promise<CryptoKey> {
  const secretBytes = encoder.encode(serverSecret);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    toArrayBuffer(secretBytes),
  );
  return crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

async function computeHmacBase64(message: string, keyBytes: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(keyBytes),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      toArrayBuffer(encoder.encode(message)),
    ),
  );
  return b64Encode(signature);
}

async function encryptBytes(plaintext: Uint8Array, key: CryptoKey): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: toArrayBuffer(nonce) },
      key,
      toArrayBuffer(plaintext),
    ),
  );
  const tagLength = 16;
  if (encrypted.length < tagLength) {
    throw new Error("Invalid ciphertext.");
  }
  const cipherText = encrypted.slice(0, encrypted.length - tagLength);
  const tag = encrypted.slice(encrypted.length - tagLength);
  return `${b64Encode(nonce)}.${b64Encode(cipherText)}.${b64Encode(tag)}`;
}

async function decryptBytes(encoded: string, key: CryptoKey): Promise<Uint8Array> {
  const parts = encoded.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid encrypted payload.");
  }
  const nonce = b64Decode(parts[0]);
  const cipherText = b64Decode(parts[1]);
  const tag = b64Decode(parts[2]);
  const combined = new Uint8Array(cipherText.length + tag.length);
  combined.set(cipherText, 0);
  combined.set(tag, cipherText.length);
  const clear = new Uint8Array(
    await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: toArrayBuffer(nonce) },
      key,
      toArrayBuffer(combined),
    ),
  );
  return clear;
}

async function getUserIdFromAuth(
  supabaseUrl: string,
  supabaseAnonKey: string,
  authHeader: string,
): Promise<string | null> {
  const response = await fetchWithTimeout(`${supabaseUrl}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: supabaseAnonKey,
      Authorization: authHeader,
    },
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json();
  if (data && typeof data.id === "string" && data.id.length > 0) {
    return data.id;
  }
  return null;
}

async function getProfileHmacKeyEncrypted(
  supabaseUrl: string,
  supabaseAnonKey: string,
  authHeader: string,
  userId: string,
): Promise<string | null> {
  const url = new URL(`${supabaseUrl}/rest/v1/profiles`);
  url.searchParams.set("id", `eq.${userId}`);
  url.searchParams.set("select", "hmac_key_encrypted");

  const response = await fetchWithTimeout(url.toString(), {
    method: "GET",
    headers: {
      apikey: supabaseAnonKey,
      Authorization: authHeader,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json();
  if (Array.isArray(data) && data.length > 0) {
    const first = data[0];
    if (first && typeof first.hmac_key_encrypted === "string" && first.hmac_key_encrypted) {
      return first.hmac_key_encrypted;
    }
  }
  return null;
}

async function verifyDecryptProof(authHeader: string, ciphertext: string, proofB64: string): Promise<boolean> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!supabaseUrl || !supabaseAnonKey) {
    return false;
  }

  const userId = await getUserIdFromAuth(supabaseUrl, supabaseAnonKey, authHeader);
  if (!userId) {
    return false;
  }

  const hmacKeyEncrypted = await getProfileHmacKeyEncrypted(
    supabaseUrl,
    supabaseAnonKey,
    authHeader,
    userId,
  );
  if (!hmacKeyEncrypted) {
    return false;
  }

  const serverSecret = Deno.env.get("SERVER_SECRET") || "";
  if (!serverSecret) {
    return false;
  }
  const serverKey = await deriveServerKey(serverSecret);
  const clearHmacKeyBytes = await decryptBytes(String(hmacKeyEncrypted), serverKey);
  const expected = await computeHmacBase64(ciphertext, clearHmacKeyBytes);
  return expected === proofB64;
}

Deno.serve(async (req: Request) => {
  const headers = new Headers({ "Content-Type": "application/json" });
  withCorsHeaders(headers);

  if (req.method === "OPTIONS") {
    return new Response(null, { headers, status: 204 });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers,
      status: 405,
    });
  }

  const authHeader = req.headers.get("authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers,
      status: 401,
    });
  }

  const serverSecret = Deno.env.get("SERVER_SECRET") || "";
  if (!serverSecret) {
    return new Response(JSON.stringify({ error: "SERVER_SECRET not configured" }), {
      headers,
      status: 500,
    });
  }

  try {
    const body = await req.json();
    const op = String(body?.op || "");
    const key = await deriveServerKey(serverSecret);

    if (op === "encrypt_text") {
      const plaintext = String(body?.plaintext || "");
      const ciphertext = await encryptBytes(encoder.encode(plaintext), key);
      return new Response(JSON.stringify({ ciphertext }), { headers, status: 200 });
    }

    if (op === "decrypt_text") {
      const ciphertext = String(body?.ciphertext || "");
      const proof = String(body?.proof_b64 || "");
      const ok = await verifyDecryptProof(authHeader, ciphertext, proof);
      if (!ok) {
        return new Response(JSON.stringify({ error: "Forbidden" }), {
          headers,
          status: 403,
        });
      }
      const clear = await decryptBytes(ciphertext, key);
      return new Response(JSON.stringify({ plaintext: decoder.decode(clear) }), {
        headers,
        status: 200,
      });
    }

    if (op === "encrypt_bytes") {
      const bytesB64 = String(body?.bytes_b64 || "");
      const plaintextBytes = b64Decode(bytesB64);
      const ciphertext = await encryptBytes(plaintextBytes, key);
      return new Response(JSON.stringify({ ciphertext }), { headers, status: 200 });
    }

    if (op === "decrypt_bytes") {
      const ciphertext = String(body?.ciphertext || "");
      const proof = String(body?.proof_b64 || "");
      const ok = await verifyDecryptProof(authHeader, ciphertext, proof);
      if (!ok) {
        return new Response(JSON.stringify({ error: "Forbidden" }), {
          headers,
          status: 403,
        });
      }
      const clear = await decryptBytes(ciphertext, key);
      return new Response(JSON.stringify({ bytes_b64: b64Encode(clear) }), {
        headers,
        status: 200,
      });
    }

    return new Response(JSON.stringify({ error: "Invalid op" }), {
      headers,
      status: 400,
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: "Bad request" }), {
      headers,
      status: 400,
    });
  }
});
