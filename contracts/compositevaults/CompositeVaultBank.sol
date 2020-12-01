// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol";

import "./IVaultMaster.sol";
import "./ICompositeVault.sol";
import "./ILpPairConverter.sol";

interface IFreeFromUpTo {
    function freeFromUpTo(address from, uint value) external returns (uint freed);
}

contract CompositeVaultBank is ContextUpgradeSafe {
    using Address for address;
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

    address public governance;
    address public strategist; // who can call harvestXXX() and update reward rate

    IVaultMaster public vaultMaster;
    
    struct UserInfo {
        uint amount;
        uint rewardDebt;
        uint accumulatedEarned; // will accumulate every time user harvest
        uint lastStakeTime;
        uint unclaimedReward;
    }

    struct RewardPoolInfo {
        IERC20 rewardToken;     // Address of rewardPool token contract.
        uint lastRewardBlock;   // Last block number that rewardPool distribution occurs.
        uint endRewardBlock;    // Block number which rewardPool distribution ends.
        uint rewardPerBlock;    // Reward token amount to distribute per block.
        uint rewardLockedTime;  // Time to lock reward (in seconds).
        uint accRewardPerShare; // Accumulated rewardPool per share, times 1e18.
        uint totalPaidRewards;  // for stat only
    }

    mapping(address => RewardPoolInfo) public rewardPoolInfo; // vault address => reward info
    mapping(address => mapping(address => UserInfo)) public userInfo; // vault address => account => userInfo

    bool public acceptContractDepositor = false;
    mapping(address => bool) public whitelistedContract;

    event Deposit(address indexed vault, address indexed user, uint amount);
    event Withdraw(address indexed vault, address indexed user, uint amount);
    event RewardPaid(address indexed vault, address indexed user, uint reward);

    function initialize(IVaultMaster _vaultMaster) public initializer {
        vaultMaster = _vaultMaster;
        governance = msg.sender;
        strategist = msg.sender;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    /**
     * @dev Throws if called by a not-whitelisted contract while we do not accept contract depositor.
     */
    modifier checkContract() {
        if (!acceptContractDepositor && !whitelistedContract[msg.sender]) {
            require(!address(msg.sender).isContract() && msg.sender == tx.origin, "contract not support");
        }
        _;
    }

    function setAcceptContractDepositor(bool _acceptContractDepositor) external onlyGovernance {
        acceptContractDepositor = _acceptContractDepositor;
    }

    function whitelistContract(address _contract) external onlyGovernance {
        whitelistedContract[_contract] = true;
    }

    function unwhitelistContract(address _contract) external onlyGovernance {
        whitelistedContract[_contract] = false;
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function setStrategist(address _strategist) external onlyGovernance {
        strategist = _strategist;
    }

    function setVaultMaster(IVaultMaster _vaultMaster) external onlyGovernance {
        vaultMaster = _vaultMaster;
    }

    function addPool(address _vault, IERC20 _rewardToken, uint _startBlock, uint _endRewardBlock, uint _rewardPerBlock, uint _rewardLockedTime) external onlyGovernance {
        _startBlock = (block.number > _startBlock) ? block.number : _startBlock;
        require(_startBlock <= _endRewardBlock, "sVB>eVB");
        rewardPoolInfo[_vault].rewardToken = _rewardToken;
        rewardPoolInfo[_vault].lastRewardBlock = _startBlock;
        rewardPoolInfo[_vault].endRewardBlock = _endRewardBlock;
        rewardPoolInfo[_vault].rewardPerBlock = _rewardPerBlock;
        rewardPoolInfo[_vault].rewardLockedTime = _rewardLockedTime;
        rewardPoolInfo[_vault].accRewardPerShare = 0;
        rewardPoolInfo[_vault].totalPaidRewards = 0;
    }

    function updatePool(address _vault, uint _endRewardBlock, uint _rewardPerBlock, uint _rewardLockedTime) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        updateReward(_vault);
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        require(block.number <= rewardPool.endRewardBlock, "late");
        rewardPool.endRewardBlock = _endRewardBlock;
        rewardPool.rewardPerBlock = _rewardPerBlock;
        rewardPool.rewardLockedTime = _rewardLockedTime;
    }

    function updatePoolReward(address[] calldata _vaults, uint[] calldata _rewardPerBlocks) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        uint leng = _vaults.length;
        uint currTotalRwd = 0;
        uint updatedTotalRwd = 0;
        for (uint i = 0; i < leng; i++) {
            address _vault = _vaults[i];
            RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
            if (block.number < rewardPool.endRewardBlock) {
                updateReward(_vault);
                currTotalRwd = currTotalRwd.add(rewardPool.rewardPerBlock);
                updatedTotalRwd = updatedTotalRwd.add(_rewardPerBlocks[i]);
                rewardPool.rewardPerBlock = _rewardPerBlocks[i];
            }
        }
        require(currTotalRwd <= updatedTotalRwd.mul(4), "over increased");
        require(currTotalRwd.mul(4) >= updatedTotalRwd, "over decreased");
    }

    function updateReward(address _vault) public {
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
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

    function cap(ICompositeVault _vault) external view returns (uint) {
        return _vault.cap();
    }

    function approveForSpender(IERC20 _token, address _spender, uint _amount) external onlyGovernance {
        require(!vaultMaster.isVault(address(_token)), "vaultToken");
        _token.safeApprove(_spender, _amount);
    }

    function calculateMultiMinReceive(ICompositeVault[] calldata _vaults, address _input, uint[] calldata _amounts) external view returns (uint[] memory minReceives) {
        require(_vaults.length == _amounts.length, "Invalid input length data");
        uint leng = _vaults.length;
        minReceives = new uint[](leng);
        for (uint i = 0; i < leng; i++) {
            ICompositeVault vault = _vaults[i];
            minReceives[i] = ILpPairConverter(vault.getConverter()).convert_rate(_input, vault.token(), _amounts[i]);
        }
    }

    function depositMultiVault(ICompositeVault[] calldata _vaults, address _input, uint[] calldata _amounts, uint[] calldata _min_mint_amounts, bool _isStake, uint8 _flag) public discountCHI(_flag) {
        uint leng = _vaults.length;
        for (uint i = 0; i < leng; i++) {
            deposit(_vaults[i], _input, _amounts[i], _min_mint_amounts[i], _isStake, uint8(0));
        }
    }

    function deposit(ICompositeVault _vault, address _input, uint _amount, uint _min_mint_amount, bool _isStake, uint8 _flag) public discountCHI(_flag) checkContract {
        require(_vault.accept(_input), "vault does not accept this asset");
        require(_amount > 0, "!_amount");

        IERC20(_input).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_input).safeIncreaseAllowance(address(_vault), _amount);

        address _token = _vault.token();
        uint _mint_amount;
        if (_token == _input || (_flag & 0x10) > 0) { // bit #1 is to enable donate dust
            _mint_amount = _vault.deposit(_input, _amount, _min_mint_amount);
        } else {
            ILpPairConverter _cnvrt = ILpPairConverter(_vault.getConverter());
            IERC20 _token0 = IERC20(_cnvrt.token0());
            IERC20 _token1 = IERC20(_cnvrt.token1());
            uint _before0 = _token0.balanceOf(address(this));
            uint _before1 = _token1.balanceOf(address(this));
            _mint_amount = _vault.deposit(_input, _amount, _min_mint_amount);
            uint _after0 = _token0.balanceOf(address(this));
            uint _after1 = _token1.balanceOf(address(this));
            if (_after0 > _before0) {
                _token0.safeTransfer(msg.sender, _after0.sub(_before0));
            }
            if (_after1 > _before1) {
                _token1.safeTransfer(msg.sender, _after1.sub(_before1));
            }
        }
        if (!_isStake) {
            IERC20(address(_vault)).safeTransfer(msg.sender, _mint_amount);
        } else {
            _stakeVaultShares(address(_vault), _mint_amount);
        }
    }

    function transferVault(ICompositeVault _srcVault, ICompositeVault _destVault, uint _srcShares, uint _min_mint_amount, bool _isStake, uint8 _flag) public discountCHI(_flag) checkContract {
        address _srcVaultToken = _srcVault.token();
        require(_destVault.accept(_srcVaultToken), "_destVault does not accept _srcVault asset");
        require(_srcShares > 0, "!_srcShares");

        uint _depositAmt;
        {
            uint _wdAmt = _withdraw(address(_srcVault), _srcShares);
            uint _before = IERC20(_srcVaultToken).balanceOf(address(this));
            _srcVault.withdraw(_wdAmt, _srcVaultToken, 1);
            uint _after = IERC20(_srcVaultToken).balanceOf(address(this));
            _depositAmt = _after.sub(_before);
        }

        IERC20(_srcVaultToken).safeIncreaseAllowance(address(_destVault), _depositAmt);

        uint _mint_amount;
        if (_destVault.token() == _srcVaultToken || (_flag & 0x10) > 0) { // bit #1 is to enable donate dust
            _mint_amount = _destVault.deposit(_srcVaultToken, _depositAmt, _min_mint_amount);
        } else {
            IERC20 _token0;
            IERC20 _token1;
            {
                ILpPairConverter _cnvrt = ILpPairConverter(_destVault.getConverter());
                _token0 = IERC20(_cnvrt.token0());
                _token1 = IERC20(_cnvrt.token1());
            }
            uint _before0 = _token0.balanceOf(address(this));
            uint _before1 = _token1.balanceOf(address(this));
            _mint_amount = _destVault.deposit(_srcVaultToken, _depositAmt, _min_mint_amount);
            uint _after0 = _token0.balanceOf(address(this));
            uint _after1 = _token1.balanceOf(address(this));
            if (_after0 > _before0) {
                _token0.safeTransfer(msg.sender, _after0.sub(_before0));
            }
            if (_after1 > _before1) {
                _token1.safeTransfer(msg.sender, _after1.sub(_before1));
            }
        }

        if (!_isStake) {
            IERC20(address(_destVault)).safeTransfer(msg.sender, _mint_amount);
        } else {
            _stakeVaultShares(address(_destVault), _mint_amount);
        }
    }

    function addLiquidity(ICompositeVault _vault, uint _amount0, uint _amount1, uint _min_mint_amount, bool _isStake, uint8 _flag) public discountCHI(_flag) checkContract {
        require(_amount0 > 0 || _amount1 > 0, "!(_amount0 && _amount1)");

        ILpPairConverter _cnvrt = ILpPairConverter(_vault.getConverter());
        IERC20 _token0 = IERC20(_cnvrt.token0());
        IERC20 _token1 = IERC20(_cnvrt.token1());

        _token0.safeTransferFrom(msg.sender, address(this), _amount0);
        _token1.safeTransferFrom(msg.sender, address(this), _amount1);
        _token0.safeIncreaseAllowance(address(_vault), _amount0);
        _token1.safeIncreaseAllowance(address(_vault), _amount1);

        uint _mint_amount;
        if ((_flag & 0x10) > 0) { // bit #1 is to enable donate dust
            _mint_amount = _vault.addLiquidity(_amount0, _amount1, _min_mint_amount);
        } else {
            uint _before0 = _token0.balanceOf(address(this));
            uint _before1 = _token1.balanceOf(address(this));
            _mint_amount = _vault.addLiquidity(_amount0, _amount1, _min_mint_amount);
            uint _after0 = _token0.balanceOf(address(this));
            uint _after1 = _token1.balanceOf(address(this));
            if (_after0 > _before0) {
                _token0.safeTransfer(msg.sender, _after0.sub(_before0));
            }
            if (_after1 > _before1) {
                _token1.safeTransfer(msg.sender, _after1.sub(_before1));
            }
        }

        if (!_isStake) {
            IERC20(address(_vault)).safeTransfer(msg.sender, _mint_amount);
        } else {
            _stakeVaultShares(address(_vault), _mint_amount);
        }
    }

    function stakeVaultShares(address _vault, uint _shares, uint8 _flag) public discountCHI(_flag) {
        uint _before = IERC20(address(_vault)).balanceOf(address(this));
        IERC20(address(_vault)).safeTransferFrom(msg.sender, address(this), _shares);
        uint _after = IERC20(address(_vault)).balanceOf(address(this));
        _shares = _after.sub(_before); // Additional check for deflationary tokens
        _stakeVaultShares(_vault, _shares);
    }

    function _stakeVaultShares(address _vault, uint _shares) internal {
        UserInfo storage user = userInfo[_vault][msg.sender];
        user.lastStakeTime = block.timestamp;
        updateReward(_vault);
        if (user.amount > 0) {
            getReward(_vault, msg.sender, uint8(0));
        }
        user.amount = user.amount.add(_shares);
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        user.rewardDebt = user.amount.mul(rewardPool.accRewardPerShare).div(1e18);
        emit Deposit(_vault, msg.sender, _shares);
    }

    function unfrozenStakeTime(address _vault, address _account) public view returns (uint) {
        UserInfo storage user = userInfo[_vault][_account];
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        return user.lastStakeTime + rewardPool.rewardLockedTime;
    }

    function unstake(address _vault, uint _amount, uint8 _flag) public discountCHI(_flag) {
        UserInfo storage user = userInfo[_vault][msg.sender];
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        updateReward(_vault);
        if (user.amount > 0) {
            getReward(_vault, msg.sender, uint8(0));
            if (user.lastStakeTime + rewardPool.rewardLockedTime > block.timestamp) {
                user.unclaimedReward = 0;
            } else if (user.unclaimedReward > 0) {
                safeTokenTransfer(rewardPool.rewardToken, msg.sender, user.unclaimedReward);
                user.unclaimedReward = 0;
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            IERC20(address(_vault)).safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(rewardPool.accRewardPerShare).div(1e18);
        emit Withdraw(_vault, msg.sender, _amount);
    }

    function claimReward(address _vault, uint8 _flag) public discountCHI(_flag) {
        UserInfo storage user = userInfo[_vault][msg.sender];
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        require(user.lastStakeTime + rewardPool.rewardLockedTime <= block.timestamp, "locked rewards");
        getReward(_vault, msg.sender, uint8(0));
        uint _pendingReward = user.unclaimedReward;
        if (_pendingReward > 0) {
            safeTokenTransfer(rewardPool.rewardToken, msg.sender, _pendingReward);
            user.unclaimedReward = 0;
        }
    }

    // using PUSH pattern
    function getReward(address _vault, address _account, uint8 _flag) public discountCHI(_flag) {
        updateReward(_vault);
        UserInfo storage user = userInfo[_vault][_account];
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        uint _pendingReward = user.amount.mul(rewardPool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (_pendingReward > 0) {
            user.accumulatedEarned = user.accumulatedEarned.add(_pendingReward);
            rewardPool.totalPaidRewards = rewardPool.totalPaidRewards.add(_pendingReward);
            // safeTokenTransfer(rewardPool.rewardToken, _account, _pendingReward);
            user.unclaimedReward = user.unclaimedReward.add(_pendingReward);
            emit RewardPaid(_vault, _account, _pendingReward);
            user.rewardDebt = user.amount.mul(rewardPool.accRewardPerShare).div(1e18);
        }
    }

    function pendingReward(address _vault, address _account) public view returns (uint _pending) {
        UserInfo storage user = userInfo[_vault][_account];
        RewardPoolInfo storage rewardPool = rewardPoolInfo[_vault];
        uint _accRewardPerShare = rewardPool.accRewardPerShare;
        uint lpSupply = IERC20(_vault).balanceOf(address(this));
        uint _endRewardBlockApplicable = block.number > rewardPool.endRewardBlock ? rewardPool.endRewardBlock : block.number;
        if (_endRewardBlockApplicable > rewardPool.lastRewardBlock && lpSupply != 0) {
            uint _numBlocks = _endRewardBlockApplicable.sub(rewardPool.lastRewardBlock);
            uint _incRewardPerShare = _numBlocks.mul(rewardPool.rewardPerBlock).mul(1e18).div(lpSupply);
            _accRewardPerShare = _accRewardPerShare.add(_incRewardPerShare);
        }
        _pending = user.amount.mul(_accRewardPerShare).div(1e18).sub(user.rewardDebt);
        _pending = _pending.add(user.unclaimedReward);
    }

    function shares_owner(address _vault, address _account) public view returns (uint) {
        return IERC20(_vault).balanceOf(_account).add(userInfo[_vault][_account].amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(address _vault, uint _shares, address _output, uint _min_output_amount, uint8 _flag) public discountCHI(_flag) {
        uint _wdAmt = _withdraw(_vault, _shares);
        ICompositeVault(_vault).withdrawFor(msg.sender, _wdAmt, _output, _min_output_amount);
    }

    function _withdraw(address _vault, uint _shares) internal returns (uint){
        uint _userBal = IERC20(address(_vault)).balanceOf(msg.sender);
        if (_shares > _userBal) {
            uint _need = _shares.sub(_userBal);
            require(_need <= userInfo[_vault][msg.sender].amount, "_userBal+staked < _shares");
            unstake(_vault, _need, uint8(0));
        }
        uint _before = IERC20(address(_vault)).balanceOf(address(this));
        IERC20(address(_vault)).safeTransferFrom(msg.sender, address(this), _shares);
        uint _after = IERC20(address(_vault)).balanceOf(address(this));
        return _after.sub(_before);
    }

    function exit(address _vault, address _output, uint _min_output_amount, uint8 _flag) external discountCHI(_flag) {
        unstake(_vault, userInfo[_vault][msg.sender].amount, uint8(0));
        withdraw(_vault, IERC20(address(_vault)).balanceOf(msg.sender), _output, _min_output_amount, uint8(0));
    }

    function withdraw_fee(ICompositeVault _vault, uint _shares) external view returns (uint) {
        return _vault.withdraw_fee(_shares);
    }

    function calc_token_amount_deposit(ICompositeVault _vault, address _input, uint _amount) external view returns (uint) {
        return _vault.calc_token_amount_deposit(_input, _amount);
    }

    function calc_add_liquidity(ICompositeVault _vault, uint _amount0, uint _amount1) external view returns (uint) {
        return _vault.calc_add_liquidity(_amount0, _amount1);
    }

    function calc_token_amount_withdraw(ICompositeVault _vault, uint _shares, address _output) external view returns (uint) {
        return _vault.calc_token_amount_withdraw(_shares, _output);
    }

    function calc_remove_liquidity(ICompositeVault _vault, uint _shares) external view returns (uint _amount0, uint _amount1) {
        return _vault.calc_remove_liquidity(_shares);
    }

    function calc_transfer_vault_shares(ICompositeVault _srcVault, ICompositeVault _destVault, uint _srcShares) external view returns (uint) {
        address _srcVaultToken = _srcVault.token();
        uint _amount = _srcVault.calc_token_amount_withdraw(_srcShares, _srcVaultToken);
        return _destVault.calc_token_amount_deposit(_srcVaultToken, _amount);
    }

    function harvestStrategy(ICompositeVault _vault, address _strategy, uint8 _flag) external discountCHI(_flag) {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _vault.harvestStrategy(_strategy);
    }

    function harvestAllStrategies(ICompositeVault _vault, uint8 _flag) external discountCHI(_flag) {
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
