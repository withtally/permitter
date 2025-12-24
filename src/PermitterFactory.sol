// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Permitter} from "./Permitter.sol";

/// @title PermitterFactory
/// @notice Factory for creating Permitter validation hooks for CCA auctions
/// @dev Uses EIP-1167 minimal proxies for gas-efficient deployment
contract PermitterFactory {
  using Clones for address;

  // ========== STORAGE ==========

  /// @notice The Permitter implementation contract
  address public immutable IMPLEMENTATION;

  /// @notice Registry of deployed permitters
  mapping(address permitter => bool isValid) public isPermitter;

  /// @notice Permitters created by each address
  mapping(address creator => address[] permitters) internal _permittersByCreator;

  // ========== EVENTS ==========

  /// @notice Emitted when a new Permitter is created
  /// @param permitter The address of the new permitter
  /// @param creator The address that created the permitter
  /// @param auction The CCA auction this permitter validates
  event PermitterCreated(
    address indexed permitter, address indexed creator, address indexed auction
  );

  // ========== ERRORS ==========

  /// @notice Thrown when a zero address is provided where not allowed
  error ZeroAddress();

  // ========== CONSTRUCTOR ==========

  /// @notice Deploys the factory and creates the Permitter implementation
  constructor() {
    IMPLEMENTATION = address(new Permitter());
  }

  // ========== EXTERNAL FUNCTIONS ==========

  /// @notice Creates a new Permitter for an auction
  /// @param config The configuration for the permitter
  /// @return permitter The address of the new permitter
  function createPermitter(Permitter.Config calldata config) external returns (address permitter) {
    if (config.auction == address(0)) revert ZeroAddress();

    // Clone the implementation
    permitter = IMPLEMENTATION.clone();

    // Initialize the clone
    Permitter(permitter).initialize(msg.sender, config);

    // Register the permitter
    isPermitter[permitter] = true;
    _permittersByCreator[msg.sender].push(permitter);

    emit PermitterCreated(permitter, msg.sender, config.auction);
  }

  /// @notice Creates a permitter with deterministic address
  /// @param config The configuration for the permitter
  /// @param salt The salt for deterministic deployment
  /// @return permitter The address of the new permitter
  function createPermitterDeterministic(Permitter.Config calldata config, bytes32 salt)
    external
    returns (address permitter)
  {
    if (config.auction == address(0)) revert ZeroAddress();

    permitter = IMPLEMENTATION.cloneDeterministic(salt);
    Permitter(permitter).initialize(msg.sender, config);
    isPermitter[permitter] = true;
    _permittersByCreator[msg.sender].push(permitter);

    emit PermitterCreated(permitter, msg.sender, config.auction);
  }

  /// @notice Predicts the address of a deterministic permitter
  /// @param salt The salt that would be used for deployment
  /// @return predicted The predicted address
  function predictPermitterAddress(bytes32 salt) external view returns (address predicted) {
    return IMPLEMENTATION.predictDeterministicAddress(salt);
  }

  /// @notice Gets all permitters created by an address
  /// @param creator The creator address
  /// @return permitters Array of permitter addresses
  function getPermittersByCreator(address creator)
    external
    view
    returns (address[] memory permitters)
  {
    return _permittersByCreator[creator];
  }
}
