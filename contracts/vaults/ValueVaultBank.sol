// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./v1/strategies/IStrategy.sol";

interface IValueVaultMaster {
    function minorPool() view external returns(address);
    function performanceReward() view external returns(address);
    function minStakeTimeToClaimVaultReward() view external returns(uint256);
}

interface IValueVault {
    function balanceOf(address account) view external returns(uint256);
    function getStrategyCount() external view returns(uint256);
    function depositAvailable() external view returns(bool);
    function strategies(uint256 _index) view external returns(IStrategy);
    function mintByBank(IERC20 _token, address _to, uint256 _amount) external;
    function burnByBank(IERC20 _token, address _account, uint256 _amount) external;
    function harvestAllStrategies(uint256 _bankPoolId) external;
    function harvestStrategy(IStrategy _strategy, uint256 _bankPoolId) external;
}

interface IValueMinorPool {
    function depositOnBehalf(address farmer, uint256 _pid, uint256 _amount, address _referrer) external;
    function withdrawOnBehalf(address farmer, uint256 _pid, uint256 _amount) external;
}

interface IFreeFromUpTo {
    function freeFromUpTo(address from, uint256 value) external returns (uint256 freed);
}

contract ValueVaultBank {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IFreeFromUpTo public constant chi = IFreeFromUpTo(0x0000000000004946c0e9F43F4Dee607b0eF1fA1c);

    modifier discountCHI {
        uint256 gasStart = gasleft();
        _;
        uint256 gasSpent = 21000 + gasStart - gasleft() + 16 * msg.data.length;
//        chi.freeFromUpTo(msg.sender, (gasSpent + 14154) / 41130);
    }

    address public governance;
    IValueVaultMaster public vaultMaster;

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of token contract.
        IValueVault vault; // Address of vault contract.
        uint256 minorPoolId; // minorPool's subpool id
        uint256 startTime;
        uint256 individualCap; // 0 to disable
        uint256 totalCap; // 0 to disable
    }

    // Info of each pool.
    mapping(uint256 => PoolInfo) public poolMap;  // By poolId

    struct Staker {
        uint256 stake;
        uint256 payout;
        uint256 total_out;
    }

    mapping(uint256 => mapping(address => Staker)) public stakers; // poolId -> stakerAddress -> staker's info

    struct Global {
        uint256 total_stake;
        uint256 total_out;
        uint256 earnings_per_share;
    }

    mapping(uint256 => Global) public global; // poolId -> global data

    mapping(uint256 => mapping(address => uint256)) public lastStakeTimes; // poolId -> user's last staked
    uint256 constant internal magnitude = 10 ** 40;

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    event Claim(address indexed user, uint256 indexed poolId);

    constructor() public {
        governance = tx.origin;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
 
    function setVaultMaster(IValueVaultMaster _vaultMaster) external {
        require(msg.sender == governance, "!governance");
        vaultMaster = _vaultMaster;
    }

    function setPoolInfo(uint256 _poolId, IERC20 _token, IValueVault _vault, uint256 _minorPoolId, uint256 _startTime, uint256 _individualCap, uint256 _totalCap) public {
        require(msg.sender == governance, "!governance");
        poolMap[_poolId].token = _token;
        poolMap[_poolId].vault = _vault;
        poolMap[_poolId].minorPoolId = _minorPoolId;
        poolMap[_poolId].startTime = _startTime;
        poolMap[_poolId].individualCap = _individualCap;
        poolMap[_poolId].totalCap = _totalCap;
    }

    function setPoolCap(uint256 _poolId, uint256 _individualCap, uint256 _totalCap) public {
        require(msg.sender == governance, "!governance");
        require(_totalCap == 0 || _totalCap >= _individualCap, "_totalCap < _individualCap");
        poolMap[_poolId].individualCap = _individualCap;
        poolMap[_poolId].totalCap = _totalCap;
    }

    function depositAvailable(uint256 _poolId) external view returns(bool) {
        return poolMap[_poolId].vault.depositAvailable();
    }

    // Deposit tokens to Bank. If we have a strategy, then tokens will be moved there.
    function deposit(uint256 _poolId, uint256 _amount, bool _farmMinorPool, address _referrer) public discountCHI {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "deposit: after startTime");
        require(_amount > 0, "!_amount");
        require(address(pool.vault) != address(0), "pool.vault = 0");
        require(pool.individualCap == 0 || stakers[_poolId][msg.sender].stake.add(_amount) <= pool.individualCap, "Exceed pool.individualCap");
        require(pool.totalCap == 0 || global[_poolId].total_stake.add(_amount) <= pool.totalCap, "Exceed pool.totalCap");

        pool.token.safeTransferFrom(msg.sender, address(pool.vault), _amount);
        pool.vault.mintByBank(pool.token, msg.sender, _amount);
        if (_farmMinorPool && address(vaultMaster) != address(0)) {
            address minorPool = vaultMaster.minorPool();
            if (minorPool != address(0)) {
                IValueMinorPool(minorPool).depositOnBehalf(msg.sender, pool.minorPoolId, pool.vault.balanceOf(msg.sender), _referrer);
            }
        }

        _handleDepositStakeInfo(_poolId, _amount);
        emit Deposit(msg.sender, _poolId, _amount);
    }

    function _handleDepositStakeInfo(uint256 _poolId, uint256 _amount) internal {
        stakers[_poolId][msg.sender].stake = stakers[_poolId][msg.sender].stake.add(_amount);
        if (global[_poolId].earnings_per_share != 0) {
            stakers[_poolId][msg.sender].payout = stakers[_poolId][msg.sender].payout.add(
                global[_poolId].earnings_per_share.mul(_amount).sub(1).div(magnitude).add(1)
            );
        }
        global[_poolId].total_stake = global[_poolId].total_stake.add(_amount);
        lastStakeTimes[_poolId][msg.sender] = block.timestamp;
    }

    // Withdraw tokens from ValueVaultBank (from a strategy first if there is one).
    function withdraw(uint256 _poolId, uint256 _amount, bool _farmMinorPool) public discountCHI {
        PoolInfo storage pool = poolMap[_poolId];
        require(address(pool.vault) != address(0), "pool.vault = 0");
        require(now >= pool.startTime, "withdraw: after startTime");
        require(_amount <= stakers[_poolId][msg.sender].stake, "!balance");

        claimProfit(_poolId);

        if (_farmMinorPool && address(vaultMaster) != address(0)) {
            address minorPool = vaultMaster.minorPool();
            if (minorPool != address(0)) {
                IValueMinorPool(minorPool).withdrawOnBehalf(msg.sender, pool.minorPoolId, _amount);
            }
        }
        pool.vault.burnByBank(pool.token, msg.sender, _amount);
        pool.token.safeTransfer(msg.sender, _amount);

        _handleWithdrawStakeInfo(_poolId, _amount);
        emit Withdraw(msg.sender, _poolId, _amount);
    }

    function _handleWithdrawStakeInfo(uint256 _poolId, uint256 _amount) internal {
        stakers[_poolId][msg.sender].payout = stakers[_poolId][msg.sender].payout.sub(
            global[_poolId].earnings_per_share.mul(_amount).div(magnitude)
        );
        stakers[_poolId][msg.sender].stake = stakers[_poolId][msg.sender].stake.sub(_amount);
        global[_poolId].total_stake = global[_poolId].total_stake.sub(_amount);
    }

    function exit(uint256 _poolId, bool _farmMinorPool) external discountCHI {
        withdraw(_poolId, stakers[_poolId][msg.sender].stake, _farmMinorPool);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _poolId) public {
        uint256 amount = stakers[_poolId][msg.sender].stake;
        poolMap[_poolId].token.safeTransfer(address(msg.sender), amount);
        stakers[_poolId][msg.sender].stake = 0;
        global[_poolId].total_stake = global[_poolId].total_stake.sub(amount);
    }

    function harvestVault(uint256 _poolId) external discountCHI {
        poolMap[_poolId].vault.harvestAllStrategies(_poolId);
    }

    function harvestStrategy(uint256 _poolId, IStrategy _strategy) external discountCHI {
        poolMap[_poolId].vault.harvestStrategy(_strategy, _poolId);
    }

    function make_profit(uint256 _poolId, uint256 _amount) public {
        require(_amount > 0, "not 0");
        PoolInfo storage pool = poolMap[_poolId];
        pool.token.safeTransferFrom(msg.sender, address(this), _amount);
        if (global[_poolId].total_stake > 0) {
            global[_poolId].earnings_per_share = global[_poolId].earnings_per_share.add(
                _amount.mul(magnitude).div(global[_poolId].total_stake)
            );
        }
        global[_poolId].total_out = global[_poolId].total_out.add(_amount);
    }

    function cal_out(uint256 _poolId, address user) public view returns (uint256) {
        uint256 _cal = global[_poolId].earnings_per_share.mul(stakers[_poolId][user].stake).div(magnitude);
        if (_cal < stakers[_poolId][user].payout) {
            return 0;
        } else {
            return _cal.sub(stakers[_poolId][user].payout);
        }
    }

    function cal_out_pending(uint256 _pendingBalance, uint256 _poolId, address user) public view returns (uint256) {
        uint256 _earnings_per_share = global[_poolId].earnings_per_share.add(
            _pendingBalance.mul(magnitude).div(global[_poolId].total_stake)
        );
        uint256 _cal = _earnings_per_share.mul(stakers[_poolId][user].stake).div(magnitude);
        _cal = _cal.sub(cal_out(_poolId, user));
        if (_cal < stakers[_poolId][user].payout) {
            return 0;
        } else {
            return _cal.sub(stakers[_poolId][user].payout);
        }
    }

    function claimProfit(uint256 _poolId) public discountCHI {
        uint256 out = cal_out(_poolId, msg.sender);
        stakers[_poolId][msg.sender].payout = global[_poolId].earnings_per_share.mul(stakers[_poolId][msg.sender].stake).div(magnitude);
        stakers[_poolId][msg.sender].total_out = stakers[_poolId][msg.sender].total_out.add(out);

        if (out > 0) {
            PoolInfo storage pool = poolMap[_poolId];
            uint256 _stakeTime = now - lastStakeTimes[_poolId][msg.sender];
            if (address(vaultMaster) != address(0) && _stakeTime < vaultMaster.minStakeTimeToClaimVaultReward()) { // claim too soon
                uint256 actually_out = _stakeTime.mul(out).mul(1e18).div(vaultMaster.minStakeTimeToClaimVaultReward()).div(1e18);
                uint256 earlyClaimCost = out.sub(actually_out);
                safeTokenTransfer(pool.token, vaultMaster.performanceReward(), earlyClaimCost);
                out = actually_out;
            }
            safeTokenTransfer(pool.token, msg.sender, out);
        }
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough token.
    function safeTokenTransfer(IERC20 _token, address _to, uint256 _amount) internal {
        uint256 bal = _token.balanceOf(address(this));
        if (_amount > bal) {
            _token.safeTransfer(_to, bal);
        } else {
            _token.safeTransfer(_to, _amount);
        }
    }

    /**
     * @dev if there is any token stuck we will need governance support to rescue the fund
     */
    function governanceRescueFromStrategy(IERC20 _token, IStrategy _strategy) external {
        require(msg.sender == governance, "!governance");
        _strategy.governanceRescueToken(_token);
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract.
     * This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these.
     * It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external {
        require(msg.sender == governance, "!governance");
        _token.safeTransfer(to, amount);
    }
}
