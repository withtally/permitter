// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ICredentialRegistry
/// @notice Interface for Chainlink CCID Credential Registry
/// @dev Stores and queries credentials associated with CCIDs
interface ICredentialRegistry {
  /// @notice Credential data structure
  struct Credential {
    uint40 expiresAt;
    bytes data;
  }

  /// @notice Checks if a credential is expired
  /// @param ccid The cross-chain identity
  /// @param credentialTypeId The type of credential
  /// @return isExpired True if the credential is expired or doesn't exist
  function isCredentialExpired(
    bytes32 ccid,
    bytes32 credentialTypeId
  ) external view returns (bool isExpired);

  /// @notice Gets a credential for a CCID
  /// @param ccid The cross-chain identity
  /// @param credentialTypeId The type of credential to retrieve
  /// @return credential The credential data
  function getCredential(
    bytes32 ccid,
    bytes32 credentialTypeId
  ) external view returns (Credential memory credential);

  /// @notice Gets all credential types for a CCID
  /// @param ccid The cross-chain identity
  /// @return credentialTypeIds Array of credential type IDs
  function getCredentialTypes(bytes32 ccid) external view returns (bytes32[] memory credentialTypeIds);
}
