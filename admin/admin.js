/* ============================================================================
   Afterword Admin Panel — Vanilla JS SPA
   All data access via SECURITY DEFINER RPCs over the Supabase anon key.
   ========================================================================== */

// ---------------------------------------------------------------------------
// 1. Supabase Client (lazy singleton — same pattern as the viewer)
// ---------------------------------------------------------------------------
const _cfg = window.AFTERWORD_ADMIN_CONFIG || {};

let _supabaseClient = null;

function getClient() {
  if (_supabaseClient) return _supabaseClient;
  const url = _cfg.supabaseUrl || "";
  const key = _cfg.supabaseAnonKey || "";
  if (!url || !key || url.includes("YOUR_") || key.includes("YOUR_")) {
    return null;
  }
  _supabaseClient = supabase.createClient(url, key);
  return _supabaseClient;
}

// ---------------------------------------------------------------------------
// 2. Utility helpers
// ---------------------------------------------------------------------------

function debounce(fn, ms) {
  let timer;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), ms);
  };
}

function timeAgo(date) {
  if (!date) return "-";
  const now = Date.now();
  const then = new Date(date).getTime();
  const diff = Math.max(0, now - then);
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return "Just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months}mo ago`;
  const years = Math.floor(months / 12);
  return `${years}y ago`;
}

