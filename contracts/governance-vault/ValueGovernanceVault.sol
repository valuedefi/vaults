// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

import "./IController.sol";

interface ITokenInterface is IERC20 {
    /** VALUE, YFV, vUSD, vETH has minters **/
    function minters(address account) external view returns (bool);
    function mint(address _to, uint _amount) external;

    /** YFV <-> VALUE **/
    function deposit(uint _amount) external;
    function withdraw(uint _amount) external;
    function cap() external returns (uint);
    function yfvLockedBalance() external returns (uint);
}

interface IYFVReferral {
    function setReferrer(address farmer, address referrer) external;
    function getReferrer(address farmer) external view returns (address);
}

interface IFreeFromUpTo {
    function freeFromUpTo(address from, uint valueToken) external returns (uint freed);
}

contract ValueGovernanceVault is ERC20 {
    using Address for address;
    using SafeMath for uint;

    IFreeFromUpTo public constant chi = IFreeFromUpTo(0x0000000000004946c0e9F43F4Dee607b0eF1fA1c);

    modifier discountCHI(uint8 _flag) {
        if ((_flag & 0x1) == 0) {
            _;
        } else {
            uint gasStart = gasleft();
            _;
            uint gasSpent = 21000 + gasStart - gasleft() + 16 * msg.data.length;
            chi.freeFromUpTo(msg.sender, (gasSpent + 14154) / 41130);
        }
    }

    ITokenInterface public yfvToken; // stake and wrap to VALUE
    ITokenInterface public valueToken; // stake and reward token
    ITokenInterface public vUSD; // reward token
    ITokenInterface public vETH; // reward token

    uint public fundCap = 9500; // use up to 95% of fund (to keep small withdrawals cheap)
    uint public constant FUND_CAP_DENOMINATOR = 10000;

    uint public earnLowerlimit;

    address public governance;
    address public controller;
    address public rewardReferral;

    // Info of each user.
    struct UserInfo {
        uint amount;
        uint valueRewardDebt;
        uint vusdRewardDebt;
        uint lastStakeTime;
        uint accumulatedStakingPower; // will accumulate every time user harvest

        uint lockedAmount;
        uint lockedDays; // 7 days -> 150 days (5 months)
        uint boostedExtra; // times 1e12 (285200000000 -> +28.52%). See below.
        uint unlockedTime;
    }

    uint maxLockedDays = 150;

    uint lastRewardBlock;  // Last block number that reward distribution occurs.
    uint accValuePerShare; // Accumulated VALUEs per share, times 1e12. See below.
    uint accVusdPerShare; // Accumulated vUSD per share, times 1e12. See below.

    uint public valuePerBlock; // 0.2 VALUE/block at start
    uint public vusdPerBlock; // 5 vUSD/block at start

    mapping(address => UserInfo) public userInfo;
    uint public totalDepositCap;

    uint public constant vETH_REWARD_FRACTION_RATE = 1000;
    uint public minStakingAmount = 0 ether;
    uint public unstakingFrozenTime = 40 hours;
    // ** unlockWithdrawFee = 1.92%: stakers will need to pay 1.92% (sent to insurance fund) of amount they want to withdraw if the coin still frozen
    uint public unlockWithdrawFee = 192; // per ten thousand (eg. 15 -> 0.15%)
    address public valueInsuranceFund = 0xb7b2Ea8A1198368f950834875047aA7294A2bDAa; // set to Governance Multisig at start

    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);
    event CommissionPaid(address indexed user, uint reward);
    event Locked(address indexed user, uint amount, uint _days);
    event EmergencyWithdraw(address indexed user, uint amount);

    constructor (ITokenInterface _yfvToken,
        ITokenInterface _valueToken,
        ITokenInterface _vUSD,
        ITokenInterface _vETH,
        uint _valuePerBlock,
        uint _vusdPerBlock,
        uint _startBlock) public ERC20("GovVault:ValueLiquidity", "gvVALUE") {
        yfvToken = _yfvToken;
        valueToken = _valueToken;
        vUSD = _vUSD;
        vETH = _vETH;
        valuePerBlock = _valuePerBlock;
        vusdPerBlock = _vusdPerBlock;
        lastRewardBlock = _startBlock;
        governance = msg.sender;
    }

    function balance() public view returns (uint) {
        uint bal = valueToken.balanceOf(address(this));
        if (controller != address(0)) bal = bal.add(IController(controller).balanceOf(address(valueToken)));
        return bal;
    }

    function setFundCap(uint _fundCap) external {
        require(msg.sender == governance, "!governance");
        fundCap = _fundCap;
    }

    function setTotalDepositCap(uint _totalDepositCap) external {
        require(msg.sender == governance, "!governance");
        totalDepositCap = _totalDepositCap;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setRewardReferral(address _rewardReferral) external {
        require(msg.sender == governance, "!governance");
        rewardReferral = _rewardReferral;
    }

    function setEarnLowerlimit(uint _earnLowerlimit) public {
        require(msg.sender == governance, "!governance");
        earnLowerlimit = _earnLowerlimit;
    }

    function setMaxLockedDays(uint _maxLockedDays) public {
        require(msg.sender == governance, "!governance");
        maxLockedDays = _maxLockedDays;
    }

    function setValuePerBlock(uint _valuePerBlock) public {
        require(msg.sender == governance, "!governance");
        require(_valuePerBlock <= 10 ether, "Too big _valuePerBlock"); // <= 10 VALUE
        updateReward();
        valuePerBlock = _valuePerBlock;
    }

    function setVusdPerBlock(uint _vusdPerBlock) public {
        require(msg.sender == governance, "!governance");
        require(_vusdPerBlock <= 200 * (10 ** 9), "Too big _vusdPerBlock"); // <= 200 vUSD
        updateReward();
        vusdPerBlock = _vusdPerBlock;
    }

    function setMinStakingAmount(uint _minStakingAmount) public {
        require(msg.sender == governance, "!governance");
        minStakingAmount = _minStakingAmount;
    }

    function setUnstakingFrozenTime(uint _unstakingFrozenTime) public {
        require(msg.sender == governance, "!governance");
        unstakingFrozenTime = _unstakingFrozenTime;
    }

    function setUnlockWithdrawFee(uint _unlockWithdrawFee) public {
        require(msg.sender == governance, "!governance");
        require(_unlockWithdrawFee <= 1000, "Dont be too greedy"); // <= 10%
        unlockWithdrawFee = _unlockWithdrawFee;
    }

    function setValueInsuranceFund(address _valueInsuranceFund) public {
        require(msg.sender == governance, "!governance");
        valueInsuranceFund = _valueInsuranceFund;
    }

    // To upgrade vUSD contract (v1 is still experimental, we may need vUSDv2 with rebase() function working soon - then governance will call this upgrade)
    function upgradeVUSDContract(address _vUSDContract) public {
        require(msg.sender == governance, "!governance");
        vUSD = ITokenInterface(_vUSDContract);
    }

    // To upgrade vETH contract (v1 is still experimental, we may need vETHv2 with rebase() function working soon - then governance will call this upgrade)
    function upgradeVETHContract(address _vETHContract) public {
        require(msg.sender == governance, "!governance");
        vETH = ITokenInterface(_vETHContract);
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint) {
        return valueToken.balanceOf(address(this)).mul(fundCap).div(FUND_CAP_DENOMINATOR);
    }

    function earn(uint8 _flag) public discountCHI(_flag) {
        if (controller != address(0)) {
            uint _amount = available();
            uint _accepted = IController(controller).maxAcceptAmount(address(valueToken));
            if (_amount > _accepted) _amount = _accepted;
            if (_amount > 0) {
                yfvToken.transfer(controller, _amount);
                IController(controller).earn(address(yfvToken), _amount);
            }
        }
    }

    function getRewardAndDepositAll(uint8 _flag) external discountCHI(_flag) {
        unstake(0, 0x0);
        depositAll(address(0), 0x0);
    }

    function depositAll(address _referrer, uint8 _flag) public discountCHI(_flag) {
        deposit(valueToken.balanceOf(msg.sender), _referrer, 0x0);
    }

    function deposit(uint _amount, address _referrer, uint8 _flag) public discountCHI(_flag) {
        uint _pool = balance();
        uint _before = valueToken.balanceOf(address(this));
        valueToken.transferFrom(msg.sender, address(this), _amount);
        uint _after = valueToken.balanceOf(address(this));
        require(totalDepositCap == 0 || _after <= totalDepositCap, ">totalDepositCap");
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint _shares = _deposit(address(this), _pool, _amount);
        _stakeShares(msg.sender, _shares, _referrer);
    }

    function depositYFV(uint _amount, address _referrer, uint8 _flag) public discountCHI(_flag) {
        uint _pool = balance();
        yfvToken.transferFrom(msg.sender, address(this), _amount);
        uint _before = valueToken.balanceOf(address(this));
        yfvToken.approve(address(valueToken), 0);
        yfvToken.approve(address(valueToken), _amount);
        valueToken.deposit(_amount);
        uint _after = valueToken.balanceOf(address(this));
        require(totalDepositCap == 0 || _after <= totalDepositCap, ">totalDepositCap");
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint _shares = _deposit(address(this), _pool, _amount);
        _stakeShares(msg.sender, _shares, _referrer);
    }

    function buyShares(uint _amount, uint8 _flag) public discountCHI(_flag) {
        uint _pool = balance();
        uint _before = valueToken.balanceOf(address(this));
        valueToken.transferFrom(msg.sender, address(this), _amount);
        uint _after = valueToken.balanceOf(address(this));
        require(totalDepositCap == 0 || _after <= totalDepositCap, ">totalDepositCap");
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        _deposit(msg.sender, _pool, _amount);
    }

    function depositShares(uint _shares, address _referrer, uint8 _flag) public discountCHI(_flag) {
        require(totalDepositCap == 0 || balance().add(_shares) <= totalDepositCap, ">totalDepositCap");
        uint _before = balanceOf(address(this));
        IERC20(address(this)).transferFrom(msg.sender, address(this), _shares);
        uint _after = balanceOf(address(this));
        _shares = _after.sub(_before); // Additional check for deflationary tokens
        _stakeShares(msg.sender, _shares, _referrer);
    }

    function lockShares(uint _locked, uint _days, uint8 _flag) external discountCHI(_flag) {
        require(_days >= 7 && _days <= maxLockedDays, "_days out-of-range");
        UserInfo storage user = userInfo[msg.sender];
        if (user.unlockedTime < block.timestamp) {
            user.lockedAmount = 0;
        } else {
            require(_days >= user.lockedDays, "Extra days should not less than current locked days");
        }
        user.lockedAmount = user.lockedAmount.add(_locked);
        require(user.lockedAmount <= user.amount, "lockedAmount > amount");
        user.unlockedTime = block.timestamp.add(_days * 86400);
        // (%) = 5 + (lockedDays - 7) * 0.15
        user.boostedExtra = 50000000000 + (_days - 7) * 1500000000;
        emit Locked(msg.sender, user.lockedAmount, _days);
    }

    function _deposit(address _mintTo, uint _pool, uint _amount) internal returns (uint _shares) {
        _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        if (_shares > 0) {
            if (valueToken.balanceOf(address(this)) > earnLowerlimit) {
                earn(0x0);
            }
            _mint(_mintTo, _shares);
        }
    }

    function _stakeShares(address _account, uint _shares, address _referrer) internal {
        UserInfo storage user = userInfo[_account];
        require(minStakingAmount == 0 || user.amount.add(_shares) >= minStakingAmount, "<minStakingAmount");
        updateReward();
        _getReward();
        user.amount = user.amount.add(_shares);
        if (user.lockedAmount > 0 && user.unlockedTime < block.timestamp) {
            user.lockedAmount = 0;
        }
        user.valueRewardDebt = user.amount.mul(accValuePerShare).div(1e12);
        user.vusdRewardDebt = user.amount.mul(accVusdPerShare).div(1e12);
        user.lastStakeTime = block.timestamp;
        emit Deposit(_account, _shares);
        if (rewardReferral != address(0) && _account != address(0)) {
            IYFVReferral(rewardReferral).setReferrer(_account, _referrer);
        }
    }

    function unfrozenStakeTime(address _account) public view returns (uint) {
        return userInfo[_account].lastStakeTime + unstakingFrozenTime;
    }

    // View function to see pending VALUEs on frontend.
    function pendingValue(address _account) public view returns (uint _pending) {
        UserInfo storage user = userInfo[_account];
        uint _accValuePerShare = accValuePerShare;
        uint lpSupply = balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint numBlocks = block.number.sub(lastRewardBlock);
            _accValuePerShare = accValuePerShare.add(numBlocks.mul(valuePerBlock).mul(1e12).div(lpSupply));
        }
        _pending = user.amount.mul(_accValuePerShare).div(1e12).sub(user.valueRewardDebt);
        if (user.lockedAmount > 0 && user.unlockedTime >= block.timestamp) {
            uint _bonus = _pending.mul(user.lockedAmount.mul(user.boostedExtra).div(1e12)).div(user.amount);
            uint _ceilingBonus = _pending.mul(33).div(100); // 33%
            if (_bonus > _ceilingBonus) _bonus = _ceilingBonus; // Additional check to avoid insanely high bonus!
            _pending = _pending.add(_bonus);
        }
    }

    // View function to see pending vUSDs on frontend.
    function pendingVusd(address _account) public view returns (uint) {
        UserInfo storage user = userInfo[_account];
        uint _accVusdPerShare = accVusdPerShare;
        uint lpSupply = balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint numBlocks = block.number.sub(lastRewardBlock);
            _accVusdPerShare = accVusdPerShare.add(numBlocks.mul(vusdPerBlock).mul(1e12).div(lpSupply));
        }
        return user.amount.mul(_accVusdPerShare).div(1e12).sub(user.vusdRewardDebt);
    }

    // View function to see pending vETHs on frontend.
    function pendingVeth(address _account) public view returns (uint) {
        return pendingVusd(_account).div(vETH_REWARD_FRACTION_RATE);
    }

    function stakingPower(address _account) public view returns (uint) {
        return userInfo[_account].accumulatedStakingPower.add(pendingValue(_account));
    }

    function updateReward() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint lpSupply = balanceOf(address(this));
        if (lpSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint _numBlocks = block.number.sub(lastRewardBlock);
        accValuePerShare = accValuePerShare.add(_numBlocks.mul(valuePerBlock).mul(1e12).div(lpSupply));
        accVusdPerShare = accVusdPerShare.add(_numBlocks.mul(vusdPerBlock).mul(1e12).div(lpSupply));
        lastRewardBlock = block.number;
    }

    function _getReward() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint _pendingValue = user.amount.mul(accValuePerShare).div(1e12).sub(user.valueRewardDebt);
        if (_pendingValue > 0) {
            if (user.lockedAmount > 0) {
                if (user.unlockedTime < block.timestamp) {
                    user.lockedAmount = 0;
                } else {
                    uint _bonus = _pendingValue.mul(user.lockedAmount.mul(user.boostedExtra).div(1e12)).div(user.amount);
                    uint _ceilingBonus = _pendingValue.mul(33).div(100); // 33%
                    if (_bonus > _ceilingBonus) _bonus = _ceilingBonus; // Additional check to avoid insanely high bonus!
                    _pendingValue = _pendingValue.add(_bonus);
                }
            }
            user.accumulatedStakingPower = user.accumulatedStakingPower.add(_pendingValue);
            uint actualPaid = _pendingValue.mul(99).div(100); // 99%
            uint commission = _pendingValue - actualPaid; // 1%
            safeValueMint(msg.sender, actualPaid);
            address _referrer = address(0);
            if (rewardReferral != address(0)) {
                _referrer = IYFVReferral(rewardReferral).getReferrer(msg.sender);
            }
            if (_referrer != address(0)) { // send commission to referrer
                safeValueMint(_referrer, commission);
                CommissionPaid(_referrer, commission);
            } else { // send commission to valueInsuranceFund
                safeValueMint(valueInsuranceFund, commission);
                CommissionPaid(valueInsuranceFund, commission);
            }
        }
        uint _pendingVusd = user.amount.mul(accVusdPerShare).div(1e12).sub(user.vusdRewardDebt);
        if (_pendingVusd > 0) {
            safeVusdMint(msg.sender, _pendingVusd);
        }
    }

    function withdrawAll(uint8 _flag) public discountCHI(_flag) {
        UserInfo storage user = userInfo[msg.sender];
        uint _amount = user.amount;
        if (user.lockedAmount > 0) {
            if (user.unlockedTime < block.timestamp) {
                user.lockedAmount = 0;
            } else {
                _amount = user.amount.sub(user.lockedAmount);
            }
        }
        unstake(_amount, 0x0);
        withdraw(balanceOf(msg.sender), 0x0);
    }

    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint amount) external {
        require(msg.sender == controller, "!controller");
        require(reserve != address(valueToken), "token");
        ITokenInterface(reserve).transfer(controller, amount);
    }

    function unstake(uint _amount, uint8 _flag) public discountCHI(_flag) returns (uint _actualWithdraw) {
        updateReward();
        _getReward();
        UserInfo storage user = userInfo[msg.sender];
        _actualWithdraw = _amount;
        if (_amount > 0) {
            require(user.amount >= _amount, "stakedBal < _amount");
            if (user.lockedAmount > 0) {
                if (user.unlockedTime < block.timestamp) {
                    user.lockedAmount = 0;
                } else {
                    require(user.amount.sub(user.lockedAmount) >= _amount, "stakedBal-locked < _amount");
                }
            }
            user.amount = user.amount.sub(_amount);

            if (block.timestamp < user.lastStakeTime.add(unstakingFrozenTime)) {
                // if coin is still frozen and governance does not allow stakers to unstake before timer ends
                if (unlockWithdrawFee == 0 || valueInsuranceFund == address(0)) revert("Coin is still frozen");

                // otherwise withdrawFee will be calculated based on the rate
                uint _withdrawFee = _amount.mul(unlockWithdrawFee).div(10000);
                uint r = _amount.sub(_withdrawFee);
                if (_amount > r) {
                    _withdrawFee = _amount.sub(r);
                    _actualWithdraw = r;
                    IERC20(address(this)).transfer(valueInsuranceFund, _withdrawFee);
                    emit RewardPaid(valueInsuranceFund, _withdrawFee);
                }
            }

            IERC20(address(this)).transfer(msg.sender, _actualWithdraw);
        }
        user.valueRewardDebt = user.amount.mul(accValuePerShare).div(1e12);
        user.vusdRewardDebt = user.amount.mul(accVusdPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint _shares, uint8 _flag) public discountCHI(_flag) {
        uint _userBal = balanceOf(msg.sender);
        if (_shares > _userBal) {
            uint _need = _shares.sub(_userBal);
            require(_need <= userInfo[msg.sender].amount, "_userBal+staked < _shares");
            uint _actualWithdraw = unstake(_need, 0x0);
            _shares = _userBal.add(_actualWithdraw); // may be less than expected due to unlockWithdrawFee
        }
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint b = valueToken.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            if (controller != address(0)) {
                IController(controller).withdraw(address(valueToken), _withdraw);
            }
            uint _after = valueToken.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        valueToken.transfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint) {
        return balance().mul(1e18).div(totalSupply());
    }

    function getStrategyCount() external view returns (uint) {
        return (controller != address(0)) ? IController(controller).getStrategyCount(address(this)) : 0;
    }

    function depositAvailable() external view returns (bool) {
        return (controller != address(0)) ? IController(controller).depositAvailable(address(this)) : false;
    }

    function harvestAllStrategies(uint8 _flag) public discountCHI(_flag) {
        if (controller != address(0)) {
            IController(controller).harvestAllStrategies(address(this));
        }
    }

    function harvestStrategy(address _strategy, uint8 _flag) public discountCHI(_flag) {
        if (controller != address(0)) {
            IController(controller).harvestStrategy(address(this), _strategy);
        }
    }

    // Safe valueToken mint, ensure it is never over cap and we are the current owner.
    function safeValueMint(address _to, uint _amount) internal {
        if (valueToken.minters(address(this)) && _to != address(0)) {
            uint totalSupply = valueToken.totalSupply();
            uint realCap = valueToken.cap().add(valueToken.yfvLockedBalance());
            if (totalSupply.add(_amount) > realCap) {
                valueToken.mint(_to, realCap.sub(totalSupply));
            } else {
                valueToken.mint(_to, _amount);
            }
        }
    }

    // Safe vUSD mint, ensure we are the current owner.
    // vETH will be minted together with fixed rate.
    function safeVusdMint(address _to, uint _amount) internal {
        if (vUSD.minters(address(this)) && _to != address(0)) {
            vUSD.mint(_to, _amount);
        }
        if (vETH.minters(address(this)) && _to != address(0)) {
            vETH.mint(_to, _amount.div(vETH_REWARD_FRACTION_RATE));
        }
    }

    // This is for governance in some emergency circumstances to release lock immediately for an account
    function governanceResetLocked(address _account) external {
        require(msg.sender == governance, "!governance");
        UserInfo storage user = userInfo[_account];
        user.lockedAmount = 0;
        user.lockedDays = 0;
        user.boostedExtra = 0;
        user.unlockedTime = 0;
    }

    // This function allows governance to take unsupported tokens out of the contract, since this pool exists longer than the others.
    // This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these.
    // It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(IERC20 _token, uint _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        require(address(_token) != address(valueToken) || balance().sub(_amount) >= totalSupply(), "cant withdraw VALUE more than gvVALUE supply");
        _token.transfer(_to, _amount);
    }
}
