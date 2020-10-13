// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    address public governance;
    mapping(address => bool) public minters;

    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public ERC20(name, symbol) {
        governance = msg.sender;
        _mint(msg.sender, supply);
    }

    function mint(address account, uint256 amount) public {
        require(minters[msg.sender], "!minter");
        _mint(account, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function addMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = true;
    }

    function removeMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = false;
    }
}
