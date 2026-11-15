# @0xzunid/0xzunid-muse

Addresses, ABIs and chain config for the **0xzunid muse** testnet project —
Zunid + Muse. Testnet only, zero real money.

- **ERC-20 tokens** — ZND / BZND (ARC), RZND / BRZND (Robinhood Chain),
  LZND (LiteForge), SZND (Sepolia). All 1,000,000 supply, 18 decimals.
- **SimpleAMM pools** — ZND/USDC, RZND/ETH, plus the burner pools.
  No remove-liquidity function: liquidity is locked for the life of the test.
- **ZunidNameService** registries on ARC, Robinhood Chain and LiteForge.
  Names `0xzunid`, `zunid`, `muse` (no registry on Sepolia).
- **ZunidNameToken** — soulbound (non-transferable) ERC-721 name NFTs,
  one per name per chain, fully onchain metadata.
- **Wallets** — Privy `0x0B22…981`, burner `0x3a11…4D05`.

All addresses are verified onchain facts as of 2026-11-15. Nothing in this
package makes network calls: `resolveName()` is a static lookup.

## Install

Published to GitHub Packages (`npm.pkg.github.com`). Add the scope to your
npm config first (needs a GitHub token with `read:packages`):

```bash
echo "@0xzunid:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN" >> ~/.npmrc
npm install @0xzunid/0xzunid-muse
```

## Usage

```js
const { ethers } = require('ethers');
const pkg = require('@0xzunid/0xzunid-muse');

// Static lookup — no network call
pkg.resolveName('arc', '0xzunid');
// => '0x0B22789619E4c035b3A7280C97f3BE87f7A0b981'
pkg.resolveName('liteforge', 'muse');
// => '0x3a114895Dc50F4163249cC5265Ae42E1b4a74D05'
pkg.resolveName('sepolia', '0xzunid');
// => null (no registry on Sepolia)

pkg.primaryName('liteforge', pkg.addresses.wallets.privy);
// => '0xzunid'

// Live onchain read with ethers v6
const provider = new ethers.JsonRpcProvider(pkg.rpcs.arc);
const registry = new ethers.Contract(
  pkg.addresses.chains.arc.registry,
  pkg.abis.registry,
  provider
);
await registry.resolve('0xzunid');
// => '0x0B22789619E4c035b3A7280C97f3BE87f7A0b981'

// Token balance
const znd = new ethers.Contract(
  pkg.addresses.chains.arc.tokens.ZND.address,
  pkg.abis.erc20,
  provider
);
await znd.balanceOf(pkg.addresses.wallets.privy);
// => 500000000000000000000000n (500,000 ZND)
```

## Exports

- `addresses` — everything in `addresses.json`, grouped by chain
  (`arc`, `robinhood`, `liteforge`, `sepolia`): tokens, pools, registry,
  nameToken, chainId, rpc, explorer; plus `names`, `primaryNames`,
  `nameTokenIds`, `wallets` and `notes`.
- `abis` — `registry` (ZunidNameService), `nameToken` (ZunidNameToken),
  `erc20` (minimal standard ERC-20), `simpleAMM` (the real deployed
  SimpleAMM ABI: `buy`, `sell`, `getReserves`, `getBuyQuote`,
  `getSellQuote`, `addLiquidity`).
- `chainIds`, `rpcs`, `explorers` — per-chain maps.
- `resolveName(chain, name)` — static name → address lookup, `null` when unknown.
- `primaryName(chain, wallet)` — static primary-name lookup, `null` when unknown.

## Notes

- Token `0x2222…Af62` and pool `0xA995…0271` are the same address on ARC
  and Robinhood; token `0x942F…07fD` and pool `0xc715…D2D3` are the same
  address on all four chains — CREATE addresses are deterministic from
  deployer + nonce, and the nonce sequence was identical on each chain.
- `primaryName(Privy)` is still `zunid` on ARC and Robinhood;
  `setPrimary("0xzunid")` there needs a signature from Privy itself
  (pending). On LiteForge it is already `0xzunid`.
- Sepolia RPC in this package is the public PublicNode endpoint
  (`https://ethereum-sepolia-rpc.publicnode.com`); swap it for your own if
  you prefer.
- Pool reserves are live state and are intentionally **not** in this
  package — read them onchain with `simpleAMM.getReserves()`.

## License

MIT — see `LICENSE`.
