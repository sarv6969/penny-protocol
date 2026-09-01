// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only Chainlink AggregatorV3 stub with settable rounds.
contract MockAggregatorV3 {
    uint8 public decimals;
    uint80 public roundId = 1;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;
    bool public revertOnRead;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        answer = answer_;
        updatedAt = block.timestamp;
    }

    function set(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
        roundId += 1;
        answeredInRound = roundId;
    }

    function setStaleRound() external {
        // answeredInRound < roundId => unfinished round
        roundId += 1;
    }

    function setRevert(bool r) external {
        revertOnRead = r;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!revertOnRead, "AGG: down");
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}