function formatDate(date) {
  if (!date) return "-";
  return new Date(date).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function esc(str) {
  if (str == null) return "";
  const d = document.createElement("div");
  d.textContent = String(str);
  return d.innerHTML;
}

function showToast(message, type) {
  const container = document.getElementById("toast-container");
  const toast = document.createElement("div");
  toast.className = `toast${type ? " toast--" + type : ""}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.classList.add("removing");
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

function showModal(title, body, confirmText, onConfirm) {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "modal-overlay";
    overlay.innerHTML = `
      <div class="modal">
        <h3 class="modal-title">${esc(title)}</h3>
        <div class="modal-body">${body}</div>
        <div class="modal__actions">
          <button class="btn btn--ghost modal-cancel">Cancel</button>
          <button class="btn btn--danger modal-confirm">${esc(confirmText || "Confirm")}</button>
        </div>
      </div>`;
    document.body.appendChild(overlay);

    const close = (result) => {
      overlay.remove();
      resolve(result);
    };

    overlay.querySelector(".modal-cancel").addEventListener("click", () => close(false));
    overlay.querySelector(".modal-confirm").addEventListener("click", async () => {
      if (onConfirm) await onConfirm();
      close(true);
    });
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) close(false);
    });
  });
}

function fmtNum(n) {
  if (n == null) return "0";
  return Number(n).toLocaleString();
}

function pct(part, total) {
  if (!total) return "0%";
  return ((part / total) * 100).toFixed(1) + "%";
}

function ensureArray(val) {
  if (Array.isArray(val)) return val;
  if (typeof val === "string") { try { const p = JSON.parse(val); return Array.isArray(p) ? p : []; } catch { return []; } }
  return [];
}

// Encrypted / sensitive fields that must never be displayed
const HIDDEN_FIELDS = new Set([
  "payload_encrypted",
  "recipient_email_encrypted",
  "data_key_encrypted",
  "hmac_signature",
  "hmac_key_encrypted",
  "key_backup_encrypted",
  "fcm_token",
]);

// ---------------------------------------------------------------------------
// 3. Auth flow
// ---------------------------------------------------------------------------

const loginScreen = document.getElementById("login-screen");
const deniedScreen = document.getElementById("denied-screen");
const adminPanel = document.getElementById("admin-panel");
const loginForm = document.getElementById("login-screen");
const loginError = document.getElementById("login-status");
const userEmailDisplay = document.getElementById("admin-email");
const signOutBtn = document.getElementById("signout-btn");

let currentSession = null;
let currentUserEmail = null;

async function checkAdmin() {
  const client = getClient();
  if (!client) return false;
  try {
    const { data, error } = await client.rpc("admin_check");
    if (error) throw error;
    return data === true;
  } catch {
    return false;
  }
}

function showScreen(screen) {
  loginScreen.classList.add("hidden");
  deniedScreen.classList.add("hidden");
  adminPanel.classList.add("hidden");
  screen.classList.remove("hidden");
}

async function handleSession(session) {
  currentSession = session;
  if (!session) {
    showScreen(loginScreen);
    return;
  }
  currentUserEmail = session.user?.email || "";
  const isAdmin = await checkAdmin();
  if (isAdmin) {
    if (userEmailDisplay) userEmailDisplay.textContent = currentUserEmail;
    showScreen(adminPanel);
    switchTab("dashboard");
  } else {
    showScreen(deniedScreen);
  }
}

async function init() {
  const client = getClient();
  if (!client) {
    showToast("Missing Supabase configuration.", "error");
    return;
  }

  // Listen for auth changes (session expiry, sign-out from another tab, etc.)
  client.auth.onAuthStateChange((_event, session) => {
    handleSession(session);
  });

  const { data: { session } } = await client.auth.getSession();
  await handleSession(session);
}

const loginBtn = document.getElementById("login-btn");
if (loginBtn) {
  loginBtn.addEventListener("click", async (e) => {
    e.preventDefault();
    loginError.textContent = "";
    const email = document.getElementById("login-email").value.trim();
    const password = document.getElementById("login-password").value;
    if (!email || !password) {
      loginError.textContent = "Please enter email and password.";
      return;
    }
    const client = getClient();
    if (!client) return;
    try {
      const { error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      // onAuthStateChange will call handleSession
    } catch (err) {
      loginError.textContent = err.message || "Login failed.";
    }
  });
}

const googleBtn = document.getElementById("google-btn");
if (googleBtn) {
  googleBtn.addEventListener("click", async () => {
    const client = getClient();
    if (!client) return;
    try {
      const { error } = await client.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: window.location.origin },
      });
      if (error) throw error;
    } catch (err) {
      if (loginError) loginError.textContent = err.message || "Google sign-in failed.";
    }
  });
}

if (signOutBtn) {
  signOutBtn.addEventListener("click", async () => {
    const client = getClient();
    if (client) await client.auth.signOut();
    showScreen(loginScreen);
  });
}

const deniedSignOutBtn = document.getElementById("denied-signout");
if (deniedSignOutBtn) {
  deniedSignOutBtn.addEventListener("click", async () => {
    const client = getClient();
    if (client) await client.auth.signOut();
    showScreen(loginScreen);
  });
}

// ---------------------------------------------------------------------------
// 4. Tab system
// ---------------------------------------------------------------------------

const TAB_NAMES = ["dashboard", "users", "entries", "heartbeat", "settings"];

function switchTab(name) {
  TAB_NAMES.forEach((t) => {
    const btn = document.querySelector(`.tab[data-tab="${t}"]`);
    const pane = document.getElementById(`tab-${t}`);
    if (btn) btn.classList.toggle("active", t === name);
    if (pane) {
      if (t === name) {
        pane.classList.remove("hidden");
      } else {
        pane.classList.add("hidden");
      }
    }
  });
  loadTab(name);
}

document.querySelectorAll(".tab[data-tab]").forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

function loadTab(name) {
  switch (name) {
    case "dashboard":
      loadDashboard();
      break;
    case "users":
      loadUsers();
      break;
    case "entries":
      loadEntries();
      break;
    case "heartbeat":
      loadHeartbeat();
      break;
    case "settings":
      loadSettings();
      break;
  }
}

// ---------------------------------------------------------------------------
// 5. Dashboard tab
// ---------------------------------------------------------------------------

async function loadDashboard() {
  const container = document.getElementById("dashboard-content");
  container.innerHTML = '<div class="loading">Loading dashboard...</div>';
  const client = getClient();
  if (!client) return;
  try {
    const { data, error } = await client.rpc("admin_get_dashboard_stats");
    if (error) throw error;
    const s = data || {};
    container.innerHTML = `
      <div class="stat-grid">
        ${statCard("Total Users", s.total_users)}
        ${statCard("Active", s.active_users)}
        ${statCard("Inactive", s.inactive_users)}
        ${statCard("New Today", s.new_today)}
      </div>
      <div class="stat-grid">
        ${statCard("Free", s.sub_free, s.total_users)}
        ${statCard("Pro", s.sub_pro, s.total_users)}
        ${statCard("Lifetime", s.sub_lifetime, s.total_users)}
      </div>
      <div class="stat-grid">
        ${statCard("Total Entries", s.total_entries)}
        ${statCard("Active Entries", s.active_entries)}
        ${statCard("Sent Entries", s.sent_entries)}
        ${statCard("Sent Today", s.entries_sent_today)}
      </div>
      <div class="stat-grid">
        ${statCard("Text", s.entries_text)}
        ${statCard("Audio", s.entries_audio)}
        ${statCard("Recurring", s.entries_recurring)}
      </div>
      <div class="stat-grid">
        ${statCard("Vault Mode Users", s.vault_mode_users)}
        ${statCard("Scheduled Mode Users", s.scheduled_mode_users)}
        ${statCard("No Vault Activity", s.no_vault_activity, s.total_users)}
      </div>`;
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load dashboard.</div>';
    showToast(err.message || "Dashboard error", "error");
  }
}

function statCard(label, value, total) {
  const extra = total != null ? ` <span class="stat-pct">(${pct(value, total)})</span>` : "";
  return `<div class="stat-card"><div class="stat-value">${fmtNum(value)}${extra}</div><div class="stat-label">${esc(label)}</div></div>`;
}

// ---------------------------------------------------------------------------
// 6. Users tab
// ---------------------------------------------------------------------------

let usersPage = 1;
const USERS_PER_PAGE = 25;
let usersTotal = 0;

function usersFilters() {
  return {
    search: (document.getElementById("users-search") || {}).value || "",
    status: (document.getElementById("users-status") || {}).value || "all",
    subscription: (document.getElementById("users-subscription") || {}).value || "all",
  };
}

async function loadUsers(page) {
  if (page != null) usersPage = page;
  const container = document.getElementById("users-content");
  container.innerHTML = '<div class="loading">Loading users...</div>';
  const client = getClient();
  if (!client) return;
  const f = usersFilters();
  try {
    const { data, error } = await client.rpc("admin_list_users", {
      p_search: f.search || null,
      p_status: f.status === "all" ? null : f.status,
      p_subscription: f.subscription === "all" ? null : f.subscription,
      p_limit: USERS_PER_PAGE,
      p_offset: (usersPage - 1) * USERS_PER_PAGE,
    });
    if (error) throw error;
    const rows = data?.users || [];
    usersTotal = data?.total || 0;
    if (rows.length === 0) {
      container.innerHTML = '<div class="empty">No users found.</div>';
      return;
    }
    container.innerHTML = renderUsersTable(rows) + renderPagination(usersPage, usersTotal, USERS_PER_PAGE, "users");
    bindUsersEvents();
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load users.</div>';
    showToast(err.message || "Users error", "error");
  }
}

function statusBadge(status) {
  const map = { active: "badge--active", inactive: "badge--inactive", archived: "badge--archived" };
  return `<span class="badge ${map[status] || ""}">${esc(status)}</span>`;
}

function subBadge(sub) {
  const map = { free: "badge--free", pro: "badge--pro", lifetime: "badge--lifetime" };
  return `<span class="badge ${map[sub] || ""}">${esc(sub)}</span>`;
}

function timerDisplay(row) {
  if (row.timer_days == null) return "-";
  let out = `${row.timer_days}d`;
  if (row.last_check_in) {
    out += ` - checked in ${timeAgo(row.last_check_in)}`;
  }
  return out;
}

function renderUsersTable(rows) {
  return `
    <table class="data-table">
      <thead>
        <tr>
          <th>Email</th><th>Sender Name</th><th>Status</th><th>Subscription</th>
          <th>Mode</th><th>Entries</th><th>Timer</th><th>Last Check-in</th>
          <th>Joined</th><th>Actions</th>
        </tr>
      </thead>
      <tbody>
        ${rows.map((r) => `
          <tr class="user-row" data-id="${esc(r.id)}">
            <td>${esc(r.email)}</td>
            <td>${esc(r.sender_name)}</td>
            <td>${statusBadge(r.status)}</td>
            <td>${subBadge(r.subscription_status)}</td>
            <td>${esc(r.app_mode || "vault")}</td>
            <td>${fmtNum(r.total_entry_count)}</td>
            <td>${timerDisplay(r)}</td>
            <td title="${esc(formatDate(r.last_check_in))}">${timeAgo(r.last_check_in)}</td>
            <td title="${esc(formatDate(r.created_at))}">${timeAgo(r.created_at)}</td>
            <td class="actions-cell">
              ${r.status === "archived"
                ? `<button class="btn btn--sm action-unban" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Unban</button>`
                : `<button class="btn btn--sm btn--accent action-ban" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Ban</button>`
              }
              <button class="btn btn--sm btn--danger action-delete-user" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Delete</button>
            </td>
          </tr>`).join("")}
      </tbody>
    </table>`;
}

function bindUsersEvents() {
  // Row click -> detail view
  document.querySelectorAll(".user-row").forEach((row) => {
    row.addEventListener("click", (e) => {
      if (e.target.closest("button")) return;
      loadUserDetail(row.dataset.id);
    });
  });

  // Ban buttons
  document.querySelectorAll(".action-ban").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      const email = btn.dataset.email;
      const confirmed = await showModal(
        "Ban User",
        `<p>Are you sure you want to ban <strong>${esc(email)}</strong>?</p>`,
        "Ban"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_ban_user", { p_user_id: btn.dataset.id });
        if (error) throw error;
        showToast(`${email} has been banned.`, "success");
        loadUsers();
      } catch (err) {
        showToast(err.message || "Ban failed", "error");
      }
    });
  });

  // Unban buttons
  document.querySelectorAll(".action-unban").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      const email = btn.dataset.email;
      const confirmed = await showModal(
        "Unban User",
        `<p>Are you sure you want to unban <strong>${esc(email)}</strong>?</p>`,
        "Unban"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_unban_user", { p_user_id: btn.dataset.id });
        if (error) throw error;
        showToast(`${email} has been unbanned.`, "success");
        loadUsers();
      } catch (err) {
        showToast(err.message || "Unban failed", "error");
      }
    });
  });

  // Delete buttons
  document.querySelectorAll(".action-delete-user").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      const email = btn.dataset.email;
      const confirmed = await showModal(
        "Delete User",
        `<p>This will permanently delete <strong>${esc(email)}</strong> and ALL their data. This cannot be undone.</p>`,
        "Delete Forever"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_delete_user", { p_user_id: btn.dataset.id });
        if (error) throw error;
        showToast(`${email} has been deleted.`, "success");
        loadUsers();
      } catch (err) {
        showToast(err.message || "Delete failed", "error");
      }
    });
  });
}

// Users search & filter bindings
const usersSearch = document.getElementById("users-search");
if (usersSearch) {
  usersSearch.addEventListener("input", debounce(() => loadUsers(1), 300));
}
const usersStatusSelect = document.getElementById("users-status");
if (usersStatusSelect) {
  usersStatusSelect.addEventListener("change", () => loadUsers(1));
}
const usersSubSelect = document.getElementById("users-subscription");
if (usersSubSelect) {
  usersSubSelect.addEventListener("change", () => loadUsers(1));
}

// ---------------------------------------------------------------------------
// 6b. User detail view
// ---------------------------------------------------------------------------

async function loadUserDetail(userId) {
  const container = document.getElementById("users-content");
  container.innerHTML = '<div class="loading">Loading user detail...</div>';
  const client = getClient();
  if (!client) return;
  try {
    const { data, error } = await client.rpc("admin_get_user_detail", { p_user_id: userId });
    if (error) throw error;
    if (!data) {
      container.innerHTML = '<div class="empty">User not found.</div>';
      return;
    }
    container.innerHTML = renderUserDetail(data);
    document.getElementById("back-to-users")?.addEventListener("click", () => loadUsers());
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load user detail.</div>';
    showToast(err.message || "User detail error", "error");
  }
}

function renderUserDetail(d) {
  const profile = d.profile || {};
  const entries = (d.entries || []).filter((e) => filterSensitiveEntry(e));
  const devices = d.devices || [];
  const tombstones = d.tombstones || [];

  return `
    <button class="btn btn--ghost" id="back-to-users">&larr; Back to Users</button>
    <div class="detail-section">
      <h3>Profile</h3>
      <div class="detail-grid">
        ${detailField("Email", profile.email)}
        ${detailField("Sender Name", profile.sender_name)}
        ${detailField("Status", profile.status)}
        ${detailField("Subscription", profile.subscription_status)}
        ${detailField("App Mode", profile.app_mode || "vault")}
        ${detailField("Timer", `${profile.timer_days || "-"}d`)}
        ${detailField("Last Check-in", formatDate(profile.last_check_in))}
        ${detailField("Theme", profile.selected_theme || "default")}
        ${detailField("Soul Fire", profile.selected_soul_fire || "default")}
        ${detailField("Warning Sent", formatDate(profile.warning_sent_at))}
        ${detailField("Protocol Executed", formatDate(profile.protocol_executed_at))}
        ${detailField("Had Vault Activity", profile.had_vault_activity ? "Yes" : "No")}
        ${detailField("Created", formatDate(profile.created_at))}
        ${detailField("Updated", formatDate(profile.updated_at))}
      </div>
    </div>

    <div class="detail-section">
      <h3>Entries (${entries.length})</h3>
      ${entries.length > 0 ? `
        <table class="data-table">
          <thead><tr><th>Title</th><th>Type</th><th>Mode</th><th>Status</th><th>Action</th><th>Scheduled At</th><th>Sent At</th><th>Created At</th></tr></thead>
          <tbody>
            ${entries.map((e) => `
              <tr>
                <td>${esc(e.title)}</td>
                <td>${typeBadge(e.data_type)}</td>
                <td>${esc(e.entry_mode || "standard")}</td>
                <td>${statusBadge(e.status)}</td>
                <td>${esc(e.action_type)}</td>
                <td title="${esc(formatDate(e.scheduled_at))}">${timeAgo(e.scheduled_at)}</td>
                <td title="${esc(formatDate(e.sent_at))}">${timeAgo(e.sent_at)}</td>
                <td title="${esc(formatDate(e.created_at))}">${timeAgo(e.created_at)}</td>
              </tr>`).join("")}
          </tbody>
        </table>` : '<div class="empty">No entries.</div>'}
    </div>

    <div class="detail-section">
      <h3>Devices (${devices.length})</h3>
      ${devices.length > 0 ? `
        <table class="data-table">
          <thead><tr><th>Platform</th><th>Created</th><th>Updated</th></tr></thead>
          <tbody>
            ${devices.map((d) => `
              <tr>
                <td>${esc(d.platform || "unknown")}</td>
                <td>${formatDate(d.created_at)}</td>
                <td>${formatDate(d.updated_at)}</td>
              </tr>`).join("")}
          </tbody>
        </table>` : '<div class="empty">No devices.</div>'}
    </div>

    <div class="detail-section">
      <h3>Tombstones (${tombstones.length})</h3>
      ${tombstones.length > 0 ? `
        <table class="data-table">
          <thead><tr><th>Entry ID</th><th>Sender Name</th><th>Sent At</th><th>Expired At</th></tr></thead>
          <tbody>
            ${tombstones.map((t) => `
              <tr>
                <td>${esc(t.vault_entry_id)}</td>
                <td>${esc(t.sender_name)}</td>
                <td>${formatDate(t.sent_at)}</td>
                <td>${formatDate(t.expired_at)}</td>
              </tr>`).join("")}
          </tbody>
        </table>` : '<div class="empty">No tombstones.</div>'}
    </div>`;
}

function detailField(label, value) {
  return `<div class="detail-field"><span class="detail-label">${esc(label)}</span><span class="detail-value">${esc(value)}</span></div>`;
}

function filterSensitiveEntry(entry) {
  // Remove sensitive fields from entry objects before rendering
  HIDDEN_FIELDS.forEach((f) => delete entry[f]);
  return true;
}

function typeBadge(type) {
  const map = { text: "badge--free", audio: "badge--pro" };
  return `<span class="badge ${map[type] || ""}">${esc(type)}</span>`;
}

// ---------------------------------------------------------------------------
// 7. Entries tab
// ---------------------------------------------------------------------------

let entriesPage = 1;
const ENTRIES_PER_PAGE = 25;
let entriesTotal = 0;

function entriesFilters() {
  return {
    status: (document.getElementById("entries-status") || {}).value || "all",
    entry_mode: (document.getElementById("entries-mode") || {}).value || "all",
    data_type: (document.getElementById("entries-type") || {}).value || "all",
    action_type: (document.getElementById("entries-action") || {}).value || "all",
  };
}

async function loadEntries(page) {
  if (page != null) entriesPage = page;
  const container = document.getElementById("entries-content");
  container.innerHTML = '<div class="loading">Loading entries...</div>';
  const client = getClient();
  if (!client) return;
  const f = entriesFilters();
  try {
    const { data, error } = await client.rpc("admin_list_entries", {
      p_status: f.status === "all" ? null : f.status,
      p_entry_mode: f.entry_mode === "all" ? null : f.entry_mode,
      p_data_type: f.data_type === "all" ? null : f.data_type,
      p_action_type: f.action_type === "all" ? null : f.action_type,
      p_limit: ENTRIES_PER_PAGE,
      p_offset: (entriesPage - 1) * ENTRIES_PER_PAGE,
    });
    if (error) throw error;
    const rows = data?.entries || [];
    entriesTotal = data?.total || 0;
    if (rows.length === 0) {
      container.innerHTML = '<div class="empty">No entries found.</div>';
      return;
    }
    container.innerHTML = renderEntriesTable(rows) + renderPagination(entriesPage, entriesTotal, ENTRIES_PER_PAGE, "entries");
    bindEntriesEvents();
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load entries.</div>';
    showToast(err.message || "Entries error", "error");
  }
}

function renderEntriesTable(rows) {
  return `
    <table class="data-table">
      <thead>
        <tr>
          <th>Title</th><th>User Email</th><th>Type</th><th>Mode</th>
          <th>Status</th><th>Scheduled At</th><th>Sent At</th><th>Created At</th><th>Actions</th>
        </tr>
      </thead>
      <tbody>
        ${rows.map((r) => `
          <tr>
            <td>${esc(r.title)}</td>
            <td>${esc(r.user_email)}</td>
            <td>${typeBadge(r.data_type)}</td>
            <td>${esc(r.entry_mode || "standard")}</td>
            <td>${statusBadge(r.status)}</td>
            <td title="${esc(formatDate(r.scheduled_at))}">${timeAgo(r.scheduled_at)}</td>
            <td title="${esc(formatDate(r.sent_at))}">${timeAgo(r.sent_at)}</td>
            <td title="${esc(formatDate(r.created_at))}">${timeAgo(r.created_at)}</td>
            <td>
              <button class="btn btn--sm btn--danger action-delete-entry" data-id="${esc(r.id)}" data-title="${esc(r.title)}">Delete</button>
            </td>
          </tr>`).join("")}
      </tbody>
    </table>`;
}

function bindEntriesEvents() {
  document.querySelectorAll(".action-delete-entry").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const title = btn.dataset.title || "this entry";
      const confirmed = await showModal(
        "Delete Entry",
        `<p>Are you sure you want to permanently delete <strong>${esc(title)}</strong>?</p>`,
        "Delete"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_delete_entry", { p_entry_id: btn.dataset.id });
        if (error) throw error;
        showToast("Entry deleted.", "success");
        loadEntries();
      } catch (err) {
        showToast(err.message || "Delete failed", "error");
      }
    });
  });
}

// Entries filter bindings
["entries-status", "entries-mode", "entries-type", "entries-action"].forEach((id) => {
  const el = document.getElementById(id);
  if (el) el.addEventListener("change", () => loadEntries(1));
});

// ---------------------------------------------------------------------------
// 8. Heartbeat tab
// ---------------------------------------------------------------------------

let heartbeatPage = 1;
const HEARTBEAT_PER_PAGE = 20;
let heartbeatTotal = 0;

async function loadHeartbeat(page) {
  if (page != null) heartbeatPage = page;
  const container = document.getElementById("heartbeat-content");
  container.innerHTML = '<div class="loading">Loading heartbeat runs...</div>';
  const client = getClient();
  if (!client) return;
  try {
    const { data, error } = await client.rpc("admin_list_heartbeat_runs", {
      p_limit: HEARTBEAT_PER_PAGE,
      p_offset: (heartbeatPage - 1) * HEARTBEAT_PER_PAGE,
    });
    if (error) throw error;
    const rows = data?.runs || [];
    heartbeatTotal = data?.total || 0;
    if (rows.length === 0) {
      container.innerHTML = '<div class="empty">No heartbeat runs found.</div>';
      return;
    }
    container.innerHTML =
      `<div class="hb-toolbar"><button class="btn btn--sm btn--danger" id="clear-all-runs">Clear All</button></div>` +
      renderHeartbeatTimeline(rows) + renderPagination(heartbeatPage, heartbeatTotal, HEARTBEAT_PER_PAGE, "heartbeat");
    bindHeartbeatEvents();
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load heartbeat runs.</div>';
    showToast(err.message || "Heartbeat error", "error");
  }
}

function hbStatusDot(run) {
  const errors = ensureArray(run.errors);
  const warnings = ensureArray(run.warnings);
  if (errors.length > 0) return "error";
  if (warnings.length > 0) return "warn";
  return "ok";
}

function renderHeartbeatTimeline(rows) {
  return `<div class="hb-timeline">
    ${rows.map((r) => {
      const dot = hbStatusDot(r);
      const runtime = r.runtime_seconds != null ? `${Number(r.runtime_seconds).toFixed(1)}s` : "-";
      const errors = ensureArray(r.errors);
      const warnings = ensureArray(r.warnings);
      return `
        <div class="hb-card">
          <div class="hb-card__header">
            <span class="hb-dot hb-dot--${dot}"></span>
            <span title="${esc(formatDate(r.started_at))}">${timeAgo(r.started_at)} &middot; ${esc(formatDate(r.started_at))}</span>
            <span class="badge badge--free">${runtime}</span>
          </div>
          <div class="hb-metrics">
            ${hbMetric("Profiles", r.profiles_processed)}
            ${hbMetric("Entries Seen", r.entries_seen)}
            ${hbMetric("Emails Sent", r.emails_sent)}
            ${hbMetric("Emails Failed", r.emails_failed)}
            ${hbMetric("Pushes", r.pushes_sent)}
            ${hbMetric("Delivered", r.entries_delivered)}
            ${hbMetric("Destroyed", r.entries_destroyed)}
            ${hbMetric("Recurring", r.recurring_sent)}
            ${hbMetric("Scheduled", r.scheduled_delivered)}
            ${hbMetric("Cleanups", r.entries_cleaned_up)}
            ${hbMetric("Bots", r.bots_cleaned_up)}
            ${hbMetric("Downgrades", r.downgrades_processed)}
          </div>
          ${errors.length > 0 ? `
            <details class="hb-expandable hb-errors">
              <summary>${errors.length} error${errors.length !== 1 ? "s" : ""}</summary>
              <ul>${errors.map((e) => `<li><span class="hb-err-ts">${esc(e.timestamp || "")}</span> ${esc(e.message || e)}</li>`).join("")}</ul>
            </details>` : ""}
          ${warnings.length > 0 ? `
            <details class="hb-expandable hb-warnings">
              <summary>${warnings.length} warning${warnings.length !== 1 ? "s" : ""}</summary>
              <ul>${warnings.map((w) => `<li><span class="hb-warn-ts">${esc(w.timestamp || "")}</span> ${esc(w.message || w)}</li>`).join("")}</ul>
            </details>` : ""}
          ${r.stdout_log ? `
            <details class="hb-expandable hb-log">
              <summary>Full Log</summary>
              <pre class="hb-log-pre">${esc(r.stdout_log)}</pre>
            </details>` : ""}
          <div class="hb-card__actions">
            <button class="btn btn--sm btn--danger action-delete-run" data-id="${esc(r.id)}">Delete</button>
          </div>
        </div>`;
    }).join("")}
  </div>`;
}

function hbMetric(label, value) {
  return `<div class="hb-metric"><span class="hb-metric__value">${fmtNum(value)}</span><span class="hb-metric__label">${esc(label)}</span></div>`;
}

function bindHeartbeatEvents() {
  // Delete single run
  document.querySelectorAll(".action-delete-run").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const confirmed = await showModal(
        "Delete Run",
        "<p>Delete this heartbeat run log?</p>",
        "Delete"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_delete_heartbeat_run", { p_run_id: btn.dataset.id });
        if (error) throw error;
        showToast("Run deleted.", "success");
        loadHeartbeat();
      } catch (err) {
        showToast(err.message || "Delete failed", "error");
      }
    });
  });

  // Clear all runs
  const clearBtn = document.getElementById("clear-all-runs");
  if (clearBtn) {
    clearBtn.addEventListener("click", async () => {
      const confirmed = await showModal(
        "Clear All Runs",
        "<p>Delete <strong>all</strong> heartbeat run logs? This cannot be undone.</p>",
        "Clear All"
      );
      if (!confirmed) return;
      try {
        const { data, error } = await getClient().rpc("admin_clear_heartbeat_runs");
        if (error) throw error;
        showToast(`${data} run(s) deleted.`, "success");
        loadHeartbeat();
      } catch (err) {
        showToast(err.message || "Clear failed", "error");
      }
    });
  }
}

// ---------------------------------------------------------------------------
// 9. Settings tab
// ---------------------------------------------------------------------------

async function loadSettings() {
  const container = document.getElementById("settings-content");
  container.innerHTML = '<div class="loading">Loading settings...</div>';
  const client = getClient();
  if (!client) return;
  try {
    const { data, error } = await client.rpc("admin_list_admins");
    if (error) throw error;
    const admins = data || [];
    container.innerHTML = renderSettings(admins);
    bindSettingsEvents(admins);
  } catch (err) {
    container.innerHTML = '<div class="empty">Failed to load settings.</div>';
    showToast(err.message || "Settings error", "error");
  }
}

function renderSettings(admins) {
  return `
    <div class="settings-section">
      <h3>Admin Users</h3>
      <table class="data-table">
        <thead><tr><th>Email</th><th>Added</th><th>Actions</th></tr></thead>
        <tbody>
          ${admins.map((a) => `
            <tr>
              <td>${esc(a.email)}</td>
              <td>${formatDate(a.created_at || a.added_at)}</td>
              <td>
                ${a.email === currentUserEmail
                  ? '<span class="badge muted">You</span>'
                  : `<button class="btn btn--sm btn--danger action-remove-admin" data-userid="${esc(a.user_id)}" data-email="${esc(a.email)}">Remove</button>`}
              </td>
            </tr>`).join("")}
        </tbody>
      </table>
      <div class="add-admin-form">
        <input type="email" id="new-admin-email" placeholder="Email address" class="input" />
        <button class="btn btn--accent" id="add-admin-btn">Add Admin</button>
      </div>
    </div>`;
}

function bindSettingsEvents() {
  // Remove admin buttons
  document.querySelectorAll(".action-remove-admin").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const email = btn.dataset.email;
      const confirmed = await showModal(
        "Remove Admin",
        `<p>Remove <strong>${esc(email)}</strong> from admins?</p>`,
        "Remove"
      );
      if (!confirmed) return;
      try {
        const { error } = await getClient().rpc("admin_remove_admin", { p_user_id: btn.dataset.userid });
        if (error) throw error;
        showToast(`${email} removed from admins.`, "success");
        loadSettings();
      } catch (err) {
        showToast(err.message || "Remove failed", "error");
      }
    });
  });

  // Add admin
  const addBtn = document.getElementById("add-admin-btn");
  const emailInput = document.getElementById("new-admin-email");
  if (addBtn && emailInput) {
    addBtn.addEventListener("click", async () => {
      const email = emailInput.value.trim();
      if (!email) {
        showToast("Please enter an email address.", "error");
        return;
      }
      try {
        const { error } = await getClient().rpc("admin_add_admin", { p_email: email });
        if (error) throw error;
        showToast(`${email} added as admin.`, "success");
        emailInput.value = "";
        loadSettings();
      } catch (err) {
        showToast(err.message || "Add failed", "error");
      }
    });
    emailInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") addBtn.click();
    });
  }
}

// ---------------------------------------------------------------------------
// 10. Shared pagination renderer
// ---------------------------------------------------------------------------

function renderPagination(currentPage, total, perPage, scope) {
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  return `
    <div class="pagination" data-scope="${scope}">
      <button class="page-btn page-prev" ${currentPage <= 1 ? "disabled" : ""}>Prev</button>
      <span class="page-info">Page ${currentPage} of ${fmtNum(totalPages)}</span>
      <button class="page-btn page-next" ${currentPage >= totalPages ? "disabled" : ""}>Next</button>
    </div>`;
}

document.addEventListener("click", (e) => {
  const prev = e.target.closest(".page-prev");
  const next = e.target.closest(".page-next");
  if (!prev && !next) return;
  const pagination = e.target.closest(".pagination");
  if (!pagination) return;
  const scope = pagination.dataset.scope;
  const delta = prev ? -1 : 1;
  switch (scope) {
    case "users":
      loadUsers(usersPage + delta);
      break;
    case "entries":
      loadEntries(entriesPage + delta);
      break;
    case "heartbeat":
      loadHeartbeat(heartbeatPage + delta);
      break;
  }
});

// ---------------------------------------------------------------------------
// 11. Boot
// ---------------------------------------------------------------------------

init();
