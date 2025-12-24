// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Permitter} from "../src/Permitter.sol";
import {PermitterFactory} from "../src/PermitterFactory.sol";
import {MockCCA} from "./mocks/MockCCA.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockPolicyEngine} from "./mocks/MockPolicyEngine.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PermitterTest is Test {
  PermitterFactory factory;
  Permitter permitter;
  MockCCA cca;
  MockIdentityRegistry identityRegistry;
  MockPolicyEngine policyEngine;
  MockPriceOracle priceOracle;

  address owner = makeAddr("owner");
  address bidder1 = makeAddr("bidder1");
  address bidder2 = makeAddr("bidder2");
  bytes32 ccid1 = keccak256("ccid1");
  bytes32 ccid2 = keccak256("ccid2");

  // Default test values
  uint256 constant PER_USER_LIMIT = 10_000e18; // $10,000
  uint256 constant GLOBAL_CAP = 50_000_000e18; // $50M
  int256 constant PRICE = 1e8; // $1 with 8 decimals
  uint8 constant ORACLE_DECIMALS = 8;
  uint8 constant BID_TOKEN_DECIMALS = 18;

  function setUp() public virtual {
    factory = new PermitterFactory();
    identityRegistry = new MockIdentityRegistry();
    policyEngine = new MockPolicyEngine();
    priceOracle = new MockPriceOracle(PRICE, ORACLE_DECIMALS);

    // Create a permitter through the factory
    Permitter.Config memory config = Permitter.Config({
      auction: address(0), // Will be set to CCA after CCA is created
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    // Create permitter first with a placeholder auction
    config.auction = makeAddr("placeholder");
    vm.prank(owner);
    address permitterAddr = factory.createPermitter(config);
    permitter = Permitter(permitterAddr);

    // Create CCA with the permitter
    cca = new MockCCA(permitterAddr);

    // Register CCIDs
    identityRegistry.registerIdentity(bidder1, ccid1);
    identityRegistry.registerIdentity(bidder2, ccid2);
  }

  function _createPermitterWithAuction(address auction) internal returns (Permitter) {
    Permitter.Config memory config = Permitter.Config({
      auction: auction,
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    return Permitter(factory.createPermitter(config));
  }
}

// ========== INITIALIZATION TESTS ==========

contract Initialize is PermitterTest {
  function test_InitializesCorrectly() public view {
    assertEq(permitter.owner(), owner);
    assertEq(permitter.perUserLimitUsd(), PER_USER_LIMIT);
    assertEq(permitter.globalCapUsd(), GLOBAL_CAP);
    assertEq(permitter.bidTokenDecimals(), BID_TOKEN_DECIMALS);
    assertTrue(permitter.requireSanctionsCheck());
    assertFalse(permitter.requireAllowlist());
    assertFalse(permitter.paused());
  }

  function test_SetsDefaultGlobalCap() public {
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: 0, // Should default to 50M
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: false,
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    assertEq(p.globalCapUsd(), 50_000_000e18);
  }

  function test_RevertIf_ReinitializeAttempted() public {
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(0),
      policyEngine: address(0),
      priceOracle: address(0),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 0,
      globalCapUsd: 0,
      bidTokenDecimals: 18,
      requireSanctionsCheck: false,
      requireAllowlist: false
    });

    vm.expectRevert();
    permitter.initialize(owner, config);
  }

  function test_RevertIf_ZeroOwner() public {
    // Deploy a fresh Permitter (not through factory)
    Permitter freshPermitter = new Permitter();

    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(0),
      policyEngine: address(0),
      priceOracle: address(0),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 0,
      globalCapUsd: 0,
      bidTokenDecimals: 18,
      requireSanctionsCheck: false,
      requireAllowlist: false
    });

    vm.expectRevert(Permitter.ZeroAddress.selector);
    freshPermitter.initialize(address(0), config);
  }

  function test_RevertIf_ZeroAuction() public {
    // Deploy a fresh Permitter (not through factory)
    Permitter freshPermitter = new Permitter();

    Permitter.Config memory config = Permitter.Config({
      auction: address(0), // Zero auction
      identityRegistry: address(0),
      policyEngine: address(0),
      priceOracle: address(0),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 0,
      globalCapUsd: 0,
      bidTokenDecimals: 18,
      requireSanctionsCheck: false,
      requireAllowlist: false
    });

    vm.expectRevert(Permitter.ZeroAddress.selector);
    freshPermitter.initialize(owner, config);
  }
}

