const {expectRevert, time} = require('@openzeppelin/test-helpers');

const ethers = require('ethers');
const ValueLiquidityToken = artifacts.require('ValueLiquidityToken');
const ValueVaultBank = artifacts.require('ValueVaultBank');
const ValueVaultMaster = artifacts.require('ValueVaultMaster');
const MockERC20 = artifacts.require('MockERC20');
const MockGovVault = artifacts.require('MockGovVault');
const MockSodaPool = artifacts.require('MockSodaPool');
const MockSodaVault = artifacts.require('MockSodaVault');
const MockUniswapRouter = artifacts.require('MockUniswapRouter');
const MockFarmingPool = artifacts.require('MockFarmingPool');
const YFVReferral = artifacts.require('YFVReferral');
const ValueMinorPool = artifacts.require('ValueMinorPool');
const ValueVaultProfitSharer = artifacts.require('ValueVaultProfitSharer');
const WETHVault = artifacts.require('WETHVault');
const WETHSodaPoolStrategy = artifacts.require('WETHSodaPoolStrategy');
const WETHGolffPoolStrategy = artifacts.require('WETHGolffPoolStrategy');

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';
const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

contract('MultiStrategies', ([alice, bob, carol, insuranceFund]) => {
    beforeEach(async () => {
        this.yfv = await MockERC20.new('YFValue', 'YFV', 1000000, {from: alice});
        this.value = await ValueLiquidityToken.new(this.yfv.address, 2370000, {from: alice});
        await this.value.addMinter(alice, {from: alice});
        this.soda = await MockERC20.new('SodaToken', 'SODA', 1000000, {from: alice});
        this.golff = await MockERC20.new('Golff.finance', 'GOF', 1000000, {from: alice});
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

        this.unirouter = await MockUniswapRouter.new({from: alice});
        await this.yfv.transfer(this.unirouter.address, 10000, {from: alice});
        await this.value.mint(this.unirouter.address, 10000, {from: alice});
        await this.soda.transfer(this.unirouter.address, 10000, {from: alice});
        await this.wETH.transfer(this.unirouter.address, 10000, {from: alice});

        this.minorPool = await ValueMinorPool.new(this.value.address, insuranceFund, 1, 0, this.master.address, {from: alice});
        await this.value.addMinter(this.minorPool.address, {from: alice});
        await this.master.setMinorPool(this.minorPool.address, {from: alice});

        this.golffPool = await MockFarmingPool.new(this.wETH.address, this.golff.address, 500, {from: alice});
        await this.golff.transfer(this.golffPool.address, 10000, {from: alice});
    });

    it('multi strategies: should work', async () => {
        this.strategy_0 = await WETHSodaPoolStrategy.new(this.master.address, this.soda.address, this.sodaPool.address, this.sodaVault.address, 10, {from: alice});
        await this.strategy_0.approve(this.wETH.address, {from: alice});
        await this.strategy_0.approve(this.soda.address, {from: alice});

        this.strategy_1 = await WETHGolffPoolStrategy.new(this.master.address, this.wETH.address, this.golff.address, this.golffPool.address, 10, {from: alice});
        await this.strategy_1.approve(this.wETH.address, {from: alice});
        await this.strategy_1.approve(this.golff.address, {from: alice});

        this.unirouter = await MockUniswapRouter.new({from: alice});
        await this.yfv.transfer(this.unirouter.address, 10000, {from: alice});
        await this.value.mint(this.unirouter.address, 10000, {from: alice});
        await this.soda.transfer(this.unirouter.address, 10000, {from: alice});
        await this.wETH.transfer(this.unirouter.address, 10000, {from: alice});

        await this.strategy_0.setUnirouter(this.unirouter.address, {from: alice});
        await this.strategy_1.setUnirouter(this.unirouter.address, {from: alice});

        this.wethVault = await WETHVault.new(this.master.address, ADDRESS_ZERO, {from: alice});
        await this.wethVault.setStrategies([this.strategy_0.address, this.strategy_1.address], {from: alice});
        await this.wethVault.setStrategyPreferredOrders([1, 0], {from: alice});

        await this.minorPool.add('100', this.wethVault.address, true, 0, {from: alice});

        await this.master.setStrategyQuota(this.strategy_0.address, 15, {from: alice});
        await this.master.setStrategyQuota(this.strategy_1.address, 15, {from: alice});
        
        await this.strategy_0.setPoolInfo(this.wethVault.address, this.wETH.address, 0, {from: alice});
        await this.strategy_0.approve(this.wETH.address, {from: alice});
        await this.strategy_0.approve(this.soda.address, {from: alice});

        await this.strategy_1.approve(this.wETH.address, {from: alice});
        await this.strategy_1.approve(this.golff.address, {from: alice});
        await this.strategy_1.approveForSpender(this.wETH.address, this.wethVault.address, {from: alice});

        const K_VAULT_WETH = 0;
        await this.master.addVault(K_VAULT_WETH, this.wethVault.address, {from: alice});

        // Let the bank start now.
        await this.bank.setPoolInfo(0, this.wETH.address, this.wethVault.address, 0, 0, 0, 0, {from: alice});

        // alice give bob and carol 1000 for test purpose
        await this.wETH.transfer(bob, 1000, {from: alice});
        await this.wETH.transfer(carol, 1000, {from: alice});

        // bob and carol stake 100
        await this.wETH.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.wethVault.approve(this.minorPool.address, MAX_UINT256, {from: bob});

        console.log('bank\'s depositAvailable(0): ', String(await this.bank.depositAvailable(0)));
        await this.bank.deposit(0, 10, true, carol, {from: bob});

        // remove strategy_1
        // await this.wethVault.setStrategies([this.strategy_0.address], {from: alice});
        // await this.wethVault.setStrategyPreferredOrders([0], {from: alice});

        console.log('strategy_0\'s balanceOf(vault): ', String(await this.strategy_0.balanceOf(this.wethVault.address)));
        console.log('strategy_1\'s balanceOf(vault): ', String(await this.strategy_1.balanceOf(this.wethVault.address)));

        await this.wETH.approve(this.bank.address, MAX_UINT256, {from: carol});
        await this.wethVault.approve(this.minorPool.address, MAX_UINT256, {from: carol});

        console.log('bank\'s depositAvailable(0): ', String(await this.bank.depositAvailable(0)));
        await this.bank.deposit(0, 10, true, bob, {from: carol});

        console.log('strategy_0\'s balanceOf(vault): ', String(await this.strategy_0.balanceOf(this.wethVault.address)));
        console.log('strategy_1\'s balanceOf(vault): ', String(await this.strategy_1.balanceOf(this.wethVault.address)));

        console.log('bank\'s depositAvailable(0): ', String(await this.bank.depositAvailable(0)));
        await this.bank.deposit(0, 10, true, bob, {from: carol});

        console.log('strategy_0\'s balanceOf(vault): ', String(await this.strategy_0.balanceOf(this.wethVault.address)));
        console.log('strategy_1\'s balanceOf(vault): ', String(await this.strategy_1.balanceOf(this.wethVault.address)));

        console.log('bank\'s depositAvailable(0): ', String(await this.bank.depositAvailable(0)));
        // await expectRevert(
        //     this.bank.deposit(0, 10, true, bob, {from: carol}),
        //     'Exceeded quota',
        // );

        await this.soda.transfer(this.sodaPool.address, 99, {from: alice});
        await this.bank.harvestVault(0, {from: carol}); // can be called by public

        console.log('strategy_0\'s balanceOf(vault): ', String(await this.strategy_0.balanceOf(this.wethVault.address)));
        console.log('strategy_1\'s balanceOf(vault): ', String(await this.strategy_1.balanceOf(this.wethVault.address)));

        console.log('bank\'s WETH: ', String(await this.wETH.balanceOf(this.bank.address)));
        console.log('bank\'s SODA: ', String(await this.soda.balanceOf(this.bank.address)));
        
        console.log('bob\'s WETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('carol\'s WETH: ', String(await this.wETH.balanceOf(carol)));

        await time.advanceBlock(); // Block 0
        await time.increase(100);

        console.log('strategy_1\'s WETH: ', String(await this.wETH.balanceOf(this.strategy_1.address)));
        console.log('strategy_1\'s SODA: ', String(await this.soda.balanceOf(this.strategy_1.address)));
        
        await this.soda.transfer(this.sodaPool.address, 88, {from: alice});

        await this.wethVault.withdrawStrategy(this.strategy_1.address, 10, {from: alice});
        await this.wethVault.claimStrategy(this.strategy_1.address, {from: alice});

        console.log('strategy_1\'s WETH: ', String(await this.wETH.balanceOf(this.strategy_1.address)));
        console.log('strategy_1\'s SODA: ', String(await this.soda.balanceOf(this.strategy_1.address)));

        await this.bank.governanceRescueFromStrategy(this.wETH.address, this.strategy_1.address, {from: alice});
        await this.bank.governanceRescueFromStrategy(this.soda.address, this.strategy_1.address, {from: alice});

        console.log('strategy_1\'s WETH: ', String(await this.wETH.balanceOf(this.strategy_1.address)));
        console.log('strategy_1\'s SODA: ', String(await this.soda.balanceOf(this.strategy_1.address)));

        await this.bank.withdraw(0, 10, true, {from: bob});
        await this.bank.withdraw(0, 20, true, {from: carol});

        console.log('bob\'s WETH: ', String(await this.wETH.balanceOf(bob)));
        console.log('carol\'s WETH: ', String(await this.wETH.balanceOf(carol)));
    });
});
