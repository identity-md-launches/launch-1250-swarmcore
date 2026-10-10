// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SwarmCore (SWORE)
/// @notice A fixed supply of one billion tokens with 18 decimals, minted once to the deployer.
/// @dev Uses standard ERC-20 transfers and allowances. There are no administrative powers.
contract SwarmCore is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev During a factory launch, msg.sender is the factory, which receives the entire supply.
    constructor() ERC20("SwarmCore", "SWORE") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
