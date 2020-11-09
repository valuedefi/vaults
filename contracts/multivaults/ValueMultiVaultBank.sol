// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./IValueVaultMaster.sol";
import "./IValueMultiVault.sol";
import "./IMultiVaultConverter.sol";

interface IFreeFromUpTo {
    function freeFromUpTo(address from, uint value) external returns (uint freed);
}

contract ValueMultiVaultBank {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

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

    IERC20 public valueToken = IERC20(0x49E833337ECe7aFE375e44F4E3e8481029218E5c);

    address public governance;
    address public strategist; // who can call harvestXXX()

    IValueVaultMaster public vaultMaster;
    
    struct UserInfo {
        uint amount;
        mapping(uint8 => uint) rewardDebt;
        mapping(uint8 => uint) accumulatedEarned; // will accumulate every time user harvest
    }

    struct RewardPoolInfo {
        IERC20 rewardToken;     // Address of rewardPool token contract.
        uint lastRewardBlock;   // Last block number that rewardPool distribution occurs.
        uint endRewardBlock;    // Block number which rewardPool distribution ends.
        uint rewardPerBlock;    // Reward token amount to distribute per block.
        uint accRewardPerShare; // Accumulated rewardPool per share, times 1e18.
        uint totalPaidRewards;  // for stat only
    }

    mapping(address => RewardPoolInfo[]) public rewardPoolInfos; // vault address => pool info
    mapping(address => mapping(address => UserInfo)) public userInfo; // vault address => account => userInfo

    event Deposit(address indexed vault, address indexed user, uint amount);
    event Withdraw(address indexed vault, address indexed user, uint amount);
    event RewardPaid(address indexed vault, uint pid, address indexed user, uint reward);

    constructor(IERC20 _valueToken, IValueVaultMaster _vaultMaster) public {
        valueToken = _valueToken;
        vaultMaster = _vaultMaster;
        governance = msg.sender;
        strategist = msg.sender;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setVaultMaster(IValueVaultMaster _vaultMaster) external {
        require(msg.sender == governance, "!governance");
        vaultMaster = _vaultMaster;
    }

    function addVaultRewardPool(address _vault, IERC20 _rewardToken, uint _startBlock, uint _endRewardBlock, uint _rewardPerBlock) external {
        require(msg.sender == governance, "!governance");
        RewardPoolInfo[] storage rewardPools = rewardPoolInfos[_vault];
        require(rewardPools.length < 8, "exceed rwdPoolLim");
        _startBlock = (block.number > _startBlock) ? block.number : _startBlock;
        require(_startBlock <= _endRewardBlock, "sVB>eVB");
        updateReward(_vault);
        rewardPools.push(RewardPoolInfo({
            rewardToken : _rewardToken,
            lastRewardBlock : _startBlock,
            endRewardBlock : _endRewardBlock,
            rewardPerBlock : _rewardPerBlock,
            accRewardPerShare : 0,
            totalPaidRewards : 0
            }));
    }

    function updateRewardPool(address _vault, uint8 _pid, uint _endRewardBlock, uint _rewardPerBlock) external {
        require(msg.sender == governance, "!governance");
        updateRewardPool(_vault, _pid);
        RewardPoolInfo storage rewardPool = rewardPoolInfos[_vault][_pid];
        require(block.number <= rewardPool.endRewardBlock, "late");
        rewardPool.endRewardBlock = _endRewardBlock;
        rewardPool.rewardPerBlock = _rewardPerBlock;
    }

    function updateReward(address _vault) public {
        uint8 rewardPoolLength = uint8(rewardPoolInfos[_vault].length);
        for (uint8 _pid = 0; _pid < rewardPoolLength; ++_pid) {
            updateRewardPool(_vault, _pid);
        }
    }

    function updateRewardPool(address _vault, uint8 _pid) public {
        RewardPoolInfo storage rewardPool = rewardPoolInfos[_vault][_pid];
        uint _endRewardBlockApplicable = block.number > rewardPool.endRewardBlock ? rewardPool.endRewardBlock : block.number;
        if (_endRewardBlockApplicable > rewardPool.lastRewardBlock) {
            uint lpSupply = IERC20(address(_vault)).balanceOf(address(this));
            if (lpSupply > 0) {
                uint _numBlocks = _endRewardBlockApplicable.sub(rewardPool.lastRewardBlock);
                uint _incRewardPerShare = _numBlocks.mul(rewardPool.rewardPerBlock).mul(1e18).div(lpSupply);
                rewardPool.accRewardPerShare = rewardPool.accRewardPerShare.add(_incRewardPerShare);
            }
            rewardPool.lastRewardBlock = _endRewardBlockApplicable;
        }
    }

    function cap(IValueMultiVault _vault) external view returns (uint) {
        return _vault.cap();
    }

    function approveForSpender(IERC20 _token, address _spender, uint _amount) external {
        require(msg.sender == governance, "!governance");
        require(!vaultMaster.isVault(address(_token)), "vaultToken");
        _token.safeApprove(_spender, _amount);
    }

    function deposit(IValueMultiVault _vault, address _input, uint _amount, uint _min_mint_amount, bool _isStake, uint8 _flag) public discountCHI(_flag) {
        require(_vault.accept(_input), "vault does not accept this asset");
        require(_amount > 0, "!_amount");

        if (!_isStake) {
            _vault.depositFor(msg.sender, msg.sender, _input, _amount, _min_mint_amount);
        } else {
            uint _mint_amount = _vault.depositFor(msg.sender, address(this), _input, _amount, _min_mint_amount);
            _stakeVaultShares(address(_vault), _mint_amount);
        }
    }

    function depositAll(IValueMultiVault _vault, uint[] calldata _amounts, uint _min_mint_amount, bool _isStake, uint8 _flag) public discountCHI(_flag) {
        if (!_isStake) {
            _vault.depositAllFor(msg.sender, msg.sender, _amounts, _min_mint_amount);
        } else {
            uint _mint_amount = _vault.depositAllFor(msg.sender, address(this), _amounts, _min_mint_amount);
            _stakeVaultShares(address(_vault), _mint_amount);
        }
    }

    function stakeVaultShares(address _vault, uint _shares) external {
        uint _before = IERC20(address(_vault)).balanceOf(address(this));
        IERC20(address(_vault)).safeTransferFrom(msg.sender, address(this), _shares);
        uint _after = IERC20(address(_vault)).balanceOf(address(this));
        _shares = _after.sub(_before); // Additional check for deflationary tokens
        _stakeVaultShares(_vault, _shares);
    }

    function _stakeVaultShares(address _vault, uint _shares) internal {
        UserInfo storage user = userInfo[_vault][msg.sender];
        updateReward(_vault);
        if (user.amount > 0) {
            getAllRewards(_vault, msg.sender, uint8(0));
        }
        user.amount = user.amount.add(_shares);
        RewardPoolInfo[] storage rewardPools = rewardPoolInfos[_vault];
        uint8 rewardPoolLength = uint8(rewardPools.length);
        for (uint8 _pid = 0; _pid < rewardPoolLength; ++_pid) {
            user.rewardDebt[_pid] = user.amount.mul(rewardPools[_pid].accRewardPerShare).div(1e18);
        }
        emit Deposit(_vault, msg.sender, _shares);
    }

    // call unstake(_vault, 0) for getting reward
    function unstake(address _vault, uint _amount, uint8 _flag) public discountCHI(_flag) {
        UserInfo storage user = userInfo[_vault][msg.sender];
        updateReward(_vault);
        if (user.amount > 0) {
            getAllRewards(_vault, msg.sender, uint8(0));
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            IERC20(address(_vault)).safeTransfer(msg.sender, _amount);
        }
        RewardPoolInfo[] storage rewardPools = rewardPoolInfos[_vault];
        uint8 rewardPoolLength = uint8(rewardPools.length);
        for (uint8 _pid = 0; _pid < rewardPoolLength; ++_pid) {
            user.rewardDebt[_pid] = user.amount.mul(rewardPools[_pid].accRewardPerShare).div(1e18);
        }
        emit Withdraw(_vault, msg.sender, _amount);
    }

    // using PUSH pattern
    function getAllRewards(address _vault, address _account, uint8 _flag) public discountCHI(_flag) {
        uint8 rewardPoolLength = uint8(rewardPoolInfos[_vault].length);
        for (uint8 _pid = 0; _pid < rewardPoolLength; ++_pid) {
            getReward(_vault, _pid, _account, uint8(0));
        }
    }

    function getReward(address _vault, uint8 _pid, address _account, uint8 _flag) public discountCHI(_flag) {
        updateRewardPool(_vault, _pid);
        UserInfo storage user = userInfo[_vault][_account];
        RewardPoolInfo storage rewardPool = rewardPoolInfos[_vault][_pid];
        uint _pendingReward = user.amount.mul(rewardPool.accRewardPerShare).div(1e18).sub(user.rewardDebt[_pid]);
        if (_pendingReward > 0) {
            user.accumulatedEarned[_pid] = user.accumulatedEarned[_pid].add(_pendingReward);
            rewardPool.totalPaidRewards = rewardPool.totalPaidRewards.add(_pendingReward);
            safeTokenTransfer(rewardPool.rewardToken, _account, _pendingReward);
            emit RewardPaid(_vault, _pid, _account, _pendingReward);
            user.rewardDebt[_pid] = user.amount.mul(rewardPool.accRewardPerShare).div(1e18);
        }
    }

    function pendingReward(address _vault, uint8 _pid, address _account) public view returns (uint _pending) {
        UserInfo storage user = userInfo[_vault][_account];
        RewardPoolInfo storage rewardPool = rewardPoolInfos[_vault][_pid];
        uint _accRewardPerShare = rewardPool.accRewardPerShare;
        uint lpSupply = IERC20(_vault).balanceOf(address(this));
        uint _endRewardBlockApplicable = block.number > rewardPool.endRewardBlock ? rewardPool.endRewardBlock : block.number;
        if (_endRewardBlockApplicable > rewardPool.lastRewardBlock && lpSupply != 0) {
            uint _numBlocks = _endRewardBlockApplicable.sub(rewardPool.lastRewardBlock);
            uint _incRewardPerShare = _numBlocks.mul(rewardPool.rewardPerBlock).mul(1e18).div(lpSupply);
            _accRewardPerShare = _accRewardPerShare.add(_incRewardPerShare);
        }
        _pending = user.amount.mul(_accRewardPerShare).div(1e18).sub(user.rewardDebt[_pid]);
    }

    function shares_owner(address _vault, address _account) public view returns (uint) {
        return IERC20(_vault).balanceOf(_account).add(userInfo[_vault][_account].amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(address _vault, uint _shares, address _output, uint _min_output_amount, uint8 _flag) public discountCHI(_flag) {
        uint _userBal = IERC20(address(_vault)).balanceOf(msg.sender);
        if (_shares > _userBal) {
            uint _need = _shares.sub(_userBal);
            require(_need <= userInfo[_vault][msg.sender].amount, "_userBal+staked < _shares");
            unstake(_vault, _need, uint8(0));
        }
        IERC20(address(_vault)).safeTransferFrom(msg.sender, address(this), _shares);
        IValueMultiVault(_vault).withdrawFor(msg.sender, _shares, _output, _min_output_amount);
    }

    function exit(address _vault, address _output, uint _min_output_amount, uint8 _flag) external discountCHI(_flag) {
        unstake(_vault, userInfo[_vault][msg.sender].amount, uint8(0));
        withdraw(_vault, IERC20(address(_vault)).balanceOf(msg.sender), _output, _min_output_amount, uint8(0));
    }

    function withdraw_fee(IValueMultiVault _vault, uint _shares) external view returns (uint) {
        return _vault.withdraw_fee(_shares);
    }

    function calc_token_amount_deposit(IValueMultiVault _vault, uint[] calldata _amounts) external view returns (uint) {
        return _vault.calc_token_amount_deposit(_amounts);
    }

    function calc_token_amount_withdraw(IValueMultiVault _vault, uint _shares, address _output) external view returns (uint) {
        return _vault.calc_token_amount_withdraw(_shares, _output);
    }

    function convert_rate(IValueMultiVault _vault, address _input, uint _amount) external view returns (uint) {
        return _vault.convert_rate(_input, _amount);
    }

    function harvestStrategy(IValueMultiVault _vault, address _strategy, uint8 _flag) external discountCHI(_flag) {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _vault.harvestStrategy(_strategy);
    }

    function harvestWant(IValueMultiVault _vault, address _want, uint8 _flag) external discountCHI(_flag) {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _vault.harvestWant(_want);
    }

    function harvestAllStrategies(IValueMultiVault _vault, uint8 _flag) external discountCHI(_flag) {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _vault.harvestAllStrategies();
    }

    // Safe token transfer function, just in case if rounding error causes vinfo to not have enough token.
    function safeTokenTransfer(IERC20 _token, address _to, uint _amount) internal {
        uint bal = _token.balanceOf(address(this));
        if (_amount > bal) {
            _token.safeTransfer(_to, bal);
        } else {
            _token.safeTransfer(_to, _amount);
        }
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint amount, address to) external {
        require(msg.sender == governance, "!governance");
        require(!vaultMaster.isVault(address(_token)), "vaultToken");
        _token.safeTransfer(to, amount);
    }
}
