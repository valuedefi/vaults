const {expectRevert, time} = require('@openzeppelin/test-helpers');
const ethers = require('ethers');
const ValueLiquidityToken = artifacts.require('ValueLiquidityToken');
const ValueVaultBank = artifacts.require('ValueVaultBank');
const ValueVaultMaster = artifacts.require('ValueVaultMaster');
const MockERC20 = artifacts.require('MockERC20');
const MockGovVault = artifacts.require('MockGovVault');
const MockFarmingPool = artifacts.require('MockFarmingPool');
const MockUniswapRouter = artifacts.require('MockUniswapRouter');
const YFVReferral = artifacts.require('YFVReferral');
const ValueMinorPool = artifacts.require('ValueMinorPool');
const ValueVaultProfitSharer = artifacts.require('ValueVaultProfitSharer');
const UNIv2ETHUSDCVault = artifacts.require('UNIv2ETHUSDCVault');
const Univ2ETHUSDCMultiPoolStrategy = artifacts.require('Univ2ETHUSDCMultiPoolStrategy');

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';
const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

const K_VAULT_ETH_USDC_UNI_V2_LP = 1;
const K_STRATEGY_ETHUSDC_MULTIPOOL = 100;
const K_STRATEGY_ETHWBTC_MULTIPOOL = 200;

function encodeParameters(types, values) {
    const abi = new ethers.utils.AbiCoder();
    return abi.encode(types, values);
}

