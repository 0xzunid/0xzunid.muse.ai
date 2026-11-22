# 8888LuckyLotteryTicket (8888LLT) — Arc mainnet

**8,888 lottery-ticket NFTs on Arc. Mint price 0.08888 USDC. 888 winners per round — 8 GOLDEN, 80 EMBER, 800 SPARK — share 70% of the prize pool; every other ticket claims an equal dividend from the remaining 30%. Perpetual rounds, 90-day claim windows.**

- **Live mint (OpenSea):** https://opensea.io/collection/8888luckylotteryticket
- **Mirror on this site:** https://0xzunid.github.io/8888LLT
- **Chain:** Arc mainnet (chain 5042), native USDC (18 decimals)
- **Deployed:** 2026-11-22 · **First mint:** 2026-11-22 ~04:33 GMT+7 — token #1, by the creator from his phone
- **Status:** LIVE — minting open until sellout (no deadline; only the 90-day per-round claim window limits time)

## Contracts (Arc mainnet, all Sourcify `exact_match`)

| Contract | Address |
| --- | --- |
| LuckyLottery8888V3 (token) | `0x19C121C501caAA0DAd3E4dEf5632F3F1C5055531` |
| PrizePool8888 | `0x8C0D0E74D7e5b7b176Ee8f48e1C7660c2762CA3E` |
| MintFeeSplitter8888 | `0x5c7B2194176B5Dd3C29E83e92f6829e5F94298d8` |
| RoyaltySplitter8888 | `0x09875209f7b4A1723B2877842c6dfE10613FE0B8` |
| SeaDrop (Arc mainnet) | `0x00005EA00Ac477B1030CE78506496e8C2dE24BF5` |

- Mint fee split: **88.88% deployer / 11.12% prize pool**, after SeaDrop's 10% fee. Per ticket via SeaDrop: deployer 0.0710968896 USDC, pool 0.0088951104 USDC (verified exact on the first mint).
- Royalties: **5% ERC-2981**, split 50/50 deployer / pool, paid to the RoyaltySplitter.
- Cap **5 per wallet**. Round 1 commitment (public, on-chain): `0x552a35d12537d5386ae6685b6aead96bd28dda067b2808a00c30912b92c30980`.
- At full sellout, mint fees ≈ 790 USDC total (~702 deployer / ~88 pool).

## The build — V1 → V2 → V3 (one night, 2026-11-22)

- **V1** (token `0x1275911d5aad33fd2bb46b9a22d4d05eb910a9f7`) — deployed ~01:07 with a **free mint** (spec error). 10 tickets were minted by two strangers before the drop was closed at 01:33. Those tickets live forever on the abandoned contract; no replacements owed.
- **V2** (token `0x8ee85e0E8B93bF8b2e3CFC6b45cb81D8a0989208`) — deployed ~01:39 with the paid 0.08888 USDC mint. Could **never be published on OpenSea**: OpenSea's publish sends a `multiConfigure` tx (selector `0x911f456b`) and V2 had no such function — the publish tx failed on-chain (status 0, `0x8f010d6e…`).
- **V3** — V2 + the standard ERC721SeaDrop `multiConfigure` (with an empty-string guard so publish can't wipe the metadata URIs). **53/53 forge tests pass**, including a replay of the exact failed publish calldata. Deployed ~04:15 (10 txs, 0.14407 USDC), published ~04:25 (publish tx `0xfe677ddc…`, status 1), Mint button live, first mint #1 ~04:33.
- Funding: half the burner's remaining Base ETH (0.00015336) bridged via Relay → +0.23639 USDC on Arc.

Full deploy log: `../workspace/goals/lt8888arc-lottery-collection/hidden_files/deploy-mainnet-v3-2026-11-22.md` (working notes, not in this repo).

## Source

- `contracts/` — Foundry project: token V1/V2/V3 + pool + splitters, 53 tests, deploy scripts. **The Round 1 winner lists are NOT in this repo** — they are drawn offline, kept secret until reveal, and only their commitment hash is public (see `contracts/README.md`).
- `metadata/` — 8,888 token metadata JSONs + `collection.json` (image `media/LLT.jpg`, 3D video `animation_url`).
- `media/` — `LLT.jpg` (collection art), `lucky-lottery-8888-3d.mp4`, `lucky-lottery-3d.mp4`.
- `../8888LLT/` — the showcase page that mirrors the OpenSea collection (live minted count + prize pool from the Arc RPC, minted-ticket grid).

## Sister collection

**FireUn** — the same lottery design on Base mainnet (free mint + 0.0001 ETH fee), contract `0xa5F10378A83eB65204e72593776a2dAe13d9B3f1`, showcase at `../fireun/showcase.html`, OpenSea https://opensea.io/collection/fireun.
