// Shared client helpers for the Yozgat dashboard.
const TOKEN_KEY = "yozgat_token";

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function storeToken(token) {
  localStorage.setItem(TOKEN_KEY, token);
}

function clearToken() {
  localStorage.removeItem(TOKEN_KEY);
}

function logout() {
  clearToken();
  location.href = "/login.html";
}

async function api(path, options = {}) {
  const headers = Object.assign({ "Content-Type": "application/json" }, options.headers || {});
  const token = getToken();
  if (token) headers["Authorization"] = "Bearer " + token;
  return fetch(path, Object.assign({}, options, { headers }));
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
