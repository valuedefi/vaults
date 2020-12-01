// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/SushiMasterChef.sol";

import "./StrategyBase.sol";

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

contract StrategySushiEthUsdc is StrategyBase {
    uint public poolId = 1;

    uint public blocksToReleaseCompound = 1 * 6500; // 2 days to release all the new compounding amount

    address public farmingPool;

    // lpPair       = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0 (SLP ETH-USDC)
    // token0       = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
    // token1       = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 (WETH)
    // farmingToken = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2 (SUSHI)
    // farmingPool  = 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd (Sushiswap's MasterChef)
    constructor(address _converter, address _farmingToken, address _farmingPool, address _weth, address _controller) public
        StrategyBase(_converter, _farmingToken, _weth, _controller) {
        farmingPool = _farmingPool;
        IERC20(lpPair).safeApprove(address(farmingPool), type(uint256).max);
    }

    function getName() public override pure returns (string memory) {
        return "StrategySushiEthUsdc";
    }

    function deposit() public override {
        uint _lpPairBal = IERC20(lpPair).balanceOf(address(this));
        if (_lpPairBal > 0) {
            SushiMasterChef(farmingPool).deposit(poolId, _lpPairBal);
        }
    }

    function _withdrawSome(uint _amount) internal override returns (uint) {
        (uint _stakedAmount,) = SushiMasterChef(farmingPool).userInfo(poolId, address(this));
        if (_amount > _stakedAmount) {
            _amount = _stakedAmount;
        }
        uint _before = IERC20(lpPair).balanceOf(address(this));
        SushiMasterChef(farmingPool).withdraw(poolId, _amount);
        uint _after = IERC20(lpPair).balanceOf(address(this));
        _amount = _after.sub(_before);

        return _amount;
    }

    function _withdrawAll() internal override {
        (uint _stakedAmount,) = SushiMasterChef(farmingPool).userInfo(poolId, address(this));
        SushiMasterChef(farmingPool).withdraw(poolId, _stakedAmount);
    }

    function claimReward() public override {
        SushiMasterChef(farmingPool).withdraw(poolId, 0);
    }

    function _buyWantAndReinvest() internal override {
        uint256 _wethBal = IERC20(weth).balanceOf(address(this));
        uint256 _wethToBuyToken0 = _wethBal.mul(495).div(1000); // we have Token1 (WETH) already, so use 49.5% balance to buy Token0 (USDC)
        _swapTokens(weth, token0, _wethToBuyToken0);
        uint _before = IERC20(lpPair).balanceOf(address(this));
        _addLiquidity();
        uint _after = IERC20(lpPair).balanceOf(address(this));
        if (_after > 0) {
            if (_after > _before) {
                uint _compound = _after.sub(_before);
                vault.addNewCompound(_compound, blocksToReleaseCompound);
            }
            deposit();
        }
    }

    function balanceOfPool() public override view returns (uint) {
        (uint amount,) = SushiMasterChef(farmingPool).userInfo(poolId, address(this));
        return amount;
    }

    function claimable_tokens() external override view returns (uint) {
        return SushiMasterChef(farmingPool).pendingSushi(poolId, address(this));
    }

    function setBlocksToReleaseCompound(uint _blocks) external onlyStrategist {
        blocksToReleaseCompound = _blocks;
    }
}
