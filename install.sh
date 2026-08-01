#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Yozgat (Crystal) Installer
#  Usage: curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-crystal/main/install.sh | sudo bash
# ─────────────────────────────────────────────

REPO="GroophyLifefor/yozgat-crystal"
ARCHIVE_NAME="yozgat-x86_64-linux-gnu.tar.gz"
INSTALL_BIN="/usr/local/bin/yozgat"
INSTALL_LIB="/usr/local/lib/yozgat"
LIBATA="$INSTALL_LIB/libata.so"
PUBLIC_DIR="$INSTALL_LIB/public"
SERVICE_FILE="/etc/systemd/system/yozgat.service"
ENV_DIR="/etc/yozgat"
ENV_FILE="$ENV_DIR/env"
VERSION_FILE="$ENV_DIR/version"
DATA_DIR="/var/lib/yozgat"
SERVICE_USER="yozgat"

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

generate_jwt_secret() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
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
  local redirect_url http_code
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

# ── Root check ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Use: sudo bash install.sh"
fi

# ── Dependency check ────────────────────────
for cmd in curl systemctl tar; do
  command -v "$cmd" &>/dev/null || error "'$cmd' is required but not installed."
done

# ── Fetch latest release tag ────────────────
info "Fetching latest release from GitHub..."
fetch_latest_release
info "Latest version: ${LATEST_TAG}"

# ── Download and extract release bundle ─────
info "Downloading release bundle..."
TMP_ARCHIVE=$(mktemp)
TMP_EXTRACT=$(mktemp -d)
trap 'rm -f "$TMP_ARCHIVE"; rm -rf "$TMP_EXTRACT"' EXIT

download_github_asset "$ASSET_API_URL" "$TMP_ARCHIVE" \
  || error "Download failed for ${ARCHIVE_NAME} in release ${LATEST_TAG}."
tar -xzf "$TMP_ARCHIVE" -C "$TMP_EXTRACT" || error "Failed to extract release bundle."

[[ -f "$TMP_EXTRACT/yozgat" ]] || error "Release bundle is missing the yozgat binary."
[[ -f "$TMP_EXTRACT/libata.so" ]] || error "Release bundle is missing libata.so."
[[ -d "$TMP_EXTRACT/public" ]] || error "Release bundle is missing the public directory."

# ── Install binary, native lib and public assets ─
info "Installing binary to $INSTALL_BIN..."
install -m 755 "$TMP_EXTRACT/yozgat" "$INSTALL_BIN"

info "Installing native library and public assets..."
mkdir -p "$INSTALL_LIB"
install -m 644 "$TMP_EXTRACT/libata.so" "$LIBATA"
rm -rf "$PUBLIC_DIR"
mkdir -p "$PUBLIC_DIR"
cp -a "$TMP_EXTRACT/public/." "$PUBLIC_DIR/"
chmod -R a+rX "$PUBLIC_DIR"

# ── Create system user ───────────────────────
if ! id "$SERVICE_USER" &>/dev/null; then
  info "Creating system user '$SERVICE_USER'..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

# ── Create directories ───────────────────────
mkdir -p "$ENV_DIR" "$DATA_DIR"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$DATA_DIR"
chmod 750 "$ENV_DIR"

# ── Write env file (only if it doesn't exist) ─
if [[ ! -f "$ENV_FILE" ]]; then
  JWT_SECRET=$(generate_jwt_secret)
  info "Creating environment file at $ENV_FILE..."
  cat > "$ENV_FILE" <<EOF
# Yozgat environment configuration
# Edit this file and run: sudo systemctl restart yozgat

PORT=6637
YOZGAT_DATA_DIR=$DATA_DIR
YOZGAT_PUBLIC_DIR=$PUBLIC_DIR
YOZGAT_JWT_SECRET=$JWT_SECRET
EOF
  chmod 640 "$ENV_FILE"
  chown root:"$SERVICE_USER" "$ENV_FILE"
else
  info "Environment file already exists at $ENV_FILE — skipping."
fi

# ── Write version file ───────────────────────
echo "$LATEST_TAG" > "$VERSION_FILE"

# ── Install systemd service ──────────────────
info "Installing systemd service..."
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Yozgat Service (Crystal)
Documentation=https://github.com/GroophyLifefor/yozgat-crystal
After=network.target

[Service]
Type=simple
User=yozgat
Group=yozgat

WorkingDirectory=/var/lib/yozgat
EnvironmentFile=/etc/yozgat/env
Environment=HOME=/var/lib/yozgat
Environment=LD_LIBRARY_PATH=/usr/local/lib/yozgat

ExecStart=/usr/local/bin/yozgat

Restart=on-failure
RestartSec=5s
TimeoutStartSec=30s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=yozgat

NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/lib/yozgat

[Install]
WantedBy=multi-user.target
EOF

# ── Reload & enable ──────────────────────────
systemctl daemon-reload
systemctl enable yozgat
systemctl start yozgat

success "✓ Yozgat ${LATEST_TAG} installed successfully!"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  1. Check status:            ${CYAN}sudo systemctl status yozgat${NC}"
echo -e "  2. View logs:               ${CYAN}sudo journalctl -u yozgat -f${NC}"
echo -e "  3. Open dashboard:          ${CYAN}http://<your-vps-ip>:6637${NC}"
echo -e "  4. Optional env edits:      ${CYAN}sudo nano $ENV_FILE${NC}"
echo ""
