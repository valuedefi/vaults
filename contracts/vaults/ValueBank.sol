// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./strategies/IStrategy.sol";

interface IValueVault {
    function getStrategyCount() view external returns(uint256);
    function strategies(uint256 _index) view external returns(IStrategy);
    function rewards(address _who, uint256 _index) view external returns(uint256);
    function mintByBank(address _to, uint256 _amount) external;
    function burnByBank(address _account, uint256 _amount) external;
    function clearRewardByBank(address _who) external;
}

contract ValueBank is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of token contract.
        IValueVault vault; // Address of vault contract.
        uint256 startTime;
    }

    /* 
  function make_profit(uint256 amount) public discountCHI {
         require(amount > 0, "not 0");
        value.safeTransferFrom(msg.sender, address(this), amount);
        global.earnings_per_share = global.earnings_per_share.add(
            amount.mul(magnitude).div(global.total_stake)
        );
        global.total_out = global.total_out.add(amount);
    }*/

    /**     struct Global {
        uint256 total_stake;
        uint256 total_out;
        uint256 earnings_per_share;
    }

    Global public global; // global data
     */

    // Info of each pool.
    mapping (uint256 => PoolInfo) public poolMap;  // By poolId

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    event Claim(address indexed user, uint256 indexed poolId);

    constructor() public {
    }

    function setPoolInfo(uint256 _poolId, IERC20 _token, IValueVault _vault, uint256 _startTime) public onlyOwner {
        poolMap[_poolId].token = _token;
        poolMap[_poolId].vault = _vault;
        poolMap[_poolId].startTime = _startTime;
    }

    function _handleDeposit(IValueVault _vault, IERC20 _token, uint256 _amount) internal {
        uint256 count = _vault.getStrategyCount();
        require(count == 1 || count == 2, "_handleDeposit: count");

        // NOTE: strategy0 is always the main strategy.
        address strategy0 = address(_vault.strategies(0));
        _token.safeTransferFrom(address(msg.sender), strategy0, _amount);
    }

    function _handleWithdraw(IValueVault _vault, IERC20 _token, uint256 _amount) internal {
        uint256 count = _vault.getStrategyCount();
        require(count == 1 || count == 2, "_handleWithdraw: count");

        address strategy0 = address(_vault.strategies(0));
        _token.safeTransferFrom(strategy0, address(msg.sender), _amount);
    }

    function _handleRewards(IValueVault _vault) internal {
        uint256 count = _vault.getStrategyCount();

        for (uint256 i = 0; i < count; ++i) {
            uint256 rewardPending = _vault.rewards(msg.sender, i);
            if (rewardPending > 0) {
                IERC20(_vault.strategies(i).getTargetToken()).safeTransferFrom(
                    address(_vault.strategies(i)), msg.sender, rewardPending);
            }
        }

        _vault.clearRewardByBank(msg.sender);
    }

    // Deposit tokens to ValueBank for SODA allocation.
    // If we have a strategy, then tokens will be moved there.
    function deposit(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "deposit: after startTime");

        _handleDeposit(pool.vault, pool.token, _amount);
        pool.vault.mintByBank(msg.sender, _amount);

        emit Deposit(msg.sender, _poolId, _amount);
    }

    // Claim SODA (and potentially other tokens depends on strategy).
    function claim(uint256 _poolId) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "claim: after startTime");

        pool.vault.mintByBank(msg.sender, 0);
        _handleRewards(pool.vault);

        emit Claim(msg.sender, _poolId);
    }

    // Withdraw tokens from ValueBank (from a strategy first if there is one).
    function withdraw(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "withdraw: after startTime");

        pool.vault.burnByBank(msg.sender, _amount);

        _handleWithdraw(pool.vault, pool.token, _amount);
        _handleRewards(pool.vault);

        emit Withdraw(msg.sender, _poolId, _amount);
    }
}
