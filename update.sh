#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Yozgat (Crystal) Updater
#  Usage: sudo bash update.sh
#  Uses the version recorded at install time (/etc/yozgat/version) and rolls
#  back automatically if the new release fails its health check.
# ─────────────────────────────────────────────

REPO="GroophyLifefor/yozgat-mrt"
ARCHIVE_NAME="yozgat-x86_64-linux-gnu.tar.gz"
INSTALL_BIN="/usr/local/bin/yozgat"
INSTALL_BIN_OLD="/usr/local/bin/yozgat.old"
INSTALL_LIB="/usr/local/lib/yozgat"
LIBATA="$INSTALL_LIB/libata.so"
LIBATA_OLD="$INSTALL_LIB/libata.so.old"
PUBLIC_DIR="$INSTALL_LIB/public"
PUBLIC_DIR_OLD="$INSTALL_LIB/public.old"
ENV_DIR="/etc/yozgat"
ENV_FILE="$ENV_DIR/env"
VERSION_FILE="$ENV_DIR/version"
DATA_DIR="/var/lib/yozgat"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[yozgat]${NC} $*"; }
success() { echo -e "${GREEN}[yozgat]${NC} $*"; }
warn()    { echo -e "${YELLOW}[yozgat]${NC} $*"; }
error()   { echo -e "${RED}[yozgat] ERROR:${NC} $*" >&2; exit 1; }

can_prompt_user() { [[ -r /dev/tty ]]; }

read_prompt() {
  if can_prompt_user; then
    read "$@" </dev/tty
  elif [[ -t 0 ]]; then
    read "$@"
  else
    return 1
  fi
}

prompt_newline() {
  if can_prompt_user; then
    echo "" >/dev/tty
  else
    echo ""
  fi
}

GITHUB_TOKEN="${YOZGAT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

prompt_github_pat() {
  if [[ -n "$GITHUB_TOKEN" ]]; then
    return 0
  fi

  echo ""
  warn "GitHub returned 404. The repository or release may be private."
  echo "Create a Personal Access Token with 'repo' scope:"
  echo "  https://github.com/settings/tokens"
  if ! read_prompt -r -s -p "GitHub PAT: " GITHUB_TOKEN; then
    error "GitHub returned 404. Set YOZGAT_GITHUB_TOKEN and re-run."
  fi
  prompt_newline
  [[ -n "$GITHUB_TOKEN" ]] || error "A GitHub PAT is required to continue."
}

