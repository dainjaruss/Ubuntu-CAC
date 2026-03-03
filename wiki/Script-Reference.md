# Script Reference

All scripts live under `scripts/`, source `lib/common.sh`, and are idempotent. They can be run directly or via `./cac-setup` menu options.

| Script | How to run | Purpose |
|--------|------------|---------|
| `cac-install-middleware.sh` | `sudo ./scripts/cac-install-middleware.sh` | Install pcscd, libccid, opensc, libnss3-tools, libpam-pkcs11; enable pcscd. Respects `CAC_ONLINE_MODE`. |
| `cac-update-dod-pki.sh` | `sudo ./scripts/cac-update-dod-pki.sh` or `--online` | Install DoD PKI from `certs/` into system trust store. `--online` also fetches/normalizes the DoD bundle. |
| `cac-configure-pam-sudo.sh` | `sudo ./scripts/cac-configure-pam-sudo.sh` or `--dry-run` | Configure PAM for sudo with pam_pkcs11. `--dry-run` shows proposed changes only. |
| `cac-configure-pam-sddm.sh` | `sudo ./scripts/cac-configure-pam-sddm.sh` or `--dry-run` | Configure PAM for SDDM (same logic as sudo script). |
| `cac-configure-browser-firefox.sh` | `sudo ./scripts/cac-configure-browser-firefox.sh` | Configure Firefox (Snap/APT) PKCS#11 via policies.json and Snap pcscd. |
| `cac-configure-browser-chromium.sh` | `sudo ./scripts/cac-configure-browser-chromium.sh` | Register OpenSC PKCS#11 in NSS DBs for Chromium/Chrome (runs as $SUDO_USER). |
| `cac-map-user.sh` | `sudo ./scripts/cac-map-user.sh <username>` | Map CAC auth cert fingerprint to Linux user in digest_mapping. |
| `cac-rollback-pam.sh` | `sudo ./scripts/cac-rollback-pam.sh` | Restore PAM-related `.cac.bak` backups. |
| `cac-diagnose.sh` | `./scripts/cac-diagnose.sh` or `sudo ./scripts/cac-diagnose.sh` | Read-only health report; no changes. |

**Standalone (repo root):** `update-dod-certs.sh` — fetch/normalize DoD bundle into `certs/`; used by `cac-update-dod-pki.sh --online`.
