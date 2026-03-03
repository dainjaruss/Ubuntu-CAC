#!/usr/bin/env bash

# Shared constants (overridable via environment)
OPENSC_MODULE="${OPENSC_MODULE:-/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so}"
PAM_PKCS11_CONF="${PAM_PKCS11_CONF:-/etc/pam_pkcs11/pam_pkcs11.conf}"
PAM_PKCS11_CACERTS_DIR="${PAM_PKCS11_CACERTS_DIR:-/etc/pam_pkcs11/cacerts}"
PAM_PKCS11_CRLS_DIR="${PAM_PKCS11_CRLS_DIR:-/etc/pam_pkcs11/crls}"
PAM_PKCS11_DIGEST_MAP="${PAM_PKCS11_DIGEST_MAP:-/etc/pam_pkcs11/digest_mapping}"
PAM_PKCS11_SUBJECT_MAP="${PAM_PKCS11_SUBJECT_MAP:-/etc/pam_pkcs11/subject_mapping}"
DOD_CA_SYSTEM_DIR="${DOD_CA_SYSTEM_DIR:-/usr/local/share/ca-certificates/dod}"
COMMON_AUTH="${COMMON_AUTH:-/etc/pam.d/common-auth}"

export OPENSC_MODULE \
  PAM_PKCS11_CONF \
  PAM_PKCS11_CACERTS_DIR \
  PAM_PKCS11_CRLS_DIR \
  PAM_PKCS11_DIGEST_MAP \
  PAM_PKCS11_SUBJECT_MAP \
  DOD_CA_SYSTEM_DIR \
  COMMON_AUTH

info() {
  printf '[INFO] %s\n' "$*" >&2
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "This script must be run as root (use sudo)."
    exit 1
  fi
}

backup_file_once() {
  local src="$1"
  local backup="${src}.cac.bak"

  if [[ ! -e "${src}" ]]; then
    warn "File '${src}' does not exist; nothing to back up."
    return 0
  fi

  if [[ -e "${backup}" ]]; then
    info "Backup for '${src}' already exists at '${backup}'."
    return 0
  fi

  cp -a "${src}" "${backup}"
  info "Backed up '${src}' to '${backup}'."
}

restore_backup_if_present() {
  local src="$1"
  local backup="${src}.cac.bak"

  if [[ ! -e "${backup}" ]]; then
    warn "No backup present at '${backup}'."
    return 0
  fi

  cp -a "${backup}" "${src}"
  info "Restored '${src}' from '${backup}'."
}

run_as_user() {
  local username="$1"
  shift || true

  if [[ -z "${username}" ]]; then
    error "run_as_user: username is required."
    return 1
  fi

  if [[ "$#" -eq 0 ]]; then
    error "run_as_user: command to execute is required."
    return 1
  fi

  sudo -u "${username}" "$@"
}

detect_sudo_user() {
  local user="${SUDO_USER:-}"

  if [[ -z "${user}" ]]; then
    error "No SUDO_USER detected. Please invoke this script via sudo (e.g., 'sudo ./script.sh')."
    exit 1
  fi

  printf '%s\n' "${user}"
}

ensure_pam_dirs() {
  mkdir -p "${PAM_PKCS11_CACERTS_DIR}" "${PAM_PKCS11_CRLS_DIR}"
}

