// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title AggregatorV3Interface
/// @notice Interface for Chainlink Price Feeds
/// @dev Standard interface for getting price data from Chainlink oracles
interface AggregatorV3Interface {
  /// @notice Returns the number of decimals in the response
  function decimals() external view returns (uint8);

  /// @notice Returns a human-readable description of the feed
  function description() external view returns (string memory);

  /// @notice Returns the version of the aggregator
  function version() external view returns (uint256);

  /// @notice Gets data from a specific round
  /// @param _roundId The round ID to get data for
  /// @return roundId The round ID
  /// @return answer The price answer
  /// @return startedAt Timestamp when the round started
  /// @return updatedAt Timestamp when the round was updated
  /// @return answeredInRound The round ID in which the answer was computed
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  /// @notice Gets the latest round data
  /// @return roundId The round ID
  /// @return answer The price answer
  /// @return startedAt Timestamp when the round started
  /// @return updatedAt Timestamp when the round was updated
  /// @return answeredInRound The round ID in which the answer was computed
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}
