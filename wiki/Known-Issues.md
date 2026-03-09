# Known Issues

## Segmentation Fault in `pam_pkcs11` on Ubuntu 24.04 (Noble) — OpenSSL 3 Cert Verification Crash

**Affects:** Ubuntu 24.04 LTS (Noble Numbat)  
**Packages:** `libpam-pkcs11 0.6.12-*`, `opensc 0.25.0~rc1-*`, `openssl 3.0.x`  
**Status:** ✅ Workaround available (see fix below)

---

### Symptoms

When `pam_pkcs11` is enabled in `/etc/pam.d/common-auth`, any command requiring authentication (`sudo`, `su`, `login`) segfaults immediately after PIN entry:

```console
Smart card found.
Welcome <NAME>.<NAME>.<NAME>.<ID>!
Smart card PIN:
verifying certificate
Segmentation fault (core dumped)
```

Exit code: `139` (SIGSEGV).

The crash happens **only when a CAC is inserted**. When the card is absent, `pam_pkcs11` fails gracefully with:

```console
ERROR:pam_pkcs11.c:365: no suitable token available
Error 2308: No smart card found.
[sudo] password for <NAME>ja:
```

…and falls through normally to password authentication. **Password access is never lost** — `pam_pkcs11.so` is `sufficient`, not `required`.

---

### Root Cause

The crash occurs in `pam_pkcs11`'s certificate verification code path, triggered by the `cert_policy = ca,signature` setting in `/etc/pam_pkcs11/pam_pkcs11.conf`.

With this policy, `pam_pkcs11` calls into `opensc-pkcs11.so`, which attempts to register legacy digest algorithms (SHA-1, MD5) via OpenSSL 3.
On Ubuntu 24.04, OpenSSL 3 disables these legacy algorithms by default.
OpenSC is left with a `NULL` EVP digest handle and dereferences it, crashing with SIGSEGV.

**Crash call chain (simplified):**

```text
sudo → PAM → pam_pkcs11.so
  → opensc-pkcs11.so
    → C_VerifyInit() / C_Verify()
      → EVP_get_digestbyname("sha1")   ← returns NULL on OpenSSL 3 (legacy restricted)
        → dereference NULL             → SIGSEGV
```

This is a known upstream interaction bug between `libpam-pkcs11`, `opensc`, and OpenSSL 3.

> **Also affected:** The helper tools `pkcs11_inspect` and `cac-map-user.sh` (option **7** in `./cac-setup`) trigger the same crash when a card is inserted, because they use the same code path internally.

**Journalctl evidence:**

```console
pam_pkcs11(sudo:auth): init_pkcs11_module() failed: C_GetSlotInfo() failed: 0x00000030
pam_unix(sudo:auth): conversation failed
pam_unix(sudo:auth): auth could not identify password for [<NAME>ja]
```

---

### Fix / Workaround

#### Step 1 — Change `cert_policy` in `/etc/pam_pkcs11/pam_pkcs11.conf`

```bash
sudo sed -i 's/cert_policy = ca,signature;/cert_policy = none;/' \
  /etc/pam_pkcs11/pam_pkcs11.conf
```

This changes:

```text
cert_policy = ca,signature;
```

to:

```text
cert_policy = none;
```

> **Security note:** Setting `cert_policy = none` disables OpenSC-level signature verification of the certificate chain.
> DoD CA certificates remain installed in `/etc/pam_pkcs11/cacerts` and the system trust store.
> Authentication still requires physical card possession, correct PIN, and a certificate fingerprint in `digest_mapping`.
> This workaround skips only the crashing PKCS#11-level crypto step.

#### Step 2 — Manually populate the digest mapping

Because `cac-map-user.sh` and `pkcs11_inspect` also hit the crash, generate the mapping manually using `pkcs11-tool` (which does **not** trigger the bug):

```bash
# Export the PIV Authentication certificate (ID=01) from the card
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
  --read-object --type cert --id 01 -o /tmp/cac.der

# Compute the SHA1 fingerprint
FP=$(openssl x509 -inform DER -in /tmp/cac.der -noout -fingerprint -sha1 \
  | awk -F= '{print $2}' | tr -d '\r\n')
echo "Fingerprint: $FP"

# Write the mapping — replace YOUR_USERNAME with your Linux username
sudo bash -c "echo '$FP -> YOUR_USERNAME' > /etc/pam_pkcs11/digest_mapping"

# Clean up
rm /tmp/cac.der
```

Verify:

```bash
cat /etc/pam_pkcs11/digest_mapping
# Expected: 6A:93:0E:37:... -> yourusername
```

#### Step 3 — Re-enable `pam_pkcs11` in `common-auth`

Run option **3** (`Configure PAM for sudo`) from `./cac-setup` — it is now safe with `cert_policy = none` in place.

Or manually:

```bash
sudo sed -i '/^# here are the per-package modules/a auth\tsufficient\tpam_pkcs11.so' \
  /etc/pam.d/common-auth
```

---

### Verification

With CAC **inserted**:

```bash
sudo -k ls
```

Expected (no segfault):

```console
Smart card found.
Welcome <YOUR NAME>!
Smart card PIN:
verifying certificate
Checking signature
[directory listing]
```

With CAC **removed**, `sudo` falls back to password as normal.

---

### Long-Term Fix

Monitor for updated packages:

```bash
sudo apt-get update && apt-cache policy opensc libpam-pkcs11
```

A version of `opensc` newer than `0.25.0~rc1-1ubuntu0.2` may include a proper fix from Canonical. Until then, `cert_policy = none` is the recommended workaround for all Ubuntu 24.04 installations using this toolset.

---

### History

Diagnosed: 2026-03-08 | Environment: Ubuntu 24.04 LTS, KDE/SDDM, OpenSC 0.25.0~rc1, OpenSSL 3.0.13
