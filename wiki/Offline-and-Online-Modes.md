# Offline and Online Modes

The setup is **offline-capable by default**.

- **Offline (default):** `setup-cac.sh` does **not** run `apt-get update`. Use when APT indexes are already available (e.g. pre-seeded image or local mirror).
- **Online:** Set `CAC_ONLINE_MODE=1` (or `true`/`yes`) so the script runs `apt-get update` before installing packages:

  ```bash
  CAC_ONLINE_MODE=1 sudo ./setup-cac.sh
  ```

Individual scripts (e.g. `cac-install-middleware.sh`) also respect `CAC_ONLINE_MODE` where applicable.
