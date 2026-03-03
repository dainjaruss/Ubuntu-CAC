## DoD CAC Setup on Ubuntu/Debian Linux (KDE Plasma)

This repository provides a **modular, idempotent setup toolkit** for using a DoD Common Access Card (CAC) on an Ubuntu/Debian-based Linux system running the KDE Plasma desktop (SDDM). The long‑term goal is:

- **Browser CAC auth**: Firefox and Chromium-based browsers can use your CAC to access DoD sites.
- **OS login via CAC**: SDDM graphical login accepts CAC + PIN.
- **`sudo` via CAC**: Terminal `sudo` can accept CAC + PIN as an alternative to your account password.

The refactored tool splits the original monolithic `setup-cac.sh` into a small set of reusable scripts under `scripts/` plus a shared library in `lib/`, with `cac-setup` (interactive) and `setup-cac.sh` (non-interactive) as the primary entry points.

---

### Repository Layout

- `cac-setup` — interactive, menu-driven wrapper for running individual setup and utility steps.
- `setup-cac.sh` — thin non-interactive orchestrator that runs all major steps in order; still supports `--map-user` and `--rollback-pam` for backward compatibility.
- `update-dod-certs.sh` — standalone helper to download and normalize official DoD CA bundles into `certs/`.
- `lib/common.sh` — shared logging helpers and all path/tool constants (OpenSC module path, PAM locations, trust store paths, etc.).
- `scripts/` — per-feature scripts (all `chmod +x` and source `lib/common.sh`):
  - `scripts/cac-install-middleware.sh` — install smartcard middleware packages and enable the `pcscd` daemon.
  - `scripts/cac-update-dod-pki.sh` — install DoD PKI CA certificates from `certs/` into the system trust store (optionally updating the bundle first).
  - `scripts/cac-configure-pam-sudo.sh` — configure PAM for `sudo` with CAC support (with hardening and `--dry-run` mode).
  - `scripts/cac-configure-pam-sddm.sh` — configure PAM for SDDM graphical logins with CAC support (with hardening and `--dry-run` mode).
  - `scripts/cac-configure-browser-firefox.sh` — configure Firefox (Snap or APT) PKCS#11 via managed policies.
  - `scripts/cac-configure-browser-chromium.sh` — configure Chromium/Chrome PKCS#11 via NSS `modutil`.
  - `scripts/cac-map-user.sh` — map a CAC authentication certificate to a Linux user in `digest_mapping`.
  - `scripts/cac-rollback-pam.sh` — restore PAM-related `.cac.bak` backups (rollback for `common-auth` and pam_pkcs11 files).
  - `scripts/cac-diagnose.sh` — read-only diagnostics / health report.
- `certs/` — staging area where DoD root and intermediate CA certificate files live. Normalized DoD bundles are written as `certs/dod-managed-*.crt` without touching your hand-managed certs.

---

### Prerequisites

- Ubuntu or Debian derivative with:
  - APT package manager available.
  - KDE Plasma desktop using SDDM as the display manager.
- A supported CAC card reader.
- Ability to run commands with `sudo` (or as root).
- (Optional, contributors) `shellcheck` for static analysis of the shell scripts.

---

### Quick Start

1. **Clone or copy this repo onto the target machine.**

   ```bash
   git clone <your-repo-url> ~/CaC   # or copy the directory some other way
   cd ~/CaC
   ```

   (Adjust the path as needed; all commands below assume you are in the repository root.)

