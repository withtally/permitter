// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPolicyEngine} from "../../src/interfaces/IPolicyEngine.sol";

/// @title MockPolicyEngine
/// @notice Mock Chainlink ACE Policy Engine for testing
contract MockPolicyEngine is IPolicyEngine {
  /// @notice Whether to allow all requests
  bool public allowAll = true;

  /// @notice Blocked CCIDs (sanctioned)
  mapping(bytes32 ccid => bool blocked) public blockedCCIDs;

  /// @notice Blocked addresses
  mapping(address user => bool blocked) public blockedAddresses;

  error PolicyRejected(address user, bytes32 ccid);

  /// @notice Sets whether to allow all requests
  function setAllowAll(bool _allowAll) external {
    allowAll = _allowAll;
  }

  /// @notice Blocks a CCID (simulates sanctions)
  function blockCCID(bytes32 ccid) external {
    blockedCCIDs[ccid] = true;
  }

  /// @notice Unblocks a CCID
  function unblockCCID(bytes32 ccid) external {
    blockedCCIDs[ccid] = false;
  }

  /// @notice Blocks an address
  function blockAddress(address user) external {
    blockedAddresses[user] = true;
  }

  /// @notice Unblocks an address
  function unblockAddress(address user) external {
    blockedAddresses[user] = false;
  }

  /// @inheritdoc IPolicyEngine
  function run(Payload memory payload) external view override {
    PolicyResult result = _checkPolicy(payload);
    if (result == PolicyResult.None) {
      bytes32 ccid = abi.decode(payload.calldata_, (bytes32));
      revert PolicyRejected(payload.sender, ccid);
    }
  }

  /// @inheritdoc IPolicyEngine
  function check(Payload memory payload) external view override returns (PolicyResult) {
    return _checkPolicy(payload);
  }

  function _checkPolicy(Payload memory payload) internal view returns (PolicyResult) {
    if (allowAll) {
      return PolicyResult.Allowed;
    }

    // Check if address is blocked
    if (blockedAddresses[payload.sender]) {
      return PolicyResult.None;
    }

    // Check if CCID is blocked
    if (payload.calldata_.length > 0) {
      bytes32 ccid = abi.decode(payload.calldata_, (bytes32));
      if (blockedCCIDs[ccid]) {
        return PolicyResult.None;
      }
    }

    return PolicyResult.Allowed;
  }
}
