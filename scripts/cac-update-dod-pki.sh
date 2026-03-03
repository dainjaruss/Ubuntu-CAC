#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

CERTS_DIR="${SCRIPT_DIR}/../certs"

install_local_dod_certs() {
  local src_dir dst_dir
  src_dir="${CERTS_DIR}"
  dst_dir="${DOD_CA_SYSTEM_DIR}"

  if [[ ! -d "${src_dir}" ]]; then
    warn "No local DoD cert bundle directory found at '${src_dir}'. Skipping system trust store update."
    return 0
  fi

  shopt -s nullglob
  local certs=("${src_dir}"/*.crt "${src_dir}"/*.pem)
  shopt -u nullglob

  if [[ "${#certs[@]}" -eq 0 ]]; then
    warn "No .crt or .pem files found in '${src_dir}'. Skipping system trust store update."
    return 0
  fi

  info "Installing DoD CA certificates into system trust store…"
  mkdir -p "${dst_dir}"

  local have_openssl=0
  if command -v openssl >/dev/null 2>&1; then
    have_openssl=1
  else
    warn "openssl not found; certificate files will not be validated before import."
  fi

  local cert base ext dest_name imported_count=0
  for cert in "${certs[@]}"; do
    base="$(basename "${cert}")"
    ext="${base##*.}"
    dest_name="${base}"

    if [[ "${ext}" == "pem" ]]; then
      dest_name="${base%.*}.crt"
      info "Normalizing PEM certificate '${base}' to '${dest_name}' for Debian/Ubuntu trust store compatibility."
    fi

    if [[ "${have_openssl}" -eq 1 ]]; then
      if ! openssl x509 -in "${cert}" -noout >/dev/null 2>&1; then
        warn "Skipping '${base}': not a valid X.509 certificate."
        continue
      fi
    fi

    cp -f "${cert}" "${dst_dir}/${dest_name}"
    imported_count=$((imported_count + 1))
  done

  if [[ "${imported_count}" -eq 0 ]]; then
    warn "No valid certificates were imported into '${dst_dir}'. System trust store will not be changed."
    return 0
  fi

  if command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates
  else
    warn "update-ca-certificates not found; you may need to update the system trust store manually."
  fi
}

maybe_update_online_bundle() {
  if [[ "${1:-}" != "--online" ]]; then
    return 0
  fi

  local updater="${SCRIPT_DIR}/../update-dod-certs.sh"
  if [[ -x "${updater}" ]]; then
    info "Running update-dod-certs.sh to retrieve latest DoD PKI bundle…"
    "${updater}"
  elif [[ -f "${updater}" ]]; then
    info "Running update-dod-certs.sh via bash to retrieve latest DoD PKI bundle…"
    bash "${updater}"
  else
    warn "update-dod-certs.sh not found at '${updater}'; skipping online bundle update."
  fi
}

main() {
  local online_flag="${1:-}"

  require_root

  maybe_update_online_bundle "${online_flag}"
  install_local_dod_certs

  info "DoD PKI CA installation step complete."
}

main "$@"

