// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IPolicyEngine
/// @notice Interface for Chainlink ACE Policy Engine
/// @dev Orchestrates policy execution for compliance checks
interface IPolicyEngine {
  /// @notice Payload structure for policy execution
  struct Payload {
    bytes4 selector;
    address sender;
    bytes calldata_;
    bytes context;
  }

  /// @notice Parameter structure for policy configuration
  struct Parameter {
    bytes32 name;
    bytes value;
  }

  /// @notice Policy execution result
  enum PolicyResult {
    None,
    Allowed,
    Continue
  }

  /// @notice Executes policies and reverts on failure
  /// @param payload The payload containing validation data
  /// @dev Reverts if any policy rejects the request
  function run(Payload memory payload) external;

  /// @notice View function for offchain policy validation
  /// @param payload The payload containing validation data
  /// @return result The policy execution result
  function check(Payload memory payload) external view returns (PolicyResult result);
}
