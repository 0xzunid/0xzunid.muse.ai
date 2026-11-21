// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LuckyLottery8888V3.sol";

/**
 * @notice Set the PAID public drop + creator payout + fee-recipient
 *         allowlist on Arc MAINNET V3 (run after DeployMainnetV3.s.sol).
 * @dev Four steps, all required before any paid SeaDrop mint works
 *      AND before OpenSea's publish can succeed:
 *      1) updateAllowedFeeRecipient(SEADROP, 0x0000a26b..., true) —
 *         the verified OpenSea fee recipient on Arc (seen in the v1
 *         mainnet mint) — and updateAllowedFeeRecipient(SEADROP,
 *         0xfCe4b311..., true) — the address OpenSea's publish data
 *         carries (signer slot); belt-and-braces in case it is the
 *         Arc fee recipient. Both are OpenSea-controlled.
 *      2) updateCreatorPayoutAddress(SEADROP, feeSplitter) — SeaDrop
 *         REVERTS paid mints while the creator payout is zero.
 *         The fee splitter divides SeaDrop's net 90% 88.88%
 *         deployer / 11.12% pool.
 *      3) updatePublicDrop(SEADROP, {mintPrice: 0.08888 USDC,
 *         startTime: now, endTime: 4102444800 (2100-01-01, open-ended
 *         — NOT 0, which would permanently close the drop),
 *         maxTotalMintableByWallet: 5, feeBps: 1000 (SeaDrop's own
 *         10% fee, taken off the top), restrictFeeRecipients: TRUE
 *         from the start — OpenSea's publish refuses a drop whose
 *         fee recipients are unrestricted (the v2 lesson, fixed
 *         on-chain 2026-11-22 02:00). Allowlist goes in FIRST so
 *         the drop is never live-but-unallowlisted.
 *      Env: PRIVATE_KEY, TOKEN, FEESPLITTER.
 */
contract SetDropMainnetV3 is Script {
    address constant SEADROP_ARC = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant SEA_FEE_RECIPIENT = 0x0000a26b00c1F0DF003000390027140000fAa719;
    address constant OPENSEA_PUBLISH_ADDR = 0xfCe4b31128100915f2980BBC3a08894Ee5e8F8C3;
    uint256 constant FEE = 0.08888 ether;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        LuckyLottery8888V3 token = LuckyLottery8888V3(vm.envAddress("TOKEN"));
        address feeSplitter = vm.envAddress("FEESPLITTER");

        vm.startBroadcast(pk);
        token.updateAllowedFeeRecipient(SEADROP_ARC, SEA_FEE_RECIPIENT, true);
        token.updateAllowedFeeRecipient(SEADROP_ARC, OPENSEA_PUBLISH_ADDR, true);
        token.updateCreatorPayoutAddress(SEADROP_ARC, feeSplitter);
        PublicDrop memory drop = PublicDrop({
            mintPrice: uint80(FEE),
            startTime: uint48(block.timestamp),
            endTime: uint48(4102444800), // 2100-01-01 — open-ended
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: true
        });
        token.updatePublicDrop(SEADROP_ARC, drop);
        vm.stopBroadcast();

        console.log("Fee recipients allowlisted:", SEA_FEE_RECIPIENT);
        console.log("Fee recipients allowlisted:", OPENSEA_PUBLISH_ADDR);
        console.log("Creator payout set to fee splitter:", feeSplitter);
        console.log("Public drop set on token:", address(token));
        console.log("mintPrice: 0.08888 USDC, startTime: now, endTime: 4102444800 (2100-01-01)");
        console.log("maxTotalMintableByWallet: 5, feeBps: 1000, restrictFeeRecipients: true");
    }
}
