# Troubleshooting

> **Ubuntu 24.04 users:** If `sudo` crashes with `verifying certificate` → `Segmentation fault (core dumped)` when your CAC is inserted, see [Known Issues](Known-Issues) for the root cause and fix.

- **No smartcard reader or token detected**
  - Run `./scripts/cac-diagnose.sh` and check **[1] pcscd**, **[2] Smartcard Readers**, **[3] CAC Token & Certificates**.
  - Ensure `pcscd` is active: `sudo systemctl status pcscd`. Reseat card/reader and re-run diagnostics if needed.

- **CAC prompts but authentication falls back to password**
  - Check **[5] User Mapping** in diagnostics; ensure your user is in `digest_mapping`.
  - If missing: `sudo ./setup-cac.sh --map-user YOUR_USERNAME`, then test with `sudo -k ls`.
  - Check **[6] PAM Stacks** for `pam_pkcs11.so` in `common-auth` and that `sudo`/`sddm` include `common-auth`.

- **Browser does not offer CAC certificates**
  - Run diagnostics and review **[7] Firefox** and **[8] Chromium / Chrome**.
  - Re-run: `sudo ./scripts/cac-configure-browser-firefox.sh` or `sudo ./scripts/cac-configure-browser-chromium.sh`.
  - Firefox Snap: ensure `firefox:pcscd` is connected: `sudo snap connect firefox:pcscd`.

- **Certificate validation errors** (e.g. “unable to get local issuer certificate”)
  - Refresh DoD bundle: `./update-dod-certs.sh` (or `--from-file`), then `sudo ./setup-cac.sh` or `sudo ./scripts/cac-update-dod-pki.sh`.
  - In diagnostics, confirm both pam_pkcs11 CA directory and system DoD CA directory show non-zero certificate counts.
