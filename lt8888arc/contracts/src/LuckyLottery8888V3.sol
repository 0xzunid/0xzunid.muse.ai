// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./SeaDropTypes.sol";
import "./Interfaces.sol";

/**
 * @notice The full SeaDrop token interface (current spec). Its
 *         interface id is 0x4a7369f3. The SeaDrop v1 contract actually
 *         deployed on Arc mainnet checks 0x1890fe8e instead (verified
 *         from its bytecode), so supportsInterface() answers true for
 *         both ids.
 */
interface ISeaDropTokenV3 {
    error OnlyAllowedSeaDrop();
    event AllowedSeaDropUpdated(address[] allowedSeaDrop);
    event SeaDropTokenDeployed();
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event ContractURIUpdated(string newContractURI);
    event ContractURIUpdated();
    event ProvenanceHashUpdated(bytes32 previousHash, bytes32 newHash);
    event RoyaltyInfoUpdated(address receiver, uint256 bps);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setBaseURI(string calldata newBaseURI) external;
    function setContractURI(string calldata newContractURI) external;
    function setMaxSupply(uint256 newMaxSupply) external;
    function setProvenanceHash(bytes32 newProvenanceHash) external;
    function setRoyaltyInfo(SeaDropRoyaltyInfo calldata newInfo) external;
    function baseURI() external view returns (string memory);
    function contractURI() external view returns (string memory);
    function maxSupply() external view returns (uint256);
    function provenanceHash() external view returns (bytes32);
    function royaltyAddress() external view returns (address);
    function royaltyBasisPoints() external view returns (uint256);
    // IERC2981 (inherited by the reference metadata interface):
    // its selector is part of the interface id.
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop) external;
    function mintSeaDrop(address minter, uint256 quantity) external;
    function getMintStats(address minter)
        external
        view
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply_);
    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external;
    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData) external;
    function updateTokenGatedDrop(address seaDropImpl, address allowedNftToken, TokenGatedDropStage calldata dropStage) external;
    function updateDropURI(address seaDropImpl, string calldata dropURI) external;
    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) external;
    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed) external;
    function updateSignedMintValidationParams(address seaDropImpl, address signer, SignedMintValidationParams memory params) external;
    function updatePayer(address seaDropImpl, address payer, bool allowed) external;
}


/**
 * @notice The standard SeaDrop multiConfigure struct (ProjectOpenSea/
 *         seadrop, ERC721SeaDropStructsErrorsAndEvents.sol). Field
 *         order and types match the canonical ABI exactly, so the
 *         multiConfigure selector is 0x911f456b — the selector
 *         OpenSea's Studio/API publish sends. PublicDrop,
 *         AllowListData, TokenGatedDropStage and
 *         SignedMintValidationParams come from SeaDropTypes.sol
 *         (identical definitions).
 */
struct MultiConfigureStruct {
    uint256 maxSupply;
    string baseURI;
    string contractURI;
    address seaDropImpl;
    PublicDrop publicDrop;
    string dropURI;
    AllowListData allowListData;
    address creatorPayoutAddress;
    bytes32 provenanceHash;
    address[] allowedFeeRecipients;
    address[] disallowedFeeRecipients;
    address[] allowedPayers;
    address[] disallowedPayers;
    address[] tokenGatedAllowedNftTokens;
    TokenGatedDropStage[] tokenGatedDropStages;
    address[] disallowedTokenGatedAllowedNftTokens;
    address[] signers;
    SignedMintValidationParams[] signedMintValidationParams;
    address[] disallowedSigners;
}

error TokenGatedMismatch();
error SignersMismatch();

