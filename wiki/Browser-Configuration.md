# Browser Configuration

Configure browsers to use your CAC via **automation first**; use manual steps only when automation cannot be used.

---

## Firefox (automation-first)

1. **Interactive menu:** `./cac-setup` → option **5** (Configure Firefox PKCS#11).
2. **Direct script:**
   ```bash
   sudo ./scripts/cac-configure-browser-firefox.sh
   ```
   The script detects Snap vs APT, connects `firefox:pcscd` when needed, and writes managed `policies.json`. Safe to re-run.

### Manual fallback — Firefox

Use only when automation does not apply (e.g. locked-down `policies.json`, non-standard profiles, or manual troubleshooting).

- Connect Snap interface: `sudo snap connect firefox:pcscd`
- In Firefox: **Settings → Privacy & Security → Certificates → Security Devices → Load**
  - Module filename (Snap): `/var/lib/snapd/hostfs/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so`
- Set **“When a server requests your personal certificate”** to **“Ask every time”**.

---

## Chromium / Chrome (automation-first)

1. **Interactive menu:** `./cac-setup` → option **6** (Configure Chromium / Chrome PKCS#11).
2. **Direct script:**
   ```bash
   sudo ./scripts/cac-configure-browser-chromium.sh
   ```
   Registers OpenSC PKCS#11 in per-user NSS DBs; runs as root but operates as `$SUDO_USER`. Safe to re-run.

### Manual fallback — Chromium/Chrome

Use only when the script cannot be used (e.g. custom profile layout, read-only home, or policy-managed NSS DBs).

- Ensure `libnss3-tools` is installed (done by `setup-cac.sh`).
- Create NSS DB if needed: `mkdir -p "$HOME/.pki/nssdb"` and `certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password`
- Add module: `modutil -dbdir "sql:$HOME/.pki/nssdb" -add "OpenSC PKCS#11" -libfile /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -force`
- For Chrome profiles (e.g. `~/.config/google-chrome/Default`), run the same `modutil` with that `-dbdir`.

If the browser still does not offer CAC certs, run [Diagnostics](Diagnostics) and re-run the browser script or check the correct NSS DB for your profile.
