// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../ValueVaultMaster.sol";

interface IStrategy {
    function approve(IERC20 _token) external;
    function approveForSpender(IERC20 _token, address spender) external;

    // Deposit tokens to a farm to yield more tokens.
    function deposit(address _vault, uint256 _amount) external;

    // Claim farming tokens
    function claim(address _vault) external;

    // The vault request to harvest the profit
    function harvest(uint256 _bankPoolId) external;

    // Withdraw the principal from a farm.
    function withdraw(address _vault, uint256 _amount) external;

    // Target farming token of this strategy.
    function getTargetToken() external view returns(address);

    function balanceOf(address _vault) external view returns (uint256);

    function pendingReward(address _vault) external view returns (uint256);

    function expectedAPY(address _vault) external view returns (uint256);

    function governanceRescueToken(IERC20 _token) external returns (uint256);
}


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
}

interface ISodaPool {
    // Deposit LP tokens to SodaPool for SODA allocation
    function deposit(uint256 _poolId, uint256 _amount) external;

    // Claim SODA (and potentially other tokens depends on strategy).
    function claim(uint256 _poolId) external;

    // Withdraw LP tokens from SodaPool
    function withdraw(uint256 _poolId, uint256 _amount) external;
}

interface ISodaVault {
    function balanceOf(address account) external view returns (uint256);
    function getPendingReward(address _who, uint256 _index) external view returns (uint256);
}

interface IProfitSharer {
    function shareProfit() external returns (uint256);
}

interface IValueVaultBank {
    function make_profit(uint256 _poolId, uint256 _amount) external;
}

