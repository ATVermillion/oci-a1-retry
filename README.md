# oci-a1-retry

Tries every 5 minutes (in runs of about 5 hours, started every 4 hours) (GitHub Actions) to create an Oracle Cloud *Always Free*
Arm VM (`VM.Standard.A1.Flex`, 2 OCPU / 12 GB) in Sydney, where capacity is scarce.
Each run makes one launch call (`--no-retry`, so no rate limiting). When the VM
exists, the workflow switches itself off.

## Secrets (Settings → Secrets and variables → Actions → Repository secrets)

`OCI_PRIVATE_KEY`: the API private key file contents (`-----BEGIN PRIVATE KEY-----` …).

`OCI_SETTINGS`: one `NAME = value` per line:

```
USER_OCID = ocid1.user.oc1..
TENANCY_OCID = ocid1.tenancy.oc1..
FINGERPRINT = aa:bb:...
REGION = ap-sydney-1
AD = xxxx:AP-SYDNEY-1-AD-1
SUBNET_ID = ocid1.subnet.oc1.ap-sydney-1...
IMAGE_ID = ocid1.image.oc1.ap-sydney-1...
SSH_PUBLIC_KEY = ssh-rsa AAAA...
```

Optional: `OCPUS`, `MEMORY_GB`, `BOOT_GB`, `VM_NAME`, `COMPARTMENT_OCID`.

Runs that find no capacity succeed quietly; a red run means a real problem
(bad key, wrong ID). Re-enable the workflow under Actions if you ever delete the VM.
