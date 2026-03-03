#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

main() {
  require_root

  restore_backup_if_present "${COMMON_AUTH}"
  restore_backup_if_present "${PAM_PKCS11_CONF}"
  restore_backup_if_present "${PAM_PKCS11_DIGEST_MAP}"
  restore_backup_if_present "${PAM_PKCS11_SUBJECT_MAP}"

  info "Rollback complete. If you were having sudo issues, remove the CAC and try: sudo -k ls"
}

main "$@"

