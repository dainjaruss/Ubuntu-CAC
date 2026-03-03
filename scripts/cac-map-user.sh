#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

sha1_hexdot_from_pem() {
  local pem_path="$1"
  openssl x509 -in "${pem_path}" -noout -fingerprint -sha1 \
    | awk -F= '{print $2}' \
    | tr -d '\r\n'
}

extract_cac_auth_cert_pem() {
  local module="${OPENSC_MODULE}"

  if [[ ! -f "${module}" ]]; then
    error "OpenSC PKCS#11 module not found at '${module}'."
    return 1
  fi

  if ! command -v pkcs11-tool >/dev/null 2>&1; then
    error "pkcs11-tool not found (install opensc)."
    return 1
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    error "openssl not found; cannot export/parse certificate."
    return 1
  fi

  local list
  if ! list="$(pkcs11-tool --module "${module}" --list-objects --type cert 2>/dev/null)"; then
    error "Failed to list certificates via pkcs11-tool. Ensure your CAC is inserted and pcscd is running."
    return 1
  fi

  local ids=()
  local labels=()
  local current_label="" current_id=""

  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*label:[[:space:]]*(.*)$ ]]; then
      current_label="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[[:space:]]*ID:[[:space:]]*([0-9A-Fa-f]+)$ ]]; then
      current_id="${BASH_REMATCH[1]}"
      if [[ -n "${current_id}" ]]; then
        ids+=("${current_id}")
        labels+=("${current_label}")
        current_label=""
        current_id=""
      fi
    fi
  done <<< "${list}"

  if [[ "${#ids[@]}" -eq 0 ]]; then
    error "No certificate objects found on token."
    return 1
  fi

  local chosen_idx=0
  local i
  for i in "${!ids[@]}"; do
    if [[ "${labels[$i]}" =~ [Aa]uth ]]; then
      chosen_idx="${i}"
      break
    fi
  done

  info "Discovered the following certificates on the inserted token:"
  for i in "${!ids[@]}"; do
    printf '  [%d] ID=%s  label=%s\n' "$i" "${ids[$i]}" "${labels[$i]:-(no label)}"
  done

  printf 'Default selection is [%d] %s (first label containing "auth" if present).\n' \
    "${chosen_idx}" "${labels[$chosen_idx]:-(no label)}"
  printf 'Press ENTER to accept default, or type an index to use a different certificate: '

  local selection=""
  read -r selection || selection=""

  if [[ -n "${selection}" ]]; then
    if ! [[ "${selection}" =~ ^[0-9]+$ ]]; then
      error "Selection must be a numeric index."
      return 1
    fi
    if (( selection < 0 || selection >= ${#ids[@]} )); then
      error "Selection '${selection}' is out of range."
      return 1
    fi
    chosen_idx="${selection}"
  fi

  info "Using certificate [%d] ID=%s label=%s" \
    "${chosen_idx}" "${ids[$chosen_idx]}" "${labels[$chosen_idx]:-(no label)}"

  local cert_der cert_pem
  cert_der="$(mktemp --tmpdir cac-cert-XXXXXX.der)"
  cert_pem="$(mktemp --tmpdir cac-cert-XXXXXX.pem)"

  if ! pkcs11-tool --module "${module}" --read-object --type cert --id "${ids[$chosen_idx]}" -o "${cert_der}" >/dev/null 2>&1; then
    rm -f "${cert_der}" "${cert_pem}"
    error "Failed to export certificate (id=${ids[$chosen_idx]} label='${labels[$chosen_idx]}')."
    return 1
  fi

  if ! openssl x509 -inform DER -in "${cert_der}" -out "${cert_pem}" >/dev/null 2>&1; then
    rm -f "${cert_der}" "${cert_pem}"
    error "Failed to parse exported certificate as X.509."
    return 1
  fi

  rm -f "${cert_der}"
  printf '%s\n' "${cert_pem}"
}

ensure_username_mapping_digest() {
  local username="$1"
  local map_file="${PAM_PKCS11_DIGEST_MAP}"

  if [[ -z "${username}" ]]; then
    error "Username is required for mapping."
    return 1
  fi

  ensure_pam_pkcs11_config

  if [[ ! -f "${map_file}" ]]; then
    install -m 0644 -o root -g root /dev/null "${map_file}"
  fi

  local cert_pem
  cert_pem="$(extract_cac_auth_cert_pem)"

  local fp
  fp="$(sha1_hexdot_from_pem "${cert_pem}")"

  rm -f "${cert_pem}"

  if [[ -z "${fp}" ]]; then
    error "Unable to compute certificate SHA1 fingerprint."
    return 1
  fi

  if grep -qF "${fp} -> ${username}" "${map_file}"; then
    info "Digest mapping already exists in '${map_file}' for user '${username}'."
    return 0
  fi

  backup_file_once "${map_file}"

  info "Adding digest mapping for '${username}' to '${map_file}'."
  printf '%s -> %s\n' "${fp}" "${username}" >> "${map_file}"
}

main() {
  require_root

  local username="${1:-}"
  if [[ -z "${username}" ]]; then
    error "Usage: $0 <linux-username>"
    exit 2
  fi

  ensure_username_mapping_digest "${username}"
  info "Mapping complete. Try: sudo -k ls"
}

main "$@"

