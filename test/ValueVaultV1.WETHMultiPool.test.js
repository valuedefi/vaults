const {expectRevert, time} = require('@openzeppelin/test-helpers');
const ethers = require('ethers');
const ValueLiquidityToken = artifacts.require('ValueLiquidityToken');
const ValueVaultBank = artifacts.require('ValueVaultBank');
const ValueVaultMaster = artifacts.require('ValueVaultMaster');
const MockERC20 = artifacts.require('MockERC20');
const MockGovVault = artifacts.require('MockGovVault');
const MockSodaPool = artifacts.require('MockSodaPool');
const MockSodaVault = artifacts.require('MockSodaVault');
const MockSushiPool = artifacts.require('MockSushiPool');
const MockFarmingPool = artifacts.require('MockFarmingPool');
const MockUniswapRouter = artifacts.require('MockUniswapRouter');
const YFVReferral = artifacts.require('YFVReferral');
const ValueMinorPool = artifacts.require('ValueMinorPool');
const ValueVaultProfitSharer = artifacts.require('ValueVaultProfitSharer');
const WETHVault = artifacts.require('WETHVault');
const WETHSodaPoolStrategy = artifacts.require('WETHSodaPoolStrategy');
const WETHMultiPoolStrategy = artifacts.require('WETHMultiPoolStrategy');

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';
const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

const K_STRATEGY_WETH_SODA_POOL = 0;
const K_STRATEGY_WETH_MULTI_POOL = 1;

