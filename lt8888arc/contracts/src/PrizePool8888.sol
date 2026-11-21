// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Interfaces.sol";

/**
 * @title 8888LuckyLotteryTicket PrizePool — perpetual rounds
 * @notice Holds prize funds in native USDC (Arc's gas token): royalty
 *         income forwarded by the RoyaltySplitter, mint income (none
 *         while the mint is free), and any owner top-up. Each round
 *         snapshots the pool balance at reveal and splits it 70%
 *         winners / 30% dividends. Winner shares are fixed at reveal:
 *         golden = 80/2240, ember = 10/2240, spark = 1/2240 of the
 *         round's winner pool (2240 units total). Every other minted
 *         ticket claims an equal dividend: dividendPool /
 *         nonWinnerCount. Claims pay DIRECTLY to the token owner
 *         (no ERC-6551 vaults in this collection — the owner is paid,
 *         whoever holds the ticket at claim time). Claim window is 90
 *         days per round. No sweep: after a round's window ends,
 *         unclaimed funds stay in the pool and are captured by the next
 *         round's snapshot.
 * @dev Dividend denominator: nonWinnerCount = totalSupply at snapshot
 *      minus the number of winners actually minted (counted by the
 *      token at reveal). Exact in all cases, identical to
 *      (totalSupply - 888) at full sellout.
 */
contract PrizePool8888 is Ownable, ReentrancyGuard {
    uint256 public constant GOLDEN_WEIGHT = 80;
    uint256 public constant EMBER_WEIGHT = 10;
    uint256 public constant SPARK_WEIGHT = 1;
    uint256 public constant TOTAL_UNITS = 2240; // 8*80 + 80*10 + 800*1
    uint256 public constant WINNER_BPS = 7000; // 70% winners / 30% dividends
    uint256 public constant CLAIM_WINDOW = 90 days;

    struct Round {
        uint256 winnerPool;
        uint256 dividendPool;
        uint256 nonWinnerCount;
        uint256 revealTime;
        uint256 claimDeadline;
        bool snapshotTaken;
    }

    address public token;

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(uint256 => bool)) public claimed;
    mapping(uint256 => mapping(uint256 => bool)) public dividendClaimed;
    mapping(uint256 => uint256) public claimedCount;
    mapping(uint256 => uint256) public dividendClaimedCount;

    event Deposited(address indexed from, uint256 amount);
    event RoundSnapshot(
        uint256 indexed roundId,
        uint256 winnerPool,
        uint256 dividendPool,
        uint256 nonWinnerCount,
        uint256 claimDeadline
    );
    event Claimed(uint256 indexed roundId, uint256 indexed tokenId, address indexed owner, uint256 amount);
    event DividendClaimed(uint256 indexed roundId, uint256 indexed tokenId, address indexed owner, uint256 amount);

    constructor(address owner_) Ownable(owner_) {}

    /// @notice One-time wiring after the token is deployed. Owner only.
    function setToken(address token_) external onlyOwner {
        require(token == address(0), "Already set");
        require(token_ != address(0), "Zero address");
        token = token_;
    }

    /// @notice Open deposit: anyone may add prize funds (splitter, owner, anyone).
    function deposit() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Accept plain native-token transfers too (e.g. direct royalty payments).
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Called by the token's revealRound; fixes this round's pools.
    function snapshot(uint256 roundId, uint256 mintedWinners) external {
        require(msg.sender == token, "Only token");
        Round storage r = rounds[roundId];
        require(!r.snapshotTaken, "Snapshot taken");
        uint256 balance = address(this).balance;
        r.winnerPool = (balance * WINNER_BPS) / 10000;
        r.dividendPool = balance - r.winnerPool;
        r.nonWinnerCount = ILotteryToken(token).totalSupply() - mintedWinners;
        r.revealTime = block.timestamp;
        r.claimDeadline = block.timestamp + CLAIM_WINDOW;
        r.snapshotTaken = true;
        emit RoundSnapshot(roundId, r.winnerPool, r.dividendPool, r.nonWinnerCount, r.claimDeadline);
    }

    /// @notice Fixed winner share for a token ID in a round (0 for non-winners / pre-reveal).
    function shareFor(uint256 roundId, uint256 tokenId) public view returns (uint256) {
        Round storage r = rounds[roundId];
        if (!r.snapshotTaken) return 0;
        uint8 tier = ILotteryToken(token).tierOf(roundId, tokenId);
        uint256 weight;
        if (tier == 1) weight = GOLDEN_WEIGHT;
        else if (tier == 2) weight = EMBER_WEIGHT;
        else if (tier == 3) weight = SPARK_WEIGHT;
        else return 0;
        return (r.winnerPool * weight) / TOTAL_UNITS;
    }

    /// @notice Fixed dividend for a non-winner token ID in a round (0 for winners / pre-reveal).
    function dividendFor(uint256 roundId, uint256 tokenId) public view returns (uint256) {
        Round storage r = rounds[roundId];
        if (!r.snapshotTaken) return 0;
        if (ILotteryToken(token).tierOf(roundId, tokenId) != 0) return 0;
        if (r.nonWinnerCount == 0) return 0;
        return r.dividendPool / r.nonWinnerCount;
    }

    /**
     * @notice Pay the winner's share directly to the token owner.
     *         Anyone may call it; the funds land with whoever holds
     *         the ticket at claim time.
     */
    function claim(uint256 roundId, uint256 tokenId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(r.snapshotTaken, "Not revealed");
        require(block.timestamp <= r.claimDeadline, "Claim window closed");
        require(!claimed[roundId][tokenId], "Already claimed");
        address owner = ILotteryToken(token).ownerOf(tokenId);
        uint256 amount = shareFor(roundId, tokenId);
        require(amount > 0, "Not a winner");

        claimed[roundId][tokenId] = true;
        claimedCount[roundId]++;

        (bool ok, ) = owner.call{value: amount}("");
        require(ok, "Payout failed");
        emit Claimed(roundId, tokenId, owner, amount);
    }

    /**
     * @notice Pay a non-winner's dividend directly to the token owner.
     *         Winners cannot claim the dividend — they get the bigger
     *         tier prize instead.
     */
    function claimDividend(uint256 roundId, uint256 tokenId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(r.snapshotTaken, "Not revealed");
        require(block.timestamp <= r.claimDeadline, "Claim window closed");
        require(!dividendClaimed[roundId][tokenId], "Already claimed");
        address owner = ILotteryToken(token).ownerOf(tokenId);
        require(ILotteryToken(token).tierOf(roundId, tokenId) == 0, "Winner cannot claim dividend");
        uint256 amount = dividendFor(roundId, tokenId);
        require(amount > 0, "No dividend");

        dividendClaimed[roundId][tokenId] = true;
        dividendClaimedCount[roundId]++;

        (bool ok, ) = owner.call{value: amount}("");
        require(ok, "Payout failed");
        emit DividendClaimed(roundId, tokenId, owner, amount);
    }
}
