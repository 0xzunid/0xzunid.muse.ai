// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../src/LuckyLottery8888.sol";

/**
 * @notice Minimal stand-in for the deployed SeaDrop contract, for
 *         tests and testnet E2E only. It replicates SeaDrop's exact
 *         token-side checks in the same order: ERC-165 interface
 *         check (0x1890fe8e, the id the deployed SeaDrop uses),
 *         getMintStats() cap checks, then mintSeaDrop(). It also
 *         records drop-config forwards.
 */
contract MockSeaDrop {
    PublicDrop public lastPublicDrop;
    bool public gotPublicDrop;

    function mintPublic(address nftContract, uint256 quantity) external payable {
        require(
            IERC165(nftContract).supportsInterface(0x1890fe8e),
            "token does not support SeaDrop v1 interface"
        );
        // Replicates SeaDrop's _checkActive exactly (SeaDrop.sol): the
        // drop is active only while startTime <= now <= endTime, with
        // NO zero-guard — endTime 0 means the drop is PERMANENTLY
        // closed, not open-ended. Open-ended = far-future endTime.
        // Only enforced once a drop has been configured.
        if (gotPublicDrop) {
            require(
                block.timestamp >= lastPublicDrop.startTime
                    && block.timestamp <= lastPublicDrop.endTime,
                "Drop not active"
            );
        }
        (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply) =
            ISeaDropToken(nftContract).getMintStats(msg.sender);
        require(quantity + minterNumMinted <= 5, "exceeds per-wallet cap");
        require(quantity + currentTotalSupply <= maxSupply, "exceeds max supply");
        ISeaDropToken(nftContract).mintSeaDrop(msg.sender, quantity);
    }

    function updatePublicDrop(PublicDrop calldata publicDrop) external {
        lastPublicDrop = publicDrop;
        gotPublicDrop = true;
    }
    function updateAllowList(AllowListData calldata) external {}
    function updateTokenGatedDrop(address, TokenGatedDropStage calldata) external {}
    function updateDropURI(string calldata) external {}
    function updateCreatorPayoutAddress(address) external {}
    function updateAllowedFeeRecipient(address, bool) external {}
    function updateSignedMintValidationParams(address, SignedMintValidationParams calldata) external {}
    function updatePayer(address, bool) external {}
}
