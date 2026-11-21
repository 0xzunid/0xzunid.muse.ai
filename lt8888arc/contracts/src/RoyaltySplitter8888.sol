// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interfaces.sol";

/**
 * @title 8888LuckyLotteryTicket RoyaltySplitter
 * @notice Receives the 5% ERC-2981 royalties (it is the token's
 *         royalty receiver) and splits every payment 50/50 on receipt:
 *         half to the deployer, half to PrizePool8888 to fund future
 *         rounds. Odd wei goes to the deployer (pool share rounds down).
 *         Payments are in native USDC on Arc.
 */
contract RoyaltySplitter8888 {
    address public immutable deployer;
    address public immutable pool;

    event Split(address indexed from, uint256 deployerShare, uint256 poolShare);

    constructor(address deployer_, address pool_) {
        require(deployer_ != address(0), "Zero deployer");
        require(pool_ != address(0), "Zero pool");
        deployer = deployer_;
        pool = pool_;
    }

    /// @notice Split an explicit payment 50/50.
    function split() external payable {
        _split(msg.value);
    }

    /// @notice Split plain native-token transfers (royalty payouts) 50/50.
    receive() external payable {
        _split(msg.value);
    }

    function _split(uint256 total) internal {
        require(total > 0, "Nothing to split");
        uint256 poolShare = total / 2;
        uint256 deployerShare = total - poolShare;
        IPrizePool8888(pool).deposit{value: poolShare}();
        (bool ok, ) = deployer.call{value: deployerShare}("");
        require(ok, "Deployer payout failed");
        emit Split(msg.sender, deployerShare, poolShare);
    }
}
