// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/// @title MockPriceOracle
/// @notice Mock Chainlink Price Feed for testing
contract MockPriceOracle is AggregatorV3Interface {
  int256 public price;
  uint8 public override decimals;
  uint256 public updatedAt;

  constructor(int256 _price, uint8 _decimals) {
    price = _price;
    decimals = _decimals;
    updatedAt = block.timestamp;
  }

  /// @notice Sets the price
  function setPrice(int256 _price) external {
    price = _price;
    updatedAt = block.timestamp;
  }

  /// @notice Sets the updated timestamp
  function setUpdatedAt(uint256 _updatedAt) external {
    updatedAt = _updatedAt;
  }

  /// @notice Sets price to negative (invalid)
  function setInvalidPrice() external {
    price = -1;
  }

  /// @inheritdoc AggregatorV3Interface
  function description() external pure override returns (string memory) {
    return "Mock Price Oracle";
  }

  /// @inheritdoc AggregatorV3Interface
  function version() external pure override returns (uint256) {
    return 1;
  }

  /// @inheritdoc AggregatorV3Interface
  function getRoundData(uint80 _roundId)
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
  {
    return (_roundId, price, updatedAt, updatedAt, _roundId);
  }

  /// @inheritdoc AggregatorV3Interface
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
  {
    return (1, price, updatedAt, updatedAt, 1);
  }
}