github_api_get() {
  local url=$1
  local output=$2
  local -a args=(-sS -o "$output" -w "%{http_code}")

  if [[ -n "$GITHUB_TOKEN" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    args+=(-H "Accept: application/vnd.github+json")
    args+=(-H "X-GitHub-Api-Version: 2022-11-28")
  fi

  curl "${args[@]}" "$url"
}

extract_asset_api_url() {
  local file=$1
  local name=$2

  awk -v target="$name" '
    BEGIN { url="" }
    /"url": "https:\/\/api\.github\.com\/repos\/.*\/releases\/assets\// {
      line=$0
      sub(/.*"url": "/, "", line)
      sub(/".*/, "", line)
      url=line
    }
    /"name": "/ {
      line=$0
      sub(/.*"name": "/, "", line)
      sub(/".*/, "", line)
      if (line == target && url != "") {
        print url
        exit
      }
      url=""
    }
  ' "$file"
}

download_github_asset() {
  # GitHub API returns 302 to S3 — capture redirect, then download without auth.
  local asset_api_url=$1
  local output=$2
  local redirect_url="" http_code
  local -a auth_args=(-sS -w "%{redirect_url}" -o /dev/null)

  if [[ -n "$GITHUB_TOKEN" ]]; then
    auth_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    auth_args+=(-H "Accept: application/octet-stream")
    redirect_url=$(curl "${auth_args[@]}" "$asset_api_url")
  fi

  if [[ -n "$redirect_url" ]]; then
    http_code=$(curl -sS -L -w "%{http_code}" -o "$output" "$redirect_url")
  else
    http_code=$(curl -sS -L -w "%{http_code}" -o "$output" "$asset_api_url")
  fi

  [[ "$http_code" == "200" ]] || return 1
}

fetch_latest_release() {
  local api_url="https://api.github.com/repos/${REPO}/releases/latest"
  local response_file
  response_file=$(mktemp)

  local http_code prompted=false
  while true; do
    http_code=$(github_api_get "$api_url" "$response_file")
    case "$http_code" in
      200) break ;;
      404|401|403)
        [[ "$prompted" == true ]] && error "Authentication failed (HTTP $http_code). Check your PAT."
        GITHUB_TOKEN=""
        prompt_github_pat
        prompted=true
        ;;
      *) error "GitHub API failed (HTTP $http_code)" ;;
    esac
  done

  LATEST_TAG=$(grep '"tag_name"' "$response_file" | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
  [[ -n "$LATEST_TAG" ]] || error "Could not determine latest release."

  ASSET_API_URL=$(extract_asset_api_url "$response_file" "$ARCHIVE_NAME")
  rm -f "$response_file"
  [[ -n "$ASSET_API_URL" ]] || error "Release ${LATEST_TAG} has no asset named ${ARCHIVE_NAME}."
}

# Health check: probe the local HTTP endpoint until it answers, or time out.
wait_healthy() {
  local port=6637
  local attempts=30
  if [[ -f "$ENV_FILE" ]]; then
    local port_from_env
    port_from_env=$(grep '^PORT=' "$ENV_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    [[ -n "$port_from_env" ]] && port="$port_from_env"
  fi

  info "Waiting for yozgat to become healthy on port $port..."
  for i in $(seq 1 "$attempts"); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${port}/setup-status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# ── Root check ───────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Use: sudo bash update.sh"
fi

# ── Dependency check ─────────────────────────
for cmd in curl systemctl tar; do
  command -v "$cmd" &>/dev/null || error "'$cmd' is required but not installed."
done

# ── Fetch latest release tag ─────────────────
info "Fetching latest release from GitHub..."
fetch_latest_release

CURRENT_TAG=""
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_TAG=$(cat "$VERSION_FILE" | tr -d '[:space:]')
fi

if [[ -n "$CURRENT_TAG" && "$CURRENT_TAG" == "$LATEST_TAG" ]]; then
  success "Yozgat is already up to date (${CURRENT_TAG})."
  exit 0
fi

info "Current version: ${CURRENT_TAG:-not installed}"
info "New version:     ${LATEST_TAG}"

# ── Confirm update ───────────────────────────
if ! read_prompt -r -p "  Update now? [y/N] " confirm; then
  error "Cannot prompt for confirmation. Pass input via tty."
fi
[[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Download and extract ─────────────────────
info "Downloading release bundle..."
TMP_ARCHIVE=$(mktemp)
TMP_EXTRACT=$(mktemp -d)
trap 'rm -f "$TMP_ARCHIVE"; rm -rf "$TMP_EXTRACT"; rm -rf "$PUBLIC_DIR_OLD"' EXIT

download_github_asset "$ASSET_API_URL" "$TMP_ARCHIVE" \
  || error "Download failed for ${ARCHIVE_NAME} in release ${LATEST_TAG}."
tar -xzf "$TMP_ARCHIVE" -C "$TMP_EXTRACT" || error "Failed to extract release bundle."

[[ -f "$TMP_EXTRACT/yozgat" ]] || error "Release bundle is missing the yozgat binary."
[[ -f "$TMP_EXTRACT/libata.so" ]] || error "Release bundle is missing libata.so."
[[ -d "$TMP_EXTRACT/public" ]] || error "Release bundle is missing the public directory."

# ── Backup current install ───────────────────
info "Backing up current install..."
rm -f "$INSTALL_BIN_OLD"
rm -rf "$PUBLIC_DIR_OLD"
if [[ -f "$INSTALL_BIN" ]]; then
  cp -a "$INSTALL_BIN" "$INSTALL_BIN_OLD"
fi
if [[ -f "$LIBATA" ]]; then
  cp -a "$LIBATA" "$LIBATA_OLD"
fi
if [[ -d "$PUBLIC_DIR" ]]; then
  cp -a "$PUBLIC_DIR" "$PUBLIC_DIR_OLD"
fi

# ── Install new release ──────────────────────
info "Installing ${LATEST_TAG}..."
install -m 755 "$TMP_EXTRACT/yozgat" "$INSTALL_BIN"
install -m 644 "$TMP_EXTRACT/libata.so" "$LIBATA"
rm -rf "$PUBLIC_DIR"
mkdir -p "$PUBLIC_DIR"
cp -a "$TMP_EXTRACT/public/." "$PUBLIC_DIR/"
chmod -R a+rX "$PUBLIC_DIR"

systemctl restart yozgat

# ── Health check with rollback ───────────────
if wait_healthy; then
  echo "$LATEST_TAG" > "$VERSION_FILE"
  rm -f "$INSTALL_BIN_OLD"
  rm -f "$LIBATA_OLD"
  rm -rf "$PUBLIC_DIR_OLD"
  success "✓ Yozgat updated to ${LATEST_TAG}."
  echo ""
  echo -e "  View logs: ${CYAN}sudo journalctl -u yozgat -f${NC}"
  echo ""
else
  warn "Health check failed — rolling back to ${CURRENT_TAG:-previous}."
  systemctl stop yozgat 2>/dev/null || true

  if [[ -f "$INSTALL_BIN_OLD" ]]; then
    install -m 755 "$INSTALL_BIN_OLD" "$INSTALL_BIN"
  fi
  if [[ -f "$LIBATA_OLD" ]]; then
    install -m 644 "$LIBATA_OLD" "$LIBATA"
  fi
  if [[ -d "$PUBLIC_DIR_OLD" ]]; then
    rm -rf "$PUBLIC_DIR"
    mv "$PUBLIC_DIR_OLD" "$PUBLIC_DIR"
    chmod -R a+rX "$PUBLIC_DIR"
  fi

  systemctl start yozgat
  if wait_healthy; then
    if [[ -n "$CURRENT_TAG" ]]; then
      echo "$CURRENT_TAG" > "$VERSION_FILE"
    fi
    success "Rolled back successfully."
    warn "Keep an eye on the logs; ${LATEST_TAG} may have a startup issue."
    echo ""
    echo -e "  View logs: ${CYAN}sudo journalctl -u yozgat -f${NC}"
    echo ""
  else
    error "Rollback also failed — the service needs manual intervention."
  fi
fi