ensure_pam_pkcs11_config() {
  local conf="${PAM_PKCS11_CONF}"

  if [[ -f "${conf}" ]]; then
    info "Found pam_pkcs11 configuration at '${conf}'."
    if grep -qE '^[[:space:]]*ca_dir[[:space:]]*=[[:space:]]*/etc/ssl/certs;' "${conf}"; then
      backup_file_once "${conf}"
      sed -i "s#^[[:space:]]*ca_dir[[:space:]]*=[[:space:]]*/etc/ssl/certs;#    ca_dir = ${PAM_PKCS11_CACERTS_DIR};#" "${conf}"
      info "Updated '${conf}' to use ca_dir=${PAM_PKCS11_CACERTS_DIR}."
    fi
    return 0
  fi

  info "Creating pam_pkcs11 configuration at '${conf}'."
  mkdir -p "$(dirname "${conf}")"

  cat > "${conf}" <<EOF
pam_pkcs11 {
  debug = false;
  nullok = true;
  card_only = false;
  wait_for_card = false;

  use_pkcs11_module = opensc;

  pkcs11_module opensc {
    module = ${OPENSC_MODULE};
    description = "OpenSC PKCS#11 module";
    slot_description = "none";

    ca_dir = ${PAM_PKCS11_CACERTS_DIR};
    crl_dir = ${PAM_PKCS11_CRLS_DIR};

    cert_policy = ca,signature;
    token_type = "Smart card";
  }

  use_mappers = ms, digest, subject, null;

  mapper ms {
    debug = false;
    module = internal;
    ignorecase = false;
    ignoredomain = true;
    domainname = "";
  }

  mapper digest {
    debug = false;
    module = internal;
    algorithm = "sha1";
    mapfile = file://${PAM_PKCS11_DIGEST_MAP};
  }

  mapper subject {
    debug = false;
    module = internal;
    ignorecase = false;
    mapfile = file://${PAM_PKCS11_SUBJECT_MAP};
  }

  mapper null {
    debug = false;
    module = internal;
    default_match = false;
    default_user = nobody;
  }
}
EOF

  chmod 0644 "${conf}"
  chown root:root "${conf}"

  install -m 0644 -o root -g root /dev/null "${PAM_PKCS11_DIGEST_MAP}" || true
  install -m 0644 -o root -g root /dev/null "${PAM_PKCS11_SUBJECT_MAP}" || true

  info "Created '${conf}'."
}

validate_common_auth_output() {
  local file="$1"

  if ! grep -qE 'pam_unix\.so' "${file}"; then
    error "Proposed common-auth at '${file}' does not contain pam_unix.so; refusing to write."
    return 1
  fi
}

enable_cac_in_common_auth() {
  local maybe_dry_run="${1:-}"
  local common_auth="${COMMON_AUTH}"

  if [[ ! -f "${common_auth}" ]]; then
    warn "PAM file '${common_auth}' not found; cannot enable CAC authentication."
    return 0
  fi

  if grep -qE 'pam_pkcs11\.so' "${common_auth}"; then
    info "CAC (pam_pkcs11) is already referenced in '${common_auth}'."
    return 0
  fi

  info "Enabling CAC (pam_pkcs11) in '${common_auth}' (this affects both sudo and display managers that include common-auth)."
  backup_file_once "${common_auth}"

  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN { inserted = 0 }
    /^auth[[:space:]]/ && inserted == 0 {
      print "auth\tsufficient\tpam_pkcs11.so"
      inserted = 1
    }
    { print }
    END {
      if (inserted == 0) {
        print "auth\tsufficient\tpam_pkcs11.so"
      }
    }
  ' "${common_auth}" > "${tmp}"

  validate_common_auth_output "${tmp}"

  if [[ "${maybe_dry_run}" == "--dry-run" ]]; then
    cat "${tmp}"
    rm -f "${tmp}"
    info "Dry-run only; '${common_auth}' was not modified."
    return 0
  fi

  install -m 0644 "${tmp}" "${common_auth}"
  rm -f "${tmp}"

  info "Updated '${common_auth}' to include pam_pkcs11 as a sufficient auth method."
}

