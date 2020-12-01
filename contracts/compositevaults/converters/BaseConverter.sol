// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/IUniswapV2Router.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../libraries/Math.sol";
import "../../interfaces/Balancer.sol";
import "../../interfaces/OneSplitAudit.sol";

import "../ILpPairConverter.sol";
import "./ConverterHelper.sol";
import "./IDecimals.sol";

abstract contract BaseConverter is ILpPairConverter {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public governance;

    IUniswapV2Router public uniswapRouter = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router public sushiswapRouter = IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address public lpUni;
    address public lpSlp;
    address public lpBpt;

    // To calculate virtual_price (dollar value)
    OneSplitAudit public oneSplitAudit = OneSplitAudit(0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E);
    IERC20 public tokenUSDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint private unlocked = 1;
    uint public preset_virtual_price = 0;

    modifier lock() {
        require(unlocked == 1, 'Converter: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor (
        IUniswapV2Router _uniswapRouter,
        IUniswapV2Router _sushiswapRouter,
        address _lpUni, address _lpSlp, address _lpBpt,
        OneSplitAudit _oneSplitAudit,
        IERC20 _usdc
    ) public {
        if (address(_uniswapRouter) != address(0)) uniswapRouter = _uniswapRouter;
        if (address(_sushiswapRouter) != address(0)) sushiswapRouter = _sushiswapRouter;

        lpUni = _lpUni;
        lpSlp = _lpSlp;
        lpBpt = _lpBpt;

        address token0_ = IUniswapV2Pair(lpUni).token0();
        address token1_ = IUniswapV2Pair(lpUni).token1();

        IERC20(lpUni).safeApprove(address(uniswapRouter), type(uint256).max);
        IERC20(token0_).safeApprove(address(uniswapRouter), type(uint256).max);
        IERC20(token1_).safeApprove(address(uniswapRouter), type(uint256).max);

        IERC20(lpSlp).safeApprove(address(sushiswapRouter), type(uint256).max);
        IERC20(token0_).safeApprove(address(sushiswapRouter), type(uint256).max);
        IERC20(token1_).safeApprove(address(sushiswapRouter), type(uint256).max);

        IERC20(token0_).safeApprove(address(lpBpt), type(uint256).max);
        IERC20(token1_).safeApprove(address(lpBpt), type(uint256).max);

        if (address(_oneSplitAudit) != address(0)) oneSplitAudit = _oneSplitAudit;
        if (address(_usdc) != address(0)) tokenUSDC = _usdc;

        governance = msg.sender;
    }

    function getName() public virtual pure returns (string memory);

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function approveForSpender(IERC20 _token, address _spender, uint _amount) external {
        require(msg.sender == governance, "!governance");
        _token.safeApprove(_spender, _amount);
    }

    function set_preset_virtual_price(uint _preset_virtual_price) public {
        require(msg.sender == governance, "!governance");
        preset_virtual_price = _preset_virtual_price;
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(to, amount);
    }
}