/**
 * @title 8888LuckyLotteryTicket V3 — lottery-ticket NFT on Arc (SeaDrop-compatible)
 * @notice 8,888 supply. PAID mint: 0.08888 USDC per ticket (corrected
 *         2026-11-22 — the user said 0.18 USDC was too expensive),
 *         5 per wallet, no mint price deadline. Mint fee splits
 *         88.88% deployer / 11.12% prize pool (FireUn numbers), on
 *         BOTH mint paths:
 *         - Direct mint(): the minter pays count * MINT_FEE in native
 *           USDC; the token splits it inline, FireUn-style (deployer
 *           share -> owner, pool share -> PrizePool8888).
 *         - SeaDrop mintSeaDrop(): SeaDrop collects the same
 *           0.08888/ticket, keeps its 10% fee, and sends the net 90%
 *           to the creator payout address, which MUST be the
 *           MintFeeSplitter8888 (set via updateCreatorPayoutAddress);
 *           the splitter divides that net 88.88/11.12. The token
 *           itself never touches SeaDrop-path money.
 *         Every round: 888 winning token IDs (8 GOLDEN + 80 EMBER +
 *         800 SPARK), committed by hash per round and revealed by the
 *         owner only if the lists match the commitment. Tier flags are
 *         stored PER ROUND as a 2-bit-per-token bitmap (~70 storage
 *         slots per reveal instead of 888), so the reveal stays cheap.
 *         Winners claim from PrizePool8888 (paid in native USDC, direct
 *         to the token owner); every other minted ticket claims a
 *         dividend from the same round's pool. Royalties: 5% ERC-2981
 *         to the RoyaltySplitter (50% deployer / 50% prize pool).
 *         SeaDrop: this contract implements the SeaDrop token
 *         interface, so OpenSea's drop system can mint through it and
 *         the collection shows a Mint button on OpenSea. SeaDrop's fee
 *         is 10% of mint price. Direct mint() (our own mint page) and
 *         mintSeaDrop() (OpenSea) share one per-wallet cap of 5.
 *         tokenURI is per-token: baseURI + tokenId + ".json".
 *         Art: gold/purple "Lucky Lottery 8888" — image LLT.jpg,
 *         animation lucky-lottery-8888-3d.mp4, hosted on GitHub Pages.
 * @dev V3 replaces the v2 paid-mint contracts (deployed on Arc
 *      mainnet 2026-11-22, token 0x8ee85e0E8B93bF8b2e3CFC6b45cb81D8a0989208)
 *      for ONE reason only: v2 had no multiConfigure function, so
 *      OpenSea's publish tx (multiConfigure, selector 0x911f456b)
 *      reverted in the fallback and no Mint button could ever appear
 *      on the v2 collection (failed publish tx 0x8f010d6e...,
 *      2026-11-22). V3 is v2 + the standard SeaDrop multiConfigure
 *      (selector 0x911f456b, verified against ProjectOpenSea/seadrop),
 *      delegating to the existing individual updaters. All lottery
 *      logic, fees, caps and metadata are IDENTICAL to v2. V2 has
 *      0 mints (totalSupply 0) so nothing is stranded by the move.
 */
