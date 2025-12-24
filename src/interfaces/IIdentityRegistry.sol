// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IIdentityRegistry
/// @notice Interface for Chainlink CCID Identity Registry
/// @dev Maps blockchain addresses to cross-chain identities (CCIDs)
interface IIdentityRegistry {
  /// @notice Gets the CCID for an account
  /// @param account The address to look up
  /// @return ccid The cross-chain identity hash (bytes32(0) if not registered)
  function getIdentity(address account) external view returns (bytes32 ccid);

  /// @notice Gets all addresses associated with a CCID on this chain
  /// @param ccid The cross-chain identity
  /// @return accounts Array of addresses linked to the CCID
  function getAccounts(bytes32 ccid) external view returns (address[] memory accounts);
}
