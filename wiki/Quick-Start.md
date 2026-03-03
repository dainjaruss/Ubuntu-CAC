# Quick Start

1. **Clone the repo**

   ```bash
   git clone https://github.com/dainjaruss/Ubuntu-CAC.git ~/CaC
   cd ~/CaC
   ```

2. **(Optional) Refresh DoD CA bundle**

   ```bash
   ./update-dod-certs.sh
   ```

   Or with a local bundle: `./update-dod-certs.sh --from-file /path/to/bundle.zip`

3. **Run the interactive menu**

   ```bash
   ./cac-setup
   ```

   Run options in order: **1** (middleware) → **2** (DoD PKI) → **3** (sudo PAM) → **4** (SDDM PAM) → **5** (Firefox) → **6** (Chromium/Chrome) → **7** (map user).

4. **Or run everything non-interactively**

   ```bash
   sudo ./setup-cac.sh
   ```

   For online mode (e.g. `apt-get update`): `CAC_ONLINE_MODE=1 sudo ./setup-cac.sh`

5. **Map your CAC to your Linux user** (if not done in step 3)

   ```bash
   sudo ./setup-cac.sh --map-user YOUR_USERNAME
   ```

See [Browser Configuration](Browser-Configuration) for automation-first browser setup and [PAM and User Mapping](PAM-and-User-Mapping) for mapping details.
