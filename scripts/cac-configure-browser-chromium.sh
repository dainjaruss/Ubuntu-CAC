#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

detect_browser_user() {
  detect_sudo_user
}

user_home_dir() {
  local username="$1"
  local home

  if home="$(getent passwd "${username}" 2>/dev/null | cut -d: -f6)"; then
    if [[ -n "${home}" ]]; then
      printf '%s\n' "${home}"
      return 0
    fi
  fi

  # Fallback to shell expansion if getent is unavailable or incomplete.
  home="$(eval echo "~${username}")" || true
  if [[ -n "${home}" && "${home}" != "~${username}" ]]; then
    printf '%s\n' "${home}"
    return 0
  fi

  error "Unable to determine home directory for user '${username}'."
  return 1
}

configure_nss_db() {
  local username="$1"
  local db_path="$2"

  if [[ -z "${db_path}" ]]; then
    return 0
  fi

  info "Configuring NSS DB at '${db_path}' for user '${username}'."

  run_as_user "${username}" mkdir -p "${db_path}"

  # Initialize the NSS DB if needed. Non-zero exit is acceptable if the DB already exists.
  if ! run_as_user "${username}" certutil -N -d "sql:${db_path}" --empty-password >/dev/null 2>&1; then
    info "NSS DB at '${db_path}' appears to be already initialized (certutil -N returned non-zero). Continuing."
  fi

  # Check whether the OpenSC module is already registered.
  local list_output
  if list_output="$(run_as_user "${username}" modutil -dbdir "sql:${db_path}" -list 2>/dev/null)"; then
    if grep -q "OpenSC PKCS#11" <<< "${list_output}"; then
      info "OpenSC PKCS#11 module is already present in NSS DB '${db_path}'."
      return 0
    fi
  fi

  info "Adding OpenSC PKCS#11 module to NSS DB '${db_path}'."
  if ! run_as_user "${username}" modutil -dbdir "sql:${db_path}" \
    -add "OpenSC PKCS#11" \
    -libfile "${OPENSC_MODULE}" \
    -force >/dev/null 2>&1; then
    warn "Failed to add OpenSC PKCS#11 module to NSS DB '${db_path}'."
    return 1
  fi
}

detect_chromium_binaries() {
  local found=0

  if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
    info "Detected Chromium browser installation."
    found=1
  fi

  if command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    info "Detected Google Chrome installation."
    found=1
  fi

  if (( found == 0 )); then
    warn "No Chromium/Chrome binaries detected in PATH. NSS DBs will still be configured if paths exist."
  fi
}

main() {
  require_root

  if ! command -v modutil >/dev/null 2>&1 || ! command -v certutil >/dev/null 2>&1; then
    error "modutil/certutil (libnss3-tools) not found. Ensure libnss3-tools is installed via APT."
    exit 1
  fi

  if [[ -z "${OPENSC_MODULE:-}" ]]; then
    error "OPENSC_MODULE is not set. It should point to the OpenSC PKCS#11 library (e.g., /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so)."
    error "Set OPENSC_MODULE appropriately (or adjust lib/common.sh defaults) before running this script."
    exit 1
  fi

  if [[ ! -f "${OPENSC_MODULE}" ]]; then
    error "OPENSC_MODULE='${OPENSC_MODULE}' does not point to an existing file."
    error "Verify that OpenSC is installed and that OPENSC_MODULE is set to the correct pkcs11 library path, then re-run this script."
    exit 1
  fi

  local browser_user
  browser_user="$(detect_browser_user)"

  local home
  home="$(user_home_dir "${browser_user}")"

  info "Configuring Chromium/Chrome PKCS#11 support for user '${browser_user}' (home='${home}')."

  detect_chromium_binaries

  local db_paths=()
  # Primary per-user NSS DB.
  db_paths+=("${home}/.pki/nssdb")

  # Google Chrome profiles (Default and Profile*).
  local chrome_base="${home}/.config/google-chrome"
  if [[ -d "${chrome_base}" ]]; then
    if [[ -d "${chrome_base}/Default" ]]; then
      db_paths+=("${chrome_base}/Default")
    fi
    local p
    for p in "${chrome_base}"/Profile*; do
      if [[ -d "${p}" ]]; then
        db_paths+=("${p}")
      fi
    done
  fi

  # Chromium profiles (Default and Profile*).
  local chromium_base="${home}/.config/chromium"
  if [[ -d "${chromium_base}" ]]; then
    if [[ -d "${chromium_base}/Default" ]]; then
      db_paths+=("${chromium_base}/Default")
    fi
    local q
    for q in "${chromium_base}"/Profile*; do
      if [[ -d "${q}" ]]; then
        db_paths+=("${q}")
      fi
    done
  fi

  local configured_any=0
  local db_path
  for db_path in "${db_paths[@]}"; do
    if configure_nss_db "${browser_user}" "${db_path}"; then
      configured_any=1
    fi
  done

  if (( configured_any == 0 )); then
    warn "No NSS databases were successfully configured. Verify user home and browser profiles, then re-run this script."
  else
    info "Chromium/Chrome PKCS#11 configuration step complete."
    info "Restart any running Chromium/Chrome instances and test a CAC-protected site."
  fi
}

main "$@"