// ========== VALIDATION TESTS ==========

contract Validate is PermitterTest {
  function setUp() public override {
    super.setUp();
    // Create a proper permitter with the CCA as auction
    permitter = _createPermitterWithAuction(address(cca));
    cca.setValidationHook(address(permitter));
  }

  function test_ValidatesSuccessfulBid() public {
    uint128 amount = 1000e18; // $1000

    vm.prank(bidder1);
    cca.submitBid(1e18, amount, bidder1, "");

    // Check state was updated
    assertEq(permitter.getUserPurchases(bidder1), 1000e18);
    assertEq(permitter.totalPurchasesUsd(), 1000e18);
  }

  function test_RevertIf_NotFromAuction() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.NotFromAuction.selector);
    permitter.validate(1e18, 1000e18, bidder1, bidder1, "");
  }

  function test_RevertIf_Paused() public {
    vm.prank(owner);
    permitter.setPaused(true);

    vm.prank(bidder1);
    vm.expectRevert(Permitter.Paused.selector);
    cca.submitBid(1e18, 1000e18, bidder1, "");
  }
}

// ========== SANCTIONS TESTS ==========

contract SanctionsCheck is PermitterTest {
  function setUp() public override {
    super.setUp();
    permitter = _createPermitterWithAuction(address(cca));
    cca.setValidationHook(address(permitter));
  }

  function test_PassesWhenNotSanctioned() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e18, bidder1, "");
    assertEq(permitter.getUserPurchases(bidder1), 1000e18);
  }

  function test_RevertIf_NoCCID() public {
    address noCcidBidder = makeAddr("noCcidBidder");
    // Don't register CCID for this bidder

    vm.prank(noCcidBidder);
    vm.expectRevert(abi.encodeWithSelector(Permitter.NoCCIDRegistered.selector, noCcidBidder));
    cca.submitBid(1e18, 1000e18, noCcidBidder, "");
  }

  function test_RevertIf_Sanctioned() public {
    // Block the CCID
    policyEngine.setAllowAll(false);
    policyEngine.blockCCID(ccid1);

    vm.prank(bidder1);
    vm.expectRevert(abi.encodeWithSelector(Permitter.PolicyCheckFailed.selector, bidder1, ccid1));
    cca.submitBid(1e18, 1000e18, bidder1, "");
  }

  function test_SkipsSanctionsWhenNotRequired() public {
    // Create permitter without sanctions check
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: false, // Disabled
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(p));

    // Bidder without CCID should pass
    address noCcidBidder = makeAddr("noCcidBidder");
    vm.prank(noCcidBidder);
    cca.submitBid(1e18, 1000e18, noCcidBidder, "");

    assertEq(p.getUserPurchases(noCcidBidder), 1000e18);
  }
}

// ========== PER-USER LIMIT TESTS ==========

