// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only mock of a canonical Robinhood Stock Token surface.
contract MockStockToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public uiMultiplier = 1e18;
    bool public oraclePaused;

    constructor(string memory symbol_, string memory name_) {
        symbol = symbol_;
        name = name_;
    }

    function setUiMultiplier(uint256 value) external {
        uiMultiplier = value;
    }

    function setOraclePaused(bool paused) external {
        oraclePaused = paused;
    }

    // Test-only token plumbing so MockAdapter can deliver purchases and the RewardVault can
    // PULL custody (approve/transferFrom) like a real ERC-20.
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 value) external {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "MST: allowance too low");
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "MST: balance too low");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
