#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer shared helpers/constants from lib/common.sh when present.
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  . "${SCRIPT_DIR}/lib/common.sh"
fi

# Fallback logging helpers if lib/common.sh was not loaded.
if ! command -v info >/dev/null 2>&1; then
  info() {
    printf '[INFO] %s\n' "$*" >&2
  }
fi

if ! command -v warn >/dev/null 2>&1; then
  warn() {
    printf '[WARN] %s\n' "$*" >&2
  }
fi

if ! command -v error >/dev/null 2>&1; then
  error() {
    printf '[ERROR] %s\n' "$*" >&2
  }
fi

if ! command -v require_root >/dev/null 2>&1; then
  require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      error "This script must be run as root (use sudo)."
      exit 1
    fi
  }
fi

usage() {
  cat <<EOF
Usage:
  sudo ./setup-cac.sh
    Run full CAC setup end-to-end (middleware, PKI, PAM, browsers).

  sudo ./setup-cac.sh --map-user <linux-username>
    Map a CAC authentication certificate to a Linux user (digest_mapping).

  sudo ./setup-cac.sh --rollback-pam
    Restore PAM-related .cac.bak backups for common-auth and pam_pkcs11 files.
EOF
}

main() {
  # Backward-compatible argument handling (delegated to extracted scripts).
  case "${1:-}" in
    --rollback-pam)
      exec "${SCRIPT_DIR}/scripts/cac-rollback-pam.sh"
      ;;
    --map-user)
      if [[ -z "${2:-}" ]]; then
        error "Usage: $0 --map-user <linux-username>"
        exit 2
      fi
      exec "${SCRIPT_DIR}/scripts/cac-map-user.sh" "$2"
      ;;
    "" )
      ;;
    *)
      error "Unknown argument: ${1}"
      usage
      exit 2
      ;;
  esac

  require_root

  info "Starting full CAC setup (middleware, PKI, PAM, browsers)…"

  "${SCRIPT_DIR}/scripts/cac-install-middleware.sh"
  "${SCRIPT_DIR}/scripts/cac-update-dod-pki.sh"
  "${SCRIPT_DIR}/scripts/cac-configure-pam-sudo.sh"
  "${SCRIPT_DIR}/scripts/cac-configure-pam-sddm.sh"
  "${SCRIPT_DIR}/scripts/cac-configure-browser-firefox.sh"
  "${SCRIPT_DIR}/scripts/cac-configure-browser-chromium.sh"

  info "Full CAC setup complete."
  info "You can run './cac-setup' for individual options or './scripts/cac-diagnose.sh' to verify."
}

main "$@"

