# Rollback

To undo PAM-related changes (e.g. CAC auth issues or unwanted prompts):

```bash
cd /path/to/CaC
sudo ./setup-cac.sh --rollback-pam
# or:
sudo ./scripts/cac-rollback-pam.sh
```

This restores `.cac.bak` backups for:

- `/etc/pam.d/common-auth`
- `/etc/pam_pkcs11/pam_pkcs11.conf`
- `/etc/pam_pkcs11/digest_mapping`
- `/etc/pam_pkcs11/subject_mapping`

Existing `.cac.bak` files are not overwritten; rollback only copies from them when present.
