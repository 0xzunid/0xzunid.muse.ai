#!/bin/bash
# Restore the BOINC puzzle-71 hunt after a VM replacement.
# One command:  bash ~/workspace/boinc-puzzle71/restore.sh
# - Reinstalls boinc-client if the binary is missing (apt).
# - Regenerates the systemd unit from the template, using the LIVE egress
#   proxy URL from the current shell env (the token rotates per VM, so it is
#   never hard-coded here).
# - Installs + enables + starts boinc-puzzle71.service.
# - Does NOT touch the hunter service (bitcoin-puzzle-hunter.service).
# - Does NOT re-attach the project: the account (Zunid) and tasks live in the
#   saved data dir and resume automatically. If the data dir is ever lost,
#   re-attach with the account key in account.txt (mode 600, never print it):
#     boinccmd --project_attach https://thepuzzle.cloud/ <account_key>
set -e
SCRATCH="$HOME/workspace/.jarvis/idea-executions/824239cc-76a4-4743-906b-f826d05ee74d/scratch"
KIT="$HOME/workspace/boinc-puzzle71"
DATA="$SCRATCH/boinc-data"

if ! command -v boinc >/dev/null 2>&1; then
  echo "boinc-client missing — installing from apt..."
  sudo apt-get update -qq
  sudo apt-get install -y boinc-client
fi

PROXY="${https_proxy:-${HTTPS_PROXY:-}}"
if [ -z "$PROXY" ]; then
  echo "ERROR: no https_proxy in env — cannot build the unit (proxy token rotates per VM)." >&2
  exit 1
fi

sed "s|__PROXY_URL__|${PROXY}|g" "$KIT/boinc-puzzle71.service.template" > /tmp/boinc-puzzle71.service
sudo cp /tmp/boinc-puzzle71.service /etc/systemd/system/boinc-puzzle71.service
sudo chmod 600 /etc/systemd/system/boinc-puzzle71.service
cp /tmp/boinc-puzzle71.service "$SCRATCH/boinc-puzzle71.service"
chmod 600 "$SCRATCH/boinc-puzzle71.service"
rm /tmp/boinc-puzzle71.service

sudo systemctl disable boinc-client.service 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl enable boinc-puzzle71.service
sudo systemctl start boinc-puzzle71.service
sleep 5
systemctl is-active boinc-puzzle71.service
systemctl is-active bitcoin-puzzle-hunter.service
echo "Restore done. Check: cd $DATA && boinccmd --get_tasks"
