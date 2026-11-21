// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface PrizePool8888 exposes to the token.
interface IPrizePool8888 {
    function deposit() external payable;
    function snapshot(uint256 roundId, uint256 mintedWinners) external;
}

/// @notice Minimal interface the token exposes to PrizePool8888.
interface ILotteryToken {
    function ownerOf(uint256 tokenId) external view returns (address);
    function tierOf(uint256 roundId, uint256 tokenId) external view returns (uint8);
    function totalSupply() external view returns (uint256);
}
