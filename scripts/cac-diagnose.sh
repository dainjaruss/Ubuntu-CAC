#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

is_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  return 1
}

print_header() {
  printf '══════════════════════════════════════════\n'
  printf ' CAC Diagnostics — %s\n' "$(date)"
  printf '══════════════════════════════════════════\n\n'
}

section_pcscd_service() {
  printf '[1] pcscd Service\n'

  if ! command -v systemctl >/dev/null 2>&1; then
    printf '  [SKIPPED] systemctl not available on this system.\n\n'
    return 0
  fi

  local state
  state="$(systemctl is-active pcscd 2>/dev/null || true)"

  case "${state}" in
    active)
      printf '  ✓ pcscd is active (running)\n\n'
      ;;
    inactive|failed|dead)
      printf '  ✗ pcscd is not active (state: %s)\n' "${state}"
      printf '    Check smartcard daemon status: sudo systemctl status pcscd\n\n'
      ;;
    *)
      printf '  ⚠ Unable to determine pcscd status (state: %s)\n' "${state:-unknown}"
      printf '    You can inspect manually with: systemctl status pcscd\n\n'
      ;;
  esac
}

section_smartcard_readers() {
  printf '[2] Smartcard Readers\n'

  if ! command -v pcsc_scan >/dev/null 2>&1; then
    printf '  [SKIPPED] pcsc_scan (pcsc-tools) is not installed.\n'
    printf '    Install pcsc-tools to run interactive smartcard diagnostics.\n\n'
    return 0
  fi

  local output
  # pcsc_scan -r lists readers and exits quickly; avoid interactive mode.
  output="$(pcsc_scan -r 2>/dev/null || true)"

  if [[ -z "${output}" ]]; then
    printf '  ⚠ No reader information returned. Ensure pcscd is running and a reader is connected.\n\n'
    return 0
  fi

  local readers=()
  local line
  while IFS= read -r line; do
    case "${line}" in
      Reader\ *|*" reader"*|*"Reader "*) readers+=("${line}") ;;
      *) ;;
    esac
  done <<< "${output}"

  if [[ "${#readers[@]}" -eq 0 ]]; then
    printf '  ⚠ No smartcard readers detected.\n'
    printf '    Verify the reader is connected and recognized by the OS.\n\n'
    return 0
  fi

  printf '  ✓ %d reader(s) detected:\n' "${#readers[@]}"
  for line in "${readers[@]}"; do
    printf '    %s\n' "${line}"
  done
  printf '\n'
}

section_cac_token_and_certs() {
  printf '[3] CAC Token & Certificates\n'

  if ! command -v pkcs11-tool >/dev/null 2>&1; then
    printf '  [SKIPPED] pkcs11-tool (from opensc) is not installed.\n'
    printf '    Install opensc to inspect token certificates.\n\n'
    return 0
  fi

  if [[ ! -f "${OPENSC_MODULE}" ]]; then
    printf '  ✗ OpenSC PKCS#11 module not found at "%s".\n' "${OPENSC_MODULE}"
    printf '    Adjust OPENSC_MODULE in lib/common.sh for your architecture.\n\n'
    return 0
  fi

  local token_info cert_output
  token_info="$(pkcs11-tool --module "${OPENSC_MODULE}" -L 2>&1 || true)"
  cert_output="$(pkcs11-tool --module "${OPENSC_MODULE}" --list-objects --type cert 2>&1 || true)"

  if printf '%s\n' "${token_info}" | grep -qi 'no slots'; then
    printf '  ⚠ No token detected. Insert your CAC and ensure the reader is working.\n\n'
    return 0
  fi

  if ! printf '%s\n' "${token_info}" | grep -qi 'token'; then
    printf '  ⚠ Unable to detect a token via pkcs11-tool.\n'
    printf '    Raw output:\n'
    printf '      %s\n\n' "$(printf '%s' "${token_info}" | head -n 3)"
    return 0
  fi

  printf '  ✓ Token detected via pkcs11-tool.\n'

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
  done <<< "${cert_output}"

  if [[ "${#ids[@]}" -eq 0 ]]; then
    printf '  ⚠ No certificate objects found on token.\n\n'
    return 0
  fi

  printf '    Certificates on token:\n'
  local i
  for i in "${!ids[@]}"; do
    printf '      ID=%s  %s\n' "${ids[$i]}" "${labels[$i]:-(no label)}"
  done
  printf '\n'
}

