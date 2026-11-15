'use strict';

/**
 * @0xzunid/0xzunid-muse — addresses, ABIs and chain config for the
 * 0xzunid muse testnet project (ARC, Robinhood Chain, LiteForge, Sepolia).
 *
 * Everything here is a static, verified onchain fact. This module makes
 * NO network calls — resolveName() is a static lookup of the registered
 * names recorded in addresses.json. For a live onchain read, use the
 * exported ABIs + RPCs with ethers (see README.md).
 */

const addresses = require('./addresses.json');
const registryAbi = require('./abis/registry.json');
const nameTokenAbi = require('./abis/nameToken.json');
const erc20Abi = require('./abis/erc20.json');
const simpleAMMAbi = require('./abis/simpleAMM.json');

const chainIds = {};
const rpcs = {};
const explorers = {};
for (const [key, chain] of Object.entries(addresses.chains)) {
  chainIds[key] = chain.chainId;
  rpcs[key] = chain.rpc;
  explorers[key] = chain.explorer;
}

/**
 * Static name lookup — no network call.
 * @param {string} chain - 'arc' | 'robinhood' | 'liteforge' | 'sepolia'
 * @param {string} name - '0xzunid' | 'zunid' | 'muse'
 * @returns {string|null} resolved address, or null when unknown.
 * Names only exist on arc / robinhood / liteforge (no registry on Sepolia).
 */
function resolveName(chain, name) {
  if (typeof chain !== 'string' || typeof name !== 'string') return null;
  const key = chain.toLowerCase();
  const chainData = addresses.chains[key];
  if (!chainData || !chainData.registry) return null;
  const resolved = addresses.names[name.toLowerCase()];
  return resolved || null;
}

/**
 * Static primary-name lookup (verified onchain at package build time).
 * @param {string} chain - 'arc' | 'robinhood' | 'liteforge'
 * @param {string} wallet - wallet address (checksummed or lowercase)
 * @returns {string|null} primary name, or null when unknown.
 */
function primaryName(chain, wallet) {
  if (typeof chain !== 'string' || typeof wallet !== 'string') return null;
  const primaries = addresses.primaryNames[chain.toLowerCase()];
  if (!primaries) return null;
  return primaries[wallet] || primaries[wallet.toLowerCase()] || null;
}

module.exports = {
  addresses,
  abis: {
    registry: registryAbi,
    nameToken: nameTokenAbi,
    erc20: erc20Abi,
    simpleAMM: simpleAMMAbi,
  },
  chainIds,
  rpcs,
  explorers,
  resolveName,
  primaryName,
};
