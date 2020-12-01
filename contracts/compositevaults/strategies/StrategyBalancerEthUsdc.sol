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

contract StrategyBalancerEthUsdc is StrategyBase {
    uint public blocksToReleaseCompound = 7 * 6500; // 7 days to release all the new compounding amount

    // lpPair       = 0x8a649274E4d777FFC6851F13d23A86BBFA2f2Fbf (BPT ETH-USDC 50/50)
    // token0       = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
    // token1       = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 (WETH)
    // farmingToken = 0xba100000625a3754423978a60c9317c58a424e3D (BAL)
    constructor(address _converter, address _farmingToken, address _weth, address _controller) public
        StrategyBase(_converter, _farmingToken, _weth, _controller) {
    }

    function getName() public override pure returns (string memory) {
        return "StrategyBalancerEthUsdc";
    }

    function deposit() public override {
        // do nothing
    }

    function _withdrawSome(uint) internal override returns (uint) {
        return 0;
    }

    function _withdrawAll() internal override {
        // do nothing
    }

    function claimReward() public override {
        // do nothing
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
        }
    }

    function balanceOfPool() public override view returns (uint) {
        return 0;
    }

    function claimable_tokens() external override view returns (uint) {
        return 0;
    }

    function setBlocksToReleaseCompound(uint _blocks) external onlyStrategist {
        blocksToReleaseCompound = _blocks;
    }
}
