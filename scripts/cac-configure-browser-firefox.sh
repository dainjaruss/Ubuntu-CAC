#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

firefox_is_running() {
  if pgrep -x firefox >/dev/null 2>&1 || pgrep -f 'firefox' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

detect_firefox_variant() {
  # Sets global FIREFOX_VARIANT to one of: snap, apt, none
  FIREFOX_VARIANT="none"

  if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
    FIREFOX_VARIANT="snap"
    return 0
  fi

  if command -v firefox >/dev/null 2>&1 || [[ -x /usr/bin/firefox ]]; then
    FIREFOX_VARIANT="apt"
    return 0
  fi

  FIREFOX_VARIANT="none"
}

connect_snap_pcscd_if_needed() {
  if [[ "${FIREFOX_VARIANT}" != "snap" ]]; then
    return 0
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, but Firefox Snap appears to be installed. Skipping snap interface check."
    return 0
  fi

  # Attempt to connect firefox:pcscd; this is idempotent and safe to re-run.
  if snap connections firefox 2>/dev/null | grep -q 'firefox:pcscd'; then
    info "Firefox Snap pcscd interface is present. Ensuring it is connected…"
  else
    info "Firefox Snap pcscd interface not listed explicitly; attempting connection anyway."
  fi

  if ! snap connect firefox:pcscd >/dev/null 2>&1; then
    warn "Failed to connect Firefox Snap to pcscd interface automatically."
    warn "You may need to run 'sudo snap connect firefox:pcscd' manually."
  else
    info "Connected Firefox Snap to pcscd interface."
  fi
}

write_firefox_policies() {
  local policies_dir policies_json

  case "${FIREFOX_VARIANT}" in
    snap)
      # Prefer the traditional system-wide policies path when available; fall back to
      # the Snap-specific policies directory if needed.
      if [[ -d /etc/firefox/policies ]]; then
        policies_dir="/etc/firefox/policies"
      else
        policies_dir="/var/snap/firefox/common/.mozilla/firefox/policies"
      fi
      ;;
    apt)
      policies_dir="/etc/firefox/policies"
      ;;
    *)
      policies_dir="/etc/firefox/policies"
      ;;
  esac

  policies_json="${policies_dir}/policies.json"

  mkdir -p "${policies_dir}"

  # Determine the module path as seen from inside Firefox.
  local module_path
  case "${FIREFOX_VARIANT}" in
    snap)
      # Snap Firefox sees the host filesystem under /var/lib/snapd/hostfs.
      module_path="/var/lib/snapd/hostfs${OPENSC_MODULE}"
      ;;
    apt)
      module_path="${OPENSC_MODULE}"
      ;;
    *)
      # Fallback: assume native view of OPENSC_MODULE.
      module_path="${OPENSC_MODULE}"
      ;;
  esac

  if [[ ! -f "${module_path}" ]]; then
    warn "Expected OpenSC module path '${module_path}' not found on filesystem."
    warn "Firefox policy will still be written, but you may need to adjust the module path manually."
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    error "python3 is required to safely merge existing Firefox policies.json; please install python3 and re-run."
    exit 1
  fi

  local tmp
  tmp="$(mktemp)"

  if [[ -f "${policies_json}" ]]; then
    backup_file_once "${policies_json}"
  fi

  python3 - "$policies_json" "$tmp" "$module_path" <<'PY'
import json
import os
import sys

source_path, dest_path, module_path = sys.argv[1], sys.argv[2], sys.argv[3]

data = {}
if os.path.isfile(source_path):
    try:
        with open(source_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        # If the existing file is not valid JSON, fall back to a fresh structure.
        data = {}

policies = data.get("policies")
if not isinstance(policies, dict):
    policies = {}
    data["policies"] = policies

sec_devices = policies.get("SecurityDevices")
if not isinstance(sec_devices, dict):
    sec_devices = {}
    policies["SecurityDevices"] = sec_devices

sec_devices["OpenSC PKCS#11"] = module_path

with open(dest_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY

  mv "${tmp}" "${policies_json}"
  chmod 0644 "${policies_json}"
  info "Merged Firefox managed policy at '${policies_json}' to register OpenSC PKCS#11."
  info "Firefox will apply this policy on next startup. You can inspect it via about:policies."
}

warn_if_firefox_running() {
  if firefox_is_running; then
    warn "Firefox appears to be running while policies are being updated."
    warn "New or changed policies may not take effect until Firefox is fully restarted."
    if [[ "${CAC_FIREFOX_POLICY_FORCE:-0}" != "1" ]]; then
      warn "To suppress this warning in non-interactive environments, set CAC_FIREFOX_POLICY_FORCE=1."
    fi
  fi
}

main() {
  require_root

  detect_firefox_variant

  case "${FIREFOX_VARIANT}" in
    snap)
      info "Detected Firefox Snap installation."
      ;;
    apt)
      info "Detected Firefox installed via APT (deb)."
      ;;
    none)
      warn "No Firefox installation detected (Snap or APT). Skipping Firefox PKCS#11 configuration."
      return 0
      ;;
  esac

  # Even though this script primarily performs system-level configuration via policies,
  # require a sudo user context to discourage direct root logins and to match other scripts.
  local browser_user
  browser_user="$(detect_sudo_user)"
  info "Configuring Firefox PKCS#11 support for system, invoked by user '${browser_user}'."

  connect_snap_pcscd_if_needed
  warn_if_firefox_running
  write_firefox_policies

  info "Firefox PKCS#11 configuration step complete. Restart Firefox to apply changes."
}

main "$@"