contract PerUserLimit is PermitterTest {
  function setUp() public override {
    super.setUp();
    permitter = _createPermitterWithAuction(address(cca));
    cca.setValidationHook(address(permitter));
  }

  function test_AllowsBidWithinLimit() public {
    uint128 amount = 5000e18; // $5000, under $10k limit

    vm.prank(bidder1);
    cca.submitBid(1e18, amount, bidder1, "");

    assertEq(permitter.getUserPurchases(bidder1), 5000e18);
    assertEq(permitter.getRemainingUserCapacity(bidder1), 5000e18);
  }

  function test_AllowsMultipleBidsUpToLimit() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 4000e18, bidder1, "");

    vm.prank(bidder1);
    cca.submitBid(1e18, 4000e18, bidder1, "");

    vm.prank(bidder1);
    cca.submitBid(1e18, 2000e18, bidder1, ""); // Exactly at limit

    assertEq(permitter.getUserPurchases(bidder1), 10_000e18);
    assertEq(permitter.getRemainingUserCapacity(bidder1), 0);
  }

  function test_RevertIf_ExceedsLimit() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 8000e18, bidder1, "");

    vm.prank(bidder1);
    vm.expectRevert(
      abi.encodeWithSelector(
        Permitter.PerUserLimitExceeded.selector, 3000e18, PER_USER_LIMIT, 8000e18
      )
    );
    cca.submitBid(1e18, 3000e18, bidder1, "");
  }

  function test_TracksByCCIDNotAddress() public {
    // Register second address for same CCID
    address bidder1Alt = makeAddr("bidder1Alt");
    identityRegistry.registerIdentity(bidder1Alt, ccid1);

    // Bid from first address
    vm.prank(bidder1);
    cca.submitBid(1e18, 6000e18, bidder1, "");

    // Bid from second address should share the same limit
    vm.prank(bidder1Alt);
    cca.submitBid(1e18, 3000e18, bidder1Alt, "");

    // Total should be accumulated
    assertEq(permitter.getUserPurchases(bidder1), 9000e18);
    assertEq(permitter.getUserPurchases(bidder1Alt), 9000e18);

    // Third bid should exceed limit
    vm.prank(bidder1);
    vm.expectRevert(
      abi.encodeWithSelector(
        Permitter.PerUserLimitExceeded.selector, 2000e18, PER_USER_LIMIT, 9000e18
      )
    );
    cca.submitBid(1e18, 2000e18, bidder1, "");
  }

  function test_NoLimitWhenZero() public {
    // Create permitter with no per-user limit
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 0, // No limit
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(p));

    // Should allow very large bid
    vm.prank(bidder1);
    cca.submitBid(1e18, 1_000_000e18, bidder1, "");

    assertEq(p.getRemainingUserCapacity(bidder1), type(uint256).max);
  }
}

// ========== GLOBAL CAP TESTS ==========

contract GlobalCap is PermitterTest {
  function setUp() public override {
    super.setUp();

    // Create permitter with smaller global cap for testing
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 100_000e18, // Higher user limit
      globalCapUsd: 20_000e18, // $20k global cap
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    permitter = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(permitter));
  }

  function test_AllowsBidWithinGlobalCap() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 10_000e18, bidder1, "");

    assertEq(permitter.totalPurchasesUsd(), 10_000e18);
    assertEq(permitter.getRemainingGlobalCapacity(), 10_000e18);
  }

  function test_AllowsMultipleUsersBidsUpToCap() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 10_000e18, bidder1, "");

    vm.prank(bidder2);
    cca.submitBid(1e18, 10_000e18, bidder2, "");

    assertEq(permitter.totalPurchasesUsd(), 20_000e18);
    assertEq(permitter.getRemainingGlobalCapacity(), 0);
  }

  function test_RevertIf_ExceedsGlobalCap() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 15_000e18, bidder1, "");

    vm.prank(bidder2);
    vm.expectRevert(
      abi.encodeWithSelector(Permitter.GlobalCapExceeded.selector, 10_000e18, 20_000e18, 15_000e18)
    );
    cca.submitBid(1e18, 10_000e18, bidder2, "");
  }
}

// ========== PRICE CONVERSION TESTS ==========

