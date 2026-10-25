#!/usr/bin/env bash
# Keeps trying to create the free Ampere A1 server until Oracle has capacity.
# Run it in Oracle Cloud Shell (the >_ icon at the top of the Oracle console):
#   curl -fsSL https://raw.githubusercontent.com/ReikenZ7-Coding/heycode-ai/main/server/catch-a1.sh -o catch-a1.sh
#   bash catch-a1.sh
# Keep the Cloud Shell tab open while it runs. Stop it any time with Ctrl+C.
set -uo pipefail

NAME="AI-Agent"
SUBNET_NAME="ai-agent-subnet"
WAIT_SECONDS=60          # between rounds; lower risks "Too many requests"
MAX_HOURS=12

say() { printf '\033[1;36m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }

TENANCY="${OCI_TENANCY:-}"
if [ -z "$TENANCY" ]; then
  read -rp "Paste your tenancy OCID (Profile menu > Tenancy): " TENANCY
fi

if [ ! -s "$HOME/ai-agent.pub" ]; then
  echo "Paste your SSH PUBLIC key (the line starting with ssh-rsa), then press Enter:"
  read -r PUBKEY
  case "$PUBKEY" in ssh-*) ;; *) echo "That doesn't look like a public key." >&2; exit 1 ;; esac
  printf '%s\n' "$PUBKEY" > "$HOME/ai-agent.pub"
fi

existing=$(oci compute instance list -c "$TENANCY" \
  --query "length(data[?\"display-name\"=='$NAME' && \"lifecycle-state\"!='TERMINATED' && \"lifecycle-state\"!='TERMINATING'])" \
  --raw-output 2>/dev/null)
if [ "${existing:-0}" != "0" ]; then
  say "An instance called $NAME already exists. Nothing to do."
  exit 0
fi

AD=$(oci iam availability-domain list -c "$TENANCY" --query 'data[0].name' --raw-output)
SUBNET=$(oci network subnet list -c "$TENANCY" --all \
  --query "data[?\"display-name\"=='$SUBNET_NAME'].id | [0]" --raw-output)
IMAGE=$(oci compute image list -c "$TENANCY" --all \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)

if [ -z "$SUBNET" ] || [ "$SUBNET" = "null" ]; then
  echo "Couldn't find the subnet '$SUBNET_NAME'. Create the network first (see the setup guide)." >&2
  exit 1
fi
if [ -z "$IMAGE" ] || [ "$IMAGE" = "null" ]; then
  echo "Couldn't find an Ubuntu 24.04 image for A1 in this region." >&2
  exit 1
fi
say "Availability domain: $AD"
say "Ubuntu 24.04 image found, subnet found. Starting to try."

launch() {  # $1 = OCPUs, $2 = GB memory
  oci compute instance launch \
    --availability-domain "$AD" --compartment-id "$TENANCY" \
    --display-name "$NAME" --shape VM.Standard.A1.Flex \
    --shape-config "{\"ocpus\": $1, \"memoryInGBs\": $2}" \
    --image-id "$IMAGE" --subnet-id "$SUBNET" --assign-public-ip true \
    --boot-volume-size-in-gbs 100 \
    --ssh-authorized-keys-file "$HOME/ai-agent.pub" 2>&1
}

deadline=$(( $(date +%s) + MAX_HOURS * 3600 ))
round=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  round=$((round + 1))
  for size in "2 12" "1 6"; do
    set -- $size
    out=$(launch "$1" "$2")
    if printf '%s' "$out" | grep -q '"lifecycle-state"'; then
      say "SUCCESS on round $round: $1 OCPU / $2 GB server is being created! 🎉"
      say "Go to Compute > Instances in the console; it turns green in 1-2 minutes."
      exit 0
    fi
    if printf '%s' "$out" | grep -qi 'TooManyRequests\|Too many requests'; then
      say "Oracle asked us to slow down. Pausing 5 minutes."
      sleep 300
    elif printf '%s' "$out" | grep -qi 'capacity'; then
      say "Round $round: no capacity for $1 OCPU / $2 GB yet."
    else
      say "Unexpected answer from Oracle, stopping so you can check it:"
      printf '%s\n' "$out"
      exit 1
    fi
    sleep 20
  done
  sleep "$WAIT_SECONDS"
done
say "No luck after $MAX_HOURS hours. Run the script again later."
exit 1
