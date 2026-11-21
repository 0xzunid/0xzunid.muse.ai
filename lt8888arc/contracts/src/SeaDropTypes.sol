// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SeaDropTypes — SeaDrop drop-config structs + minimal interfaces
 * @notice Written from the public SeaDrop interface specification
 *         (ProjectOpenSea/seadrop). Struct field order and types match
 *         SeaDrop's ABI exactly, so calls from this token into the
 *         deployed SeaDrop contract encode correctly.
 * @dev The deployed SeaDrop on Arc mainnet is
 *      0x00005EA00Ac477B1030CE78506496e8C2dE24BF5 (v1). It checks
 *      supportsInterface(0x1890fe8e) — the v1 INonFungibleSeaDropToken
 *      interface id, verified from the deployed bytecode — before
 *      accepting any drop configuration from a token contract.
 */
struct PublicDrop {
    uint80 mintPrice;
    uint48 startTime;
    uint48 endTime;
    uint16 maxTotalMintableByWallet;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct TokenGatedDropStage {
    uint80 mintPrice;
    uint16 maxTotalMintableByWallet;
    uint48 startTime;
    uint48 endTime;
    uint8 dropStageIndex;
    uint32 maxTokenSupplyForStage;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

struct AllowListData {
    bytes32 merkleRoot;
    string[] publicKeyURIs;
    string allowListURI;
}

struct SignedMintValidationParams {
    uint80 minMintPrice;
    uint24 maxMaxTotalMintableByWallet;
    uint40 minStartTime;
    uint40 maxEndTime;
    uint40 maxMaxTokenSupplyForStage;
    uint16 minFeeBps;
    uint16 maxFeeBps;
}

struct SeaDropRoyaltyInfo {
    address royaltyAddress;
    uint96 royaltyBps;
}

/// @notice Minimal SeaDrop-side interface: only the drop-configuration
///         functions this token forwards to. Called by the token owner
///         through the token's update* functions.
interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata publicDrop) external;
    function updateAllowList(AllowListData calldata allowListData) external;
    function updateTokenGatedDrop(address allowedNftToken, TokenGatedDropStage calldata dropStage) external;
    function updateDropURI(string calldata dropURI) external;
    function updateCreatorPayoutAddress(address payoutAddress) external;
    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external;
    function updateSignedMintValidationParams(address signer, SignedMintValidationParams calldata params) external;
    function updatePayer(address payer, bool allowed) external;
}