contract PriceConversion is PermitterTest {
  function setUp() public override {
    super.setUp();
    permitter = _createPermitterWithAuction(address(cca));
    cca.setValidationHook(address(permitter));
  }

  function test_ConvertsCorrectlyAtParity() public {
    // Price is $1, so 1000 tokens = $1000
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e18, bidder1, "");

    assertEq(permitter.getUserPurchases(bidder1), 1000e18);
  }

  function test_ConvertsCorrectlyWithHigherPrice() public {
    priceOracle.setPrice(2e8); // $2

    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e18, bidder1, "");

    assertEq(permitter.getUserPurchases(bidder1), 2000e18);
  }

  function test_RevertIf_InvalidPrice() public {
    priceOracle.setInvalidPrice();

    vm.prank(bidder1);
    vm.expectRevert(Permitter.InvalidPriceData.selector);
    cca.submitBid(1e18, 1000e18, bidder1, "");
  }

  function test_RevertIf_StalePrice() public {
    // Warp to a reasonable timestamp first
    vm.warp(10_000);

    // Set updated time to 2 hours ago
    uint256 staleTime = block.timestamp - 7200;
    priceOracle.setUpdatedAt(staleTime);

    vm.prank(bidder1);
    vm.expectRevert(abi.encodeWithSelector(Permitter.StalePriceData.selector, staleTime, 3600));
    cca.submitBid(1e18, 1000e18, bidder1, "");
  }

  function test_WorksWithoutOracle() public {
    // Create permitter without price oracle
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(0), // No oracle
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: 6, // USDC-like
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(p));

    // Bid 1000 USDC (6 decimals) should scale to 18 decimals
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e6, bidder1, "");

    assertEq(p.getUserPurchases(bidder1), 1000e18);
  }

  function test_WorksWithHighDecimalToken() public {
    // Create permitter without price oracle and a token with >18 decimals
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(0), // No oracle
      merkleRoot: bytes32(0),
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: 24, // Token with 24 decimals
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(p));

    // Bid 1000 tokens (24 decimals) should scale to 18 decimals (divide by 1e6)
    // 1000 * 1e24 / 1e6 = 1000e18
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e24, bidder1, "");

    assertEq(p.getUserPurchases(bidder1), 1000e18);
  }
}

// ========== ALLOWLIST TESTS ==========

contract AllowlistCheck is PermitterTest {
  bytes32 merkleRoot;
  bytes32[] proof1;

  function setUp() public override {
    super.setUp();

    // Build a simple merkle tree with bidder1 and bidder2
    bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(bidder1))));
    bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(bidder2))));

    // Simple 2-leaf tree: root = hash(leaf1, leaf2)
    if (leaf1 < leaf2) {
      merkleRoot = keccak256(bytes.concat(leaf1, leaf2));
      proof1 = new bytes32[](1);
      proof1[0] = leaf2;
    } else {
      merkleRoot = keccak256(bytes.concat(leaf2, leaf1));
      proof1 = new bytes32[](1);
      proof1[0] = leaf2;
    }

    // Create permitter with allowlist
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: merkleRoot,
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: true
    });

    vm.prank(owner);
    permitter = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(permitter));
  }

  function test_PassesWithValidProof() public {
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e18, bidder1, abi.encode(proof1));

    assertEq(permitter.getUserPurchases(bidder1), 1000e18);
  }

  function test_RevertIf_NotOnAllowlist() public {
    address notAllowed = makeAddr("notAllowed");
    identityRegistry.registerIdentity(notAllowed, keccak256("notAllowedCcid"));

    // Empty proof
    bytes32[] memory emptyProof = new bytes32[](0);

    vm.prank(notAllowed);
    vm.expectRevert(abi.encodeWithSelector(Permitter.NotOnAllowlist.selector, notAllowed));
    cca.submitBid(1e18, 1000e18, notAllowed, abi.encode(emptyProof));
  }

  function test_RevertIf_InvalidProof() public {
    bytes32[] memory wrongProof = new bytes32[](1);
    wrongProof[0] = keccak256("wrong");

    vm.prank(bidder1);
    vm.expectRevert(abi.encodeWithSelector(Permitter.NotOnAllowlist.selector, bidder1));
    cca.submitBid(1e18, 1000e18, bidder1, abi.encode(wrongProof));
  }

  function test_SkipsAllowlistWhenNoMerkleRoot() public {
    // Create permitter with allowlist required but no merkle root
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0), // No merkle root
      perUserLimitUsd: PER_USER_LIMIT,
      globalCapUsd: GLOBAL_CAP,
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: true
    });

    vm.prank(owner);
    Permitter p = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(p));

    // Should pass without proof
    vm.prank(bidder1);
    cca.submitBid(1e18, 1000e18, bidder1, "");

    assertEq(p.getUserPurchases(bidder1), 1000e18);
  }
}

// ========== ADMIN TESTS ==========

