// SPDX-License-Identifier: WTFPL

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";
import "../ValueVaultMaster.sol";

interface ISodaPool {
    // Deposit LP tokens to SodaPool for SODA allocation
    function deposit(uint256 _poolId, uint256 _amount) external;
    // Withdraw LP tokens from SodaPool
    function withdraw(uint256 _poolId, uint256 _amount) external;
}

interface ISodaVault {
    function getPendingReward(address _who, uint256 _index) external view returns (uint256);
}

// This contract is owned by Timelock.
// What it does is simple: deposit WETH to soda.finance, and wait for ValueBank's command.
contract WETHDrinkSoda is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 constant PER_SHARE_SIZE = 1e12;

    ISodaPool public sodaPool;
    ISodaVault public sodaVault;

    ValueVaultMaster public valueVaultMaster;
    IERC20 public sodaToken;

    struct PoolInfo {
        IERC20 lpToken;
        uint256 poolId;  // poolId in soda pool.
    }

    mapping(address => PoolInfo) public poolMap;  // By vault.
    mapping(address => uint256) private valuePerShare;  // By vault.

    // weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    // sodaToken = "0x7AfB39837Fd244A651e4F0C5660B4037214D4aDF"
    // sodaPool = "0x74BCb8b78996F49F46497be185174B2a89191fD6"
    // sodaWETHVault = "0x8d5d838Db2522C187A3062CAd0C7d55158F31EbF"
    // wethPId = 0
    constructor(ValueVaultMaster _valueVaultMaster,
                IERC20 _sodaToken,
                ISodaPool _sodaPool,
                ISodaVault _sodaVault) public {
        valueVaultMaster = _valueVaultMaster;
        sodaToken = _sodaToken;
        sodaPool = _sodaPool;
        sodaVault = _sodaVault;
        // Approve all
        sodaToken.approve(valueVaultMaster.bank(), type(uint256).max);
    }

    function approve(IERC20 _token) external override onlyOwner {
        _token.approve(valueVaultMaster.bank(), type(uint256).max);
        _token.approve(address(sodaPool), type(uint256).max);
    }

    function setPoolInfo(
        address _vault,
        IERC20 _lpToken,
        uint256 _sodaPoolId
    ) external onlyOwner {
        poolMap[_vault].lpToken = _lpToken;
        poolMap[_vault].poolId = _sodaPoolId;
        _lpToken.approve(valueVaultMaster.bank(), type(uint256).max);
        _lpToken.approve(address(sodaPool), type(uint256).max);
    }

    function getValuePerShare(address _vault) external view override returns(uint256) {
        return valuePerShare[_vault];
    }

    function pendingValuePerShare(address _vault) external view override returns (uint256) {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount == 0) {
            return 0;
        }

        uint256 amount = sodaVault.getPendingReward(poolMap[_vault].poolId, address(this));
        return amount.mul(PER_SHARE_SIZE).div(shareAmount);
    }

    function _update(address _vault, uint256 _tokenAmountDelta) internal {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount > 0) {
            valuePerShare[_vault] = valuePerShare[_vault].add(
                _tokenAmountDelta.mul(PER_SHARE_SIZE).div(shareAmount));
        }
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) public override {
        require(valueVaultMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = sodaToken.balanceOf(address(this));
        sodaPool.deposit(poolMap[_vault].poolId, _amount);
        uint256 tokenAmountAfter = sodaToken.balanceOf(address(this));

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) external override {
        require(valueVaultMaster.isVault(msg.sender), "sender not vault");

        // Sushi is strage that it uses deposit to claim.
        deposit(_vault, 0);
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) external override {
        require(valueVaultMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = sodaToken.balanceOf(address(this));
        sodaPool.withdraw(poolMap[_vault].poolId, _amount);
        uint256 tokenAmountAfter = sodaToken.balanceOf(address(this));

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken() external view override returns(address) {
        return address(sodaToken);
    }
}
