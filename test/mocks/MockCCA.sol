// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IValidationHook} from "../../src/interfaces/IValidationHook.sol";

/// @title MockCCA
/// @notice Mock CCA auction contract for testing validation hooks
contract MockCCA {
  IValidationHook public validationHook;

  constructor(address _validationHook) {
    validationHook = IValidationHook(_validationHook);
  }

  /// @notice Sets the validation hook
  function setValidationHook(address _validationHook) external {
    validationHook = IValidationHook(_validationHook);
  }

  /// @notice Simulates a bid submission that calls the validation hook
  function submitBid(uint256 maxPrice, uint128 amount, address bidOwner, bytes calldata hookData)
    external
  {
    // Call validation hook before processing bid
    validationHook.validate(maxPrice, amount, bidOwner, msg.sender, hookData);

    // In a real CCA, the bid would be processed here
  }
}
