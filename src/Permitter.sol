// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IValidationHook} from "./interfaces/IValidationHook.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title Permitter
/// @notice Validation hook for CCA auctions with sanctions, purchase limits, and allowlist
/// enforcement @dev Implements IValidationHook and integrates with Chainlink ACE Policy Engine and
/// CCID
contract Permitter is IValidationHook, Initializable {
  // ========== CONSTANTS ==========

  /// @notice Default global cap of $50M in USD with 18 decimals
  uint256 public constant DEFAULT_GLOBAL_CAP_USD = 50_000_000e18;

  /// @notice Maximum staleness for price feed data (1 hour)
  uint256 public constant PRICE_STALENESS_THRESHOLD = 3600;

  // ========== STRUCTS ==========

  /// @notice Configuration for initializing a Permitter
  struct Config {
    address auction;
    address identityRegistry;
    address policyEngine;
    address priceOracle;
    bytes32 merkleRoot;
    uint256 perUserLimitUsd;
    uint256 globalCapUsd;
    uint8 bidTokenDecimals;
    bool requireSanctionsCheck;
    bool requireAllowlist;
  }

  // ========== STORAGE ==========

  /// @notice The auction this permitter validates
  address public auction;

  /// @notice The owner/admin of this permitter
  address public owner;

  /// @notice Chainlink CCID Identity Registry
  IIdentityRegistry public identityRegistry;

  /// @notice Chainlink ACE Policy Engine
  IPolicyEngine public policyEngine;

  /// @notice Chainlink price oracle for bid token
  AggregatorV3Interface public priceOracle;

  /// @notice Merkle root for allowlist verification
  bytes32 public merkleRoot;

  /// @notice Per-user purchase limit in USD (18 decimals)
  uint256 public perUserLimitUsd;

  /// @notice Global purchase cap in USD (18 decimals)
  uint256 public globalCapUsd;

  /// @notice Decimals of the bid token
  uint8 public bidTokenDecimals;

  /// @notice Whether sanctions check is required
  bool public requireSanctionsCheck;

  /// @notice Whether allowlist is required
  bool public requireAllowlist;

  /// @notice Whether the permitter is paused
  bool public paused;

  /// @notice Total purchases in USD for this auction
  uint256 public totalPurchasesUsd;

  /// @notice Per-user purchase totals in USD (by CCID)
  mapping(bytes32 ccid => uint256 amountUsd) public userPurchasesUsd;

  /// @notice Per-address purchase totals (fallback if no CCID)
  mapping(address user => uint256 amountUsd) public addressPurchasesUsd;

  // ========== ERRORS ==========

  error Unauthorized();
  error NotFromAuction();
  error Paused();
  error NoCCIDRegistered(address user);
  error NotOnAllowlist(address user);
  error InvalidMerkleProof();
  error PolicyCheckFailed(address user, bytes32 ccid);
  error PerUserLimitExceeded(uint256 requested, uint256 limit, uint256 current);
  error GlobalCapExceeded(uint256 requested, uint256 cap, uint256 current);
  error InvalidPriceData();
  error StalePriceData(uint256 updatedAt, uint256 threshold);
  error ZeroAddress();

  // ========== EVENTS ==========

  /// @notice Emitted when permitter is initialized
  event Initialized(
    address indexed auction, address indexed owner, uint256 perUserLimitUsd, uint256 globalCapUsd
  );

  /// @notice Emitted when a bid is successfully validated
  event BidValidated(
    address indexed bidOwner,
    bytes32 indexed ccid,
    uint256 amountUsd,
    uint256 userTotalUsd,
    uint256 globalTotalUsd
  );

  /// @notice Emitted when per-user limit is updated
  event PerUserLimitUpdated(uint256 oldLimit, uint256 newLimit);

  /// @notice Emitted when global cap is updated
  event GlobalCapUpdated(uint256 oldCap, uint256 newCap);

  /// @notice Emitted when merkle root is updated
  event MerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);

  /// @notice Emitted when paused state changes
  event PausedStateChanged(bool paused);

  /// @notice Emitted when ownership is transferred
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  // ========== MODIFIERS ==========

  modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
  }

  modifier whenNotPaused() {
    if (paused) revert Paused();
    _;
  }

  // ========== INITIALIZATION ==========

  /// @notice Initializes the permitter (called by factory)
  /// @param _owner The owner of this permitter
  /// @param config The configuration from the factory
  function initialize(address _owner, Config calldata config) external initializer {
    if (_owner == address(0)) revert ZeroAddress();
    if (config.auction == address(0)) revert ZeroAddress();

    owner = _owner;
    auction = config.auction;
    identityRegistry = IIdentityRegistry(config.identityRegistry);
    policyEngine = IPolicyEngine(config.policyEngine);
    priceOracle = AggregatorV3Interface(config.priceOracle);
    merkleRoot = config.merkleRoot;
    perUserLimitUsd = config.perUserLimitUsd;
    globalCapUsd = config.globalCapUsd > 0 ? config.globalCapUsd : DEFAULT_GLOBAL_CAP_USD;
    bidTokenDecimals = config.bidTokenDecimals;
    requireSanctionsCheck = config.requireSanctionsCheck;
    requireAllowlist = config.requireAllowlist;

    emit Initialized(config.auction, _owner, config.perUserLimitUsd, globalCapUsd);
  }

  // ========== VALIDATION HOOK ==========

  /// @notice Validates a bid according to configured policies
  /// @param amount Currency amount being bid
  /// @param bidOwner Address receiving purchased tokens or refunds (the buyer)
  /// @param hookData Merkle proof if allowlist is required
  /// @dev Reverts if validation fails
  function validate(uint256, uint128 amount, address bidOwner, address, bytes calldata hookData)
    external
    override
    whenNotPaused
  {
    // Only allow calls from the auction contract
    if (msg.sender != auction) revert NotFromAuction();

    // Check allowlist if required
    if (requireAllowlist) _checkAllowlist(bidOwner, hookData);

    // Get the user's CCID
    bytes32 ccid = _getCCID(bidOwner);

    // Check sanctions via Policy Engine if required
    if (requireSanctionsCheck) _checkSanctions(bidOwner, ccid);

    // Convert bid amount to USD
    uint256 amountUsd = _convertToUsd(amount);

    // Check per-user limit
    _checkPerUserLimit(bidOwner, ccid, amountUsd);

    // Check global cap
    _checkGlobalCap(amountUsd);

    // Update state
    _recordPurchase(bidOwner, ccid, amountUsd);

    emit BidValidated(bidOwner, ccid, amountUsd, _getUserTotal(bidOwner, ccid), totalPurchasesUsd);
  }

  // ========== INTERNAL FUNCTIONS ==========

  /// @notice Gets the CCID for a user
  function _getCCID(address user) internal view returns (bytes32) {
    if (address(identityRegistry) == address(0)) return bytes32(0);
    return identityRegistry.getIdentity(user);
  }

  /// @notice Checks if user is on the allowlist
  function _checkAllowlist(address user, bytes calldata hookData) internal view {
    if (merkleRoot == bytes32(0)) {
      // No merkle root set, allowlist is effectively disabled
      return;
    }

    // Decode the merkle proof from hookData
    bytes32[] memory proof = abi.decode(hookData, (bytes32[]));

    // Compute the leaf
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user))));

    // Verify the proof
    if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert NotOnAllowlist(user);
  }

  /// @notice Checks sanctions status via Policy Engine
  function _checkSanctions(address user, bytes32 ccid) internal view {
    // If no CCID and sanctions required, revert
    if (ccid == bytes32(0)) revert NoCCIDRegistered(user);

    // If no policy engine configured, skip
    if (address(policyEngine) == address(0)) return;

    // Build payload for policy engine
    IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
      selector: this.validate.selector, sender: user, calldata_: abi.encode(ccid), context: ""
    });

    // Check policy - this will revert if policy rejects
    IPolicyEngine.PolicyResult result = policyEngine.check(payload);
    if (result == IPolicyEngine.PolicyResult.None) revert PolicyCheckFailed(user, ccid);
  }

  /// @notice Converts bid amount to USD using price oracle
  function _convertToUsd(uint128 amount) internal view returns (uint256) {
    if (address(priceOracle) == address(0)) {
      // If no oracle, assume amount is already in USD (scaled to 18 decimals)
      return _scaleToUsd(uint256(amount), bidTokenDecimals);
    }

    (, int256 price,, uint256 updatedAt,) = priceOracle.latestRoundData();

    // Validate price data
    if (price <= 0) revert InvalidPriceData();
    if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
      revert StalePriceData(updatedAt, PRICE_STALENESS_THRESHOLD);
    }

    // Get oracle decimals
    uint8 oracleDecimals = priceOracle.decimals();

    // Convert: amountUsd = amount * price, normalized to 18 decimals
    // amount has bidTokenDecimals, price has oracleDecimals
    // Result should have 18 decimals
    uint256 amountUsd =
      (uint256(amount) * uint256(price) * 1e18) / (10 ** oracleDecimals) / (10 ** bidTokenDecimals);

    return amountUsd;
  }

  /// @notice Scales an amount to 18 decimals
  function _scaleToUsd(uint256 amount, uint8 decimals) internal pure returns (uint256) {
    if (decimals == 18) return amount;
    if (decimals < 18) return amount * (10 ** (18 - decimals));
    return amount / (10 ** (decimals - 18));
  }

  /// @notice Checks if purchase would exceed per-user limit
  function _checkPerUserLimit(address user, bytes32 ccid, uint256 amountUsd) internal view {
    if (perUserLimitUsd == 0) return; // No limit set

    uint256 currentTotal = _getUserTotal(user, ccid);

    if (currentTotal + amountUsd > perUserLimitUsd) {
      revert PerUserLimitExceeded(amountUsd, perUserLimitUsd, currentTotal);
    }
  }

  /// @notice Gets the total purchases for a user
  function _getUserTotal(address user, bytes32 ccid) internal view returns (uint256) {
    if (ccid != bytes32(0)) return userPurchasesUsd[ccid];
    return addressPurchasesUsd[user];
  }

  /// @notice Checks if purchase would exceed global cap
  function _checkGlobalCap(uint256 amountUsd) internal view {
    if (totalPurchasesUsd + amountUsd > globalCapUsd) {
      revert GlobalCapExceeded(amountUsd, globalCapUsd, totalPurchasesUsd);
    }
  }

  /// @notice Records a purchase
  function _recordPurchase(address user, bytes32 ccid, uint256 amountUsd) internal {
    if (ccid != bytes32(0)) userPurchasesUsd[ccid] += amountUsd;
    else addressPurchasesUsd[user] += amountUsd;
    totalPurchasesUsd += amountUsd;
  }

  // ========== VIEW FUNCTIONS ==========

  /// @notice Gets remaining purchase capacity for a user
  /// @param user The user address
  /// @return remaining The remaining capacity in USD (18 decimals)
  function getRemainingUserCapacity(address user) external view returns (uint256 remaining) {
    if (perUserLimitUsd == 0) return type(uint256).max;

    bytes32 ccid = _getCCID(user);
    uint256 current = _getUserTotal(user, ccid);

    if (current >= perUserLimitUsd) return 0;
    return perUserLimitUsd - current;
  }

  /// @notice Gets remaining global capacity
  /// @return remaining The remaining capacity in USD (18 decimals)
  function getRemainingGlobalCapacity() external view returns (uint256 remaining) {
    if (totalPurchasesUsd >= globalCapUsd) return 0;
    return globalCapUsd - totalPurchasesUsd;
  }

  /// @notice Gets total purchases for a user
  /// @param user The user address
  /// @return total The total purchases in USD (18 decimals)
  function getUserPurchases(address user) external view returns (uint256 total) {
    bytes32 ccid = _getCCID(user);
    return _getUserTotal(user, ccid);
  }

  // ========== ADMIN FUNCTIONS ==========

  /// @notice Updates the per-user limit
  /// @param newLimit New limit in USD (18 decimals)
  function setPerUserLimit(uint256 newLimit) external onlyOwner {
    emit PerUserLimitUpdated(perUserLimitUsd, newLimit);
    perUserLimitUsd = newLimit;
  }

  /// @notice Updates the global cap
  /// @param newCap New cap in USD (18 decimals)
  function setGlobalCap(uint256 newCap) external onlyOwner {
    emit GlobalCapUpdated(globalCapUsd, newCap);
    globalCapUsd = newCap;
  }

  /// @notice Updates the merkle root for allowlist
  /// @param newRoot New merkle root
  function setMerkleRoot(bytes32 newRoot) external onlyOwner {
    emit MerkleRootUpdated(merkleRoot, newRoot);
    merkleRoot = newRoot;
  }

  /// @notice Pauses or unpauses the permitter
  /// @param _paused New paused state
  function setPaused(bool _paused) external onlyOwner {
    paused = _paused;
    emit PausedStateChanged(_paused);
  }

  /// @notice Transfers ownership
  /// @param newOwner New owner address
  function transferOwnership(address newOwner) external onlyOwner {
    if (newOwner == address(0)) revert ZeroAddress();
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}
