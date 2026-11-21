// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LuckyLottery8888V3.sol";
import "../src/PrizePool8888.sol";
import "../src/RoyaltySplitter8888.sol";
import "../src/MintFeeSplitter8888.sol";

/**
 * @notice Deploy 8888LuckyLotteryTicket V2 on Arc MAINNET.
 * @dev V3 = paid mint + multiConfigure (0.08888 USDC/ticket, 88.88/11.12 split).
 *      Deploys PrizePool8888 -> MintFeeSplitter8888 ->
 *      RoyaltySplitter8888 -> LuckyLottery8888V3, wires the pool,
 *      commits Round 1 by its public commitment hash. The winner
 *      lists themselves are drawn offline and NEVER published here
 *      (they are revealed only through the contract's revealRound).
 *      The token's
 *      allowed SeaDrop is the Arc MAINNET SeaDrop address.
 *      Run ONLY after closing the v1 drop (CloseOldDrop.s.sol) and
 *      ONLY with the user's confirmation: v1 already has 10 minted
 *      tickets (IDs 1-5 to 0x4105e170E6E60F8874CE5D32553B1591798f3bA2,
 *      IDs 6-10 to 0xcC997b58dB9C2B0d6C71B90e2434f8f73275E34c, all free
 *      via SeaDrop before the drop was closed) that stay on the
 *      abandoned v1 contract.
 *      Env: PRIVATE_KEY (burner key, never printed).
 */
contract DeployMainnetV3 is Script {
    address constant BURNER = 0x3a114895Dc50F4163249cC5265Ae42E1b4a74D05;
    address constant SEADROP_ARC = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    string constant BASE_URI = "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/";
    string constant CONTRACT_URI =
        "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/collection.json";

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        // Round 1 winner lists are drawn offline and kept SECRET until the
        // reveal — only their keccak256 commitment is public (and on-chain).
        bytes32 commitment = 0x552a35d12537d5386ae6685b6aead96bd28dda067b2808a00c30912b92c30980;
        console.log("Round 1 (MAINNET V3) winners commitment:");
        console.logBytes32(commitment);

        vm.startBroadcast(pk);
        PrizePool8888 pool = new PrizePool8888(BURNER);
        MintFeeSplitter8888 feeSplitter = new MintFeeSplitter8888(BURNER, address(pool));
        RoyaltySplitter8888 royaltySplitter = new RoyaltySplitter8888(BURNER, address(pool));
        address[] memory allowed = new address[](1);
        allowed[0] = SEADROP_ARC;
        LuckyLottery8888V3 token = new LuckyLottery8888V3(
            BURNER, address(royaltySplitter), address(pool), BASE_URI, CONTRACT_URI, allowed
        );
        pool.setToken(address(token));
        token.commitRound(1, commitment);
        vm.stopBroadcast();

        console.log("PrizePool8888:", address(pool));
        console.log("MintFeeSplitter8888:", address(feeSplitter));
        console.log("RoyaltySplitter8888:", address(royaltySplitter));
        console.log("LuckyLottery8888V3:", address(token));
        console.log("owner:", BURNER);
        console.log("mintFee (USDC): 0.08888");
        console.log("royaltyReceiver (splitter):", address(royaltySplitter));
        console.log("baseURI:", BASE_URI);
        console.log("contractURI:", CONTRACT_URI);
        console.log("allowedSeaDrop (Arc mainnet SeaDrop):", SEADROP_ARC);
    }
}
