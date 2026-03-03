#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

is_online_mode() {
  case "${CAC_ONLINE_MODE:-0}" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian)
        info "Detected supported distro: ${NAME:-$ID}"
        ;;
      *)
        warn "Detected unsupported distro ID='${ID:-unknown}'. This script is only tested on Ubuntu/Debian."
        ;;
    esac
  else
    warn "/etc/os-release not found; unable to detect distro."
  fi
}

apt_install_packages() {
  if is_online_mode; then
    info "Online mode enabled: updating APT package index…"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
  else
    info "Offline mode: skipping 'apt-get update' (expects APT indexes to be pre-seeded or provided by local mirrors)."
  fi

  info "Installing smartcard and CAC-related packages…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    pcscd \
    pcsc-tools \
    libccid \
    opensc \
    libnss3-tools \
    libpam-pkcs11
}

ensure_pcscd_running() {
  if command -v systemctl >/dev/null 2>&1; then
    info "Enabling and starting pcscd service…"
    systemctl enable pcscd >/dev/null 2>&1 || warn "Failed to enable pcscd service (continuing)."
    systemctl restart pcscd >/dev/null 2>&1 || warn "Failed to restart pcscd service; check logs."
  else
    warn "systemctl not found; ensure the pcscd smartcard daemon is running."
  fi
}

main() {
  require_root
  detect_distro
  apt_install_packages
  ensure_pcscd_running

  info "Middleware installation and pcscd configuration complete."
}

main "$@"