contract('ValueVaultV1.WETHMultiPool.test', ([alice, bob, carol, insuranceFund]) => {
    beforeEach(async () => {
        this.yfv = await MockERC20.new('YFValue', 'YFV', 1000000, {from: alice});
        this.value = await ValueLiquidityToken.new(this.yfv.address, 2370000, {from: alice});
        await this.value.addMinter(alice, {from: alice});
        await this.value.addMinter(alice, {from: alice});
        this.soda = await MockERC20.new('SodaToken', 'SODA', 1000000, {from: alice});
        this.golff = await MockERC20.new('Golff.finance', 'GOF', 1000000, {from: alice});
        this.chicken = await MockERC20.new('Chicken', 'KFC', 1000000, {from: alice});
        this.wETH = await MockERC20.new('Wrapped ETH', 'WETH', 1000000, {from: alice});
        this.usdc = await MockERC20.new('USD Coin', 'USDC', 1000000, {from: alice});

        this.govVault = await MockGovVault.new(this.value.address, {from: alice});
        this.profitSharer = await ValueVaultProfitSharer.new(this.value.address, this.yfv.address, {from: alice});
        await this.profitSharer.setGovVault(this.govVault.address, {from: alice});
        this.bank = await ValueVaultBank.new({from: alice});

        this.master = await ValueVaultMaster.new(this.value.address, this.yfv.address, this.usdc.address, {from: alice});

        await this.bank.setVaultMaster(this.master.address, {from: alice});
        await this.master.setGovVault(this.govVault.address, {from: alice});
        await this.master.setProfitSharer(this.profitSharer.address, {from: alice});
        await this.master.setBank(this.bank.address, {from: alice});
        await this.master.setMinStakeTimeToClaimVaultReward(20, {from: alice});

        this.sodaPool = await MockSodaPool.new(this.soda.address, this.wETH.address, {from: alice});
        this.sodaVault = await MockSodaVault.new(this.soda.address, this.sodaPool.address, {from: alice});
        const minHarvestForTakeProfit = 10;
        this.wethSodaPoolStrategy = await WETHSodaPoolStrategy.new(this.master.address, this.soda.address, this.sodaPool.address, this.sodaVault.address, minHarvestForTakeProfit, {from: alice});
        await this.wethSodaPoolStrategy.approve(this.wETH.address, {from: alice});
        await this.wethSodaPoolStrategy.approve(this.soda.address, {from: alice});

        this.golffPool = await MockFarmingPool.new(this.wETH.address, this.golff.address, 500, {from: alice});
        this.chickenPool = await MockSushiPool.new(this.chicken.address, this.wETH.address, {from: alice});

        // this.v2Strategy = await Univ2ETHUSDCMultiPoolStrategy.new(this.master.address, this.univ2LP.address, this.usdc.address, this.wETH.address, true, {from: alice});

//        // function setPoolInfo(uint256 _poolId, address _vault, IERC20 _targetToken, IStakingRewards _targetPool, uint256 _minHarvestForTakeProfit, uint256 _poolQuota) external {
//         await this.v2Strategy.setPoolInfo(0, this.univ2EthUsdcVault.address, this.uniToken.address, this.uniPool.address, minHarvestForTakeProfit, 1000);
//         console.log('_poolQuota = ', JSON.stringify(await this.v2Strategy.poolQuota(0)));
//         // await this.v2Strategy.approve(this.uniToken.address, {from: alice});
//         // await this.v2Strategy.approve(this.univ2LP.address, {from: alice});
//         // await this.v2Strategy.approveForSpender(this.univ2LP.address, this.univ2EthUsdcVault.address, {from: alice});

        this.wethMultiPoolStrategy = await WETHMultiPoolStrategy.new(this.master.address, this.wETH.address, true, {from: alice});

        this.unirouter = await MockUniswapRouter.new(ADDRESS_ZERO, {from: alice});
        await this.yfv.transfer(this.unirouter.address, 10000, {from: alice});
        await this.value.mint(this.unirouter.address, 10000, {from: alice});
        await this.golff.transfer(this.unirouter.address, 10000, {from: alice});
        await this.chicken.transfer(this.unirouter.address, 10000, {from: alice});
        await this.wETH.transfer(this.unirouter.address, 10000, {from: alice});

        await this.wethSodaPoolStrategy.setUnirouter(this.unirouter.address, {from: alice});
        await this.wethMultiPoolStrategy.setUnirouter(this.unirouter.address, {from: alice});

        this.wethVault = await WETHVault.new(this.master.address, this.wethSodaPoolStrategy.address, {from: alice});
        await this.wethSodaPoolStrategy.setPoolInfo(this.wethVault.address, this.wETH.address, 0, {from: alice});

        await this.wethSodaPoolStrategy.approve(this.soda.address, {from: alice});
        await this.wethSodaPoolStrategy.approve(this.wETH.address, {from: alice});

        await this.wethMultiPoolStrategy.approve(this.golff.address, {from: alice});
        await this.wethMultiPoolStrategy.approve(this.wETH.address, {from: alice});

        // this.wethVault = await WETHVault.new(this.master.address, this.wethMultiPoolStrategy.address, {from: alice});
        // function setPoolInfo(uint256 _poolId, address _vault, IERC20 _targetToken, address _targetPool, uint256 _targetPoolId, uint256 _minHarvestForTakeProfit, uint256 _poolType, uint256 _poolQuota) external {
        await this.wethMultiPoolStrategy.setPoolInfo(0, this.wethVault.address, this.golff.address, this.golffPool.address, 0, 1, 0, 10, {from: alice});
        await this.wethMultiPoolStrategy.setPoolInfo(1, this.wethVault.address, this.chicken.address, this.chickenPool.address, 0, 1, 1, 1000, {from: alice});
        await this.wethMultiPoolStrategy.setPoolPreferredIds([0, 1], {from: alice});
        // await this.wethMultiPoolStrategy.approve(this.golff.address, {from: alice});
        // await this.wethMultiPoolStrategy.approve(this.wETH.address, {from: alice});
        // await this.wethMultiPoolStrategy.approveForSpender(this.wETH.address, this.wethVault.address, {from: alice});

        const K_VAULT_WETH = 0;
        await this.master.addVault(K_VAULT_WETH, this.wethVault.address, {from: alice});
        await this.master.addStrategy(K_STRATEGY_WETH_MULTI_POOL, this.wethMultiPoolStrategy.address, {from: alice});

        await this.wethVault.setStrategies([this.wethSodaPoolStrategy.address, this.wethMultiPoolStrategy.address], {from: alice});
        await this.wethVault.setStrategyPreferredOrders([1, 0], {from: alice});

        // Let the bank start now.
        await this.bank.setPoolInfo(0, this.wETH.address, this.wethVault.address, 0, 0, 0, 0, {from: alice});
    });

    it('without any Minor Pool: should work', async () => {
        // alice give bob and carol 1000 for test purpose
        await this.wETH.transfer(bob, 1000, {from: alice});
        await this.wETH.transfer(carol, 1000, {from: alice});

        // bob stakes 110
        await this.wETH.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.bank.deposit(0, 110, false, ADDRESS_ZERO, {from: bob});

        await this.soda.transfer(this.sodaPool.address, 10, {from: alice});
        await this.chicken.transfer(this.chickenPool.address, 100, {from: alice});
        await this.golff.transfer(this.golffPool.address, 10000, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('bob\'s wETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('------------------------------------------------------------');

        await this.bank.harvestVault(0, {from: carol}); // can be called by public
        if (this.wethMultiPoolStrategy.log_golffBal) console.log('log_golffBal: ', String(await this.wethMultiPoolStrategy.log_golffBal()));
        if (this.wethMultiPoolStrategy.log_wethBal) console.log('log_wethBal: ', String(await this.wethMultiPoolStrategy.log_wethBal()));
        if (this.wethMultiPoolStrategy.log_yfvGovVault) console.log('log_yfvGovVault: ', String(await this.wethMultiPoolStrategy.log_yfvGovVault()));

        // 2 block later, he should get some SODA.
        await time.advanceBlock(); // Block 0
        await time.increase(9);
        // await this.bank.claimProfit(0, {from: bob});  // Block 1
        console.log('wethMultiPoolStrategy\'s master: ', String(await this.wethMultiPoolStrategy.valueVaultMaster()));
        console.log('valueVaultMaster\'s bank: ', String(await this.master.bank()));
        console.log('allowance(wethMultiPoolStrategy, bank): ', String(await this.wETH.allowance(this.wethMultiPoolStrategy.address, this.bank.address)));

        console.log('wethMultiPoolStrategy.balanceOf(wethVault): ', String(await this.wethMultiPoolStrategy.balanceOf(this.wethVault.address)));
        
        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));

        // await this.wethMultiPoolStrategy.withdraw(0, 110, false, {from: alice});

        await this.bank.withdraw(0, 110, false, {from: bob});

        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));

        if (this.bank.log_strategy0Bal) console.log('log_strategy0Bal: ', String(await this.bank.log_strategy0Bal()));
        if (this.bank.log_out) console.log('log_out: ', String(await this.bank.log_out()));
        if (this.bank.log_actually_out) console.log('log_actually_out: ', String(await this.bank.log_actually_out()));
        if (this.bank.log_earlyClaimCost) console.log('log_earlyClaimCost: ', String(await this.bank.log_earlyClaimCost()));
        const balanceOfGolff = await this.golff.balanceOf(bob);

        // console.log('------------------------------------------------------------');
        // console.log('bob\'s vWETH: ', String(await this.wethVault.balanceOf(bob)));
        // await this.bank.withdraw(0, 10, {from: bob});

        console.log('------------------------------------------------------------');
        console.log('bob\'s vWETH (vault): ', String(await this.wethVault.balanceOf(bob)));

        console.log('bank\'s SODA: ', String(await this.golff.balanceOf(this.bank.address)));
        console.log('golffPool\'s SODA: ', String(await this.golff.balanceOf(this.golffPool.address)));
        console.log('wethVault\'s SODA: ', String(await this.golff.balanceOf(this.wethVault.address)));
        console.log('wethMultiPoolStrategy\'s SODA: ', String(await this.golff.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('bob\'s SODA: ', String(await this.golff.balanceOf(bob)));

        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('bob\'s wETH: ', String(await this.wETH.balanceOf(bob)));

        console.log('profitSharer\'s YFV: ', String(await this.yfv.balanceOf(this.profitSharer.address)));
        console.log('govVault\'s YFV: ', String(await this.yfv.balanceOf(this.govVault.address)));

        console.log('profitSharer\'s VALUE: ', String(await this.value.balanceOf(this.profitSharer.address)));
        console.log('govVault\'s VALUE: ', String(await this.value.balanceOf(this.govVault.address)));
        console.log('------------------------------------------------------------');

        assert.equal(balanceOfGolff.valueOf(), '0');
    });

    it('move fund from Soda -> this new pool: should work', async () => {
        await this.wethVault.setStrategies([this.wethSodaPoolStrategy.address], {from: alice});
        await this.wethVault.setStrategyPreferredOrders([0], {from: alice});

        // alice give bob and carol 1000 for test purpose
        await this.wETH.transfer(bob, 2000, {from: alice});
        await this.wETH.transfer(carol, 2000, {from: alice});

        // bob stakes 110
        await this.wETH.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.bank.deposit(0, 2000, false, ADDRESS_ZERO, {from: bob});

        await this.soda.transfer(this.sodaPool.address, 10, {from: alice});
        await this.chicken.transfer(this.chickenPool.address, 100, {from: alice});
        await this.golff.transfer(this.golffPool.address, 10000, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethSodaPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethSodaPoolStrategy.address)));
        console.log('bob\'s wETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('------------------------------------------------------------');

        await this.bank.harvestVault(0, {from: carol}); // can be called by public
        await this.wethVault.withdrawStrategy(this.wethSodaPoolStrategy.address, 2000, {from: alice});
        await this.bank.governanceRescueFromStrategy(this.wETH.address, this.wethSodaPoolStrategy.address, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('wethVault\'s wETH: ', String(await this.wETH.balanceOf(this.wethVault.address)));
        console.log('wethSodaPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethSodaPoolStrategy.address)));
        console.log('bob\'s wETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('------------------------------------------------------------');

        await this.bank.governanceRecoverUnsupported(this.wETH.address, 2000, this.wethMultiPoolStrategy.address, {from: alice});

        await this.wethVault.setStrategies([this.wethMultiPoolStrategy.address], {from: alice});

        await this.wethMultiPoolStrategy.setPoolInfo(2, this.wethVault.address, this.soda.address, this.sodaPool.address, 0, 1, 2, 100, {from: alice});
        await this.wethMultiPoolStrategy.setPoolQuota(0, 1300, {from: alice});
        await this.wethMultiPoolStrategy.setPoolQuota(1, 600, {from: alice});
        await this.wethMultiPoolStrategy.setPoolPreferredIds([0, 1, 2], {from: alice});

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('chickenPool\'s wETH: ', String(await this.wETH.balanceOf(this.chickenPool.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('------------------------------------------------------------');
        // function depositByGov(address pool, uint8 _poolType, uint256 _targetPoolId, uint256 _amount) external {
        await this.wethMultiPoolStrategy.setAggressiveMode(false, {from: alice});
        await this.wethMultiPoolStrategy.depositByGov(this.golffPool.address, 0, 0, 1000, {from: alice});
        await this.wethMultiPoolStrategy.depositByGov(this.chickenPool.address, 1, 1, 1000, {from: alice});
        // await this.wethMultiPoolStrategy.depositByGov(this.sodaPool.address, 2, 2, 100, {from: alice});
        await this.wethMultiPoolStrategy.setAggressiveMode(true, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('chickenPool\'s wETH: ', String(await this.wETH.balanceOf(this.chickenPool.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('------------------------------------------------------------');

        console.log('wethMultiPoolStrategy\'s totalBalance: ', String(await this.wethMultiPoolStrategy.totalBalance()));
        await this.wethMultiPoolStrategy.setPoolBalance(0, 1000, {from: alice});
        await this.wethMultiPoolStrategy.setPoolBalance(1, 1000, {from: alice});
        // await this.wethMultiPoolStrategy.setPoolBalance(2, 100, {from: alice});
        await this.wethMultiPoolStrategy.setTotalBalance(2000, {from: alice});

        await this.wethMultiPoolStrategy.switchBetweenPoolsByGov(0, 2, 200, {from: alice});
        console.log('wethMultiPoolStrategy\'s totalBalance: ', String(await this.wethMultiPoolStrategy.totalBalance()));
        console.log('wethMultiPoolStrategy\'s poolMap(0): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(0)));
        console.log('wethMultiPoolStrategy\'s poolMap(1): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(1)));
        console.log('wethMultiPoolStrategy\'s poolMap(2): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(2)));

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('chickenPool\'s wETH: ', String(await this.wETH.balanceOf(this.chickenPool.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('------------------------------------------------------------');

        await this.soda.transfer(this.sodaPool.address, 10, {from: alice});
        await this.bank.harvestVault(0, {from: carol}); // can be called by public

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('chickenPool\'s wETH: ', String(await this.wETH.balanceOf(this.chickenPool.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('------------------------------------------------------------');

        await expectRevert(
            this.bank.withdraw(0, 2001, false, {from: bob}),
            '!balance',
        );

        console.log('poolPreferredIds(0): ', String(await this.wethMultiPoolStrategy.poolPreferredIds(0)));
        console.log('poolPreferredIds(1): ', String(await this.wethMultiPoolStrategy.poolPreferredIds(1)));
        console.log('poolPreferredIds(2): ', String(await this.wethMultiPoolStrategy.poolPreferredIds(2)));
        await this.bank.withdraw(0, 2000, false, {from: bob});
        if (this.wethMultiPoolStrategy.log_bal_0) console.log('log_bal_0: ', String(await this.wethMultiPoolStrategy.log_bal_0()));
        if (this.wethMultiPoolStrategy.log_bal_1) console.log('log_bal_1: ', String(await this.wethMultiPoolStrategy.log_bal_1()));
        if (this.wethMultiPoolStrategy.log_bal_2) console.log('log_bal_2: ', String(await this.wethMultiPoolStrategy.log_bal_2()));
        if (this.wethMultiPoolStrategy.withdraw_amount) console.log('withdraw_amount: ', String(await this.wethMultiPoolStrategy.withdraw_amount()));

        console.log('------------------------------------------------------------');
        console.log('bank\'s wETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('bob\'s wETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('wethMultiPoolStrategy\'s wETH: ', String(await this.wETH.balanceOf(this.wethMultiPoolStrategy.address)));
        console.log('golffPool\'s wETH: ', String(await this.wETH.balanceOf(this.golffPool.address)));
        console.log('chickenPool\'s wETH: ', String(await this.wETH.balanceOf(this.chickenPool.address)));
        console.log('sodaPool\'s wETH: ', String(await this.wETH.balanceOf(this.sodaPool.address)));
        console.log('------------------------------------------------------------');

        console.log('------------------------------------------------------------');
        console.log('wethMultiPoolStrategy\'s totalBalance: ', String(await this.wethMultiPoolStrategy.totalBalance()));
        console.log('wethMultiPoolStrategy\'s poolMap(0): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(0)));
        console.log('wethMultiPoolStrategy\'s poolMap(1): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(1)));
        console.log('wethMultiPoolStrategy\'s poolMap(2): ', JSON.stringify(await this.wethMultiPoolStrategy.poolMap(2)));
        console.log('------------------------------------------------------------');
    });
});