refresh_pam_pkcs11_cacerts_from_repo() {
  local src_dir="$1"
  local dst_dir="${PAM_PKCS11_CACERTS_DIR}"

  # Invariant: from PAM's perspective, '${dst_dir}' is never missing.
  # We stage into a sibling temp dir and then *refresh in place*
  # so that the live directory is never removed, only updated.
  # This keeps PAM from ever seeing an absent CA directory, and
  # makes reruns idempotent even when '${dst_dir}' already exists.
  ensure_pam_dirs

  if [[ ! -d "${src_dir}" ]]; then
    warn "Local cert bundle directory '${src_dir}' not found; pam_pkcs11 CA directory will not be updated."
    return 0
  fi

  shopt -s nullglob
  local certs=("${src_dir}"/*.crt "${src_dir}"/*.pem)
  shopt -u nullglob

  if [[ "${#certs[@]}" -eq 0 ]]; then
    warn "No local DoD CA certificates found in '${src_dir}'."
    warn "pam_pkcs11 certificate verification may fail until you run './update-dod-certs.sh' and then re-run this setup script."
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    warn "openssl not found; certificates will be copied without validation/normalization."
  fi

  local parent
  parent="$(dirname "${dst_dir}")"
  mkdir -p "${parent}"

  local tmp_dir
  tmp_dir="$(mktemp -d "${parent}/cacerts.XXXXXX")"

  local cert base ext out
  for cert in "${certs[@]}"; do
    base="$(basename "${cert}")"
    ext="${base##*.}"
    out="${tmp_dir}/${base}"

    if [[ "${ext}" == "pem" ]]; then
      out="${tmp_dir}/${base%.*}.crt"
    fi

    if command -v openssl >/dev/null 2>&1; then
      if ! openssl x509 -in "${cert}" -noout >/dev/null 2>&1; then
        warn "Skipping '${base}': not a valid X.509 certificate."
        continue
      fi
      openssl x509 -in "${cert}" -out "${out}" >/dev/null 2>&1 || cp -f "${cert}" "${out}"
    else
      cp -f "${cert}" "${out}"
    fi
  done

  # Ensure directory ownership and permissions are correct before swap.
  chown root:root "${tmp_dir}" || true
  chmod 0755 "${tmp_dir}" || true

  if command -v pkcs11_make_hash_link >/dev/null 2>&1; then
    pkcs11_make_hash_link "${tmp_dir}" >/dev/null 2>&1 || warn "pkcs11_make_hash_link failed; pam_pkcs11 may not find issuers by hash."
  elif command -v c_rehash >/dev/null 2>&1; then
    c_rehash "${tmp_dir}" >/dev/null 2>&1 || warn "c_rehash failed; pam_pkcs11 may not find issuers by hash."
  else
    warn "Neither pkcs11_make_hash_link nor c_rehash is available; pam_pkcs11 CA hashing may be incomplete."
  fi

  info "Refreshing pam_pkcs11 CA directory at '${dst_dir}' from '${src_dir}' (atomic swap)."

  # At this point 'tmp_dir' contains a complete, self-consistent CA set.
  # To preserve the "never remove live path" invariant and support reruns
  # even when '${dst_dir}' already contains certs, we *do not* mv -T
  # over the live directory (which would fail on non-empty dirs).
  #
  # Instead, we refresh '${dst_dir}' in place:
  #   - If 'rsync' is available, use it with --delete so that the live
  #     directory becomes an exact copy of 'tmp_dir' without ever being
  #     removed. Deletions happen only after new files are present.
  #   - Otherwise, fall back to 'cp -a', which overwrites/creates all
  #     managed files but may leave extra historical files behind.

  mkdir -p "${dst_dir}"

  if command -v rsync >/dev/null 2>&1; then
    if ! rsync -a --delete "${tmp_dir}/" "${dst_dir}/"; then
      warn "rsync-based refresh of '${dst_dir}' from '${tmp_dir}' failed; keeping existing contents."
      rm -rf "${tmp_dir}"
      return 1
    fi
  else
    if ! cp -a "${tmp_dir}/." "${dst_dir}/"; then
      warn "Copy-based refresh of '${dst_dir}' from '${tmp_dir}' failed; keeping existing contents."
      rm -rf "${tmp_dir}"
      return 1
    fi
  fi

  rm -rf "${tmp_dir}"
  info "pam_pkcs11 CA directory at '${dst_dir}' refreshed successfully."
  return 0
}

