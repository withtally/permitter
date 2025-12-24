// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";

/// @title MockIdentityRegistry
/// @notice Mock CCID Identity Registry for testing
contract MockIdentityRegistry is IIdentityRegistry {
  mapping(address account => bytes32 ccid) internal _identities;
  mapping(bytes32 ccid => address[] accounts) internal _accounts;

  /// @notice Registers an identity for an account
  function registerIdentity(address account, bytes32 ccid) external {
    _identities[account] = ccid;
    _accounts[ccid].push(account);
  }

  /// @notice Removes an identity for an account
  function removeIdentity(address account) external {
    bytes32 ccid = _identities[account];
    delete _identities[account];

    // Remove from accounts array
    address[] storage accounts = _accounts[ccid];
    for (uint256 i = 0; i < accounts.length; i++) {
      if (accounts[i] == account) {
        accounts[i] = accounts[accounts.length - 1];
        accounts.pop();
        break;
      }
    }
  }

  /// @inheritdoc IIdentityRegistry
  function getIdentity(address account) external view override returns (bytes32) {
    return _identities[account];
  }

  /// @inheritdoc IIdentityRegistry
  function getAccounts(bytes32 ccid) external view override returns (address[] memory) {
    return _accounts[ccid];
  }
}
