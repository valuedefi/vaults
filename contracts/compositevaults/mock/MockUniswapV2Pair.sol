// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapV2Pair {
    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;

    uint internal _totalSupply;

    address public token0;
    address public token1;

    mapping(address => uint) private _balance;
    mapping(address => mapping(address => uint)) private _allowance;

    event Approval(address indexed src, address indexed dst, uint amt);
    event Transfer(address indexed src, address indexed dst, uint amt);

    // Math
    function add(uint a, uint b) internal pure returns (uint c) {
        require((c = a + b) >= a);
    }

    function sub(uint a, uint b) internal pure returns (uint c) {
        require((c = a - b) <= a);
    }

    constructor(string memory name, string memory symbol, address _token0, address _token1) public {
        _name = name;
        _symbol = symbol;
        token0 = _token0;
        token1 = _token1;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function _move(address src, address dst, uint amt) internal {
        require(_balance[src] >= amt, "ERR_INSUFFICIENT");
        _balance[src] = sub(_balance[src], amt);
        _balance[dst] = add(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint amt) internal {
        _move(from, address(this), amt);
    }

    function _mint(address dst, uint amt) internal {
        _balance[dst] = add(_balance[dst], amt);
        _totalSupply = add(_totalSupply, amt);
        emit Transfer(address(0), dst, amt);
    }

    function allowance(address src, address dst) external view returns (uint) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view returns (uint) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    function approve(address dst, uint amt) external returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function faucet(uint256 amt) public returns (bool) {
        _mint(msg.sender, amt);
        return true;
    }

    function mintTo(address dst, uint amt) public returns (bool) {
        _mint(dst, amt);
        return true;
    }

    function burn(uint amt) public returns (bool) {
        _burn(msg.sender, amt);
        return true;
    }

    function _burn(address dst, uint amt) internal returns (bool) {
        require(_balance[dst] >= amt, "ERR_INSUFFICIENT");
        _balance[dst] = sub(_balance[dst], amt);
        _totalSupply = sub(_totalSupply, amt);
        emit Transfer(dst, address(0), amt);
        return true;
    }

    function transfer(address dst, uint amt) external returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(address src, address dst, uint amt) external returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_BAD_CALLER");
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != uint256(- 1)) {
            _allowance[src][msg.sender] = sub(_allowance[src][msg.sender], amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }

    function getBalance(address _token) external view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }
}
