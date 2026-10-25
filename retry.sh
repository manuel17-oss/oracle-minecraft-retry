#!/bin/bash
# One GitHub run: up to 8 launch attempts about a minute apart.
# On success (or if the server already exists) it opens an issue and switches the schedule off.
export SUPPRESS_LABEL_WARNING=True PYTHONWARNINGS=ignore
T=$(grep -m1 '^tenancy=' ~/.oci/config | cut -d= -f2)
AD="Qrij:EU-MADRID-1-AD-1"

done_and_stop() {
  gh issue create --title "Oracle server created" \
    --body "The free 4 core / 24 GB Ampere server now exists. Tell Claude to carry on with the Minecraft setup." || true
  gh workflow disable retry.yml || true
  exit 0
}

existing=$(oci compute instance list -c "$T" --display-name minecraft \
  --query "length(data[?\"lifecycle-state\"!='TERMINATED'])" --raw-output 2>/dev/null)
[[ "$existing" =~ ^[1-9] ]] && { echo "Server already exists"; done_and_stop; }

for n in 1 2 3 4 5 6 7 8; do
  out=$(oci compute instance launch -c "$T" --availability-domain "$AD" --display-name minecraft \
    --shape VM.Standard.A1.Flex --shape-config '{"ocpus":4,"memoryInGBs":24}' \
    --image-id "$IMAGE" --subnet-id "$SUBNET" --assign-public-ip true \
    --ssh-authorized-keys-file minecraft.pub \
    --no-retry --query 'data.id' --raw-output 2>&1)
  if [[ "$out" == ocid1.instance.* ]]; then
    echo "Attempt $n: SUCCESS"
    done_and_stop
  fi
  reason=$(grep -oiE 'Out of host capacity|TooManyRequests|LimitExceeded|NotAuthenticated|timed out|InternalError' <<< "$out" | sort -u | tr '\n' ' ')
  echo "Attempt $n: ${reason:-unexpected error}"
  [[ "$reason" == *NotAuthenticated* || -z "$reason" ]] && exit 1
  [[ "$reason" == *TooManyRequests* ]] && sleep 120
  [[ $n -lt 8 ]] && sleep 50
done