contract LuckyLottery8888V3 is ERC721Enumerable, ERC2981, Ownable, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY_LIMIT = 8888;
    uint256 public constant MAX_PER_WALLET = 5;
    uint256 public constant GOLDEN_COUNT = 8;
    uint256 public constant EMBER_COUNT = 80;
    uint256 public constant SPARK_COUNT = 800;

    /// @notice Mint fee per ticket: 0.08888 USDC (native, 18 decimals).
    uint256 public constant MINT_FEE = 0.08888 ether;
    /// @notice Mint-fee split (FireUn numbers): 88.88% deployer.
    uint256 public constant DEPLOYER_BPS = 8888;
    /// @notice Mint-fee split: 11.12% prize pool.
    uint256 public constant POOL_BPS = 1112;

    uint8 public constant TIER_NONE = 0;
    uint8 public constant TIER_GOLDEN = 1;
    uint8 public constant TIER_EMBER = 2;
    uint8 public constant TIER_SPARK = 3;

    /// @notice SeaDrop v1 interface id, as checked by the SeaDrop
    ///         contract deployed on Arc mainnet (verified from its
    ///         bytecode: supportsInterface(0x1890fe8e)).
    bytes4 public constant SEADROP_V1_INTERFACE_ID = 0x1890fe8e;
    /// @notice SeaDrop contract on Arc mainnet (same address on
    ///         Robinhood mainnet, where CatteryRH used it).
    address public constant SEADROP_ARC_MAINNET = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    address public royaltyReceiver;
    address public prizePool;
    uint256 public maxSupply_;
    bytes32 public provenanceHash_;
    string private _baseTokenURI;
    string private _contractURI;
    uint256 private _nextTokenId = 1;

    mapping(address => uint256) public mintedPerWallet;
    mapping(address => bool) internal _allowedSeaDrop;
    address[] internal _enumeratedAllowedSeaDrop;

    mapping(uint256 => bytes32) public roundCommitment;
    mapping(uint256 => bool) public roundRevealed;
    /// @notice tierBitmap[roundId][wordIndex] — 2 bits per token ID
    ///         (0 none, 1 golden, 2 ember, 3 spark), 128 tokens per
    ///         256-bit word, word = tokenId / 128.
    mapping(uint256 => mapping(uint256 => uint256)) public tierBitmap;

    event Minted(address indexed minter, uint256[] tokenIds);
    event SeaDropMinted(address indexed minter, uint256[] tokenIds);
    event RoundCommitted(uint256 indexed roundId, bytes32 commitment);
    event RoundRevealed(uint256 indexed roundId, uint256[] golden, uint256[] ember, uint256[] spark);

    constructor(
        address owner_,
        address royaltyReceiver_,
        address prizePool_,
        string memory baseURI_,
        string memory contractURI_,
        address[] memory allowedSeaDrop_
    ) ERC721("8888LuckyLotteryTicket", "8888LLT") Ownable(owner_) {
        royaltyReceiver = royaltyReceiver_;
        prizePool = prizePool_;
        maxSupply_ = MAX_SUPPLY_LIMIT;
        _baseTokenURI = baseURI_;
        _contractURI = contractURI_;
        _setDefaultRoyalty(royaltyReceiver_, 500); // 5% ERC-2981
        for (uint256 i = 0; i < allowedSeaDrop_.length; i++) {
            _allowedSeaDrop[allowedSeaDrop_[i]] = true;
        }
        _enumeratedAllowedSeaDrop = allowedSeaDrop_;
        emit ISeaDropTokenV3.SeaDropTokenDeployed();
    }

    // ------------------------------------------------------------------
    // Direct mint (our own mint page) — PAID 0.08888 USDC/ticket,
    // 5 per wallet. Fee splits 88.88% deployer (owner) / 11.12%
    // prize pool, FireUn-style, inline on receipt.
    // ------------------------------------------------------------------

    function mint(uint256 count) external payable nonReentrant {
        require(count > 0 && count <= MAX_PER_WALLET, "Invalid count");
        require(mintedPerWallet[msg.sender] + count <= MAX_PER_WALLET, "Wallet cap exceeded");
        require(totalSupply() + count <= maxSupply_, "Sold out");
        require(msg.value == count * MINT_FEE, "Wrong fee");

        uint256 deployerShare = (msg.value * DEPLOYER_BPS) / 10000;
        uint256 poolShare = msg.value - deployerShare;

        mintedPerWallet[msg.sender] += count;
        uint256[] memory tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
            tokenIds[i] = tokenId;
        }

        (bool ok1, ) = owner().call{value: deployerShare}("");
        require(ok1, "Deployer payout failed");
        IPrizePool8888(prizePool).deposit{value: poolShare}();

        emit Minted(msg.sender, tokenIds);
    }

    // ------------------------------------------------------------------
    // SeaDrop integration
    // ------------------------------------------------------------------

    function _onlyAllowedSeaDrop(address seaDrop) internal view {
        if (!_allowedSeaDrop[seaDrop]) revert ISeaDropTokenV3.OnlyAllowedSeaDrop();
    }

    /// @notice Owner or the contract itself. multiConfigure forwards
    ///         via this.* (external calls), so the updaters must accept
    ///         the contract as caller — exactly like the standard
    ///         ERC721SeaDrop template's _onlyOwnerOrSelf(). Access
    ///         control is unchanged: only the owner can call
    ///         multiConfigure in the first place.
    function _onlyOwnerOrSelf() internal view {
        require(msg.sender == owner() || msg.sender == address(this), "Not owner or self");
    }

    /// @notice Update the allowed SeaDrop contracts. Owner only.
    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop) external onlyOwner {
        for (uint256 i = 0; i < _enumeratedAllowedSeaDrop.length; i++) {
            _allowedSeaDrop[_enumeratedAllowedSeaDrop[i]] = false;
        }
        for (uint256 i = 0; i < allowedSeaDrop.length; i++) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
        }
        _enumeratedAllowedSeaDrop = allowedSeaDrop;
        emit ISeaDropTokenV3.AllowedSeaDropUpdated(allowedSeaDrop);
    }

    function getAllowedSeaDrop() external view returns (address[] memory) {
        return _enumeratedAllowedSeaDrop;
    }

    /**
     * @notice Mint tokens, restricted to an allowed SeaDrop contract.
     * @dev Counts are updated BEFORE _safeMint (SeaDrop's reentrancy
     *      note): SeaDrop reads getMintStats() to enforce its own
     *      per-wallet and supply checks, so the numbers must already
     *      be final when the tokens move. Payment is handled entirely
     *      by SeaDrop: the minter pays quantity * MINT_FEE to SeaDrop,
     *      SeaDrop keeps its 10% fee and sends the net 90% to the
     *      creator payout address — which MUST be the
     *      MintFeeSplitter8888 (set via updateCreatorPayoutAddress),
     *      or paid mints revert in SeaDrop (creator payout zero).
     *      The token itself receives no value on this path.
     */
    function mintSeaDrop(address minter, uint256 quantity) external nonReentrant {
        _onlyAllowedSeaDrop(msg.sender);
        require(quantity > 0, "Zero quantity");
        require(totalSupply() + quantity <= maxSupply_, "Sold out");
        require(mintedPerWallet[minter] + quantity <= MAX_PER_WALLET, "Wallet cap exceeded");

        mintedPerWallet[minter] += quantity;
        uint256[] memory tokenIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(minter, tokenId);
            tokenIds[i] = tokenId;
        }
        emit SeaDropMinted(minter, tokenIds);
    }

    /// @notice Mint stats SeaDrop uses to enforce its limits.
    function getMintStats(address minter)
        external
        view
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupplyOut)
    {
        minterNumMinted = mintedPerWallet[minter];
        currentTotalSupply = totalSupply();
        maxSupplyOut = maxSupply_;
    }

    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updatePublicDrop(publicDrop);
    }

    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowList(allowListData);
    }

    function updateTokenGatedDrop(address seaDropImpl, address allowedNftToken, TokenGatedDropStage calldata dropStage)
        external
    {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateTokenGatedDrop(allowedNftToken, dropStage);
    }

    function updateDropURI(address seaDropImpl, string calldata dropURI) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateDropURI(dropURI);
    }

    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    function updateSignedMintValidationParams(address seaDropImpl, address signer, SignedMintValidationParams memory params)
        external
    {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateSignedMintValidationParams(signer, params);
    }

    function updatePayer(address seaDropImpl, address payer, bool allowed) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updatePayer(payer, allowed);
    }

    // ------------------------------------------------------------------
    // Standard SeaDrop multiConfigure (V3 only)
    // ------------------------------------------------------------------

    /// @notice Standard SeaDrop multiConfigure (selector 0x911f456b) —
    ///         the single-call config OpenSea's Studio/API publish
    ///         sends. Applies the drop draft's edits: max supply,
    ///         base/contract URI, public drop, drop URI, allow list,
    ///         creator payout, provenance hash, fee recipients,
    ///         payers, token-gated stages, and signed-mint signers.
    ///         Only the owner may call it; it forwards to this
    ///         token's own updaters (owner-or-self).
    /// @dev Logic mirrors ProjectOpenSea/seadrop ERC721SeaDrop.
    ///      multiConfigure verbatim: empty strings / zero values are
    ///      skipped, so a publish only changes what the draft sets.
    function multiConfigure(MultiConfigureStruct calldata config) external onlyOwner {
        if (config.tokenGatedAllowedNftTokens.length != config.tokenGatedDropStages.length) {
            revert TokenGatedMismatch();
        }
        if (config.signers.length != config.signedMintValidationParams.length) {
            revert SignersMismatch();
        }
        if (config.maxSupply > 0) {
            this.setMaxSupply(config.maxSupply);
        }
        if (bytes(config.baseURI).length != 0) {
            this.setBaseURI(config.baseURI);
        }
        if (bytes(config.contractURI).length != 0) {
            this.setContractURI(config.contractURI);
        }
        if (config.publicDrop.startTime != 0 || config.publicDrop.endTime != 0) {
            this.updatePublicDrop(config.seaDropImpl, config.publicDrop);
        }
        if (bytes(config.dropURI).length != 0) {
            this.updateDropURI(config.seaDropImpl, config.dropURI);
        }
        if (config.allowListData.merkleRoot != bytes32(0)) {
            this.updateAllowList(config.seaDropImpl, config.allowListData);
        }
        if (config.creatorPayoutAddress != address(0)) {
            this.updateCreatorPayoutAddress(config.seaDropImpl, config.creatorPayoutAddress);
        }
        if (config.provenanceHash != bytes32(0)) {
            this.setProvenanceHash(config.provenanceHash);
        }
        if (config.allowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < config.allowedFeeRecipients.length;) {
                this.updateAllowedFeeRecipient(config.seaDropImpl, config.allowedFeeRecipients[i], true);
                unchecked { ++i; }
            }
        }
        if (config.disallowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < config.disallowedFeeRecipients.length;) {
                this.updateAllowedFeeRecipient(config.seaDropImpl, config.disallowedFeeRecipients[i], false);
                unchecked { ++i; }
            }
        }
        if (config.allowedPayers.length > 0) {
            for (uint256 i = 0; i < config.allowedPayers.length;) {
                this.updatePayer(config.seaDropImpl, config.allowedPayers[i], true);
                unchecked { ++i; }
            }
        }
        if (config.disallowedPayers.length > 0) {
            for (uint256 i = 0; i < config.disallowedPayers.length;) {
                this.updatePayer(config.seaDropImpl, config.disallowedPayers[i], false);
                unchecked { ++i; }
            }
        }
        if (config.tokenGatedDropStages.length > 0) {
            for (uint256 i = 0; i < config.tokenGatedDropStages.length;) {
                this.updateTokenGatedDrop(
                    config.seaDropImpl, config.tokenGatedAllowedNftTokens[i], config.tokenGatedDropStages[i]
                );
                unchecked { ++i; }
            }
        }
        if (config.disallowedTokenGatedAllowedNftTokens.length > 0) {
            for (uint256 i = 0; i < config.disallowedTokenGatedAllowedNftTokens.length;) {
                TokenGatedDropStage memory emptyStage;
                this.updateTokenGatedDrop(
                    config.seaDropImpl, config.disallowedTokenGatedAllowedNftTokens[i], emptyStage
                );
                unchecked { ++i; }
            }
        }
        if (config.signedMintValidationParams.length > 0) {
            for (uint256 i = 0; i < config.signedMintValidationParams.length;) {
                this.updateSignedMintValidationParams(
                    config.seaDropImpl, config.signers[i], config.signedMintValidationParams[i]
                );
                unchecked { ++i; }
            }
        }
        if (config.disallowedSigners.length > 0) {
            for (uint256 i = 0; i < config.disallowedSigners.length;) {
                SignedMintValidationParams memory emptyParams;
                this.updateSignedMintValidationParams(config.seaDropImpl, config.disallowedSigners[i], emptyParams);
                unchecked { ++i; }
            }
        }
    }

    // ------------------------------------------------------------------
    // SeaDrop token-contract metadata (owner-settable)
    // ------------------------------------------------------------------

    function setBaseURI(string calldata newBaseURI) external {
        _onlyOwnerOrSelf();
        _baseTokenURI = newBaseURI;
        emit ISeaDropTokenV3.BatchMetadataUpdate(1, maxSupply_);
    }

    function setContractURI(string calldata newContractURI) external {
        _onlyOwnerOrSelf();
        _contractURI = newContractURI;
        emit ISeaDropTokenV3.ContractURIUpdated(newContractURI);
        emit ISeaDropTokenV3.ContractURIUpdated();
    }

    function setMaxSupply(uint256 newMaxSupply) external {
        _onlyOwnerOrSelf();
        require(newMaxSupply >= totalSupply(), "Below minted");
        require(newMaxSupply <= MAX_SUPPLY_LIMIT, "Above limit");
        maxSupply_ = newMaxSupply;
        emit ISeaDropTokenV3.MaxSupplyUpdated(newMaxSupply);
    }

    function setProvenanceHash(bytes32 newProvenanceHash) external {
        _onlyOwnerOrSelf();
        require(totalSupply() == 0, "Mint started");
        bytes32 previousHash = provenanceHash_;
        provenanceHash_ = newProvenanceHash;
        emit ISeaDropTokenV3.ProvenanceHashUpdated(previousHash, newProvenanceHash);
    }

    function setRoyaltyInfo(SeaDropRoyaltyInfo calldata newInfo) external onlyOwner {
        require(newInfo.royaltyAddress != address(0), "Zero royalty address");
        require(newInfo.royaltyBps <= 10000, "Royalty bps too high");
        royaltyReceiver = newInfo.royaltyAddress;
        _setDefaultRoyalty(newInfo.royaltyAddress, newInfo.royaltyBps);
        emit ISeaDropTokenV3.RoyaltyInfoUpdated(newInfo.royaltyAddress, newInfo.royaltyBps);
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function maxSupply() external view returns (uint256) {
        return maxSupply_;
    }

    function provenanceHash() external view returns (bytes32) {
        return provenanceHash_;
    }

    function royaltyAddress() external view returns (address) {
        return royaltyReceiver;
    }

    function royaltyBasisPoints() external view returns (uint256) {
        // royaltyInfo(tokenId, salePrice) pays bps of the sale price,
        // so a 10,000-unit sale returns exactly the bps value.
        (, uint256 amount) = royaltyInfo(0, 10000);
        return amount;
    }

    // ------------------------------------------------------------------
    // Lottery: commit / reveal / tiers
    // ------------------------------------------------------------------

    /// @notice Per-token metadata URI: baseURI + tokenId + ".json".
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId), ".json"));
    }

    function tierOf(uint256 roundId, uint256 tokenId) external view returns (uint8) {
        return _tierOf(roundId, tokenId);
    }

    function _tierOf(uint256 roundId, uint256 tokenId) internal view returns (uint8) {
        uint256 word = tierBitmap[roundId][tokenId >> 7];
        return uint8((word >> ((tokenId & 127) * 2)) & 3);
    }

    function _setTier(uint256 roundId, uint256 tokenId, uint8 tier) internal {
        tierBitmap[roundId][tokenId >> 7] |= uint256(tier) << ((tokenId & 127) * 2);
    }

    /// @notice Lock a round's winner hash. Owner only, once per round.
    function commitRound(uint256 roundId, bytes32 commitment_) external onlyOwner {
        require(roundCommitment[roundId] == bytes32(0), "Already committed");
        roundCommitment[roundId] = commitment_;
        emit RoundCommitted(roundId, commitment_);
    }

    /**
     * @notice Publish a round's winner lists. All three lists must be
     *         strictly ascending (sorted, no duplicates, no overlap) and
     *         their hash must match the round's commitment, or this
     *         reverts. Callable once per round, by the owner only.
     *         Winner arrays are NOT stored on-chain (the lists live in
     *         this event); only the bitmap words holding winners are
     *         written (~70 cold SSTOREs max), which keeps the reveal
     *         cheap. Counts minted winners for the dividend denominator
     *         and snapshots the prize pool.
     */
    function revealRound(
        uint256 roundId,
        uint256[] calldata golden,
        uint256[] calldata ember,
        uint256[] calldata spark
    ) external onlyOwner {
        require(!roundRevealed[roundId], "Already revealed");
        require(roundCommitment[roundId] != bytes32(0), "Not committed");
        require(golden.length == GOLDEN_COUNT, "Need 8 golden");
        require(ember.length == EMBER_COUNT, "Need 80 ember");
        require(spark.length == SPARK_COUNT, "Need 800 spark");
        require(
            keccak256(abi.encode(golden, ember, spark)) == roundCommitment[roundId],
            "Commitment mismatch"
        );

        uint256 mintedWinners = 0;
        for (uint256 i = 0; i < golden.length; i++) {
            require(golden[i] >= 1 && golden[i] <= MAX_SUPPLY_LIMIT, "Golden out of range");
            if (i > 0) require(golden[i] > golden[i - 1], "Golden not sorted");
            _setTier(roundId, golden[i], TIER_GOLDEN);
            if (_ownerOf(golden[i]) != address(0)) mintedWinners++;
        }
        for (uint256 i = 0; i < ember.length; i++) {
            require(ember[i] >= 1 && ember[i] <= MAX_SUPPLY_LIMIT, "Ember out of range");
            if (i > 0) require(ember[i] > ember[i - 1], "Ember not sorted");
            require(_tierOf(roundId, ember[i]) == TIER_NONE, "Golden/ember overlap");
            _setTier(roundId, ember[i], TIER_EMBER);
            if (_ownerOf(ember[i]) != address(0)) mintedWinners++;
        }
        for (uint256 i = 0; i < spark.length; i++) {
            require(spark[i] >= 1 && spark[i] <= MAX_SUPPLY_LIMIT, "Spark out of range");
            if (i > 0) require(spark[i] > spark[i - 1], "Spark not sorted");
            require(_tierOf(roundId, spark[i]) == TIER_NONE, "Winner overlap");
            _setTier(roundId, spark[i], TIER_SPARK);
            if (_ownerOf(spark[i]) != address(0)) mintedWinners++;
        }

        roundRevealed[roundId] = true;
        IPrizePool8888(prizePool).snapshot(roundId, mintedWinners);
        emit RoundRevealed(roundId, golden, ember, spark);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return interfaceId == SEADROP_V1_INTERFACE_ID
            || interfaceId == type(ISeaDropTokenV3).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
