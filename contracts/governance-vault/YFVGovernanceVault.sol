pragma solidity 0.5.17;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    function name() external view returns (string memory);

    function mint(address account, uint amount) external;

    function burn(uint amount) external;

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /** YFV, vUSD, vETH has minters **/
    function minters(address account) external view returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Context {
    constructor () internal {}
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {codehash := extcodehash(account)}
        return (codehash != 0x0 && codehash != accountHash);
    }

    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success,) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {// Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IController {
    function withdraw(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function doHardWork(address, uint256) external;
    function yfvInsuranceFund() external view returns (address);
    function performanceReward() external view returns (address);
}

interface IYFVReferral {
    function setReferrer(address farmer, address referrer) external;
    function getReferrer(address farmer) external view returns (address);
}

contract YFVGovernanceVault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public stakeToken;
    IERC20 public yfv = IERC20(0x45f24BaEef268BB6d63AEe5129015d69702BCDfa);
    IERC20 public vUSD = IERC20(0x1B8E12F839BD4e73A47adDF76cF7F0097d74c14C);
    IERC20 public vETH = IERC20(0x76A034e76Aa835363056dd418611E4f81870f16e);

    uint256 public fundCap = 9500; // use up to 95% of fund (to keep small withdrawals cheap)
    uint256 public constant FUND_CAP_DENOMINATOR = 10000;

    uint256 public earnLowerlimit;

    address public governance;
    address public controller;
    address public rewardReferral;

    struct Staker {
        uint256 stake;
        uint256 payout;
        uint256 total_out;
    }

    mapping(address => Staker) public stakers; // stakerAddress -> staker's info

    struct Global {
        uint256 total_stake;
        uint256 total_out;
        uint256 earnings_per_share;
    }

    Global public global; // global data
    uint256 constant internal magnitude = 10 ** 40;

    string public getName;

    uint256 public vETH_REWARD_FRACTION_RATE = 1000;

    uint256 public constant DURATION = 7 days;
    uint8 public constant NUMBER_EPOCHS = 38;

    uint256 public constant REFERRAL_COMMISSION_PERCENT = 1;

    uint256 public currentEpochReward = 0;
    uint256 public totalAccumulatedReward = 0;
    uint8 public currentEpoch = 0;
    uint256 public starttime = 1598968800; // Tuesday, September 1, 2020 2:00:00 PM (GMT+0)
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public constant DEFAULT_EPOCH_REWARD = 230000 * (10 ** 9); // 230,000 vUSD (and 230 vETH)
    uint256 public constant TOTAL_REWARD = DEFAULT_EPOCH_REWARD * NUMBER_EPOCHS; // 8,740,000 vUSD (and 8,740 vETH)

    uint256 public epochReward = DEFAULT_EPOCH_REWARD;
    uint256 public minStakingAmount = 0;
    uint256 public unstakingFrozenTime = 40 hours;

    // ** unlockWithdrawFee = 1.92%: stakers will need to pay 1.92% (sent to insurance fund)of amount they want to withdraw if the coin still frozen
    uint256 public unlockWithdrawFee = 0; // per ten thousand (eg. 15 -> 0.15%)

    address public yfvInsuranceFund = 0xb7b2Ea8A1198368f950834875047aA7294A2bDAa; // set to Governance Multisig at start

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastStakeTimes;

    mapping(address => uint256) public accumulatedStakingPower; // will accumulate every time staker does getReward()

    mapping(address => bool) public whitelistedPools; // for stake on behalf
    mapping(address => bool) public approvedStrategies; // to make_profit

    event RewardAdded(uint256 reward);
    event YfvRewardAdded(uint256 reward);
    event Burned(uint256 reward);
    event Staked(address indexed user, uint256 amount, uint256 actualStakeAmount);
    event Withdrawn(address indexed user, uint256 amount, uint256 actualWithdrawAmount);
    event RewardPaid(address indexed user, uint256 reward);
    event CommissionPaid(address indexed user, uint256 reward);

    constructor (address _stakeToken, uint256 _earnLowerlimit) public {
        require(_stakeToken != address(0), "!_stakeToken");
        stakeToken = IERC20(_stakeToken);
        getName = string(abi.encodePacked("yfv:GovVault:", IERC20(_stakeToken).name()));
        earnLowerlimit = _earnLowerlimit;
        governance = tx.origin;
        whitelistedPools[0x62a9fE913eb596C8faC0936fd2F51064022ba22e] = true; // BAL Pool
        whitelistedPools[0x70b83A7f5E83B3698d136887253E0bf426C9A117] = true; // YFI Pool
        whitelistedPools[0x1c990fC37F399C935625b815975D0c9fAD5C31A1] = true; // BAT Pool
        whitelistedPools[0x752037bfEf024Bd2669227BF9068cb22840174B0] = true; // REN Pool
        whitelistedPools[0x9b74774f55C0351fD064CfdfFd35dB002C433092] = true; // KNC Pool
        whitelistedPools[0xFBDE07329FFc9Ec1b70f639ad388B94532b5E063] = true; // BTC Pool
        whitelistedPools[0x67FfB615EAEb8aA88fF37cCa6A32e322286a42bb] = true; // ETH Pool
        whitelistedPools[0x196CF719251579cBc850dED0e47e972b3d7810Cd] = true; // LINK Pool
        whitelistedPools[msg.sender] = true; // to be able to stakeOnBehalf farmer who have stucked fund in Pool Stake v1.
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function balance() public view returns (uint256) {
        return stakeToken.balanceOf(address(this))
            .add(IController(controller).balanceOf(address(stakeToken)));
    }

    function setFundCap(uint256 _fundCap) external {
        require(msg.sender == governance, "!governance");
        fundCap = _fundCap;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setEarnLowerlimit(uint256 _earnLowerlimit) public {
        require(msg.sender == governance, "!governance");
        earnLowerlimit = _earnLowerlimit;
    }

    function addWhitelistedPool(address _addressPool) public {
        require(msg.sender == governance, "!governance");
        whitelistedPools[_addressPool] = true;
    }

    function removeWhitelistedPool(address _addressPool) public {
        require(msg.sender == governance, "!governance");
        whitelistedPools[_addressPool] = false;
    }

    function approveStrategy(address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_strategy] = true;
    }

    function unapproveStrategy(address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_strategy] = false;
    }

    function setYfvInsuranceFund(address _yfvInsuranceFund) public {
        require(msg.sender == governance, "!governance");
        yfvInsuranceFund = _yfvInsuranceFund;
    }

    function setEpochReward(uint256 _epochReward) public {
        require(msg.sender == governance, "!governance");
        require(_epochReward <= DEFAULT_EPOCH_REWARD * 10, "Insane big _epochReward!"); // At most 10x only
        epochReward = _epochReward;
    }

    function setMinStakingAmount(uint256 _minStakingAmount) public {
        require(msg.sender == governance, "!governance");
        minStakingAmount = _minStakingAmount;
    }

    function setUnstakingFrozenTime(uint256 _unstakingFrozenTime) public {
        require(msg.sender == governance, "!governance");
        unstakingFrozenTime = _unstakingFrozenTime;
    }

    function setUnlockWithdrawFee(uint256 _unlockWithdrawFee) public {
        require(msg.sender == governance, "!governance");
        require(_unlockWithdrawFee <= 1000, "Dont be too greedy"); // <= 10%
        unlockWithdrawFee = _unlockWithdrawFee;
    }

    // To upgrade vUSD contract (v1 is still experimental, we may need vUSDv2 with rebase() function working soon - then governance will call this upgrade)
    function upgradeVUSDContract(address _vUSDContract) public {
        require(msg.sender == governance, "!governance");
        require(_vUSDContract != address(0), "!_vUSDContract");
        vUSD = IERC20(_vUSDContract);
    }

    // To upgrade vETH contract (v1 is still experimental, we may need vETHv2 with rebase() function working soon - then governance will call this upgrade)
    function upgradeVETHContract(address _vETHContract) public {
        require(msg.sender == governance, "!governance");
        require(_vETHContract != address(0), "!_vETHContract");
        vETH = IERC20(_vETHContract);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp < periodFinish) return block.timestamp;
        else return periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (global.total_stake == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(global.total_stake)
        );
    }

    // vUSD balance
    function earned(address account) public view returns (uint256) {
        return stakers[account].stake
            .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
            .div(1e18)
            .add(rewards[account]);
    }

    function stakingPower(address account) public view returns (uint256) {
        return accumulatedStakingPower[account].add(earned(account));
    }

    function vETHBalance(address account) public view returns (uint256) {
        return earned(account).div(vETH_REWARD_FRACTION_RATE);
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint256) {
        return stakeToken.balanceOf(address(this)).mul(fundCap).div(FUND_CAP_DENOMINATOR);
    }

    function doHardWork() public {
        uint256 _bal = available();
        stakeToken.safeTransfer(controller, _bal);
        IController(controller).doHardWork(address(stakeToken), _bal);
    }

    function stake(uint256 amount, address referrer) public updateReward(msg.sender) checkNextEpoch {
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        stakers[msg.sender].stake = stakers[msg.sender].stake.add(amount);
        require(stakers[msg.sender].stake > minStakingAmount, "Cannot stake below minStakingAmount");

        if (global.earnings_per_share != 0) {
            stakers[msg.sender].payout = stakers[msg.sender].payout.add(
                global.earnings_per_share.mul(amount).sub(1).div(magnitude).add(1)
            );
        }
        global.total_stake = global.total_stake.add(amount);

        if (stakeToken.balanceOf(address(this)) > earnLowerlimit) {
            doHardWork();
        }

        lastStakeTimes[msg.sender] = block.timestamp;
        if (rewardReferral != address(0) && referrer != address(0)) {
            IYFVReferral(rewardReferral).setReferrer(msg.sender, referrer);
        }
    }

    function unfrozenStakeTime(address account) public view returns (uint256) {
        return lastStakeTimes[account] + unstakingFrozenTime;
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 amount) public updateReward(msg.sender) checkNextEpoch {
        require(amount > 0, "Cannot withdraw 0");
        claim();
        require(amount <= stakers[msg.sender].stake, "!balance");
        uint256 actualWithdrawAmount = amount;

        // Check balance
        uint256 b = stakeToken.balanceOf(address(this));
        if (b < actualWithdrawAmount) {
            uint256 _withdraw = actualWithdrawAmount.sub(b);
            IController(controller).withdraw(address(stakeToken), _withdraw);
            uint256 _after = stakeToken.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                actualWithdrawAmount = b.add(_diff);
            }
        }

        stakers[msg.sender].payout = stakers[msg.sender].payout.sub(
            global.earnings_per_share.mul(amount).div(magnitude)
        );

        stakers[msg.sender].stake = stakers[msg.sender].stake.sub(amount);
        global.total_stake = global.total_stake.sub(amount);

        if (block.timestamp < unfrozenStakeTime(msg.sender)) {
            // if coin is still frozen and governance does not allow stakers to unstake before timer ends
            if (unlockWithdrawFee == 0) revert("Coin is still frozen");

            // otherwise withdrawFee will be calculated based on the rate
            uint256 withdrawFee = amount.mul(unlockWithdrawFee).div(10000);
            uint256 r = amount.sub(withdrawFee);
            if (actualWithdrawAmount > r) {
                withdrawFee = actualWithdrawAmount.sub(r);
                actualWithdrawAmount = r;
                if (yfvInsuranceFund != address(0)) { // send fee to insurance
                    yfv.safeTransfer(yfvInsuranceFund, withdrawFee);
                    emit RewardPaid(yfvInsuranceFund, withdrawFee);
                } else { // or burn
                    yfv.burn(withdrawFee);
                    emit Burned(withdrawFee);
                }
            }
        }

        stakeToken.safeTransfer(msg.sender, actualWithdrawAmount);
        emit Withdrawn(msg.sender, amount, actualWithdrawAmount);
    }

    function make_profit(uint256 amount) public {
        require(amount > 0, "not 0");
        require(approvedStrategies[msg.sender], "!approved strategy");
        yfv.safeTransferFrom(msg.sender, address(this), amount);
        global.earnings_per_share = global.earnings_per_share.add(
            amount.mul(magnitude).div(global.total_stake)
        );
        global.total_out = global.total_out.add(amount);
    }

    function cal_out(address user) public view returns (uint256) {
        uint256 _cal = global.earnings_per_share.mul(stakers[user].stake).div(magnitude);
        if (_cal < stakers[user].payout) {
            return 0;
        } else {
            return _cal.sub(stakers[user].payout);
        }
    }

    function cal_out_pending(uint256 _pendingBalance, address user) public view returns (uint256) {
        uint256 _earnings_per_share = global.earnings_per_share.add(
            _pendingBalance.mul(magnitude).div(global.total_stake)
        );
        uint256 _cal = _earnings_per_share.mul(stakers[user].stake).div(magnitude);
        _cal = _cal.sub(cal_out(user));
        if (_cal < stakers[user].payout) {
            return 0;
        } else {
            return _cal.sub(stakers[user].payout);
        }
    }

    function claim() public {
        uint256 out = cal_out(msg.sender);
        stakers[msg.sender].payout = global.earnings_per_share.mul(stakers[msg.sender].stake).div(magnitude);
        stakers[msg.sender].total_out = stakers[msg.sender].total_out.add(out);

        if (out > 0) {
            yfv.safeTransfer(msg.sender, out);
        }
    }

    function exit() external {
        withdraw(stakers[msg.sender].stake);
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkNextEpoch {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            accumulatedStakingPower[msg.sender] = accumulatedStakingPower[msg.sender].add(rewards[msg.sender]);
            rewards[msg.sender] = 0;

            vUSD.safeTransfer(msg.sender, reward);
            vETH.safeTransfer(msg.sender, reward.div(vETH_REWARD_FRACTION_RATE));

            emit RewardPaid(msg.sender, reward);
        }
    }

    modifier checkNextEpoch() {
        if (block.timestamp >= periodFinish) {
            currentEpochReward = epochReward;

            if (totalAccumulatedReward.add(currentEpochReward) > TOTAL_REWARD) {
                currentEpochReward = TOTAL_REWARD.sub(totalAccumulatedReward); // limit total reward
            }

            if (currentEpochReward > 0) {
                if (!vUSD.minters(address(this)) || !vETH.minters(address(this))) {
                    currentEpochReward = 0;
                } else {
                    vUSD.mint(address(this), currentEpochReward);
                    vETH.mint(address(this), currentEpochReward.div(vETH_REWARD_FRACTION_RATE));
                    totalAccumulatedReward = totalAccumulatedReward.add(currentEpochReward);
                }
                currentEpoch++;
            }

            rewardRate = currentEpochReward.div(DURATION);
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(DURATION);
            emit RewardAdded(currentEpochReward);
        }
        _;
    }

    // This function allows governance to take unsupported tokens out of the contract, since this pool exists longer than the other pools.
    // This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these.
    // It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external {
        // only gov
        require(msg.sender == governance, "!governance");

        // cant take staked asset
        require(_token != yfv, "yfv");
        require(_token != stakeToken, "stakeToken");

        // cant take reward asset
        require(_token != vUSD, "vUSD");
        require(_token != vETH, "vETH");

        // transfer to
        _token.safeTransfer(to, amount);
    }
}
