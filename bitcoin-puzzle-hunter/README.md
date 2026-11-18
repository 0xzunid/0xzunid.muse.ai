# Bitcoin Puzzle Hunter — 0xzunid.muse

A fresh, from-scratch Bitcoin puzzle lottery scanner running 24/7 on this VM.
**This is a lottery, not a brute-forcer.** Puzzle #71 alone has 2^70 keys; at
~640k keys/s the chance of hitting it on any given day is about 1 in 40 million.
Never expect a win — this buys lottery tickets with spare CPU.

## Targets

- 78 unsolved puzzles, bits 71–160, total prize **916.5 BTC**.
- Source: `bitcoin-puzzle-all_0_yw2b.csv` (160 puzzles, sourced from
  [privatekeys.pw](https://privatekeys.pw)) — see `targets.json`
  (addresses + hash160 + ranges only; **no private keys** in this repo).
- Every target address was verified against its `hash160_compressed`
  (base58check decode, 0 mismatches) — all targets are **compressed** P2PKH.
- Spot-checked live: puzzle #71 `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` still holds
  7.10196696 BTC, 0 sent (via [bitaps.com](https://bitaps.com) API, 2026-11-18).

## Method

Random-lottery scanning, weighted by expected value:

1. Pick a puzzle with probability proportional to `prize / range_size`
   (expected BTC per key tested). Puzzle #71 gets ~51% of the time, #72 ~26%,
   #73 ~13%, the rest split the remainder.
2. Pick a uniform-random block start inside that puzzle's range
   (`[2^(n-1), 2^n)`), from `getrandom()`.
3. Scan a block of 4096 sequential keys with **one** scalar multiplication
   and 4095 fast EC point additions (libsecp256k1 internal API), converting
   all points to affine with one Montgomery batch inversion.
4. For each key: compressed pubkey → SHA-256 → RIPEMD-160 → compare the
   20-byte hash160 with the target. A match is a HIT.

Each tested key is uniform-random in its puzzle's range (random block starts);
sequential steps inside a block are just a fast way to test many random keys.

## Measured speed (this VM, 1 core)

| Stack | keys/sec |
|---|---|
| Node.js + native `secp256k1` npm module (one scalar mult per key) | 18,566 |
| **This hunter (C, libsecp256k1 internal API + batch inversion)** | **646,432** (60 s benchmark) |
| Live service rate (from `progress.log`) | ~638,000 |

~35× faster than the Node version. Single-threaded by design, pinned to
CPU core 0 (`CPUAffinity=0` in the service).

## Honest odds (at 646k keys/sec)

| Puzzle | Share of time | P(hit) per day | Expected years to hit |
|---|---|---|---|
| #71 (7.1 BTC) | 51.0% | 2.4e-11 | ~113,000,000 |
| #72 (7.2 BTC) | 25.9% | 6.1e-12 | ~447,000,000 |
| #73 (7.3 BTC) | 13.1% | 1.6e-12 | ~1,765,000,000 |
| #74 (7.4 BTC) | 6.6% | 3.9e-13 | ~6,965,000,000 |

Expected value across all 78 puzzles: ~2.3e-10 BTC/day (~8.4e-08 BTC/year).
Covering 1% of puzzle #71's range at its ~51% share would take ~423 million days.
**Do not promise an ETA or a win.**

## Files

- `hunter.c` — the scanner (C, ~600 lines)
- `hunter` — compiled binary (`./build.sh` rebuilds it)
- `build.sh` — build command (gcc -O3 -march=native; libsecp256k1 compiled
  in from `vendor/`, RIPEMD-160 from OpenSSL libcrypto)
- `vendor/secp256k1/` — vendored libsecp256k1 source (bitcoin-core, see
  `vendor/SECP256K1_VERSION.txt` for the commit), pruned to only the files
  the build needs (headers + precomputed tables; tests/bench/examples
  removed — the full upstream tree is not required)
- `targets.json` — the 78 unsolved targets (addresses + hash160 + ranges)
- `state.json` — per-puzzle keys-scanned counters (saved every 30 s + on stop)
- `progress.log` — one line per minute: total keys, rate, puzzle #71 count
- `HIT-<bits>.json` — created ONLY on a hit (mode 0600, contains the key)

## Safety (hard rules)

- **Private keys are NEVER printed or logged** — not in stdout, the journal,
  `progress.log`, `state.json`, or any report.
- On a HIT: the key is written only to `HIT-<bits>.json` (mode `0600`),
  that puzzle stops being scanned immediately, and the hit is reported
  WITHOUT the key.
- No paid services, no mainnet funds moved, no funds sent anywhere.
- Never reproduce private keys from the source CSV anywhere.

## Service

Installed as a systemd service (same pattern as `boinc-puzzle71.service`):

```
/etc/systemd/system/bitcoin-puzzle-hunter.service
```

```sh
sudo systemctl status bitcoin-puzzle-hunter.service   # check it
sudo systemctl stop bitcoin-puzzle-hunter.service     # stop it
sudo systemctl start bitcoin-puzzle-hunter.service    # start it
sudo systemctl restart bitcoin-puzzle-hunter.service  # restart it
journalctl -u bitcoin-puzzle-hunter.service -f        # live log
tail -f ~/workspace/bitcoin-puzzle-hunter/progress.log
cat ~/workspace/bitcoin-puzzle-hunter/state.json
```

`Restart=always`, so it survives reboots. State resumes from `state.json`
(counters are cumulative across restarts).

⚠️ VM replacements wipe `/etc`, so the unit file does NOT survive them — the
service stopped at 18:33 GMT+7 on 2026-11-18 when the VM was replaced, and was
reinstalled from the copy saved in this dir. After any VM replacement, run:
`sudo cp bitcoin-puzzle-hunter.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now bitcoin-puzzle-hunter.service`.

CPU cap: 1 core (`CPUAffinity=0`, single-threaded). It runs alongside the
BOINC puzzle-71 service without touching it — note: at install time
(2026-11-18) no `boinc-puzzle71.service` unit or BOINC process was present
on this VM, so there was nothing to interfere with; if BOINC returns it
uses the other cores.

## Self-test

Run before any live scanning (also runs automatically as part of the build check):

```sh
./hunter --dir /tmp --self-test
```

Checks, all must PASS:

1. RIPEMD-160 vectors (`""`, `"abc"`)
2. Private key 1 → hash160 `751e76e8199196d454941c45d1b3a323f1433bd6`
   (address `1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH`)
3. Point-add chain matches fresh scalar mults
4. Batch inversion matches scalar mults (4096 keys)
5. Planted hit: a random key's hash160 planted as a target is detected,
   the recovered key matches, and the HIT file is written mode `0600`

Benchmark mode (measures sustained keys/sec, no live targets needed):

```sh
taskset -c 0 ./hunter --dir . --benchmark 60
```

## Build notes / decisions

- **Why C + libsecp256k1 internal API, not Node:** the Node binding does one
  scalar mult per key (~22k mults/s max on this vCPU). The C version does
  one mult per 4096-key block and cheap point additions + one batch
  inversion per block → ~646k keys/s.
- **Why OpenSSL RIPEMD-160, not hand-rolled:** a table-driven RIPEMD-160
  was written first but failed the known test vectors (a typo in the round
  tables) and was dropped in favour of the verified library call
  (~0.5 µs/key, ~2M/s standalone). SHA-256 comes from libsecp256k1's
  internal implementation.
- **Why not brainwalletx / privatekeyfinder.io code:** both were read as
  references only. brainwalletx.github.io shows the standard client-side
  pipeline (passphrase → secret exponent → EC mult → HASH160 → address).
  privatekeyfinder.io enumerates the key space sequentially in the browser
  with @noble/curves — far slower than this native scanner, and its key
  databases/downloads were not used. Nothing was copied from either site,
  and no private-key material from them is in this repo.
- **Derivation standard reference:** [iancoleman.io/bip39](https://iancoleman.io/bip39)
  (BIP39, PBKDF2 2048, no passphrase) is Zunid's standing standard. No seed
  is ever pasted into it or any website; the hunter uses raw random private
  keys, not mnemonics.
- **Source of puzzle data:** [privatekeys.pw](https://privatekeys.pw)
  (the CSV on this VM came from there). Target addresses only.
- `bitcoinprivatekeys.com` and any site listing private keys were NOT used.
