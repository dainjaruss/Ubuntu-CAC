# DoD CAC Setup on Ubuntu/Debian (KDE Plasma)

This wiki documents the **Ubuntu-CAC** toolkit: a modular, idempotent setup for using a DoD Common Access Card (CAC) on Ubuntu/Debian with KDE Plasma (SDDM).
This toolkit supplements and simplifies directions for Linux and fills in the gap left by MilitaryCAC.

## What you get

- **Browser CAC auth** — Firefox and Chromium-based browsers use your CAC for DoD sites.
- **OS login via CAC** — SDDM graphical login accepts CAC + PIN.
- **sudo via CAC** — Terminal `sudo` can use CAC + PIN instead of your account password.

## Documentation

| Page | Description |
| :--- | :--- |
| [Quick Start](Quick-Start) | Clone, run the menu, and get going. |
| [Browser Configuration](Browser-Configuration) | Automation-first Firefox and Chromium/Chrome setup; manual fallbacks. |
| [Offline and Online Modes](Offline-and-Online-Modes) | Using the toolkit with or without network. |
| [PAM and User Mapping](PAM-and-User-Mapping) | sudo/SDDM and mapping your CAC cert to your Linux user. |
| [Diagnostics](Diagnostics) | Read-only health report (`cac-diagnose.sh`). |
| [Script Reference](Script-Reference) | All scripts under `scripts/` and how to run them. |
| [Troubleshooting](Troubleshooting) | Common issues and fixes. |
| [Known Issues](Known-Issues) | Critical bugs and hardware/OS-specific workarounds. |
| [Rollback](Rollback) | Restoring PAM configuration. |
| [Screenshot Guide](Screenshot-Guide) | Step-by-step list of screenshots to capture (filename, command or UI step, what to show). |

## Entry points

- **Interactive:** `./cac-setup` — menu-driven (options 1–9).
- **Non-interactive:** `sudo ./setup-cac.sh` — runs all steps in order.
- **Diagnostics:** `./cac-setup --diagnose` or `./scripts/cac-diagnose.sh`.

Full details are in the [main README](https://github.com/<NAME>jaruss/Ubuntu-CAC/blob/main/README.md) in the repository.
