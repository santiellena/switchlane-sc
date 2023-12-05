// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MyToken is ERC20, ERC20Permit {
    constructor() ERC20("Switchlane Test", "SLN") ERC20Permit("Switchlane Test") {
        _mint(msg.sender, 2000 * 10 ** decimals());
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
