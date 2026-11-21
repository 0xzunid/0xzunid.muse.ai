// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../src/LuckyLottery8888V2.sol";

/**
 * @notice Paid stand-in for the deployed SeaDrop contract, for v2
 *         tests and testnet E2E only. It replicates SeaDrop's exact
 *         payment flow (verified against ProjectOpenSea/seadrop
 *         SeaDrop.sol):
 *         - mintPublic(nftContract, feeRecipient, minterIfNotPayer,
 *           quantity) payable: drop must be active (startTime <= now
 *           <= endTime, NO zero-guard), msg.value must equal
 *           quantity * mintPrice exactly, per-wallet + supply caps
 *           via getMintStats(), then token.mintSeaDrop(), then
 *           _splitPayout: feeBps of the payment goes to the
 *           feeRecipient the MINTER passes in, the rest goes to the
 *           creator payout address.
 *         - The creator payout address MUST be set first via
 *           updateCreatorPayoutAddress (only callable by the token
 *           contract — mirrors SeaDrop's onlyINonFungibleSeaDropToken);
 *           otherwise paid mints revert, exactly like the real
 *           SeaDrop's CreatorPayoutAddressCannotBeZeroAddress.
 *         - updatePublicDrop records the drop config (mintPrice,
 *           window, caps, feeBps).
 */
contract MockSeaDropV2 {
    PublicDrop public lastPublicDrop;
    bool public gotPublicDrop;
    mapping(address => address) public creatorPayoutAddress;

    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable {
        require(
            IERC165(nftContract).supportsInterface(0x1890fe8e),
            "token does not support SeaDrop v1 interface"
        );
        // Replicates SeaDrop's _checkActive exactly (SeaDrop.sol): the
        // drop is active only while startTime <= now <= endTime, with
        // NO zero-guard — endTime 0 means the drop is PERMANENTLY
        // closed, not open-ended. Only enforced once a drop has been
        // configured.
        if (gotPublicDrop) {
            require(
                block.timestamp >= lastPublicDrop.startTime
                    && block.timestamp <= lastPublicDrop.endTime,
                "Drop not active"
            );
            // Replicates _checkCorrectPayment: exact payment only.
            require(
                msg.value == quantity * lastPublicDrop.mintPrice,
                "IncorrectPayment"
            );
        }
        address minter = minterIfNotPayer != address(0) ? minterIfNotPayer : msg.sender;
        (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply) =
            ISeaDropToken(nftContract).getMintStats(minter);
        require(quantity + minterNumMinted <= 5, "exceeds per-wallet cap");
        require(quantity + currentTotalSupply <= maxSupply, "exceeds max supply");
        ISeaDropToken(nftContract).mintSeaDrop(minter, quantity);

        // Replicates _splitPayout (only when there is a price).
        if (gotPublicDrop && lastPublicDrop.mintPrice != 0) {
            address payout = creatorPayoutAddress[nftContract];
            require(payout != address(0), "CreatorPayoutAddressCannotBeZeroAddress");
            uint256 feeAmount = (msg.value * lastPublicDrop.feeBps) / 10000;
            uint256 payoutAmount = msg.value - feeAmount;
            if (feeAmount > 0) {
                (bool okFee, ) = feeRecipient.call{value: feeAmount}("");
                require(okFee, "Fee payout failed");
            }
            (bool okPay, ) = payout.call{value: payoutAmount}("");
            require(okPay, "Creator payout failed");
        }
    }

    /// @notice Mirrors SeaDrop.updateCreatorPayoutAddress: only the
    ///         token contract itself may call it.
    function updateCreatorPayoutAddress(address payoutAddress) external {
        require(
            IERC165(msg.sender).supportsInterface(0x1890fe8e),
            "Only token contract"
        );
        require(payoutAddress != address(0), "CreatorPayoutAddressCannotBeZeroAddress");
        creatorPayoutAddress[msg.sender] = payoutAddress;
    }

    function updatePublicDrop(PublicDrop calldata publicDrop) external {
        lastPublicDrop = publicDrop;
        gotPublicDrop = true;
    }
    function updateAllowList(AllowListData calldata) external {}
    function updateTokenGatedDrop(address, TokenGatedDropStage calldata) external {}
    function updateDropURI(string calldata) external {}
    function updateAllowedFeeRecipient(address, bool) external {}
    function updateSignedMintValidationParams(address, SignedMintValidationParams calldata) external {}
    function updatePayer(address, bool) external {}
}
