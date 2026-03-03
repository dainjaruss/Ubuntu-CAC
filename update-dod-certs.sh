#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optionally source shared lib/common.sh for logging helpers / constants,
# but keep this script runnable as a standalone tool.
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  . "${SCRIPT_DIR}/lib/common.sh"
fi

CERTS_DIR="${CERTS_DIR:-${SCRIPT_DIR}/certs}"

info() {
  printf '[INFO] %s\n' "$*" >&2
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

ensure_certs_dir() {
  mkdir -p "${CERTS_DIR}"
}

cleanup_old_managed_certs() {
  shopt -s nullglob
  local managed_certs=("${CERTS_DIR}"/dod-managed-*.crt)
  shopt -u nullglob

  if [[ "${#managed_certs[@]}" -gt 0 ]]; then
    info "Removing ${#managed_certs[@]} previously managed DoD certificates from '${CERTS_DIR}'."
    rm -f "${managed_certs[@]}"
  fi
}

split_pem_bundle_into_certs() {
  local bundle_file="$1"
  local out_dir="$2"

  local count
  count="$(awk '
    /-----BEGIN CERTIFICATE-----/ {
      in_cert=1
      cert_index++
      filename=sprintf("%s/dod-managed-%03d.crt", "'"${out_dir}"'", cert_index)
    }
    {
      if (in_cert) {
        print > filename
      }
    }
    /-----END CERTIFICATE-----/ {
      in_cert=0
    }
    END {
      if (cert_index > 0) {
        print cert_index
      }
    }
  ' "${bundle_file}")"

  if [[ -z "${count}" ]]; then
    error "No PEM certificates found in downloaded bundle. Leaving existing certificates unchanged."
    exit 1
  fi

  info "Extracted ${count} certificate(s) into '${out_dir}/dod-managed-XXX.crt'."
}

extract_and_normalize_bundle() {
  local bundle_file="$1"

  if ! command -v openssl >/dev/null 2>&1; then
    error "'openssl' is required to process DoD certificate bundles."
    exit 1
  fi

  # DoD bundles are commonly distributed as a ZIP containing:
  # - dod_pke_chain.pem (already PEM)
  # - one or more *_der.p7b files (PKCS#7 DER)
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  local pem_source=""
  if command -v unzip >/dev/null 2>&1 && unzip -tq "${bundle_file}" >/dev/null 2>&1; then
    info "Downloaded bundle is a ZIP; extracting."
    unzip -q "${bundle_file}" -d "${tmp_dir}"

    shopt -s nullglob globstar
    local pem_candidates=("${tmp_dir}"/**/dod_pke_chain.pem)
    local p7b_candidates=("${tmp_dir}"/**/*.p7b)
    shopt -u globstar nullglob

    if [[ "${#pem_candidates[@]}" -gt 0 ]]; then
      pem_source="${pem_candidates[0]}"
    fi
    # Prefer converting all *.p7b files, since they contain the full DoD PKI set
    # (roots + intermediates). If none are present, fall back to any PEM chain.
    if [[ "${#p7b_candidates[@]}" -gt 0 ]]; then
      pem_source="${tmp_dir}/dod-pke-all-from-p7b.pem"
      : > "${pem_source}"
      info "Converting ${#p7b_candidates[@]} PKCS#7 file(s) to PEM:"
      local p7b
      for p7b in "${p7b_candidates[@]}"; do
        info "  - ${p7b}"
        if ! openssl pkcs7 -print_certs -inform DER -in "${p7b}" >> "${pem_source}" 2>/dev/null; then
          warn "OpenSSL failed to convert '${p7b}' (continuing with others)."
        fi
      done
    elif [[ -n "${pem_source}" ]]; then
      info "Found PEM chain file: ${pem_source}"
    else
      rm -rf "${tmp_dir}"
      error "ZIP bundle did not contain any .p7b files or a .pem chain file."
      exit 1
    fi
  else
    # Non-zip input: either PEM bundle or PKCS#7.
    if grep -q "BEGIN CERTIFICATE" "${bundle_file}"; then
      pem_source="${bundle_file}"
    else
      info "Downloaded bundle does not appear to be PEM. Attempting PKCS#7 → PEM conversion with openssl."
      pem_source="${tmp_dir}/dod-pke-chain-from-p7b.pem"
      if ! openssl pkcs7 -print_certs -in "${bundle_file}" -out "${pem_source}" >/dev/null 2>&1; then
        rm -rf "${tmp_dir}"
        error "OpenSSL failed to convert the downloaded bundle as PKCS#7."
        exit 1
      fi
    fi
  fi

  if [[ -z "${pem_source}" ]] || ! grep -q "BEGIN CERTIFICATE" "${pem_source}"; then
    rm -rf "${tmp_dir}"
    error "No PEM certificates were found in the bundle after processing."
    exit 1
  fi

  info "Normalizing DoD certificate bundle into '${CERTS_DIR}'."
  cleanup_old_managed_certs
  split_pem_bundle_into_certs "${pem_source}" "${CERTS_DIR}"

  rm -rf "${tmp_dir}"
}

download_bundle() {
  # Official DoD certificate bundles are published via DISA/GDS.
  # Default to the "DoD PKI only" PKCS#7 zip bundle; override with DOD_CERT_BUNDLE_URL if needed.
  local DEFAULT_BUNDLE_URL="https://crl.gds.disa.mil/pke/config/certificates_pkcs7_v5_13_dod.zip"
  local bundle_url="${DOD_CERT_BUNDLE_URL:-$DEFAULT_BUNDLE_URL}"

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    error "Neither curl nor wget is installed. Install one of them and re-run this script."
    exit 1
  fi

  info "Downloading DoD cert bundle from: ${bundle_url}"

  local tmp_file
  tmp_file="$(mktemp "${CERTS_DIR}/dod-bundle-XXXXXX")"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${bundle_url}" -o "${tmp_file}"
  else
    wget -qO "${tmp_file}" "${bundle_url}"
  fi

  info "Bundle downloaded to ${tmp_file}"
  extract_and_normalize_bundle "${tmp_file}"
  rm -f "${tmp_file}"
}

usage() {
  cat <<'EOF'
Usage:
  ./update-dod-certs.sh
    - downloads the default DoD PKI CA bundle zip and normalizes it into ./certs/dod-managed-*.crt

  ./update-dod-certs.sh --from-file /path/to/bundle.zip
    - normalizes an already-downloaded bundle file (zip / p7b / pem)

Environment:
  DOD_CERT_BUNDLE_URL
    - optional override URL to download instead of the default
EOF
}

main() {
  ensure_certs_dir

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--from-file" ]]; then
    if [[ -z "${2:-}" ]]; then
      error "Missing bundle path."
      usage
      exit 2
    fi
    if [[ ! -f "${2}" ]]; then
      error "Bundle file not found: ${2}"
      exit 2
    fi
    info "Normalizing local bundle file: ${2}"
    extract_and_normalize_bundle "${2}"
  else
    download_bundle
  fi

  info "Bundle download and normalization complete."
  info "Re-run 'setup-cac.sh' (in offline or online mode) to import the refreshed certificates into the system trust store."
}

main "$@"

