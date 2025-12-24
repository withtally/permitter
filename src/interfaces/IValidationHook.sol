// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IValidationHook
/// @notice Interface for Uniswap CCA validation hooks
/// @dev Implementations MUST revert if the bid is invalid
interface IValidationHook {
  /// @notice Validates a bid before submission
  /// @param maxPrice The bidder's maximum acceptable price
  /// @param amount Currency amount being bid
  /// @param owner Address receiving purchased tokens or refunds
  /// @param sender The caller submitting the bid
  /// @param hookData Custom data for hook-specific logic
  /// @dev MUST revert if bid is invalid
  function validate(
    uint256 maxPrice,
    uint128 amount,
    address owner,
    address sender,
    bytes calldata hookData
  ) external;
}