section_dod_ca_trust_stores() {
  printf '[4] DoD CA Trust Stores\n'

  # pam_pkcs11 cacerts directory
  if [[ -d "${PAM_PKCS11_CACERTS_DIR}" ]]; then
    local cacerts_glob
    local cacert_count hash_link_count

    cacerts_glob="${PAM_PKCS11_CACERTS_DIR}"/*.crt
    if compgen -G "${cacerts_glob}" >/dev/null 2>&1; then
      # Use an array to count matches safely.
      # shellcheck disable=SC2206
      local cacerts=( ${cacerts_glob} )
      cacert_count="${#cacerts[@]}"
    else
      cacert_count=0
    fi

    hash_link_count="$(find "${PAM_PKCS11_CACERTS_DIR}" -maxdepth 1 -type l 2>/dev/null | wc -l || true)"

    printf '  ✓ pam_pkcs11 cacerts: %s certificate(s), %s hash link(s)\n' "${cacert_count}" "${hash_link_count}"
  else
    printf '  ⚠ pam_pkcs11 cacerts directory not found at "%s".\n' "${PAM_PKCS11_CACERTS_DIR}"
  fi

  # System DoD CA directory
  if [[ -d "${DOD_CA_SYSTEM_DIR}" ]]; then
    local system_glob
    local system_count

    system_glob="${DOD_CA_SYSTEM_DIR}"/*.crt
    if compgen -G "${system_glob}" >/dev/null 2>&1; then
      # shellcheck disable=SC2206
      local system_certs=( ${system_glob} )
      system_count="${#system_certs[@]}"
    else
      system_count=0
    fi

    printf '  ✓ System trust store: %s certificate(s) in %s\n' "${system_count}" "${DOD_CA_SYSTEM_DIR}"
  else
    printf '  ⚠ System DoD CA directory not found at "%s".\n' "${DOD_CA_SYSTEM_DIR}"
  fi

  printf '\n'
}

section_user_mapping() {
  printf '[5] User Mapping\n'

  local show_map
  show_map() {
    local label="$1"
    local path="$2"

    if [[ ! -e "${path}" ]]; then
      printf '  %s: (missing)\n' "${label}"
      return 0
    fi

    if [[ ! -r "${path}" ]]; then
      printf '  %s: [SKIPPED - permission denied reading %s]\n' "${label}" "${path}"
      return 0
    fi

    if ! read -r _ < "${path}" 2>/dev/null; then
      printf '  %s: (empty)\n' "${label}"
      return 0
    fi

    local count
    count="$(wc -l < "${path}" 2>/dev/null || printf '0')"
    printf '  %s: %s entr%s\n' "${label}" "${count}" "$([[ "${count}" == "1" ]] && printf 'y' || printf 'ies')"

    # Show a few sample lines for context.
    local preview
    preview="$(head -n 3 "${path}" 2>/dev/null || true)"
    if [[ -n "${preview}" ]]; then
      printf '    Sample entries:\n'
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        printf '      %s\n' "${line}"
      done <<< "${preview}"
    fi
  }

  show_map "digest_mapping" "${PAM_PKCS11_DIGEST_MAP}"
  show_map "subject_mapping" "${PAM_PKCS11_SUBJECT_MAP}"

  printf '\n'
}

section_pam_stacks() {
  printf '[6] PAM Stacks\n'

  local describe_file
  describe_file() {
    local label="$1"
    local path="$2"

    if [[ ! -e "${path}" ]]; then
      printf '  %-11s: (missing: %s)\n' "${label}" "${path}"
      return 0
    fi

    if [[ ! -r "${path}" ]]; then
      printf '  %-11s: [SKIPPED - permission denied reading %s]\n' "${label}" "${path}"
      return 0
    fi

    local has_pkcs11="no"
    if grep -q 'pam_pkcs11\.so' "${path}" 2>/dev/null; then
      has_pkcs11="yes"
    fi

    if [[ "${label}" == "sudo" || "${label}" == "sddm" ]]; then
      local includes_common="no"
      if grep -q '@include[[:space:]]\+common-auth' "${path}" 2>/dev/null; then
        includes_common="yes"
      fi

      printf '  %-11s: pam_pkcs11.so: %s, @include common-auth: %s\n' \
        "${label}" \
        "$([[ "${has_pkcs11}" == "yes" ]] && printf 'present ✓' || printf 'absent ✗')" \
        "$([[ "${includes_common}" == "yes" ]] && printf 'present ✓' || printf 'absent ✗')"
    else
      printf '  %-11s: pam_pkcs11.so: %s\n' \
        "${label}" \
        "$([[ "${has_pkcs11}" == "yes" ]] && printf 'present ✓' || printf 'absent ✗')"
    fi
  }

  describe_file "common-auth" "${COMMON_AUTH}"
  describe_file "sudo" "/etc/pam.d/sudo"
  describe_file "sddm" "/etc/pam.d/sddm"

  printf '\n'
}

detect_firefox_variant_for_diagnostics() {
  # Echoes one of: snap, apt, none
  if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
    printf 'snap\n'
    return 0
  fi

  if command -v firefox >/dev/null 2>&1 || [[ -x /usr/bin/firefox ]]; then
    printf 'apt\n'
    return 0
  fi

  printf 'none\n'
}

section_firefox() {
  printf '[7] Firefox\n'

  local variant
  variant="$(detect_firefox_variant_for_diagnostics)"

  case "${variant}" in
    snap)
      printf '  Type: Snap\n'
      ;;
    apt)
      printf '  Type: APT (deb)\n'
      ;;
    none)
      printf '  Firefox not detected (Snap or APT).\n\n'
      return 0
      ;;
  esac

  if command -v snap >/dev/null 2>&1; then
    local connections
    connections="$(snap connections firefox 2>/dev/null || true)"
    if printf '%s\n' "${connections}" | grep -q 'firefox:pcscd'; then
      if printf '%s\n' "${connections}" | grep -q 'firefox:pcscd.*connected'; then
        printf '  pcscd interface: connected ✓\n'
      else
        printf '  pcscd interface: present but not connected ✗\n'
        printf '    You may need to run: sudo snap connect firefox:pcscd\n'
      fi
    else
      printf '  pcscd interface: not listed in snap connections (may still be implicit).\n'
    fi
  else
    printf '  [SKIPPED] snap command not available; cannot inspect firefox:pcscd interface.\n'
  fi

  # Firefox managed policies.
  local policies_json="/etc/firefox/policies/policies.json"
  if [[ -r "${policies_json}" ]]; then
    if grep -q 'OpenSC PKCS#11' "${policies_json}" 2>/dev/null; then
      printf '  policies.json: SecurityDevices.OpenSC configured ✓ (%s)\n' "${policies_json}"
    else
      printf '  policies.json: present but OpenSC PKCS#11 not configured ✗ (%s)\n' "${policies_json}"
    fi
  else
    printf '  policies.json: [SKIPPED - not found or not readable at %s]\n' "${policies_json}"
  fi

  printf '\n'
}

detect_diag_user() {
  if is_root && [[ -n "${SUDO_USER:-}" ]]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi

  printf '%s\n' "${USER:-root}"
}

user_home_dir() {
  local username="$1"
  local home

  if command -v getent >/dev/null 2>&1; then
    home="$(getent passwd "${username}" 2>/dev/null | cut -d: -f6 || true)"
    if [[ -n "${home}" ]]; then
      printf '%s\n' "${home}"
      return 0
    fi
  fi

  home="$(eval echo "~${username}" 2>/dev/null || true)"
  if [[ -n "${home}" && "${home}" != "~${username}" ]]; then
    printf '%s\n' "${home}"
    return 0
  fi

  printf '\n'
}

run_modutil_list() {
  local username="$1"
  local dbdir="$2"

  if ! command -v modutil >/dev/null 2>&1; then
    printf '[SKIPPED] modutil (libnss3-tools) not installed.\n'
    return 0
  fi

  if is_root && [[ -n "${SUDO_USER:-}" ]] && command -v sudo >/dev/null 2>&1; then
    sudo -u "${username}" modutil -dbdir "sql:${dbdir}" -list 2>/dev/null || true
  else
    modutil -dbdir "sql:${dbdir}" -list 2>/dev/null || true
  fi
}

section_chromium_chrome() {
  printf '[8] Chromium / Chrome\n'

  local diag_user
  diag_user="$(detect_diag_user)"

  local home
  home="$(user_home_dir "${diag_user}")"

  if [[ -z "${home}" ]]; then
    printf '  [SKIPPED] Unable to determine home directory for user "%s".\n\n' "${diag_user}"
    return 0
  fi

  printf '  Inspecting NSS DBs for user "%s" (home="%s").\n' "${diag_user}" "${home}"

  local db_paths=()
  db_paths+=("${home}/.pki/nssdb")
  db_paths+=("${home}/.config/chromium/Default")
  db_paths+=("${home}/.config/google-chrome/Default")

  local any_found=0
  local any_configured=0
  local db_path

  for db_path in "${db_paths[@]}"; do
    if [[ ! -d "${db_path}" ]]; then
      continue
    fi

    any_found=1
    printf '  DB: %s\n' "${db_path}"

    local list_output
    list_output="$(run_modutil_list "${diag_user}" "${db_path}")"

    if [[ -z "${list_output}" ]]; then
      printf '    ⚠ Unable to list modules (modutil output empty or permissions issue).\n'
      continue
    fi

    if printf '%s\n' "${list_output}" | grep -q 'OpenSC PKCS#11'; then
      printf '    ✓ OpenSC PKCS#11 module registered.\n'
      any_configured=1
    else
      printf '    ✗ OpenSC PKCS#11 module not found in this DB.\n'
    fi
  done

  if [[ "${any_found}" -eq 0 ]]; then
    printf '  [SKIPPED] No NSS DB directories found in common locations for user "%s".\n' "${diag_user}"
    printf '    Expected locations include ~/.pki/nssdb and Chromium/Chrome profile directories.\n'
  elif [[ "${any_configured}" -eq 0 ]]; then
    printf '  ⚠ No NSS DBs with OpenSC PKCS#11 registered were found.\n'
    printf '    Run scripts/cac-configure-browser-chromium.sh to configure browser PKCS#11 support.\n'
  fi

  printf '\n'
}

main() {
  print_header

  section_pcscd_service
  section_smartcard_readers
  section_cac_token_and_certs
  section_dod_ca_trust_stores
  section_user_mapping
  section_pam_stacks
  section_firefox
  section_chromium_chrome

  printf '══════════════════════════════════════════\n'
}

main "$@"

