# Screenshot capture guide

Use this list to create screenshots for the wiki. Save each image in **`wiki/images/`** (in the main repo) with the exact filename shown. Then run `./scripts/deploy-wiki.sh` from the repo root to publish.

---

## 1. Quick Start

### quick-start-cac-setup-menu.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Quick-Start](Quick-Start), Step 3 |
| **What to run** | In the repo root: `./cac-setup` |
| **When to capture** | As soon as the menu appears (before choosing an option). |
| **What to show** | The full terminal window with the CAC Setup Tool menu: title "CAC Setup Tool — DoD CAC on Ubuntu/Debian (KDE/SDDM)", the numbered options 1–9 and q) Quit, and the "Enter selection:" prompt. |
| **Filename** | `quick-start-cac-setup-menu.png` |

---

### quick-start-map-user.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Quick-Start](Quick-Start), Step 5 |
| **What to run** | With CAC inserted, in the repo root: `sudo ./setup-cac.sh --map-user YOUR_USERNAME` (replace YOUR_USERNAME with your real username, e.g. `jane`). |
| **When to capture** | After the command finishes—when you see the success message that a mapping was added (or that it already existed). |
| **What to show** | The terminal from the command you typed through the script output (certificate selection if prompted, fingerprint, and the line appended to digest_mapping or "already mapped" message). |
| **Filename** | `quick-start-map-user.png` |

---

## 2. Browser Configuration — Firefox (manual fallback)

### browser-firefox-security-devices.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Browser-Configuration](Browser-Configuration), Manual fallback — Firefox |
| **What to do** | 1. Open Firefox. 2. Go to **Settings** (or about:preferences). 3. **Privacy & Security** → scroll to **Certificates** → **Security Devices…**. 4. In the Device Manager dialog, click **Load** and fill in the form: Module Name e.g. "OpenSC PKCS#11", Module filename `/var/lib/snapd/hostfs/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so` (for Snap) or `/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so` (for APT). **Do not** click OK yet. |
| **When to capture** | When the "Load a PKCS#11 module" (or similar) dialog is open with the module name and path filled in, and the Security Devices list is visible in the background if possible. |
| **What to show** | The Load-module dialog with the OpenSC module path visible, and ideally the Security Devices window so users see where they opened it from. |
| **Filename** | `browser-firefox-security-devices.png` |

---

### browser-firefox-certificate-ask.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Browser-Configuration](Browser-Configuration), Manual fallback — Firefox |
| **What to do** | In Firefox: **Settings** → **Privacy & Security** → **Certificates** → find the setting **"When a server requests your personal certificate"** and set it to **"Ask every time"**. |
| **When to capture** | When the Certificates section is visible with **"Ask every time"** selected in the dropdown. |
| **What to show** | The Certificates area with the dropdown clearly showing "Ask every time" so readers can match it to their UI. |
| **Filename** | `browser-firefox-certificate-ask.png` |

---

## 3. Browser Configuration — Chromium/Chrome (manual fallback)

### browser-chromium-modutil.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Browser-Configuration](Browser-Configuration), Manual fallback — Chromium/Chrome |
| **What to run** | In a terminal (with or without Chrome/Chromium running): `modutil -dbdir "sql:$HOME/.pki/nssdb" -add "OpenSC PKCS#11" -libfile /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -force` |
| **When to capture** | After the command completes successfully (no error). Optionally capture the command and its output. |
| **What to show** | The terminal with the `modutil` command and its output (e.g. "Module added" or similar), so users see the exact command and that it succeeded. |
| **Filename** | `browser-chromium-modutil.png` |

---

## 4. PAM and User Mapping

### pam-map-user.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [PAM-and-User-Mapping](PAM-and-User-Mapping), "Map CAC to your Linux user" |
| **What to run** | With CAC inserted, in the repo root: `sudo ./setup-cac.sh --map-user YOUR_USERNAME` (use your real Linux username). If multiple certs exist, choose the authentication cert when prompted. |
| **When to capture** | After the script finishes—when you see the message that the mapping was added to digest_mapping (or that it already existed). |
| **What to show** | The terminal from the command through the script output: any certificate selection prompt, the fingerprint line, and the confirmation that the mapping was written (or already present). |
| **Filename** | `pam-map-user.png` |

---

## 5. Diagnostics

### diagnostics-output.png

| Field | Detail |
|-------|--------|
| **Wiki page** | [Diagnostics](Diagnostics), "How to run" |
| **What to run** | In the repo root: `./scripts/cac-diagnose.sh` (or `sudo ./scripts/cac-diagnose.sh` for full PAM/browser checks). Have a reader and CAC connected so the output is representative. |
| **When to capture** | After the script finishes—when the full report is visible (all 8 sections from [1] pcscd through [8] Chromium/Chrome). |
| **What to show** | The terminal showing the full diagnostics output: the header "CAC Diagnostics", and as many of the numbered sections as fit in one screenshot (or one scroll). If one screenshot is too small, capture the top portion so the format and section headers are clear. |
| **Filename** | `diagnostics-output.png` |

---

## Summary table

| Filename | Page | Action to capture |
|----------|------|-------------------|
| `quick-start-cac-setup-menu.png` | Quick-Start §3 | Run `./cac-setup` → capture menu |
| `quick-start-map-user.png` | Quick-Start §5 | Run `sudo ./setup-cac.sh --map-user USER` → capture success output |
| `browser-firefox-security-devices.png` | Browser-Configuration (Firefox fallback) | Firefox → Settings → Certificates → Security Devices → Load dialog with OpenSC path |
| `browser-firefox-certificate-ask.png` | Browser-Configuration (Firefox fallback) | Firefox → Settings → Certificates → "Ask every time" selected |
| `browser-chromium-modutil.png` | Browser-Configuration (Chromium fallback) | Run `modutil -dbdir "sql:$HOME/.pki/nssdb" -add "OpenSC PKCS#11" ...` → capture command + output |
| `pam-map-user.png` | PAM-and-User-Mapping | Run `sudo ./setup-cac.sh --map-user USER` → capture success output |
| `diagnostics-output.png` | Diagnostics | Run `./scripts/cac-diagnose.sh` → capture full report |

Save all files in **`wiki/images/`**, then run **`./scripts/deploy-wiki.sh`** from the repository root to update the wiki.
