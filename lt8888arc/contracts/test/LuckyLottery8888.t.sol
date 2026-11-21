// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../src/LuckyLottery8888.sol";
import "./MockSeaDrop.sol";
import "../src/PrizePool8888.sol";
import "../src/RoyaltySplitter8888.sol";

contract LuckyLottery8888Test is Test {
    LuckyLottery8888 public token;
    PrizePool8888 public pool;
    RoyaltySplitter8888 public splitter;
    MockSeaDrop public seaDrop;

    address public deployer = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    string constant BASE = "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/";
    string constant CONTRACT_URI = "https://0xzunid.github.io/0xzunid.muse.ai/lt8888arc/metadata/collection.json";

    // 0xaed09ac1 — INonFungibleSeaDropToken interface id (current spec,
    // computed from the function selectors; royaltyInfo takes TWO args,
    // (uint256,uint256) -> 0x2a55205a). 0x1890fe8e — the id the
    // SeaDrop v1 contract actually deployed on Arc checks (from its
    // bytecode).
    bytes4 constant SEADROP_CURRENT_ID = 0xaed09ac1;
    bytes4 constant SEADROP_V1_ID = 0x1890fe8e;

    function setUp() public {
        vm.deal(deployer, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        seaDrop = new MockSeaDrop();
        pool = new PrizePool8888(deployer);
        splitter = new RoyaltySplitter8888(deployer, address(pool));
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDrop);
        token = new LuckyLottery8888(
            deployer, address(splitter), address(pool), BASE, CONTRACT_URI, allowed
        );
        vm.prank(deployer);
        pool.setToken(address(token));
    }

    // -- helpers -------------------------------------------------------

    /// @notice Deterministic winner lists: sorted, non-overlapping,
    ///         in range. 10 of the 20 minted tokens (1..20) are winners.
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

    function commitAndReveal(uint256 roundId) internal {
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        bytes32 commitment = keccak256(abi.encode(g, e, s));
        vm.prank(deployer);
        token.commitRound(roundId, commitment);
        vm.prank(deployer);
        token.revealRound(roundId, g, e, s);
    }

    /// @notice Mint 20 tokens: alice 5 (1..5), bob 5 (6..10),
    ///         deployer 5 (11..15), + 5 more to alice's second wallet
    ///         via a fresh address (16..20). Simpler: 4 wallets x 5.
    function mint20() internal {
        address carol = address(0xCA901);
        address dave = address(0xDA9E);
        vm.deal(carol, 10 ether);
        vm.deal(dave, 10 ether);
        vm.prank(alice);
        token.mint(5);
        vm.prank(bob);
        token.mint(5);
        vm.prank(carol);
        token.mint(5);
        vm.prank(dave);
        token.mint(5);
    }

    // -- deployment / metadata -----------------------------------------

    function testDeployment() public view {
        assertEq(token.name(), "8888LuckyLotteryTicket");
        assertEq(token.symbol(), "8888LLT");
        assertEq(token.maxSupply(), 8888);
        assertEq(token.baseURI(), BASE);
        assertEq(token.contractURI(), CONTRACT_URI);
        assertEq(token.royaltyAddress(), address(splitter));
        assertEq(token.royaltyBasisPoints(), 500);
        (address receiver, uint256 amount) = token.royaltyInfo(1, 10000);
        assertEq(receiver, address(splitter));
        assertEq(amount, 500);
        assertEq(token.prizePool(), address(pool));
        assertEq(pool.token(), address(token));
        assertEq(splitter.deployer(), deployer);
        assertEq(splitter.pool(), address(pool));
    }

    function testTokenURI() public {
        vm.prank(alice);
        token.mint(1);
        assertEq(token.tokenURI(1), string.concat(BASE, "1.json"));
        vm.expectRevert();
        token.tokenURI(9999);
    }

    // -- direct mint ----------------------------------------------------

    function testFreeMint() public {
        vm.prank(alice);
        token.mint(5);
        assertEq(token.totalSupply(), 5);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.ownerOf(1), alice);
        assertEq(token.ownerOf(5), alice);
        (uint256 minted, uint256 supply, uint256 max) = token.getMintStats(alice);
        assertEq(minted, 5);
        assertEq(supply, 5);
        assertEq(max, 8888);
    }

    function testMintRejectsPayment() public {
        vm.prank(alice);
        vm.expectRevert("Free mint");
        token.mint{value: 1 wei}(1);
    }

    function testMintCapPerWallet() public {
        vm.prank(alice);
        token.mint(5);
        vm.prank(alice);
        vm.expectRevert("Wallet cap exceeded");
        token.mint(1);
    }

    function testMintInvalidCount() public {
        vm.prank(alice);
        vm.expectRevert("Invalid count");
        token.mint(0);
        vm.prank(alice);
        vm.expectRevert("Invalid count");
        token.mint(6);
    }

    function testSupplyCapViaSetMaxSupply() public {
        vm.prank(alice);
        token.mint(5);
        vm.prank(deployer);
        token.setMaxSupply(5);
        vm.prank(bob);
        vm.expectRevert("Sold out");
        token.mint(1);
        vm.prank(deployer);
        vm.expectRevert("Below minted");
        token.setMaxSupply(4);
        vm.prank(deployer);
        vm.expectRevert("Above limit");
        token.setMaxSupply(8889);
    }

    // -- SeaDrop ---------------------------------------------------------

    function testSupportsSeaDropInterfaces() public view {
        assertTrue(token.supportsInterface(SEADROP_V1_ID));
        assertTrue(token.supportsInterface(SEADROP_CURRENT_ID));
        assertTrue(token.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(token.supportsInterface(0x2a55205a)); // ERC2981
        assertFalse(token.supportsInterface(0xffffffff));
    }

    function testInterfaceIdMatchesReference() public view {
        // type(ISeaDropToken).interfaceId must equal the value computed
        // independently from the reference function selectors.
        assertEq(token.SEADROP_V1_INTERFACE_ID(), SEADROP_V1_ID);
        assertEq(type(ISeaDropToken).interfaceId, SEADROP_CURRENT_ID);
    }

    function testMintSeaDropOnlyAllowedCaller() public {
        vm.prank(alice);
        vm.expectRevert(ISeaDropToken.OnlyAllowedSeaDrop.selector);
        token.mintSeaDrop(alice, 1);
    }

    function testMintViaMockSeaDrop() public {
        vm.prank(alice);
        seaDrop.mintPublic(address(token), 5);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.totalSupply(), 5);
        (uint256 minted,,) = token.getMintStats(alice);
        assertEq(minted, 5);
        // Shared cap: SeaDrop mints count toward the 5/wallet cap.
        vm.prank(alice);
        vm.expectRevert("Wallet cap exceeded");
        token.mint(1);
        vm.prank(alice);
        vm.expectRevert("exceeds per-wallet cap");
        seaDrop.mintPublic(address(token), 1);
    }

    function testMintSeaDropSupplyCap() public {
        vm.prank(deployer);
        token.setMaxSupply(4);
        vm.prank(alice);
        vm.expectRevert("exceeds max supply");
        seaDrop.mintPublic(address(token), 5);
    }

    function testUpdateAllowedSeaDrop() public {
        address[] memory empty = new address[](0);
        vm.prank(alice);
        vm.expectRevert();
        token.updateAllowedSeaDrop(empty);
        vm.prank(deployer);
        token.updateAllowedSeaDrop(empty);
        assertEq(token.getAllowedSeaDrop().length, 0);
        // No allowed SeaDrop left: direct mintSeaDrop now reverts.
        vm.prank(alice);
        vm.expectRevert(ISeaDropToken.OnlyAllowedSeaDrop.selector);
        token.mintSeaDrop(alice, 1);
    }

    function testUpdatePublicDropForwards() public {
        // Open-ended drop (user decision 2026-11-22): mint stays open
        // until sellout — endTime 4102444800 (2100-01-01), NOT 0:
        // SeaDrop's _checkActive reverts when now > endTime with no
        // zero-guard, so endTime 0 would permanently close the drop.
        PublicDrop memory drop = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(4102444800),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        token.updatePublicDrop(address(seaDrop), drop);
        assertTrue(seaDrop.gotPublicDrop());
        (uint80 price, uint48 start, uint48 end, uint16 perWallet, uint16 fee, bool restrict) =
            seaDrop.lastPublicDrop();
        assertEq(price, 0);
        assertEq(start, block.timestamp);
        assertEq(end, 4102444800);
        assertEq(perWallet, 5);
        assertEq(fee, 1000);
        assertFalse(restrict);
    }

    function testOpenEndedDropMintsAndZeroEndTimeIsClosed() public {
        // Open-ended config (endTime 2100-01-01) mints fine through
        // the SeaDrop-faithful mock.
        PublicDrop memory openEnded = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(4102444800),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        token.updatePublicDrop(address(seaDrop), openEnded);
        vm.prank(alice);
        seaDrop.mintPublic(address(token), 1);
        assertEq(token.totalSupply(), 1);

        // endTime 0 is NOT open-ended in SeaDrop v1: _checkActive
        // reverts whenever now > 0, so the drop is permanently closed.
        PublicDrop memory zeroEnd = PublicDrop({
            mintPrice: 0,
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
        seaDrop.mintPublic(address(token), 1);

        // A past endTime is likewise closed.
        PublicDrop memory pastEnd = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp - 1),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        token.updatePublicDrop(address(seaDrop), pastEnd);
        vm.prank(bob);
        vm.expectRevert("Drop not active");
        seaDrop.mintPublic(address(token), 1);
    }

    function testUpdatePublicDropRejectsUnallowedSeaDrop() public {
        PublicDrop memory drop = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 30 days),
            maxTotalMintableByWallet: 5,
            feeBps: 0,
            restrictFeeRecipients: false
        });
        vm.prank(deployer);
        vm.expectRevert(ISeaDropToken.OnlyAllowedSeaDrop.selector);
        token.updatePublicDrop(address(0x1234), drop);
    }

    function testSetters() public {
        vm.prank(deployer);
        token.setBaseURI("https://example.com/meta/");
        assertEq(token.baseURI(), "https://example.com/meta/");
        vm.prank(deployer);
        token.setContractURI("https://example.com/collection.json");
        assertEq(token.contractURI(), "https://example.com/collection.json");
        vm.prank(deployer);
        token.setProvenanceHash(bytes32(uint256(123)));
        assertEq(token.provenanceHash(), bytes32(uint256(123)));
        vm.prank(alice);
        token.mint(1);
        vm.prank(deployer);
        vm.expectRevert("Mint started");
        token.setProvenanceHash(bytes32(uint256(456)));
        vm.prank(deployer);
        token.setRoyaltyInfo(SeaDropRoyaltyInfo({royaltyAddress: bob, royaltyBps: 750}));
        assertEq(token.royaltyAddress(), bob);
        assertEq(token.royaltyBasisPoints(), 750);
    }

    // -- lottery: commit / reveal ----------------------------------------

    function testCommitRevealHappyPath() public {
        mint20();
        commitAndReveal(1);
        assertTrue(token.roundRevealed(1));
        assertEq(token.tierOf(1, 1), 1); // golden
        assertEq(token.tierOf(1, 2), 1); // golden
        assertEq(token.tierOf(1, 3), 2); // ember
        assertEq(token.tierOf(1, 6), 3); // spark
        assertEq(token.tierOf(1, 11), 0); // not a winner
        assertEq(token.tierOf(1, 101), 1);
        assertEq(token.tierOf(1, 1000), 2);
        assertEq(token.tierOf(1, 2000), 3);
    }

    function testRevealRequiresCommitment() public {
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        vm.prank(deployer);
        vm.expectRevert("Not committed");
        token.revealRound(1, g, e, s);
    }

    function testRevealCommitmentMismatch() public {
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        vm.prank(deployer);
        token.commitRound(1, bytes32(uint256(1)));
        vm.prank(deployer);
        vm.expectRevert("Commitment mismatch");
        token.revealRound(1, g, e, s);
    }

    function testRevealRejectsUnsortedAndOverlap() public {
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        g[1] = g[0]; // duplicate golden
        vm.prank(deployer);
        token.commitRound(1, keccak256(abi.encode(g, e, s)));
        vm.prank(deployer);
        vm.expectRevert("Golden not sorted");
        token.revealRound(1, g, e, s);

        (g, e, s) = winnerLists();
        e[0] = g[0]; // ember overlaps golden (also unsorted vs ember[1]=4? e[0]=1 < 4, sorted ok, overlap caught)
        vm.prank(deployer);
        token.commitRound(2, keccak256(abi.encode(g, e, s)));
        vm.prank(deployer);
        vm.expectRevert("Golden/ember overlap");
        token.revealRound(2, g, e, s);
    }

    function testRevealRejectsWrongCounts() public {
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        uint256[] memory short = new uint256[](7);
        for (uint256 i = 0; i < 7; i++) short[i] = g[i];
        vm.prank(deployer);
        token.commitRound(1, keccak256(abi.encode(short, e, s)));
        vm.prank(deployer);
        vm.expectRevert("Need 8 golden");
        token.revealRound(1, short, e, s);
    }

    function testDoubleRevealReverts() public {
        mint20();
        commitAndReveal(1);
        (uint256[] memory g, uint256[] memory e, uint256[] memory s) = winnerLists();
        vm.prank(deployer);
        vm.expectRevert("Already revealed");
        token.revealRound(1, g, e, s);
    }

    function testCommitOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.commitRound(1, bytes32(uint256(1)));
    }

    // -- prize pool -------------------------------------------------------

    function testPoolSnapshotSplit() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        (uint256 winnerPool, uint256 dividendPool, uint256 nonWinners,, , bool taken) = pool.rounds(1);
        assertTrue(taken);
        assertEq(winnerPool, 7 ether); // 70%
        assertEq(dividendPool, 3 ether); // 30%
        assertEq(nonWinners, 10); // 20 minted - 10 minted winners
    }

    function testWinnerClaimPaysOwnerDirectly() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        // token 1 is golden: 7 ether * 80 / 2240
        uint256 expected = (7 ether * 80) / 2240;
        assertEq(pool.shareFor(1, 1), expected);
        uint256 before = alice.balance;
        vm.prank(bob);
        pool.claim(1, 1);
        assertEq(alice.balance - before, expected);
        assertEq(pool.claimedCount(1), 1);
        vm.expectRevert("Already claimed");
        pool.claim(1, 1);
        // winner cannot claim dividend
        vm.expectRevert("Winner cannot claim dividend");
        pool.claimDividend(1, 1);
    }

    function testDividendClaim() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        // token 11 is not a winner: 3 ether / 10 non-winners
        assertEq(pool.dividendFor(1, 11), 0.3 ether);
        assertEq(pool.shareFor(1, 11), 0);
        address carol = address(0xCA901);
        uint256 before = carol.balance;
        pool.claimDividend(1, 11);
        assertEq(carol.balance - before, 0.3 ether);
        vm.expectRevert("Already claimed");
        pool.claimDividend(1, 11);
    }

    function testClaimWindowExpiry() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        vm.warp(block.timestamp + 91 days);
        vm.expectRevert("Claim window closed");
        pool.claim(1, 1);
        vm.expectRevert("Claim window closed");
        pool.claimDividend(1, 11);
    }

    function testClaimRequiresReveal() public {
        mint20();
        vm.expectRevert("Not revealed");
        pool.claim(1, 1);
    }

    function testClaimUnmintedTokenReverts() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        // token 5000 was never minted (not in winner lists either)
        vm.expectRevert();
        pool.claimDividend(1, 5000);
    }

    function testUnmintedWinnersStayInPool() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);
        // Only 10 of 888 winners are minted; unminted shares stay.
        // Claim all 10 minted winners + all 10 dividends, pool keeps the rest.
        for (uint256 id = 1; id <= 10; id++) pool.claim(1, id);
        for (uint256 id = 11; id <= 20; id++) pool.claimDividend(1, id);
        // winnerPool 7 ether: claimed = 2*80 + 3*10 + 5*1 = 195 units
        uint256 claimedWinner = (7 ether * 195) / 2240;
        // dividendPool 3 ether: all 10 claimed = 3 ether
        assertEq(address(pool).balance, 10 ether - claimedWinner - 3 ether);
    }

    // -- royalty splitter --------------------------------------------------

    function testSplitter50_50() public {
        uint256 depBefore = deployer.balance;
        uint256 poolBefore = address(pool).balance;
        (bool ok,) = address(splitter).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(deployer.balance - depBefore, 0.5 ether);
        assertEq(address(pool).balance - poolBefore, 0.5 ether);
    }

    function testSplitterOddWeiToDeployer() public {
        uint256 depBefore = deployer.balance;
        (bool ok,) = address(splitter).call{value: 101}("");
        assertTrue(ok);
        assertEq(deployer.balance - depBefore, 51);
        assertEq(address(pool).balance, 50);
    }

    function testRoyaltyFlowsToPoolViaSplitter() public {
        // Simulate a marketplace paying the 5% royalty to the splitter:
        // sale of 10 ether -> 0.5 ether royalty -> 0.25 pool / 0.25 deployer.
        (address receiver, uint256 royalty) = token.royaltyInfo(1, 10 ether);
        assertEq(receiver, address(splitter));
        assertEq(royalty, 0.5 ether);
        uint256 depBefore = deployer.balance;
        (bool ok,) = receiver.call{value: royalty}("");
        assertTrue(ok);
        assertEq(address(pool).balance, 0.25 ether);
        assertEq(deployer.balance - depBefore, 0.25 ether);
    }

    // -- full E2E -----------------------------------------------------------

    function testFullE2ERound() public {
        mint20();
        vm.prank(deployer);
        pool.deposit{value: 10 ether}();
        commitAndReveal(1);

        // Golden token 1 (alice): 7 * 80 / 2240
        uint256 goldenShare = (7 ether * 80) / 2240;
        // Ember token 3 (alice): 7 * 10 / 2240
        uint256 emberShare = (7 ether * 10) / 2240;
        // Spark token 6 (bob): 7 * 1 / 2240
        uint256 sparkShare = (7 ether * 1) / 2240;
        // Dividend token 11 (carol): 3 / 10
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
        assertEq(pool.claimedCount(1), 3);
        assertEq(pool.dividendClaimedCount(1), 1);
    }
}
