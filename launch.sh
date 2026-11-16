#!/bin/bash
# One attempt to create the Always Free Arm VM. Run by GitHub Actions on a schedule.
# Exit codes: 0 = created or no capacity (try again next run); 1 = real error (email).
set -uo pipefail

# --- settings from the OCI_SETTINGS secret: lines of NAME = value -------------
if [ -z "${OCI_SETTINGS:-}" ] || [ -z "${OCI_PRIVATE_KEY:-}" ]; then
  echo "::notice::Secrets OCI_SETTINGS / OCI_PRIVATE_KEY not set yet; nothing to do"; exit 0
fi
OCI_SETTINGS=$(printf '%s' "$OCI_SETTINGS" | tr -d '\r')
OCI_PRIVATE_KEY=$(printf '%s' "$OCI_PRIVATE_KEY" | tr -d '\r')
while IFS='=' read -r k v; do
  k=$(echo "$k" | tr -d '[:space:]'); v=$(echo "$v" | sed 's/^ *//; s/ *$//; s/^"//; s/"$//')
  [ -n "$k" ] && [ -n "$v" ] && export "$k=$v"
done <<< "${OCI_SETTINGS:-}"
for k in USER_OCID TENANCY_OCID FINGERPRINT REGION AD SUBNET_ID IMAGE_ID SSH_PUBLIC_KEY; do
  [ -n "${!k:-}" ] || { echo "::error::Missing $k in the OCI_SETTINGS secret"; exit 1; }
done
OCPUS=${OCPUS:-2}; MEMORY_GB=${MEMORY_GB:-12}; BOOT_GB=${BOOT_GB:-100}
NAME=${VM_NAME:-nsw-property-vm}; COMP=${COMPARTMENT_OCID:-$TENANCY_OCID}

# --- OCI CLI config ------------------------------------------------------------
mkdir -p ~/.oci
printf '%s\n' "$OCI_PRIVATE_KEY" > ~/.oci/key.pem; chmod 600 ~/.oci/key.pem
cat > ~/.oci/config <<CFG
[DEFAULT]
user=$USER_OCID
fingerprint=$FINGERPRINT
tenancy=$TENANCY_OCID
region=$REGION
key_file=~/.oci/key.pem
CFG
chmod 600 ~/.oci/config
printf '%s\n' "$SSH_PUBLIC_KEY" > /tmp/vm_key.pub

# --- already have one? stop for good -------------------------------------------
EXISTING=$(oci compute instance list --compartment-id "$COMP" --display-name "$NAME" \
  --query 'data[?"lifecycle-state"!=`TERMINATED`] | [0].{id:id,state:"lifecycle-state"}' \
  --raw-output 2>/tmp/list_err) || { echo "::error::Cannot list instances: $(head -c 400 /tmp/list_err)"; exit 1; }
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
  echo "VM already exists: $EXISTING"; echo "created=true" >> "$GITHUB_OUTPUT"; exit 0
fi

# --- one launch attempt, no hidden retries -------------------------------------
OUT=$(oci compute instance launch --no-retry --compartment-id "$COMP" --availability-domain "$AD" \
  --shape VM.Standard.A1.Flex --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
  --subnet-id "$SUBNET_ID" --assign-public-ip true --image-id "$IMAGE_ID" \
  --boot-volume-size-in-gbs "$BOOT_GB" --display-name "$NAME" \
  --ssh-authorized-keys-file /tmp/vm_key.pub \
  --query 'data.{id:id,state:"lifecycle-state"}' --raw-output 2>/tmp/launch_err)
if echo "$OUT" | grep -q '"id"'; then
  echo "VM CREATED: $OUT"; echo "created=true" >> "$GITHUB_OUTPUT"
  echo "### VM created 🎉" >> "$GITHUB_STEP_SUMMARY"; echo "\`$OUT\`" >> "$GITHUB_STEP_SUMMARY"; exit 0
fi
ERR=$(grep -oE '"(code|message)": "[^"]{0,100}' /tmp/launch_err | tr '\n' ' ')
echo "No VM this time: ${ERR:-$(head -c 300 /tmp/launch_err)}"
case "$ERR" in
  *"Out of host capacity"*|*TooManyRequests*|*InternalError*) exit 0 ;;   # expected; try next run
  *) echo "::error::Unexpected error: ${ERR:-see log}"; exit 1 ;;
esac
