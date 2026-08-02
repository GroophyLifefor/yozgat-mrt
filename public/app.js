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
