// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces.sol";

/**
 * @title 8888LuckyLotteryTicket MintFeeSplitter (v2)
 * @notice Receives mint-fee proceeds and splits every payment
 *         88.88% deployer / 11.12% prize pool on receipt — the
 *         FireUn split. Two income paths feed it:
 *         (1) SeaDrop mints: it is the token's creator payout
 *         address (set via updateCreatorPayoutAddress), so SeaDrop
 *         sends it the mint proceeds net of SeaDrop's own 10% fee.
 *         (2) Direct payments (split() / plain transfers).
 *         Odd wei goes to the deployer (pool share rounds down):
 *         deployerShare = total * 8888 / 10000, poolShare = rest.
 *         Payments are in native USDC on Arc.
 * @dev NOT the royalty splitter: RoyaltySplitter8888 stays 50/50
 *      for the 5% ERC-2981 royalties. This contract is only for the
 *      0.08888 USDC-per-ticket mint fee.
 */
contract MintFeeSplitter8888 {
    address public immutable deployer;
    address public immutable pool;

    uint256 public constant DEPLOYER_BPS = 8888; // 88.88%
    uint256 public constant POOL_BPS = 1112; // 11.12%

    event Split(address indexed from, uint256 deployerShare, uint256 poolShare);

    constructor(address deployer_, address pool_) {
        require(deployer_ != address(0), "Zero deployer");
        require(pool_ != address(0), "Zero pool");
        deployer = deployer_;
        pool = pool_;
    }

    /// @notice Split an explicit payment 88.88/11.12.
    function split() external payable {
        _split(msg.value);
    }

    /// @notice Split plain native-token transfers (SeaDrop creator payouts) 88.88/11.12.
    receive() external payable {
        _split(msg.value);
    }

    function _split(uint256 total) internal {
        require(total > 0, "Nothing to split");
        uint256 deployerShare = (total * DEPLOYER_BPS) / 10000;
        uint256 poolShare = total - deployerShare;
        IPrizePool8888(pool).deposit{value: poolShare}();
        (bool ok, ) = deployer.call{value: deployerShare}("");
        require(ok, "Deployer payout failed");
        emit Split(msg.sender, deployerShare, poolShare);
    }
}