contract('ValueVaultV2', ([alice, bob, carol, insuranceFund]) => {
    beforeEach(async () => {
        this.yfv = await MockERC20.new('YFValue', 'YFV', 1000000, {from: alice});
        this.value = await ValueLiquidityToken.new(this.yfv.address, 2370000, {from: alice});
        await this.value.addMinter(alice, {from: alice});
        this.uniToken = await MockERC20.new('Uniswap', 'UNI', 1000000, {from: alice});
        this.wETH = await MockERC20.new('Wrapped ETH', 'WETH', 1000000, {from: alice});
        this.usdc = await MockERC20.new('USD Coin', 'USDC', 1000000, {from: alice});
        this.univ2LP = await MockERC20.new('Uniswap V2 (ETH-USDC)', 'UNI-V2', 1000000, {from: alice});

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

        this.uniPool = await MockFarmingPool.new(this.univ2LP.address, this.uniToken.address, 1000, {from: alice});

        const minHarvestForTakeProfit = 10;

        this.v2Strategy = await Univ2ETHUSDCMultiPoolStrategy.new(this.master.address, this.univ2LP.address, this.usdc.address, this.wETH.address, true, {from: alice});
        // await this.v2Strategy.approve(this.uniToken.address, {from: alice});

        this.unirouter = await MockUniswapRouter.new(this.univ2LP.address, {from: alice});
        await this.yfv.transfer(this.unirouter.address, 10000, {from: alice});
        await this.value.mint(this.unirouter.address, 10000, {from: alice});
        await this.uniToken.transfer(this.unirouter.address, 10000, {from: alice});
        await this.wETH.transfer(this.unirouter.address, 10000, {from: alice});
        await this.univ2LP.transfer(this.unirouter.address, 10000, {from: alice});
        await this.usdc.transfer(this.unirouter.address, 10000, {from: alice});

        await this.v2Strategy.setUnirouter(this.unirouter.address, {from: alice});
        await this.v2Strategy.setWETH(this.wETH.address, {from: alice});
        await this.v2Strategy.approveForSpender(this.wETH.address, this.unirouter.address, {from: alice});
        await this.v2Strategy.approveForSpender(this.uniToken.address, this.unirouter.address, {from: alice});

        this.univ2EthUsdcVault = await UNIv2ETHUSDCVault.new(this.master.address, this.v2Strategy.address, {from: alice});

        // function setPoolInfo(uint256 _poolId, address _vault, IERC20 _targetToken, IStakingRewards _targetPool, uint256 _minHarvestForTakeProfit, uint256 _poolQuota) external {
        await this.v2Strategy.setPoolInfo(0, this.univ2EthUsdcVault.address, this.uniToken.address, this.uniPool.address, minHarvestForTakeProfit, 1000);
        console.log('_poolQuota = ', JSON.stringify(await this.v2Strategy.poolQuota(0)));
        // await this.v2Strategy.approve(this.uniToken.address, {from: alice});
        // await this.v2Strategy.approve(this.univ2LP.address, {from: alice});
        // await this.v2Strategy.approveForSpender(this.univ2LP.address, this.univ2EthUsdcVault.address, {from: alice});

        await this.master.addVault(K_VAULT_ETH_USDC_UNI_V2_LP, this.univ2EthUsdcVault.address, {from: alice});
        await this.master.addStrategy(K_STRATEGY_ETHUSDC_MULTIPOOL, this.v2Strategy.address, {from: alice});

        // Let the bank start now.
        await this.bank.setPoolInfo(1, this.univ2LP.address, this.univ2EthUsdcVault.address, 0, 0, 0, 0, {from: alice});
        // console.log('bank = ', this.bank.address);
        console.log('bank\'s pool map (1) = ', JSON.stringify(await this.bank.poolMap(1)));
    });

    it('without any Minor Pool: should work', async () => {
        // alice give bob and carol 1000 for test purpose
        await this.univ2LP.transfer(bob, 1000, {from: alice});
        await this.univ2LP.transfer(carol, 1000, {from: alice});

        // bob stakes 110
        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.bank.deposit(1, 110, false, ADDRESS_ZERO, {from: bob});

        await this.uniToken.transfer(this.uniPool.address, 10000, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('bank\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.bank.address)));
        console.log('uniPool\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.uniPool.address)));
        console.log('univ2EthUsdcVault\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.univ2EthUsdcVault.address)));
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('bob\'s univ2LP: ', String(await this.univ2LP.balanceOf(bob)));
        console.log('------------------------------------------------------------');

        console.log('v2Strategy WETH: ', String(await this.v2Strategy.weth()));
        // await this.bank.harvestVault(1, {from: carol}); // can be called by public

        console.log('bank univ2LP: ', String(await this.univ2LP.balanceOf(this.bank.address)));
        await this.univ2EthUsdcVault.harvestStrategy(MAX_UINT256, 0, {from: alice});
        console.log('bank univ2LP: ', String(await this.univ2LP.balanceOf(this.bank.address)));

        console.log('alice UNI: ', String(await this.uniToken.balanceOf(alice)));
        await this.v2Strategy.claimByGov(this.uniPool.address, {from: alice}); // can be called by gov
        await this.bank.governanceRescueFromStrategy(this.uniToken.address, this.v2Strategy.address, {from: alice});
        await this.bank.governanceRecoverUnsupported(this.uniToken.address, 1, alice, {from: alice});
        console.log('alice UNI: ', String(await this.uniToken.balanceOf(alice)));
        if (this.v2Strategy.log_uniBal) console.log('log_uniBal: ', String(await this.v2Strategy.log_uniBal()));
        if (this.v2Strategy.log_wethBal) console.log('log_wethBal: ', String(await this.v2Strategy.log_wethBal()));
        if (this.v2Strategy.log_reserved) console.log('log_reserved: ', String(await this.v2Strategy.log_reserved()));
        if (this.v2Strategy.log_gasFee) console.log('log_gasFee: ', String(await this.v2Strategy.log_gasFee()));
        if (this.v2Strategy.log_govVaultProfitShareFee) console.log('log_govVaultProfitShareFee: ', String(await this.v2Strategy.log_govVaultProfitShareFee()));
        if (this.v2Strategy.log_wethToBuyTokenA) console.log('log_wethToBuyTokenA: ', String(await this.v2Strategy.log_wethToBuyTokenA()));
        if (this.v2Strategy.log_wethBal_2) console.log('log_wethBal_2: ', String(await this.v2Strategy.log_wethBal_2()));

        // 2 block later, should get some UNI.
        await time.advanceBlock(); // Block 0
        await time.increase(9);
        // await this.bank.claimProfit(0, {from: bob});  // Block 1
        console.log('v2Strategy\'s master: ', String(await this.v2Strategy.valueVaultMaster()));
        console.log('valueVaultMaster\'s bank: ', String(await this.master.bank()));
        console.log('allowance(v2Strategy, bank): ', String(await this.univ2LP.allowance(this.v2Strategy.address, this.bank.address)));

        console.log('v2Strategy.balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));

        console.log('univ2EthUsdcVault\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.univ2EthUsdcVault.address)));
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));

        await this.bank.withdraw(1, 110, false, {from: bob});

        console.log('univ2EthUsdcVault\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.univ2EthUsdcVault.address)));
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));

        if (this.bank.log_strategy0Bal) console.log('log_strategy0Bal: ', String(await this.bank.log_strategy0Bal()));
        if (this.bank.log_out) console.log('log_out: ', String(await this.bank.log_out()));
        if (this.bank.log_actually_out) console.log('log_actually_out: ', String(await this.bank.log_actually_out()));
        if (this.bank.log_earlyClaimCost) console.log('log_earlyClaimCost: ', String(await this.bank.log_earlyClaimCost()));

        // console.log('------------------------------------------------------------');
        // console.log('bob\'s vWETH: ', String(await this.univ2EthUsdcVault.balanceOf(bob)));
        // await this.bank.withdraw(0, 10, {from: bob});

        console.log('------------------------------------------------------------');
        // console.log('bob\'s vWETH (vault): ', String(await this.univ2EthUsdcVault.balanceOf(bob)));
        //
        // console.log('bank\'s SODA: ', String(await this.uniToken.balanceOf(this.bank.address)));
        // console.log('uniPool\'s SODA: ', String(await this.uniToken.balanceOf(this.uniPool.address)));
        // console.log('univ2EthUsdcVault\'s SODA: ', String(await this.uniToken.balanceOf(this.univ2EthUsdcVault.address)));
        // console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));
        // console.log('bob\'s SODA: ', String(await this.uniToken.balanceOf(bob)));

        console.log('bank\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.bank.address)));
        console.log('uniPool\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.uniPool.address)));
        console.log('univ2EthUsdcVault\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.univ2EthUsdcVault.address)));
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('bob\'s univ2LP: ', String(await this.univ2LP.balanceOf(bob)));

        console.log('profitSharer\'s YFV: ', String(await this.yfv.balanceOf(this.profitSharer.address)));
        console.log('govVault\'s YFV: ', String(await this.yfv.balanceOf(this.govVault.address)));

        console.log('profitSharer\'s VALUE: ', String(await this.value.balanceOf(this.profitSharer.address)));
        console.log('govVault\'s VALUE: ', String(await this.value.balanceOf(this.govVault.address)));
        console.log('------------------------------------------------------------');

        const balanceOfUni = await this.uniToken.balanceOf(bob);
        assert.equal(balanceOfUni.valueOf(), '0');
    });

    it('test forward to another strategy', async () => {
        this.anotherStrategy = await Univ2ETHUSDCMultiPoolStrategy.new(this.master.address, this.univ2LP.address, this.usdc.address, this.wETH.address, true, {from: alice});
        await this.master.addStrategy(K_STRATEGY_ETHUSDC_MULTIPOOL + 1, this.anotherStrategy.address, {from: alice});

        // alice give bob and carol 1000 for test purpose
        await this.univ2LP.transfer(bob, 1000, {from: alice});
        await this.univ2LP.transfer(carol, 1000, {from: alice});
        await this.univ2LP.transfer(this.v2Strategy.address, 10, {from: alice});

        // bob stakes 110
        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: bob});

        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');

        await this.bank.deposit(1, 110, false, ADDRESS_ZERO, {from: bob});

        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');

        await this.v2Strategy.withdrawByGov(this.uniPool.address, 110, {from: alice}); // can be called by gov

        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');

        await this.univ2EthUsdcVault.forwardBetweenStrategies(this.v2Strategy.address, this.anotherStrategy.address, 20, {from: alice});

        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');

        await this.anotherStrategy.approveForSpender(this.univ2LP.address, this.uniPool.address, {from: alice});
        await this.anotherStrategy.depositByGov(this.uniPool.address, 10, {from: alice}); // can be called by gov

        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('anotherStrategy\'s balanceOf(): ', String(await this.uniPool.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');

        // pool.stake(_amount);
        await this.anotherStrategy.executeTransaction(
            this.uniPool.address, '0', 'stake(uint256)',
            encodeParameters(['uint256'], ['10']), {from: alice},
        );
        console.log('------------------------------------------------------------');
        console.log('v2Strategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s balanceOf(0): ', String(await this.v2Strategy.balanceOf(0)));
        console.log('anotherStrategy\'s univ2LP: ', String(await this.univ2LP.balanceOf(this.anotherStrategy.address)));
        console.log('anotherStrategy\'s balanceOf(): ', String(await this.uniPool.balanceOf(this.anotherStrategy.address)));
        console.log('------------------------------------------------------------');
    });

    return;

    it('with Minor Pool running: should work', async () => {
        this.minorPool = await ValueMinorPool.new(this.value.address, insuranceFund, 1, 0, this.master.address, {from: alice});
        this.ref = await YFVReferral.new({from: alice});
        await this.ref.setAdminStatus(this.minorPool.address, true, {from: alice});
        await this.minorPool.setRewardReferral(this.ref.address, {from: alice});
        await this.value.addMinter(this.minorPool.address, {from: alice});

        await this.minorPool.add('100', this.univ2EthUsdcVault.address, true, 0, {from: alice});
        await this.master.setMinorPool(this.minorPool.address, {from: alice});

        // alice give bob and carol 1000 for test purpose
        await this.univ2LP.transfer(bob, 1000, {from: alice});
        await this.univ2LP.transfer(carol, 1000, {from: alice});

        // bob stakes 110
        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: bob});
        // await this.univ2EthUsdcVault.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.univ2EthUsdcVault.approve(this.minorPool.address, MAX_UINT256, {from: bob});
        await this.bank.setPoolCap(0, 10, 1000, {from: alice});

        await expectRevert(
            this.bank.deposit(0, 110, true, carol, {from: bob}),
            'Exceed pool.individualCap',
        );

        await this.bank.setPoolCap(0, 200, 1000, {from: alice});

        await this.bank.deposit(0, 110, true, carol, {from: bob});
        await this.bank.deposit(0, 90, false, carol, {from: bob});

        console.log('stakers\'s (0, bob): ', JSON.stringify(await this.bank.stakers(0, bob)));
        // userInfo[_pid][farmer]
        console.log('userInfo\'s (0, bob): ', JSON.stringify(await this.minorPool.userInfo(0, bob)));

        await this.uniToken.transfer(this.uniPool.address, 99, {from: alice});

        await this.bank.harvestVault(0, {from: carol}); // can be called by public

        // 2 block later, he should get some SODA.
        await time.advanceBlock(); // Block 0
        await time.increase(9);

        await this.bank.withdraw(0, 110, true, {from: bob});

        console.log('------------------------------------------------------------');
        console.log('bob\'s vWETH (vault): ', String(await this.univ2EthUsdcVault.balanceOf(bob)));
        console.log('bob\'s SODA: ', String(await this.uniToken.balanceOf(bob)));
        console.log('bob\'s univ2LP: ', String(await this.univ2LP.balanceOf(bob)));
        console.log('bob\'s YFV: ', String(await this.yfv.balanceOf(bob)));
        console.log('bob\'s VALUE: ', String(await this.value.balanceOf(bob)));
        console.log('------------------------------------------------------------');
    });

    it('with Ref: should work', async () => {
        this.minorPool = await ValueMinorPool.new(this.value.address, insuranceFund, 10, 0, this.master.address, {from: alice});
        this.ref = await YFVReferral.new({from: alice});
        await this.ref.setAdminStatus(this.minorPool.address, true, {from: alice});
        await this.minorPool.setRewardReferral(this.ref.address, {from: alice});
        await this.value.addMinter(this.minorPool.address, {from: alice});

        await this.minorPool.add('100', this.univ2EthUsdcVault.address, true, 0, {from: alice});
        await this.master.setMinorPool(this.minorPool.address, {from: alice});

        await this.univ2LP.transfer(bob, 1000, {from: alice});

        // bob stakes 110
        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.univ2EthUsdcVault.approve(this.minorPool.address, MAX_UINT256, {from: bob});

        await this.bank.deposit(0, 100, true, carol, {from: bob});

        await this.uniToken.transfer(this.uniPool.address, 99, {from: alice});
        await this.bank.harvestVault(0, {from: carol}); // can be called by public

        // 2 block later, he should get some SODA.
        await time.advanceBlock(); // Block 0
        await time.increase(9);

        await this.bank.withdraw(0, 100, true, {from: bob});

        console.log('------------------------------------------------------------');
        console.log('bob\'s vWETH (vault): ', String(await this.univ2EthUsdcVault.balanceOf(bob)));
        console.log('bob\'s SODA: ', String(await this.uniToken.balanceOf(bob)));
        console.log('bob\'s univ2LP: ', String(await this.univ2LP.balanceOf(bob)));
        console.log('bob\'s YFV: ', String(await this.yfv.balanceOf(bob)));
        console.log('bob\'s VALUE: ', String(await this.value.balanceOf(bob)));
        console.log('------------------------------------------------------------');

        console.log('------------------------------------------------------------');
        console.log('carol\'s vWETH (vault): ', String(await this.univ2EthUsdcVault.balanceOf(carol)));
        console.log('carol\'s SODA: ', String(await this.uniToken.balanceOf(carol)));
        console.log('carol\'s univ2LP: ', String(await this.univ2LP.balanceOf(carol)));
        console.log('carol\'s YFV: ', String(await this.yfv.balanceOf(carol)));
        console.log('carol\'s VALUE: ', String(await this.value.balanceOf(carol)));
        console.log('------------------------------------------------------------');
    });

    it('emergency: should work', async () => {
        this.minorPool = await ValueMinorPool.new(this.value.address, insuranceFund, 1, 0, this.master.address, {from: alice});
        await this.value.addMinter(this.minorPool.address, {from: alice});

        await this.minorPool.add('100', this.univ2EthUsdcVault.address, true, 0, {from: alice});
        await this.master.setMinorPool(this.minorPool.address, {from: alice});

        // alice give bob and carol 1000 for test purpose
        await this.univ2LP.transfer(bob, 1000, {from: alice});
        await this.univ2LP.transfer(carol, 1000, {from: alice});

        // bob and carol stake 100
        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: bob});
        await this.univ2EthUsdcVault.approve(this.minorPool.address, MAX_UINT256, {from: bob});
        await this.bank.deposit(0, 100, true, carol, {from: bob});

        console.log('v2Strategy\'s WETH: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));

        await this.univ2LP.approve(this.bank.address, MAX_UINT256, {from: carol});
        await this.univ2EthUsdcVault.approve(this.minorPool.address, MAX_UINT256, {from: carol});
        await this.bank.deposit(0, 100, true, bob, {from: carol});

        console.log('v2Strategy\'s WETH: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));

        await this.uniToken.transfer(this.uniPool.address, 99, {from: alice});
        // await this.bank.harvestVault(0, {from: carol}); // can be called by public
        await this.univ2EthUsdcVault.claimStrategy(this.v2Strategy.address, {from: alice}); // can be called by public

        console.log('v2Strategy\'s WETH: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));

        await this.univ2EthUsdcVault.withdrawStrategy(this.v2Strategy.address, 200);

        console.log('v2Strategy\'s WETH: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));

        console.log('bank\'s WETH: ', String(await this.univ2LP.balanceOf(this.bank.address)));
        console.log('bank\'s SODA: ', String(await this.uniToken.balanceOf(this.bank.address)));

        await this.bank.governanceRescueFromStrategy(this.univ2LP.address, this.v2Strategy.address, {from: alice});
        await this.bank.governanceRescueFromStrategy(this.uniToken.address, this.v2Strategy.address, {from: alice});

        console.log('v2Strategy\'s WETH: ', String(await this.univ2LP.balanceOf(this.v2Strategy.address)));
        console.log('v2Strategy\'s SODA: ', String(await this.uniToken.balanceOf(this.v2Strategy.address)));

        console.log('bank\'s WETH: ', String(await this.univ2LP.balanceOf(this.bank.address)));
        console.log('bank\'s SODA: ', String(await this.uniToken.balanceOf(this.bank.address)));

        console.log('bob\'s WETH: ', String(await this.univ2LP.balanceOf(bob)));
        console.log('carol\'s WETH: ', String(await this.univ2LP.balanceOf(carol)));

        await this.bank.withdraw(0, 100, true, {from: bob});
        await this.bank.withdraw(0, 100, true, {from: carol});

        console.log('bob\'s WETH: ', String(await this.univ2LP.balanceOf(bob)));
        console.log('carol\'s WETH: ', String(await this.univ2LP.balanceOf(carol)));
    });
});
