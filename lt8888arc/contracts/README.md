# 8888LuckyLotteryTicket — contracts

Foundry project (solc 0.8.31, OpenZeppelin 5.7.0). The live deployment is **V3** on Arc mainnet; V1 and V2 are kept here for the full history.

## Layout

- `src/` — `LuckyLottery8888V3.sol` (live), `LuckyLottery8888V2.sol`, `LuckyLottery8888.sol` (V1), `PrizePool8888.sol`, `MintFeeSplitter8888.sol`, `RoyaltySplitter8888.sol`, `Interfaces.sol`, `SeaDropTypes.sol`.
- `test/` — 53 tests, incl. a replay of the exact failed V2 publish calldata (passes on V3, fails on V2 as the negative control).
- `script/` — `DeployMainnetV3.s.sol` (deploys pool → fee splitter → royalty splitter → token, commits Round 1), `SetDropMainnetV3.s.sol` (fee-recipient allowlist, creator payout, public drop).

## Build & test

```sh
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0   # provides lib/openzeppelin-contracts
forge install foundry-rs/forge-std
forge build
forge test
```

## Why the winner lists are not here

Round 1's 888 winners (8 golden + 80 ember + 800 spark) were drawn offline with a CSPRNG, tier-separated and disjoint. They stay **secret until the reveal** — publishing them would let anyone mint only winning tickets. Only the keccak256 commitment is public and on-chain:

```
0x552a35d12537d5386ae6685b6aead96bd28dda067b2808a00c30912b92c30980
```

`DeployMainnetV3.s.sol` therefore commits that constant instead of importing a winners file. The live contract enforces it: `revealRound` reverts unless the revealed lists hash to the committed value.

## Deploy (reference — the live deploy already happened 2026-11-22)

```sh
export PRIVATE_KEY=...            # deployer key, never printed or committed
export RPC_URL=https://rpc.mainnet.arc.io
forge script script/DeployMainnetV3.s.sol --rpc-url $RPC_URL --broadcast
TOKEN=<token> FEESPLITTER=<splitter> forge script script/SetDropMainnetV3.s.sol --rpc-url $RPC_URL --broadcast
```

Live addresses and txs: see `../README.md`.
