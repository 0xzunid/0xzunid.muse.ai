# BOINC — Bitcoin Puzzle 71 pooled hunt (The Puzzle)

Restored 2026-11-18 ~18:48 GMT+7 after a VM replacement wiped the client
binary and the systemd unit. Account, tasks, and checkpoints survived in the
saved data dir, so the hunt resumed without re-attaching.

## Project
- **The Puzzle** — https://thepuzzle.cloud/ — Puzzle #71 ONLY
- Address `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` — 7.10195986 BTC, unsolved
- Prize split if the key is found: 20% taxes, 40% operator, 40% shared by
  volunteers in proportion to validated BOINC credit
- Account: Zunid (project user ID 2394). Credentials in
  `~/workspace/.jarvis/idea-executions/824239cc-76a4-4743-906b-f826d05ee74d/scratch/account.txt`
  (mode 600 — never print or paste the password/key anywhere)

## Service
- `boinc-puzzle71.service` — BOINC client 7.24.1, `Restart=always`, enabled
- Data dir: `.../scratch/boinc-data/` (account + tasks + checkpoints)
- CPU cap (hunter keeps priority): **CPUQuota=50%** and **CPUAffinity=1-3**
  (the hunter is pinned to core 0). Verified ~42–47% CPU on the search app.
- `global_prefs_override.xml` in the data dir sets
  `<suspend_cpu_usage>0</suspend_cpu_usage>`: BOINC's default "suspend when
  non-BOINC CPU load exceeds 25%" would suspend it forever, because the
  hunter runs 24/7 on core 0. The cgroup cap above is the real throttle.
- The stock `boinc-client.service` from the apt package is disabled — it
  would start with the wrong (default) data dir.
- The egress proxy token rotates per VM: the unit file is generated from
  `boinc-puzzle71.service.template` with the live `$https_proxy` at
  install/restore time. Never hard-code the token.

## Check status
```sh
systemctl status boinc-puzzle71.service
cd ~/workspace/.jarvis/idea-executions/824239cc-76a4-4743-906b-f826d05ee74d/scratch/boinc-data
boinccmd --get_project_status   # attached as Zunid, credit (0 until first validated result)
boinccmd --get_tasks            # task state, fraction done
tail -f ../logs/boinc-stdout.log
```

## Stop / start
```sh
sudo systemctl stop boinc-puzzle71.service    # stop (stays disabled on boot only if also disabled)
sudo systemctl start boinc-puzzle71.service   # start
sudo systemctl disable boinc-puzzle71.service # stop it coming back on boot
```

## After a VM replacement (restore)
```sh
bash ~/workspace/boinc-puzzle71/restore.sh
```
Reinstalls the client if missing, regenerates the unit from the template
with the live proxy token, installs + enables + starts the service, and
verifies both the BOINC service and the hunter are active. `/etc` and
apt-installed packages do not survive a VM replacement — this kit and the
data dir in `~/workspace` do.

## Current task (2026-11-18)
- `kr_7f7a9f2e90df5e20918aa76b03e6af14_0` — resumed from checkpoint,
  ~65% done at restore, report deadline 22 Nov 2026. At the 50% CPU cap the
  remaining ~35% takes roughly 30 wall-clock hours. User total credit: 0
  (honest zero — credit only after a result uploads and validates).
