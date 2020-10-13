// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategyV2.sol";
import "../../ValueVaultMaster.sol";

interface IOneSplit {
    function getExpectedReturn(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        uint256 parts,
        uint256 flags // See constants in IOneSplit.sol
    ) external view returns(
        uint256 returnAmount,
        uint256[] memory distribution
    );
}

interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function getRewardForDuration() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    // Mutative
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}

interface IProfitSharer {
    function shareProfit() external returns (uint256);
}

interface IValueVaultBank {
    function make_profit(uint256 _poolId, uint256 _amount) external;
}

    // Deposit UNIv2ETHWBTC to a standard StakingRewards pool (eg. UNI Pool - https://app.uniswap.org/#/uni)
// Wait for Vault commands: deposit, withdraw, claim, harvest (can be called by public via Vault)
contract Univ2ETHWBTCMultiPoolStrategy is IStrategyV2 {
    using SafeMath for uint256;

    address public governance;

    uint256 public constant FEE_DENOMINATOR = 10000;

    IERC20 public weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IOneSplit public onesplit = IOneSplit(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);
    IUniswapRouter public unirouter = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ValueVaultMaster public valueVaultMaster;
    IERC20 public lpPair; // ETHWBTC_UNIv2
    IERC20 public lpPairTokenA; // WBTC
    IERC20 public lpPairTokenB; // For this contract it will be always be WETH

    mapping(address => mapping(address => address[])) public uniswapPaths; // [input -> output] => uniswap_path

    struct PoolInfo {
        address vault;
        IERC20 targetToken;
        IStakingRewards targetPool;
        uint256 minHarvestForTakeProfit;
        uint256 poolQuota; // set 0 to disable quota (no limit)
    }

    mapping(uint256 => PoolInfo) public poolMap; // poolIndex -> poolInfo
    address public totalBalance;

    bool public aggressiveMode; // will try to stake all lpPair tokens available (be forwarded from bank or from another strategies)

    // lpPair: ETHWBTC_UNIv2 = 0xbb2b8038a1640196fbe3e38816f3e67cba72d940
    // lpPairTokenA: WBTC = 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599
    // lpPairTokenB: WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    constructor(ValueVaultMaster _valueVaultMaster,
                IERC20 _lpPair,
                IERC20 _lpPairTokenA,
                IERC20 _lpPairTokenB,
                bool _aggressiveMode) public {
        valueVaultMaster = _valueVaultMaster;
        lpPair = _lpPair;
        lpPairTokenA = _lpPairTokenA;
        lpPairTokenB = _lpPairTokenB;
        aggressiveMode = _aggressiveMode;
        governance = tx.origin;
        // Approve all
        lpPair.approve(valueVaultMaster.bank(), type(uint256).max);
        lpPairTokenA.approve(address(unirouter), type(uint256).max);
        lpPairTokenB.approve(address(unirouter), type(uint256).max);
    }

    // targetToken: uniToken = 0x1f9840a85d5af5bf1d1762f925bdaddc4201f984
    // targetPool: ETHWBTCUniPool = 0xCA35e32e7926b96A9988f61d510E038108d8068e
    function setPoolInfo(uint256 _poolId, address _vault, IERC20 _targetToken, IStakingRewards _targetPool, uint256 _minHarvestForTakeProfit, uint256 _poolQuota) external {
        require(msg.sender == governance, "!governance");
        poolMap[_poolId].vault = _vault;
        poolMap[_poolId].targetToken = _targetToken;
        poolMap[_poolId].targetPool = _targetPool;
        poolMap[_poolId].minHarvestForTakeProfit = _minHarvestForTakeProfit;
        poolMap[_poolId].poolQuota = _poolQuota;
        _targetToken.approve(address(unirouter), type(uint256).max);
        lpPair.approve(_vault, type(uint256).max);
        lpPair.approve(address(_targetPool), type(uint256).max);
    }

    function approve(IERC20 _token) external override {
        require(msg.sender == governance, "!governance");
        _token.approve(valueVaultMaster.bank(), type(uint256).max);
        _token.approve(address(unirouter), type(uint256).max);
    }

    function approveForSpender(IERC20 _token, address spender) external override {
        require(msg.sender == governance, "!governance");
        _token.approve(spender, type(uint256).max);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setMinHarvestForTakeProfit(uint256 _poolId, uint256 _minHarvestForTakeProfit) external {
        require(msg.sender == governance, "!governance");
        poolMap[_poolId].minHarvestForTakeProfit = _minHarvestForTakeProfit;
    }

    function setPoolQuota(uint256 _poolId, uint256 _poolQuota) external {
        require(msg.sender == governance, "!governance");
        poolMap[_poolId].poolQuota = _poolQuota;
    }

    function setAggressiveMode(bool _aggressiveMode) external {
        require(msg.sender == governance, "!governance");
        aggressiveMode = _aggressiveMode;
    }

    function setWETH(IERC20 _weth) external {
        require(msg.sender == governance, "!governance");
        weth = _weth;
    }

    function setOnesplit(IOneSplit _onesplit) external {
        require(msg.sender == governance, "!governance");
        onesplit = _onesplit;
    }

    function setUnirouter(IUniswapRouter _unirouter) external {
        require(msg.sender == governance, "!governance");
        unirouter = _unirouter;
        lpPairTokenA.approve(address(unirouter), type(uint256).max);
        lpPairTokenB.approve(address(unirouter), type(uint256).max);
    }

    /**
     * @dev See {IStrategyV2-deposit}.
     */
    function deposit(uint256 _poolId, uint256 _amount) public override {
        require(poolMap[_poolId].vault == msg.sender, "sender not vault");
        if (aggressiveMode) {
            _amount = lpPair.balanceOf(address(this));
        }
        poolMap[_poolId].targetPool.stake(_amount);
    }

    /**
     * @dev See {IStrategyV2-claim}.
     */
    function claim(uint256 _poolId) external override {
        require(poolMap[_poolId].vault == msg.sender, "sender not vault");
        poolMap[_poolId].targetPool.getReward();
    }

    /**
     * @dev See {IStrategyV2-withdraw}.
     */
    function withdraw(uint256 _poolId, uint256 _amount) external override {
        require(poolMap[_poolId].vault == msg.sender, "sender not vault");
        poolMap[_poolId].targetPool.withdraw(_amount);
    }

    function depositByGov(IStakingRewards pool, uint256 _amount) external {
        require(msg.sender == governance, "!governance");
        pool.stake(_amount);
    }

    function claimByGov(IStakingRewards pool) external {
        require(msg.sender == governance, "!governance");
        pool.getReward();
    }

    function withdrawByGov(IStakingRewards pool, uint256 _amount) external {
        require(msg.sender == governance, "!governance");
        pool.withdraw(_amount);
    }

    /**
     * @dev See {IStrategyV2-poolQuota}.
     */
    function poolQuota(uint256 _poolId) external override view returns (uint256) {
        return poolMap[_poolId].poolQuota;
    }

    function forwardToAnotherStrategy(address _dest, uint256 _amount) external override returns (uint256 sent) {
        require(valueVaultMaster.isVault(msg.sender), "not vault");
        require(valueVaultMaster.isStrategy(_dest), "not strategy");
        require(IStrategyV2(_dest).getLpToken() == address(lpPair), "!lpPair");
        uint256 lpPairBal = lpPair.balanceOf(address(this));
        sent = (_amount < lpPairBal) ? _amount : lpPairBal;
        lpPair.transfer(_dest, sent);
    }

    function setUnirouterPath(address _input, address _output, address [] memory _path) public {
        require(msg.sender == governance, "!governance");
        uniswapPaths[_input][_output] = _path;
    }

    function _swapTokens(address _input, address _output, uint256 _amount) internal {
        address[] memory path = uniswapPaths[_input][_output];
        if (path.length == 0) {
            // path: _input -> _output
            path = new address[](2);
            path[0] = _input;
            path[1] = _output;
        }
        // swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)
        unirouter.swapExactTokensForTokens(_amount, 1, path, address(this), now.add(1800));
    }

    function _addLiquidity() internal {
        // addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, to, deadline)
        unirouter.addLiquidity(address(lpPairTokenA), address(lpPairTokenB), lpPairTokenA.balanceOf(address(this)), lpPairTokenB.balanceOf(address(this)), 1, 1, address(this), now.add(1800));
    }

    /**
     * @dev See {IStrategyV2-harvest}.
     */
    function harvest(uint256 _bankPoolId, uint256 _poolId) external override {
        address bank = valueVaultMaster.bank();
        address _vault = msg.sender;
        require(valueVaultMaster.isVault(_vault), "!vault"); // additional protection so we don't burn the funds

        poolMap[_poolId].targetPool.getReward();
        IERC20 targetToken = poolMap[_poolId].targetToken;
        uint256 targetTokenBal = targetToken.balanceOf(address(this));

        if (targetTokenBal < poolMap[_poolId].minHarvestForTakeProfit) return;

        _swapTokens(address(targetToken), address(weth), targetTokenBal);
        uint256 wethBal = weth.balanceOf(address(this));

        if (wethBal > 0) {
            uint256 _reserved = 0;
            uint256 _gasFee = 0;
            uint256 _govVaultProfitShareFee = 0;

            if (valueVaultMaster.gasFee() > 0) {
                _gasFee = wethBal.mul(valueVaultMaster.gasFee()).div(FEE_DENOMINATOR);
                _reserved = _reserved.add(_gasFee);
            }

            if (valueVaultMaster.govVaultProfitShareFee() > 0) {
                _govVaultProfitShareFee = wethBal.mul(valueVaultMaster.govVaultProfitShareFee()).div(FEE_DENOMINATOR);
                _reserved = _reserved.add(_govVaultProfitShareFee);
            }

            uint256 wethToBuyTokenA = wethBal.sub(_reserved).div(2); // we have TokenB (WETH) already, so use 1/2 bal to buy TokenA (WBTC)

            _swapTokens(address(weth), address(lpPairTokenA), wethToBuyTokenA);
            _addLiquidity();

            wethBal = weth.balanceOf(address(this));

            address profitSharer = valueVaultMaster.profitSharer();
            address performanceReward = valueVaultMaster.performanceReward();

            if (_gasFee > 0 && performanceReward != address(0)) {
                if (_gasFee.add(_govVaultProfitShareFee) < wethBal) {
                    _gasFee = wethBal.sub(_govVaultProfitShareFee);
                }
                weth.transfer(performanceReward, _gasFee);
                wethBal = weth.balanceOf(address(this));
            }

            if (_govVaultProfitShareFee > 0 && profitSharer != address(0)) {
                address yfv = valueVaultMaster.yfv();
                _swapTokens(address(weth), yfv, wethBal);
                IERC20(yfv).transfer(profitSharer, IERC20(yfv).balanceOf(address(this)));
                IProfitSharer(profitSharer).shareProfit();
            }

            uint256 balanceLeft = lpPair.balanceOf(address(this));
            if (balanceLeft > 0) {
                if (_bankPoolId == type(uint256).max) {
                    // this called by governance of vault, send directly to bank (dont make profit)
                    lpPair.transfer(bank, balanceLeft);
                } else {
                    if (lpPair.allowance(address(this), bank) < balanceLeft) {
                        lpPair.approve(bank, 0);
                        lpPair.approve(bank, balanceLeft);
                    }
                    IValueVaultBank(bank).make_profit(_bankPoolId, balanceLeft);
                }
            }
        }
    }

    /**
     * @dev See {IStrategyV2-getLpToken}.
     */
    function getLpToken() external view override returns(address) {
        return address(lpPair);
    }

    /**
     * @dev See {IStrategyV2-getTargetToken}.
     */
    function getTargetToken(uint256 _poolId) external override view returns(address) {
        return address(poolMap[_poolId].targetToken);
    }

    function balanceOf(uint256 _poolId) public override view returns (uint256) {
        return poolMap[_poolId].targetPool.balanceOf(address(this));
    }

    function pendingReward(uint256 _poolId) public override view returns (uint256) {
        return poolMap[_poolId].targetPool.earned(address(this));
    }

    // Helper function, Should never use it on-chain.
    // Return 1e18x of APY. _lpPairUsdcPrice = current lpPair price (1-wei in WBTC-wei) multiple by 1e18
    function expectedAPY(uint256 _poolId, uint256 _lpPairUsdcPrice) public override view returns (uint256) {
        if (poolMap[_poolId].targetPool.totalSupply() == 0) return 0;
        uint256 investAmt = balanceOf(_poolId);
        uint256 oneHourReward = poolMap[_poolId].targetPool.rewardRate().mul(3600);
        uint256 returnAmt = oneHourReward.mul(investAmt).div(poolMap[_poolId].targetPool.totalSupply());
        IERC20 usdc = IERC20(valueVaultMaster.usdc());
        uint256 investInUSDC = investAmt.mul(_lpPairUsdcPrice);
        (uint256 returnInUSDC, ) = onesplit.getExpectedReturn(poolMap[_poolId].targetToken, usdc, returnAmt, 10, 0);
        return returnInUSDC.mul(8760).div(investInUSDC); // 1e16 -> 1%
    }

    /**
     * @dev if there is any token stuck we will need governance support to rescue the fund
     */
    function governanceRescueToken(IERC20 _token) external override returns (uint256 balance) {
        address bank = valueVaultMaster.bank();
        require(bank == msg.sender, "sender not bank");

        balance = _token.balanceOf(address(this));
        _token.transfer(bank, balance);
    }

    event ExecuteTransaction(address indexed target, uint value, string signature, bytes data);

    function executeTransaction(address target, uint value, string memory signature, bytes memory data) public returns (bytes memory) {
        require(msg.sender == governance, "!governance");

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Univ2ETHWBTCMultiPoolStrategy::executeTransaction: Transaction execution reverted.");

        emit ExecuteTransaction(target, value, signature, data);

        return returnData;
    }
}
