#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Yozgat (Crystal) Uninstaller
#  Usage: sudo bash uninstall.sh
#  Usage (keep data): sudo bash uninstall.sh --keep-data
# ─────────────────────────────────────────────

INSTALL_BIN="/usr/local/bin/yozgat"
INSTALL_BIN_OLD="/usr/local/bin/yozgat.old"
INSTALL_LIB="/usr/local/lib/yozgat"
SERVICE_FILE="/etc/systemd/system/yozgat.service"
ENV_DIR="/etc/yozgat"
DATA_DIR="/var/lib/yozgat"
SERVICE_USER="yozgat"

KEEP_DATA=false
for arg in "$@"; do
  [[ "$arg" == "--keep-data" ]] && KEEP_DATA=true
done

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

# ── Root check ───────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Use: sudo bash uninstall.sh"
fi

echo ""
echo -e "${RED}  Yozgat Uninstaller${NC}"
echo -e "  This will remove the yozgat binary, native library, service, and configuration."
if [[ "$KEEP_DATA" == false ]]; then
  echo -e "  ${YELLOW}Data directory ($DATA_DIR) will also be removed.${NC}"
  echo -e "  To keep it, run: ${CYAN}sudo bash uninstall.sh --keep-data${NC}"
else
  echo -e "  ${GREEN}Data directory ($DATA_DIR) will be kept.${NC}"
fi
echo ""

if ! read_prompt -r -p "  Are you sure you want to uninstall? [y/N] " confirm; then
  error "Cannot prompt for confirmation. Pass input via tty."
fi
[[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Stop and disable service ─────────────────
if systemctl list-units --full --all | grep -q "^  yozgat.service"; then
  if systemctl is-active --quiet yozgat 2>/dev/null; then
    info "Stopping yozgat..."
    systemctl stop yozgat
  fi
  if systemctl is-enabled --quiet yozgat 2>/dev/null; then
    info "Disabling yozgat..."
    systemctl disable yozgat
  fi
fi

# ── Kill any lingering yozgat processes ───────
if pgrep -x yozgat &>/dev/null; then
  info "Waiting for yozgat process to stop..."
  pkill -x yozgat 2>/dev/null || true
  # Give it 5 seconds to exit gracefully
  for i in {1..5}; do
    pgrep -x yozgat &>/dev/null || break
    sleep 1
  done
  # Force kill if still running
  if pgrep -x yozgat &>/dev/null; then
    warn "Process did not stop gracefully, force killing..."
    pkill -9 -x yozgat 2>/dev/null || true
    sleep 1
  fi
fi

# ── Remove systemd unit file ─────────────────
if [[ -f "$SERVICE_FILE" ]]; then
  info "Removing $SERVICE_FILE..."
  rm -f "$SERVICE_FILE"
fi

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# ── Remove binaries ──────────────────────────
for bin in "$INSTALL_BIN" "$INSTALL_BIN_OLD"; do
  if [[ -f "$bin" ]]; then
    info "Removing $bin..."
    rm -f "$bin"
  fi
done

# ── Remove library/public ────────────────────
if [[ -d "$INSTALL_LIB" ]]; then
  info "Removing $INSTALL_LIB..."
  rm -rf "$INSTALL_LIB"
fi

# ── Remove config ────────────────────────────
if [[ -d "$ENV_DIR" ]]; then
  info "Removing $ENV_DIR (config & env)..."
  rm -rf "$ENV_DIR"
fi

# ── Remove data directory ────────────────────
if [[ "$KEEP_DATA" == false ]]; then
  if [[ -d "$DATA_DIR" ]]; then
    info "Removing $DATA_DIR (data)..."
    rm -rf "$DATA_DIR"
  fi
else
  warn "Keeping data directory: $DATA_DIR"
fi

# ── Remove system user ───────────────────────
if id "$SERVICE_USER" &>/dev/null; then
  info "Removing system user '$SERVICE_USER'..."
  userdel "$SERVICE_USER" 2>/dev/null || warn "Could not remove user '$SERVICE_USER' — remove manually with: sudo userdel $SERVICE_USER"
fi

echo ""
success "✓ Yozgat has been fully uninstalled."
if [[ "$KEEP_DATA" == true ]]; then
  echo -e "  ${YELLOW}Your data was kept at:${NC} $DATA_DIR"
fi
echo ""
