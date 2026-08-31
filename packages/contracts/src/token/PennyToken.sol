// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @notice Fixed-supply PENNY token. No post-constructor minting, no transfer
///         tax, no blacklist, no pause, no seizure, no hidden balance mutation.
contract PennyToken is ERC20, ERC20Permit {
    constructor(uint256 totalSupply_, address initialRecipient) ERC20("Penny Stocks", "PENNY") ERC20Permit("Penny Stocks") {
        require(initialRecipient != address(0), "PENNY: zero recipient");
        _mint(initialRecipient, totalSupply_);
    }
}