// This contract is owned by Timelock.
// What it does is simple: deposit WETH to soda.finance, and wait for ValueVaultBank's command.
contract WETHSodaPoolStrategy is IStrategy {
    using SafeMath for uint256;

    address public governance;

    uint256 public constant BLOCKS_PER_YEAR = 2372500;
    uint256 public constant FEE_DENOMINATOR = 10000;

    IOneSplit public onesplit = IOneSplit(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);
    IUniswapRouter public unirouter = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ISodaPool public sodaPool;
    ISodaVault public sodaVault;

    ValueVaultMaster public valueVaultMaster;
    IERC20 public sodaToken;

    uint256 public minHarvestForTakeProfit;
    uint256 public sodaRewardPerBlock = 90909090909090909; // ~0.09 - current assigned SODA per block for Soda WETHVault (from CreateSoda)

    struct PoolInfo {
        IERC20 lpToken;
        uint256 poolId;  // poolId in soda pool.
    }

    // By vault
    mapping(address => PoolInfo) public poolMap;
    mapping(address => uint256) public _balances;

    // weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    // sodaToken = "0x7AfB39837Fd244A651e4F0C5660B4037214D4aDF"
    // sodaPool = "0x74BCb8b78996F49F46497be185174B2a89191fD6"
    // sodaWETHVault = "0x8d5d838Db2522C187A3062CAd0C7d55158F31EbF"
    // wethPId = 0
    constructor(ValueVaultMaster _valueVaultMaster,
                IERC20 _sodaToken,
                ISodaPool _sodaPool,
                ISodaVault _sodaVault,
                uint256 _minHarvestForTakeProfit) public {
        valueVaultMaster = _valueVaultMaster;
        sodaToken = _sodaToken;
        sodaPool = _sodaPool;
        sodaVault = _sodaVault;
        minHarvestForTakeProfit = _minHarvestForTakeProfit;
        governance = tx.origin;
        // Approve all
        sodaToken.approve(valueVaultMaster.bank(), type(uint256).max);
        sodaToken.approve(address(unirouter), type(uint256).max);
    }

    function approve(IERC20 _token) external override {
        require(msg.sender == governance, "!governance");
        _token.approve(valueVaultMaster.bank(), type(uint256).max);
        _token.approve(address(sodaPool), type(uint256).max);
        _token.approve(address(unirouter), type(uint256).max);
    }

    function approveForSpender(IERC20 _token, address spender) external override {
        require(msg.sender == governance, "!governance");
        _token.approve(spender, type(uint256).max);
    }

    function setPoolInfo(
        address _vault,
        IERC20 _lpToken,
        uint256 _sodaPoolId
    ) external {
        require(msg.sender == governance, "!governance");
        poolMap[_vault].lpToken = _lpToken;
        poolMap[_vault].poolId = _sodaPoolId;
        _lpToken.approve(valueVaultMaster.bank(), type(uint256).max);
        _lpToken.approve(_vault, type(uint256).max);
        _lpToken.approve(address(sodaPool), type(uint256).max);
        _lpToken.approve(address(unirouter), type(uint256).max);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setMinHarvestForTakeProfit(uint256 _minHarvestForTakeProfit) external {
        require(msg.sender == governance, "!governance");
        minHarvestForTakeProfit = _minHarvestForTakeProfit;
    }

    function setOnesplit(IOneSplit _onesplit) external {
        require(msg.sender == governance, "!governance");
        onesplit = _onesplit;
    }

    function setUnirouter(IUniswapRouter _unirouter) external {
        require(msg.sender == governance, "!governance");
        unirouter = _unirouter;
    }

    function setSodaRewardPerBlock(uint256 _sodaRewardPerBlock) external {
        require(msg.sender == governance, "!governance");
        sodaRewardPerBlock = _sodaRewardPerBlock;
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) public override {
        require(valueVaultMaster.isVault(msg.sender), "sender not vault");
        sodaPool.deposit(poolMap[_vault].poolId, _amount);
        _balances[_vault] = _balances[_vault].add(_amount);
    }

    function swapTokens(address _input, address _output, uint256 _amount) internal {
        // path: _input -> _output
        address[] memory path = new address[](2);
        path[0] = _input;
        path[1] = _output;
        // swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)
        unirouter.swapExactTokensForTokens(_amount, 0, path, address(this), now.add(1800));
    }

    /**
     * @dev See {IStrategy-harvest}.
     */
    function harvest(uint256 _bankPoolId) external override {
        address _vault = msg.sender;
        require(valueVaultMaster.isVault(_vault), "!vault"); // additional protection so we don't burn the funds
        IERC20 lpToken = poolMap[_vault].lpToken;

        sodaPool.claim(poolMap[_vault].poolId);
        if (address(lpToken) != address(0)) {
            uint256 sodaBal = sodaToken.balanceOf(address(this));

            if (sodaBal >= minHarvestForTakeProfit) {
                swapTokens(address(sodaToken), address(lpToken), sodaBal);

                uint256 wethBal = lpToken.balanceOf(address(this));
                if (wethBal > 0) {
                    address profitSharer = valueVaultMaster.profitSharer();
                    address performanceReward = valueVaultMaster.performanceReward();
                    address bank = valueVaultMaster.bank();

                    if (valueVaultMaster.govVaultProfitShareFee() > 0 && profitSharer != address(0)) {
                        address yfv = valueVaultMaster.yfv();
                        uint256 _govVaultProfitShareFee = wethBal.mul(valueVaultMaster.govVaultProfitShareFee()).div(FEE_DENOMINATOR);
                        swapTokens(address(lpToken), yfv, _govVaultProfitShareFee);
                        IERC20(yfv).transfer(profitSharer, IERC20(yfv).balanceOf(address(this)));
                        IProfitSharer(profitSharer).shareProfit();
                    }

                    if (valueVaultMaster.gasFee() > 0 && performanceReward != address(0)) {
                        uint256 _gasFee = wethBal.mul(valueVaultMaster.gasFee()).div(FEE_DENOMINATOR);
                        lpToken.transfer(performanceReward, _gasFee);
                    }

                    uint256 balanceLeft = lpToken.balanceOf(address(this));
                    if (lpToken.allowance(address(this), bank) < balanceLeft) {
                        lpToken.approve(bank, 0);
                        lpToken.approve(bank, balanceLeft);
                    }
                    IValueVaultBank(bank).make_profit(_bankPoolId, balanceLeft);
                }
            }
        }
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) external override {
        require(valueVaultMaster.isVault(_vault), "not vault");
        sodaPool.claim(poolMap[_vault].poolId);
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) external override {
        require(valueVaultMaster.isVault(msg.sender), "sender not vault");
        sodaPool.withdraw(poolMap[_vault].poolId, _amount);
        _balances[_vault] = _balances[_vault].sub(_amount);
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken() external view override returns(address) {
        return address(sodaToken);
    }

    function balanceOf(address _vault) public view override returns (uint256) {
        return _balances[_vault];
    }

    function pendingReward(address) public view override returns (uint256) {
        // not supported
        return 0;
    }

    function expectedAPY(address _vault) public view override returns (uint256) {
        uint256 investAmt = _balances[_vault];
        uint256 returnAmt = sodaRewardPerBlock * BLOCKS_PER_YEAR;
        IERC20 usdc = IERC20(valueVaultMaster.usdc());
        (uint256 investInUSDC, ) = onesplit.getExpectedReturn(poolMap[_vault].lpToken, usdc, investAmt, 10, 0);
        (uint256 returnInUSDC, ) = onesplit.getExpectedReturn(sodaToken, usdc, returnAmt, 10, 0);
        return returnInUSDC.mul(FEE_DENOMINATOR).div(investInUSDC); // 100 -> 1%
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
}
