// Shared client helpers for the Yozgat dashboard.
const ACCESS_TOKEN_KEY = "yozgat_access_token";
const REFRESH_TOKEN_KEY = "yozgat_refresh_token";

function getAccessToken() {
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

function getRefreshToken() {
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

function storeSession(data) {
  localStorage.setItem(ACCESS_TOKEN_KEY, data.accessToken);
  localStorage.setItem(REFRESH_TOKEN_KEY, data.refreshToken);
}

function clearToken() {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

async function logout() {
  const refreshToken = getRefreshToken();
  if (refreshToken) {
    try {
      await api("/auth/logout", {
        method: "POST",
        body: JSON.stringify({ refreshToken }),
      });
    } catch {
      // best-effort revoke
    }
  }
  clearToken();
  location.href = "/login.html";
}

async function refreshAccessToken() {
  const refreshToken = getRefreshToken();
  if (!refreshToken) return null;

  const res = await fetch("/auth/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken }),
  });
  const data = await parseJson(res);
  if (!res.ok || !data || !data.accessToken) return null;
  storeSession(data);
  return data.accessToken;
}

async function api(path, options = {}) {
  const headers = Object.assign({ "Content-Type": "application/json" }, options.headers || {});
  const token = getAccessToken();
  if (token) headers["Authorization"] = "Bearer " + token;

  let res = await fetch(path, Object.assign({}, options, { headers }));

  if (res.status === 401 && getRefreshToken() && !options._retried) {
    const newToken = await refreshAccessToken();
    if (newToken) {
      headers["Authorization"] = "Bearer " + newToken;
      res = await fetch(path, Object.assign({}, options, { headers, _retried: true }));
    }
  }

  return res;
}

function showError(message) {
  const el = document.getElementById("error");
  if (!el) return;
  el.textContent = message;
  el.classList.add("visible");
}

function hideError() {
  const el = document.getElementById("error");
  if (el) el.classList.remove("visible");
}

async function parseJson(res) {
  try {
    return await res.json();
  } catch {
    return null;
  }
}

async function requireAuth() {
  if (!getAccessToken()) {
    location.href = "/login.html";
    return null;
  }
  const res = await api("/auth/me");
  const data = await parseJson(res);
  if (res.status === 401 || !data || !data.user) {
    clearToken();
    location.href = "/login.html";
    return null;
  }
  return data.user;
}

async function apiJson(path, options) {
  const res = await api(path, options);
  const data = await parseJson(res);
  return { res, data };
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatDate(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso.includes("T") ? iso : iso.replace(" ", "T") + "Z").toLocaleString();
  } catch {
    return iso;
  }
}

function statusClass(status) {
  const s = (status || "").toLowerCase();
  if (s === "running") return "status-ok";
  if (s === "failed" || s === "removing") return "status-bad";
  if (s === "deploying" || s === "pending" || s === "cloning" || s === "starting" || s === "building") {
    return "status-warn";
  }
  return "status-muted";
}

function projectTypeLabel(t) {
  if (t === "static") return "Static";
  if (t === "dockerfile") return "Dockerfile";
  if (t === "dockercompose") return "Compose";
  return t || "—";
}

function queryParam(name) {
  return new URLSearchParams(location.search).get(name);
}

// Fills the app-shell sidebar footer (user email + sign out).
function mountShell(user) {
  const userEl = document.getElementById("sidebar-user");
  if (userEl && user) userEl.textContent = user.email;
  const logoutBtn = document.getElementById("logout");
  if (logoutBtn) logoutBtn.addEventListener("click", logout);
}

async function copyText(text, button) {
  if (!text) return false;
  try {
    await navigator.clipboard.writeText(text);
    if (button) {
      const prev = button.textContent;
      button.textContent = "Copied";
      setTimeout(() => {
        button.textContent = prev;
      }, 1500);
    }
    return true;
  } catch {
    return false;
  }
}
