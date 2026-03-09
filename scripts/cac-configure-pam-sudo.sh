#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

CERTS_DIR="${SCRIPT_DIR}/../certs"

preflight_lockout_warning() {
  cat <<EOF >/dev/tty
⚠ WARNING: This script will modify ${COMMON_AUTH}.
  A misconfiguration can prevent login via sudo, SDDM, and SSH.
  Ensure you have an open root terminal or know how to access
  recovery mode before proceeding.
  Press ENTER to continue, or Ctrl-C to abort.
EOF

  # Read from /dev/tty so that pipes do not interfere.
  local _ack
  if ! read -r _ack < /dev/tty; then
    :
  fi
}

validate_sudo_pam_stack() {
  local sudo_pam="/etc/pam.d/sudo"

  if [[ -f "${sudo_pam}" ]]; then
    if grep -qE '@include[[:space:]]+common-auth' "${sudo_pam}"; then
      info "sudo PAM config '${sudo_pam}' includes 'common-auth'; CAC will be honored for sudo prompts."
    else
      warn "sudo PAM config '${sudo_pam}' does not include 'common-auth'."
      warn "You may need to adjust it manually so that the CAC-enabled common-auth stack is used."
    fi
  else
    warn "sudo PAM file '${sudo_pam}' not found; terminal CAC sudo may require manual PAM configuration."
  fi
}

main() {
  local dry_run_flag=0

  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run_flag=1
  fi

  require_root

  preflight_lockout_warning

  ensure_pam_dirs
  ensure_pam_pkcs11_config
  refresh_pam_pkcs11_cacerts_from_repo "${CERTS_DIR}"

  if (( dry_run_flag == 1 )); then
    enable_cac_in_common_auth --dry-run
  else
    enable_cac_in_common_auth
  fi

  validate_sudo_pam_stack
}

main "$@"