2. **(Optional but recommended) Fetch or refresh the DoD CA bundle into `certs/`:**

   - To download the official DISA/GDS DoD PKI bundle and normalize it into `certs/dod-managed-*.crt`:

     ```bash
     ./update-dod-certs.sh
     ```

   - To normalize a bundle you already have (ZIP / PKCS#7 / PEM):

     ```bash
     ./update-dod-certs.sh --from-file /path/to/bundle.zip
     ```

   - By default the script uses the official DoD PKCS#7 bundle URL; override it with `DOD_CERT_BUNDLE_URL` if your environment requires a mirror.
   - The script removes previously generated `certs/dod-managed-*.crt` files before writing new ones, but **leaves any hand-managed `certs/*.crt` / `certs/*.pem` files intact**.

3. **Recommended: use the interactive menu wrapper (`cac-setup`):**

   ```bash
   ./cac-setup
   ```

   From the menu, run options in order:

   - `1` – Install / verify smartcard middleware (`scripts/cac-install-middleware.sh`).
   - `2` – Install DoD PKI CA bundle into the system trust store (`scripts/cac-update-dod-pki.sh`).
   - `3` – Configure PAM for `sudo` (`scripts/cac-configure-pam-sudo.sh`).
   - `4` – Configure PAM for SDDM graphical login (`scripts/cac-configure-pam-sddm.sh`).
   - `5` – Configure Firefox PKCS#11 (Snap / APT) (`scripts/cac-configure-browser-firefox.sh`).
   - `6` – Configure Chromium / Chrome PKCS#11 (`scripts/cac-configure-browser-chromium.sh`).
   - `7` – Map CAC authentication certificate → Linux user (`scripts/cac-map-user.sh`).
   - `8` – Run diagnostics (read-only system health report; `scripts/cac-diagnose.sh`).
   - `9` – Rollback PAM changes (`scripts/cac-rollback-pam.sh`).

   You can also jump directly to diagnostics with:

   ```bash
   ./cac-setup --diagnose
   ```

4. **Non-interactive alternative: thin orchestrator (`setup-cac.sh`):**

   ```bash
   # Offline mode (APT indexes already available; default)
   sudo ./setup-cac.sh

   # Online mode (also runs apt-get update)
   CAC_ONLINE_MODE=1 sudo ./setup-cac.sh
   ```

   This runs all major steps in order:

   - Install smartcard middleware and enable `pcscd`.
   - Install DoD PKI CA certificates into the system trust store from `certs/`.
   - Configure PAM for `sudo` and SDDM with CAC support.
   - Configure Firefox and Chromium/Chrome PKCS#11 to see your CAC via OpenSC.

   For backward compatibility, the following direct entry points remain supported and are documented later in this README:

   - `sudo ./setup-cac.sh --map-user <linux-username>`
   - `sudo ./setup-cac.sh --rollback-pam`

---

### Offline vs. Online Install Modes

The setup script is designed to be **offline‑capable by default**:

- **Offline mode (default)**:
  - `setup-cac.sh` does **not** run `apt-get update`.
  - This assumes APT package indexes are already available (for example, pre‑seeded image, local mirror, or prior update).
  - Use this mode for disconnected or tightly controlled environments where network access to upstream repositories is not allowed.

- **Online mode (explicit opt‑in)**:
  - Enable by setting `CAC_ONLINE_MODE` to a truthy value (`1`, `true`, `TRUE`, `yes`, or `YES`):

    ```bash
    cd /path/to/CaC
    CAC_ONLINE_MODE=1 sudo ./setup-cac.sh
    ```

  - In this mode, the script will run `apt-get update` before installing packages, which requires network access to the configured APT repositories.

---

### Browser configuration (Firefox and Chromium/Chrome)

#### Verify reader and card

After running `setup-cac.sh`, confirm that the reader and CAC are visible to the smartcard stack:

```bash
pcsc_scan
```

With a CAC inserted you should see output similar to:

- A detected reader.
- `Card state: Card inserted`.
- An ATR and card identification line.

You can also verify that OpenSC sees the token:

```bash
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -L
```

You should see at least one **slot** with a **token label** (your name or similar).

---

#### Firefox (automation-first)

In most cases you should let the toolkit configure Firefox for CAC automatically.

1. **Preferred path: interactive menu (`./cac-setup` option 5)**

   ```bash
   cd /path/to/CaC
   ./cac-setup
   # From the menu, select:
   #   5 – Configure Firefox PKCS#11 (Snap / APT)
   ```

   This runs `scripts/cac-configure-browser-firefox.sh`, which:

   - Detects whether Firefox is installed as a Snap or APT package.
   - Connects the `firefox:pcscd` Snap interface when applicable.
   - Writes/merges managed `policies.json` so `OpenSC PKCS#11` is registered at the correct module path.

2. **Direct script entry point (non-interactive / automation)**

   ```bash
   cd /path/to/CaC
   sudo ./scripts/cac-configure-browser-firefox.sh
   ```

   This is idempotent and safe to re-run if you change Firefox variants or update OpenSC.

##### Manual fallback — Firefox

Use the manual steps below **only** when automation cannot be used or does not apply, for example:

- Policy-managed environments where `policies.json` is locked down.
- Profiles stored in non-standard locations that the script does not yet detect.
- One-off troubleshooting where you want to inspect or override the module configuration by hand.

On Ubuntu, Firefox is frequently installed as a **Snap**, which runs inside a sandbox. To allow it to access the PC/SC daemon and the OpenSC PKCS#11 module:

1. **Ensure the `pcscd` Snap interface is connected:**

   ```bash
   snap connections firefox | rg -i pcscd || snap connections firefox
   sudo snap connect firefox:pcscd
   ```

2. **Add the OpenSC PKCS#11 module (Snap-friendly path):**

   - Fully quit Firefox (Menu → Quit).
   - Re-open Firefox.
   - Go to **Settings → Privacy & Security → Certificates → Security Devices…**.
   - If you previously added an OpenSC module, select it and click **Unload**.
   - Click **Load** and use:
     - **Module Name**: `OpenSC PKCS#11` (or similar).
     - **Module filename**:

       ```text
       /var/lib/snapd/hostfs/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
       ```

   - After loading, you should see a slot/token under this module when your CAC is inserted.

3. **Make Firefox ask for a certificate:**

   - In Firefox, open **Settings → Privacy & Security → Certificates**.
   - Set **“When a server requests your personal certificate”** to **“Ask every time”**.

4. **Test a CAC-protected DoD site:**

   - Navigate to a site that requires CAC authentication.
   - Firefox should:
     - Prompt you to select a certificate from your CAC.
     - Prompt for your PIN via the OpenSC middleware.

If you see a token and get a PIN prompt but the browser shows **“connection refused”** or similar, the CAC path is working; that error is usually due to network/VPN/firewall or the remote service, not the smartcard stack.

---

#### Chromium / Chrome (automation-first)

Chromium-based browsers are also configured automatically in the common case.

1. **Preferred path: interactive menu (`./cac-setup` option 6)**

   ```bash
   cd /path/to/CaC
   ./cac-setup
   # From the menu, select:
   #   6 – Configure Chromium / Chrome PKCS#11
   ```

   This runs `scripts/cac-configure-browser-chromium.sh`, which:

   - Registers `OpenSC PKCS#11` with per-user NSS databases via `modutil`.
   - Covers `~/.pki/nssdb` and common profile directories for Chromium and Google Chrome.
   - Runs as root but performs NSS operations as `$SUDO_USER`.

2. **Direct script entry point (non-interactive / automation)**

   ```bash
   cd /path/to/CaC
   sudo ./scripts/cac-configure-browser-chromium.sh
   ```

   You can re-run this safely after browser profile changes or when adding new users.

##### Manual fallback — Chromium/Chrome

Use the manual steps below **only** when the automated script cannot be used (for example, highly customized profile layouts, read-only home directories, or policy-managed NSS DBs that the script intentionally avoids modifying).

Chromium-based browsers on Linux use NSS certificate/key databases. To make them use your CAC via OpenSC:

1. **Ensure `libnss3-tools` is installed** (done by `setup-cac.sh`).

2. **Initialize an NSS DB for your user if needed:**

   ```bash
   mkdir -p "$HOME/.pki/nssdb"
   certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password
   ```

3. **Add the OpenSC PKCS#11 module with `modutil`:**

   ```bash
   modutil -dbdir "sql:$HOME/.pki/nssdb" \
     -add "OpenSC PKCS#11" \
     -libfile /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
     -force
   ```

   For Google Chrome or other profiles that use a separate NSS DB (for example, `~/.config/google-chrome/Default`), you can repeat with:

   ```bash
   modutil -dbdir "sql:$HOME/.config/google-chrome/Default" \
     -add "OpenSC PKCS#11" \
     -libfile /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
     -force
   ```

4. **Restart the browser and test a CAC-protected site.**

If the browser does not offer certificates from your CAC, first re-check `pkcs11-tool -L` and `pcsc_scan`, then confirm the PKCS#11 module was added to the correct NSS database for the profile you are using.

---

### PAM (sudo + SDDM) notes

This setup enables `pam_pkcs11` via `/etc/pam.d/common-auth`. If CAC auth does not match your local username automatically, you can add mappings in:

- `/etc/pam_pkcs11/subject_mapping`
- `/etc/pam_pkcs11/digest_mapping`

They are created if missing, but may be empty by default.

#### Generate a digest mapping automatically

With your CAC inserted, run:

```bash
cd /path/to/CaC
sudo ./setup-cac.sh --map-user <your-linux-username>
```

This is a backward-compatible wrapper around `scripts/cac-map-user.sh` and:

- Exports a best-guess authentication certificate from the card (you can override the selection interactively).
- Computes its SHA1 fingerprint in the `hexdot` format used by `pam_pkcs11`.
- Appends a mapping line like:

```text
AA:BB:CC:... -> yourusername
```

to `/etc/pam_pkcs11/digest_mapping`.

You can also call the underlying script directly:

```bash
cd /path/to/CaC
sudo ./scripts/cac-map-user.sh <your-linux-username>
```

Both flows are idempotent: re-running the mapping for the same user and certificate will not duplicate entries.

---

### Diagnostics

The `scripts/cac-diagnose.sh` script (also available as menu option `8` in `./cac-setup` or via `./cac-setup --diagnose`) generates a **read-only** health report. It covers eight categories:

1. **pcscd service** – checks whether the smartcard daemon is active and suggests `systemctl status pcscd` if not.
2. **Smartcard readers** – uses `pcsc_scan -r` to detect connected readers and highlights when none are found.
3. **CAC token & certificates** – checks token visibility via `pkcs11-tool`, then lists certificate IDs and labels on the token.
4. **DoD CA trust stores** – counts certificates and hash links in `${PAM_PKCS11_CACERTS_DIR}` and certificates in `${DOD_CA_SYSTEM_DIR}`.
5. **User mapping** – summarizes line counts and sample entries from `digest_mapping` and `subject_mapping` (when readable).
6. **PAM stacks** – reports whether `pam_pkcs11.so` and `@include common-auth` are present in `common-auth`, `sudo`, and `sddm`.
7. **Firefox** – identifies whether Firefox is installed as Snap or APT, checks the `firefox:pcscd` Snap interface, and inspects managed `policies.json` for `OpenSC PKCS#11`.
8. **Chromium / Chrome** – inspects common NSS DB locations (for the diagnostic user) and checks whether `OpenSC PKCS#11` is registered via `modutil -list`.

Run diagnostics either directly:

```bash
cd /path/to/CaC
./scripts/cac-diagnose.sh
# or, to see PAM files that require root:
sudo ./scripts/cac-diagnose.sh
```

or via the interactive wrapper:

```bash
./cac-setup --diagnose
```

---

### Per-script reference

All per-feature scripts live under `scripts/` and source `lib/common.sh`. Each is safe to re-run (idempotent) and can also be invoked via the `cac-setup` menu.

| Script | How to run (examples) | Purpose |
|---|---|---|
| `scripts/cac-install-middleware.sh` | `sudo ./scripts/cac-install-middleware.sh` | Install smartcard middleware packages (`pcscd`, `pcsc-tools`, `libccid`, `opensc`, `libnss3-tools`, `libpam-pkcs11`) and enable/restart the `pcscd` service. Respects the `CAC_ONLINE_MODE` environment variable for running `apt-get update`. |
| `scripts/cac-update-dod-pki.sh` | `sudo ./scripts/cac-update-dod-pki.sh` / `sudo ./scripts/cac-update-dod-pki.sh --online` | Install DoD PKI CA certificates from `certs/` into the system trust store (`/usr/local/share/ca-certificates/dod`), validating and normalizing `.pem` → `.crt` when needed. With `--online`, also invokes `update-dod-certs.sh` to fetch/normalize the latest DoD bundle before importing. |
| `scripts/cac-configure-pam-sudo.sh` | `sudo ./scripts/cac-configure-pam-sudo.sh` / `sudo ./scripts/cac-configure-pam-sudo.sh --dry-run` | Configure PAM for `sudo` to honor CAC authentication via `pam_pkcs11.so`. Performs a pre-flight lockout warning, ensures `pam_pkcs11.conf` and required directories exist, refreshes the pam_pkcs11 CA directory from `certs/`, and inserts `pam_pkcs11.so` into `common-auth` as `sufficient`. `--dry-run` prints the proposed `common-auth` file instead of writing it. |
| `scripts/cac-configure-pam-sddm.sh` | `sudo ./scripts/cac-configure-pam-sddm.sh` / `sudo ./scripts/cac-configure-pam-sddm.sh --dry-run` | Configure PAM for SDDM graphical login using the same hardened `common-auth` modification logic as the sudo script. Validates that `/etc/pam.d/sddm` includes `@include common-auth` and emits guidance if it does not. |
| `scripts/cac-configure-browser-firefox.sh` | `sudo ./scripts/cac-configure-browser-firefox.sh` | Configure Firefox (Snap or APT) to use the OpenSC PKCS#11 module via managed policies. Detects Firefox variant, connects the `firefox:pcscd` Snap interface when applicable, and writes/merges `policies.json` so that `SecurityDevices.OpenSC PKCS#11` points at the correct module path. |
| `scripts/cac-configure-browser-chromium.sh` | `sudo ./scripts/cac-configure-browser-chromium.sh` | Configure Chromium/Chrome NSS databases to register `OpenSC PKCS#11` using `modutil`. Runs as root but executes NSS operations as the invoking `$SUDO_USER`, covering `~/.pki/nssdb` and common profile directories for Chromium and Google Chrome. |
| `scripts/cac-map-user.sh` | `sudo ./scripts/cac-map-user.sh <linux-username>` | Export a CAC authentication certificate from the token, compute its SHA1 fingerprint (hexdot format), and append a `fingerprint -> username` mapping line to `digest_mapping`. Interactive when multiple candidate certs exist. Idempotent for existing mappings. |
| `scripts/cac-rollback-pam.sh` | `sudo ./scripts/cac-rollback-pam.sh` | Restore PAM-related `.cac.bak` backups for `common-auth`, `pam_pkcs11.conf`, `digest_mapping`, and `subject_mapping`. This is the primary rollback path if you need to undo PAM changes. |
| `scripts/cac-diagnose.sh` | `./scripts/cac-diagnose.sh` / `sudo ./scripts/cac-diagnose.sh` | Run a read-only system health report covering middleware, CAC visibility, trust stores, mappings, PAM stacks, and browser PKCS#11 configuration. No changes are made to the system. |

The `update-dod-certs.sh` script remains a standalone entry point for fetching and normalizing DoD bundles, and is also used by `scripts/cac-update-dod-pki.sh --online`.

---

### Troubleshooting

- **No smartcard reader or token detected**
  - Run `./scripts/cac-diagnose.sh` and check sections **[1] pcscd Service**, **[2] Smartcard Readers**, and **[3] CAC Token & Certificates**.
  - Ensure `pcscd` is active (`sudo systemctl status pcscd`) and that your reader is supported and connected.
  - If `pkcs11-tool` reports "no slots" or "no token", reseat the card and reader, then re-run diagnostics.

- **CAC prompts but authentication falls back to password**
  - Verify that your user is mapped in `digest_mapping` by running diagnostics and inspecting **[5] User Mapping**.
  - If no mapping exists, re-run `sudo ./setup-cac.sh --map-user <your-linux-username>` (or `sudo ./scripts/cac-map-user.sh <your-linux-username>`), then test again with `sudo -k ls`.
  - Check **[6] PAM Stacks** in diagnostics to confirm `pam_pkcs11.so` is present in `common-auth` and that `sudo`/`sddm` include `common-auth`.

- **Browser does not offer CAC certificates**
  - Run diagnostics and review **[7] Firefox** and **[8] Chromium / Chrome** for current PKCS#11 status.
  - Re-run the relevant browser configuration script: `sudo ./scripts/cac-configure-browser-firefox.sh` or `sudo ./scripts/cac-configure-browser-chromium.sh`.
  - For Firefox Snap, ensure the `firefox:pcscd` interface is connected (`sudo snap connect firefox:pcscd`).

- **Certificate validation errors (e.g., “unable to get local issuer certificate”)**
  - Ensure you have imported a current DoD PKI bundle into `certs/` (via `./update-dod-certs.sh` or `./update-dod-certs.sh --from-file ...`) and re-run `sudo ./setup-cac.sh` or `sudo ./scripts/cac-update-dod-pki.sh`.
  - Verify via diagnostics that both the pam_pkcs11 CA directory and the system DoD CA directory report a non-zero certificate count.

---

### Current Status

- **Implemented:**
  - Smartcard daemon and middleware installation (`pcscd`, `libccid`, `opensc`, `libnss3-tools`, `libpam-pkcs11`) via `scripts/cac-install-middleware.sh`.
  - DoD PKI CA bundle download/normalization (`update-dod-certs.sh`) and system trust store integration via `scripts/cac-update-dod-pki.sh`.
  - PAM integration for:
    - **sudo**: hardened updates to `/etc/pam.d/common-auth` with backups and validation, with `/etc/pam.d/sudo` including `common-auth` so sudo prompts can accept CAC + PIN.
    - **SDDM**: validation that `/etc/pam.d/sddm` includes `common-auth`, enabling graphical login via the same CAC-enabled stack.
  - Browser PKCS#11 automation for:
    - **Firefox** (Snap / APT) via managed policies and Snap `pcscd` interface handling.
    - **Chromium/Chrome** via NSS `modutil` against per-user databases.
  - Interactive menu wrapper (`cac-setup`) and comprehensive read-only diagnostics (`scripts/cac-diagnose.sh`).

- **Known limitations:**
  - Tested primarily on Ubuntu/Debian systems with KDE Plasma and SDDM; other environments may require manual adjustments.
  - There are no automated tests; verification relies on manual checks and the diagnostics script.

All scripts are written to be **idempotent and re-runnable**. They back up existing configuration where appropriate, make minimal and reversible changes, and emit clear on-screen status messages.

---

### Rollback

If a PAM change leaves your system in an undesirable state (for example, CAC auth issues or unexpected prompts), you can restore the previous configuration:

```bash
cd /path/to/CaC
sudo ./setup-cac.sh --rollback-pam
# or directly:
sudo ./scripts/cac-rollback-pam.sh
```

This restores `.cac.bak` backups for:

- `/etc/pam.d/common-auth`
- `/etc/pam_pkcs11/pam_pkcs11.conf`
- `/etc/pam_pkcs11/digest_mapping`
- `/etc/pam_pkcs11/subject_mapping`

Existing `.cac.bak` files are never overwritten; the rollback scripts simply copy from them when present.

---

### Contributing

- **Shared utilities live in `lib/common.sh`**: add new shared constants or helpers there rather than duplicating logic across scripts.
- **Per-feature behavior belongs in `scripts/`**: when adding functionality, prefer creating a new focused script or extending an existing one rather than growing `setup-cac.sh`.
- **Run `shellcheck` locally** on any new or modified scripts to catch common shell issues:

  ```bash
  shellcheck scripts/*.sh lib/common.sh setup-cac.sh cac-setup update-dod-certs.sh
  ```

- **CI** (GitHub Actions) runs on push and pull requests to `main`: shellcheck, bash syntax check, PAM script `--dry-run` smoke tests, and Markdown lint. Ensure your branch passes before merging.

- **Preserve invariants** documented in the refactoring specs, especially:
  - Scripts remain idempotent and safe to re-run.
  - Backups use the `.cac.bak` suffix and are never overwritten.
  - `sudo ./setup-cac.sh`, `sudo ./setup-cac.sh --map-user <user>`, and `sudo ./setup-cac.sh --rollback-pam` continue to work as documented.
  - System paths and constants are referenced via `lib/common.sh` variables, not hardcoded strings in individual scripts.

---

### License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
