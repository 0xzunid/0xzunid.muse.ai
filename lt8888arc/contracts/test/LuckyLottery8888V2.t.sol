// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../src/LuckyLottery8888V2.sol";
import "./MockSeaDropV2.sol";
import "../src/PrizePool8888.sol";
import "../src/RoyaltySplitter8888.sol";
import "../src/MintFeeSplitter8888.sol";

/**
 * @notice Tests for LuckyLottery8888 V2 (paid mint, 0.08888 USDC/ticket).
 * @dev Fee math (all in wei, 18-decimal native USDC):
 *      MINT_FEE = 0.08888 ether = 88,880,000,000,000,000.
 *      Direct mint 1 ticket: deployer 88.88% = 78,996,544,000,000,000,
 *      pool 11.12% = 9,883,456,000,000,000.
 *      SeaDrop mint 1 ticket: minter pays 0.08888; SeaDrop keeps 10%
 *      (0.008888) for the feeRecipient, net 0.079992 goes to the
 *      MintFeeSplitter, which splits 88.88/11.12: deployer
 *      0.0710968896, pool 0.0088951104.
 */
contract LuckyLottery8888V2Test is Test {
    LuckyLottery8888V2 public token;
    PrizePool8888 public pool;
    RoyaltySplitter8888 public royaltySplitter;
    MintFeeSplitter8888 public feeSplitter;
    MockSeaDropV2 public seaDrop;

    address public deployer = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public feeRecipient = address(0xFEED);

    string constant BASE = "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/";
    string constant CONTRACT_URI = "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/collection.json";

    uint256 constant FEE = 0.08888 ether;

    bytes4 constant SEADROP_V1_ID = 0x1890fe8e;

    function setUp() public {
        vm.deal(deployer, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        seaDrop = new MockSeaDropV2();
        pool = new PrizePool8888(deployer);
        feeSplitter = new MintFeeSplitter8888(deployer, address(pool));
        royaltySplitter = new RoyaltySplitter8888(deployer, address(pool));
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDrop);
        token = new LuckyLottery8888V2(
            deployer, address(royaltySplitter), address(pool), BASE, CONTRACT_URI, allowed
        );
        vm.prank(deployer);
        pool.setToken(address(token));
    }

    /// @notice Point the mock SeaDrop's creator payout at the fee splitter.
    function _setPayout() internal {
        vm.prank(deployer);
        token.updateCreatorPayoutAddress(address(seaDrop), address(feeSplitter));
        assertEq(seaDrop.creatorPayoutAddress(address(token)), address(feeSplitter));
    }

    /// @notice Configure the paid public drop on the mock (mirrors the
    ///         mainnet SetDrop: mintPrice 0.08888, open-ended endTime
    ///         4102444800, max 5/wallet, feeBps 1000).
    function _setPaidDrop() internal {
        PublicDrop memory drop = PublicDrop({
            mintPrice: uint80(FEE),
            startTime: uint48(block.timestamp),
            endTime: uint48(4102444800),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        token.updatePublicDrop(address(seaDrop), drop);
        assertTrue(seaDrop.gotPublicDrop());
    }

    // -- deployment / metadata -----------------------------------------

    function testDeploymentV2() public view {
        assertEq(token.name(), "8888LuckyLotteryTicket");
        assertEq(token.symbol(), "8888LLT");
        assertEq(token.maxSupply(), 8888);
        assertEq(token.MINT_FEE(), FEE);
        assertEq(token.DEPLOYER_BPS(), 8888);
        assertEq(token.POOL_BPS(), 1112);
        assertEq(token.royaltyAddress(), address(royaltySplitter));
        assertEq(token.royaltyBasisPoints(), 500);
        assertEq(token.prizePool(), address(pool));
        assertEq(pool.token(), address(token));
        assertEq(feeSplitter.deployer(), deployer);
        assertEq(feeSplitter.pool(), address(pool));
        assertEq(feeSplitter.DEPLOYER_BPS(), 8888);
        assertEq(feeSplitter.POOL_BPS(), 1112);
        assertEq(token.supportsInterface(SEADROP_V1_ID), true);
    }

    // -- direct mint: exact fee + split ---------------------------------

    function testDirectMintSplitsFee() public {
        uint256 depBefore = deployer.balance;
        uint256 poolBefore = address(pool).balance;
        vm.prank(alice);
        token.mint{value: FEE}(1);
        assertEq(token.totalSupply(), 1);
        assertEq(token.ownerOf(1), alice);
        assertEq(deployer.balance - depBefore, 78_996_544_000_000_000);
        assertEq(address(pool).balance - poolBefore, 9_883_456_000_000_000);
    }

    function testDirectMintFiveSplitsFee() public {
        uint256 depBefore = deployer.balance;
        uint256 poolBefore = address(pool).balance;
        vm.prank(alice);
        token.mint{value: 5 * FEE}(5);
        assertEq(token.totalSupply(), 5);
        assertEq(deployer.balance - depBefore, 394_982_720_000_000_000);
        assertEq(address(pool).balance - poolBefore, 49_417_280_000_000_000);
    }

    function testDirectMintRejectsWrongFee() public {
        vm.prank(alice);
        vm.expectRevert("Wrong fee");
        token.mint(1); // 0 value
        vm.prank(alice);
        vm.expectRevert("Wrong fee");
        token.mint{value: FEE / 2}(1); // underpaid
        vm.prank(alice);
        vm.expectRevert("Wrong fee");
        token.mint{value: FEE * 2}(1); // overpaid for 1
        vm.prank(alice);
        vm.expectRevert("Wrong fee");
        token.mint{value: FEE}(2); // 1 fee for 2 tickets
    }

    function testDirectMintCapStillShared() public {
        vm.prank(alice);
        token.mint{value: 5 * FEE}(5);
        vm.prank(alice);
        vm.expectRevert("Wallet cap exceeded");
        token.mint{value: FEE}(1);
    }

    // -- mint fee splitter ------------------------------------------------

    function testFeeSplitter88_88_11_12() public {
        uint256 depBefore = deployer.balance;
        uint256 poolBefore = address(pool).balance;
        (bool ok,) = address(feeSplitter).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(deployer.balance - depBefore, 0.8888 ether);
        assertEq(address(pool).balance - poolBefore, 0.1112 ether);
    }

    function testFeeSplitterOddWei() public {
        uint256 depBefore = deployer.balance;
        (bool ok,) = address(feeSplitter).call{value: 101}("");
        assertTrue(ok);
        // deployerShare = 101 * 8888 / 10000 = 89; pool gets the rest (12).
        assertEq(deployer.balance - depBefore, 89);
        assertEq(address(pool).balance, 12);
    }

    function testFeeSplitterSplitFunction() public {
        uint256 depBefore = deployer.balance;
        feeSplitter.split{value: FEE}();
        assertEq(deployer.balance - depBefore, 78_996_544_000_000_000);
        assertEq(address(pool).balance, 9_883_456_000_000_000);
    }

    // -- SeaDrop path: paid mint + split ----------------------------------

    function testSeaDropMintSplitsFee() public {
        _setPayout();
        _setPaidDrop();
        uint256 depBefore = deployer.balance;
        uint256 poolBefore = address(pool).balance;
        uint256 feeBefore = feeRecipient.balance;
        vm.prank(alice);
        seaDrop.mintPublic{value: 3 * FEE}(address(token), feeRecipient, address(0), 3);
        assertEq(token.totalSupply(), 3);
        assertEq(token.balanceOf(alice), 3);
        // 3 tickets: paid 0.26664. SeaDrop fee 10% = 0.026664 to the
        // feeRecipient; net 0.239976 to the splitter: deployer
        // 0.2132906688, pool 0.0266853312.
        assertEq(feeRecipient.balance - feeBefore, 26_664_000_000_000_000);
        assertEq(deployer.balance - depBefore, 213_290_668_800_000_000);
        assertEq(address(pool).balance - poolBefore, 26_685_331_200_000_000);
        // Shared cap: 3 via SeaDrop + 2 direct = 5 max.
        vm.prank(alice);
        token.mint{value: 2 * FEE}(2);
        assertEq(token.totalSupply(), 5);
        vm.prank(alice);
        vm.expectRevert("Wallet cap exceeded");
        token.mint{value: FEE}(1);
    }

    function testSeaDropMintRevertsWithoutCreatorPayout() public {
        _setPaidDrop(); // drop set, payout NOT set
        vm.prank(alice);
        vm.expectRevert("CreatorPayoutAddressCannotBeZeroAddress");
        seaDrop.mintPublic{value: FEE}(address(token), feeRecipient, address(0), 1);
    }

    function testSeaDropMintRevertsWrongPayment() public {
        _setPayout();
        _setPaidDrop();
        vm.prank(alice);
        vm.expectRevert("IncorrectPayment");
        seaDrop.mintPublic{value: FEE / 2}(address(token), feeRecipient, address(0), 1);
        vm.prank(alice);
        vm.expectRevert("IncorrectPayment");
        seaDrop.mintPublic(address(token), feeRecipient, address(0), 1);
    }

    function testSeaDropMintOnlyAllowedCaller() public {
        vm.prank(alice);
        vm.expectRevert(ISeaDropToken.OnlyAllowedSeaDrop.selector);
        token.mintSeaDrop(alice, 1);
    }

    function testPaidDropOpenEnded() public {
        _setPayout();
        _setPaidDrop();
        vm.prank(alice);
        seaDrop.mintPublic{value: FEE}(address(token), feeRecipient, address(0), 1);
        assertEq(token.totalSupply(), 1);

        // endTime 0 is NOT open-ended: permanently closed.
        PublicDrop memory zeroEnd = PublicDrop({
            mintPrice: uint80(FEE),
            startTime: uint48(block.timestamp),
            endTime: uint48(0),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        token.updatePublicDrop(address(seaDrop), zeroEnd);
        vm.prank(bob);
        vm.expectRevert("Drop not active");
        seaDrop.mintPublic{value: FEE}(address(token), feeRecipient, address(0), 1);
    }

    function testUpdateCreatorPayoutOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.updateCreatorPayoutAddress(address(seaDrop), address(feeSplitter));
        vm.prank(deployer);
        token.updateCreatorPayoutAddress(address(seaDrop), address(feeSplitter));
        assertEq(seaDrop.creatorPayoutAddress(address(token)), address(feeSplitter));
    }

    // -- lottery with paid mints ------------------------------------------

    /// @notice Same deterministic winner lists as the v1 tests: 10 of
    ///         the 20 minted tokens (1..20) are winners.
    function winnerLists()
        internal
        pure
        returns (uint256[] memory golden, uint256[] memory ember, uint256[] memory spark)
    {
        golden = new uint256[](8);
        golden[0] = 1; golden[1] = 2; golden[2] = 101; golden[3] = 202;
        golden[4] = 303; golden[5] = 404; golden[6] = 505; golden[7] = 606;
        ember = new uint256[](80);
        ember[0] = 3; ember[1] = 4; ember[2] = 5;
        for (uint256 i = 3; i < 80; i++) ember[i] = 1000 + (i - 3);
        spark = new uint256[](800);
        for (uint256 i = 0; i < 5; i++) spark[i] = 6 + i;
        for (uint256 i = 5; i < 800; i++) spark[i] = 2000 + (i - 5);
    }

    function mint20Paid() internal {
        address carol = address(0xCA901);
        address dave = address(0xDA9E);
        vm.deal(carol, 10 ether);
        vm.deal(dave, 10 ether);
        vm.prank(alice);
        token.mint{value: 5 * FEE}(5);
        vm.prank(bob);
        token.mint{value: 5 * FEE}(5);
        vm.prank(carol);
        token.mint{value: 5 * FEE}(5);
        vm.prank(dave);
        token.mint{value: 5 * FEE}(5);
    }

    function testFullE2ERoundPaid() public {
        mint20Paid();
        // 20 tickets * 0.08888 = 1.7776 USDC paid; pool got 11.12% =
        // 0.19766912 from mint fees alone.
        assertEq(address(pool).balance, 197_669_120_000_000_000);
        // Top the pool up to 10 for the round math (same as v1 tests).
        vm.prank(deployer);
        pool.deposit{value: 10 ether - 197_669_120_000_000_000}();
        assertEq(address(pool).balance, 10 ether);

        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        bytes32 commitment = keccak256(abi.encode(g, e, s));
        vm.prank(deployer);
        token.commitRound(1, commitment);
        vm.prank(deployer);
        token.revealRound(1, g, e, s);
        assertTrue(token.roundRevealed(1));
        assertEq(token.tierOf(1, 1), 1);
        assertEq(token.tierOf(1, 3), 2);
        assertEq(token.tierOf(1, 6), 3);

        uint256 goldenShare = (7 ether * 80) / 2240;
        uint256 emberShare = (7 ether * 10) / 2240;
        uint256 sparkShare = (7 ether * 1) / 2240;
        uint256 dividend = 0.3 ether;

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        address carol = address(0xCA901);
        uint256 carolBefore = carol.balance;

        pool.claim(1, 1);
        pool.claim(1, 3);
        pool.claim(1, 6);
        pool.claimDividend(1, 11);

        assertEq(alice.balance - aliceBefore, goldenShare + emberShare);
        assertEq(bob.balance - bobBefore, sparkShare);
        assertEq(carol.balance - carolBefore, dividend);
    }
}