contract AdminFunctions is PermitterTest {
  function setUp() public override {
    super.setUp();
    permitter = _createPermitterWithAuction(address(cca));
  }

  function test_SetPerUserLimit() public {
    vm.prank(owner);
    permitter.setPerUserLimit(20_000e18);

    assertEq(permitter.perUserLimitUsd(), 20_000e18);
  }

  function test_SetPerUserLimit_EmitsEvent() public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true);
    emit Permitter.PerUserLimitUpdated(PER_USER_LIMIT, 20_000e18);
    permitter.setPerUserLimit(20_000e18);
  }

  function test_SetPerUserLimit_RevertIf_NotOwner() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.Unauthorized.selector);
    permitter.setPerUserLimit(20_000e18);
  }

  function test_SetGlobalCap() public {
    vm.prank(owner);
    permitter.setGlobalCap(100_000_000e18);

    assertEq(permitter.globalCapUsd(), 100_000_000e18);
  }

  function test_SetMerkleRoot() public {
    bytes32 newRoot = keccak256("new-root");

    vm.prank(owner);
    permitter.setMerkleRoot(newRoot);

    assertEq(permitter.merkleRoot(), newRoot);
  }

  function test_SetPaused() public {
    vm.prank(owner);
    permitter.setPaused(true);

    assertTrue(permitter.paused());

    vm.prank(owner);
    permitter.setPaused(false);

    assertFalse(permitter.paused());
  }

  function test_TransferOwnership() public {
    address newOwner = makeAddr("newOwner");

    vm.prank(owner);
    permitter.transferOwnership(newOwner);

    assertEq(permitter.owner(), newOwner);
  }

  function test_TransferOwnership_RevertIf_ZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(Permitter.ZeroAddress.selector);
    permitter.transferOwnership(address(0));
  }

  function test_SetGlobalCap_RevertIf_NotOwner() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.Unauthorized.selector);
    permitter.setGlobalCap(100_000_000e18);
  }

  function test_SetMerkleRoot_RevertIf_NotOwner() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.Unauthorized.selector);
    permitter.setMerkleRoot(keccak256("new-root"));
  }

  function test_SetPaused_RevertIf_NotOwner() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.Unauthorized.selector);
    permitter.setPaused(true);
  }

  function test_TransferOwnership_RevertIf_NotOwner() public {
    vm.prank(bidder1);
    vm.expectRevert(Permitter.Unauthorized.selector);
    permitter.transferOwnership(bidder1);
  }
}

// ========== FUZZ TESTS ==========

contract FuzzTests is PermitterTest {
  function setUp() public override {
    super.setUp();
    permitter = _createPermitterWithAuction(address(cca));
    cca.setValidationHook(address(permitter));
  }

  function testFuzz_PriceConversion(uint128 amount, int256 price) public {
    // Create a permitter with no per-user limit for this test
    Permitter.Config memory config = Permitter.Config({
      auction: address(cca),
      identityRegistry: address(identityRegistry),
      policyEngine: address(policyEngine),
      priceOracle: address(priceOracle),
      merkleRoot: bytes32(0),
      perUserLimitUsd: 0, // No limit
      globalCapUsd: type(uint256).max, // Very high cap
      bidTokenDecimals: BID_TOKEN_DECIMALS,
      requireSanctionsCheck: true,
      requireAllowlist: false
    });

    vm.prank(owner);
    Permitter unlimitedPermitter = Permitter(factory.createPermitter(config));
    cca.setValidationHook(address(unlimitedPermitter));

    // Bound inputs to reasonable ranges
    amount = uint128(bound(amount, 1e10, 1e26));
    price = int256(bound(price, 1e4, 1e12));

    priceOracle.setPrice(price);

    vm.prank(bidder1);
    cca.submitBid(1e18, amount, bidder1, "");

    // Verify state was updated
    unlimitedPermitter.getUserPurchases(bidder1);
  }

  function testFuzz_MultiplePurchasesAccumulate(uint128[5] memory amounts) public {
    uint256 total = 0;

    for (uint256 i = 0; i < 5; i++) {
      // Bound to keep under per-user limit
      uint128 amount = uint128(bound(amounts[i], 0, 1000e18));
      if (amount == 0) continue;

      uint256 amountUsd = uint256(amount);
      if (total + amountUsd > PER_USER_LIMIT) break;

      vm.prank(bidder1);
      cca.submitBid(1e18, amount, bidder1, "");
      total += amountUsd;
    }

    assertEq(permitter.getUserPurchases(bidder1), total);
  }
}
