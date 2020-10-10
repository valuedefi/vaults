const {expectRevert, time} = require('@openzeppelin/test-helpers');

const ValueLiquidityToken = artifacts.require('ValueLiquidityToken');
const ValueGovernanceVault = artifacts.require('ValueGovernanceVault');
const YFVReferral = artifacts.require('YFVReferral');
const MockERC20 = artifacts.require('MockERC20');

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';

contract('ValueGovernanceVault.test', ([alice, bob, carol, insuranceFund, minter]) => {
    beforeEach(async () => {
        this.vUSD = await MockERC20.new('Value USD', 'vUSD', 9, 10000000, {from: alice});
        this.vETH = await MockERC20.new('Value ETH', 'vETH', 9, 10000000, {from: alice});
        this.yfv = await MockERC20.new('YFValue', 'YFV', 18, 40000000, {from: alice});
        this.value = await ValueLiquidityToken.new(this.yfv.address, 2370000, {from: alice});
        await this.yfv.approve(this.value.address, '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', {from: alice});
        await this.value.deposit(20000000, {from: alice});
    });

    it('should work', async () => {
        this.govVault = await ValueGovernanceVault.new(this.yfv.address, this.value.address, this.vUSD.address, this.vETH.address, 0, 500, 0);
        await this.value.addMinter(this.govVault.address, {from: alice});
        await this.vUSD.addMinter(this.govVault.address, {from: alice});
        await this.vETH.addMinter(this.govVault.address, {from: alice});
        await this.yfv.transfer(bob, '1000');
        await this.value.transfer(carol, '1000');
        await this.yfv.approve(this.govVault.address, '1000', {from: bob});
        await this.value.approve(this.govVault.address, '1000', {from: bob});
        await this.value.approve(this.govVault.address, '2000', {from: carol});
        await this.govVault.depositYFV(100, ADDRESS_ZERO, 0x0, {from: bob});
        await this.govVault.deposit(1000, ADDRESS_ZERO, 0x0, {from: carol});
        assert.equal(String(await this.govVault.totalSupply()), '1100');
        assert.equal(String(await this.govVault.balanceOf(this.govVault.address)), '1100');
        assert.equal(String(await this.govVault.balanceOf(bob)), '0');
        assert.equal(String(await this.govVault.balanceOf(carol)), '0');
        console.log('\n===== BEFORE setXxxPerBlock');
        for (let i = 1; i <= 10; i++) {
            await time.advanceBlock();
            console.log('latestBlock=%s', await time.latestBlock());
            console.log('--> pendingValue(bob) = %s', String(await this.govVault.pendingValue(bob)));
            console.log('--> pendingVusd(bob)  = %s', String(await this.govVault.pendingVusd(bob)));
            console.log('--> pendingValue(carol) = %s', String(await this.govVault.pendingValue(carol)));
            console.log('--> pendingVusd(carol)  = %s', String(await this.govVault.pendingVusd(carol)));
        }
        // await this.govVault.unstake(0, 0x0, {from: carol});
        await this.govVault.setValuePerBlock(20);
        await this.govVault.setVusdPerBlock(0);
        console.log('===== AFTER setXxxPerBlock');
        for (let i = 1; i <= 10; i++) {
            await time.advanceBlock();
            console.log('latestBlock=%s', await time.latestBlock());
            console.log('--> pendingValue(bob) = %s', String(await this.govVault.pendingValue(bob)));
            console.log('--> pendingVusd(bob)  = %s', String(await this.govVault.pendingVusd(bob)));
            console.log('--> pendingValue(carol) = %s', String(await this.govVault.pendingValue(carol)));
            console.log('--> pendingVusd(carol)  = %s', String(await this.govVault.pendingVusd(carol)));
        }
        // console.log('--> userInfo(bob)  = %s', JSON.stringify(await this.govVault.userInfo(bob)));
        // console.log('gvVALUE vault      = %s', String(await this.govVault.balanceOf(this.govVault.address)));
        await this.govVault.withdrawAll(0x0, {from: bob});
        // await this.govVault.unstake(100, 0x0, {from: bob});
        console.log('VALUE bob   = %s', String(await this.value.balanceOf(bob)));
        console.log('VALUE carol = %s', String(await this.value.balanceOf(carol)));
        console.log('gvVALUE bob   = %s', String(await this.govVault.balanceOf(bob)));
        console.log('gvVALUE carol = %s', String(await this.govVault.balanceOf(carol)));

        console.log('\n===== BEFORE make_profit');
        console.log('VALUE govVault       = %s', String(await this.value.balanceOf(this.govVault.address)));
        console.log('getPricePerFullShare = %s', String(await this.govVault.getPricePerFullShare()));
        await this.value.transfer(this.govVault.address, '1000');
        console.log('===== AFTER make_profit');
        console.log('VALUE govVault       = %s', String(await this.value.balanceOf(this.govVault.address)));
        console.log('getPricePerFullShare = %s', String(await this.govVault.getPricePerFullShare()));

        console.log('\n===== BEFORE buyShares');
        console.log('VALUE bob   = %s', String(await this.value.balanceOf(bob)));
        console.log('gvVALUE bob   = %s', String(await this.govVault.balanceOf(bob)));
        await this.govVault.buyShares(100, 0x0, {from: bob});
        console.log('===== AFTER buyShares');
        console.log('VALUE bob   = %s', String(await this.value.balanceOf(bob)));
        console.log('gvVALUE bob   = %s', String(await this.govVault.balanceOf(bob)));
        console.log('--> userInfo(carol)  = %s', JSON.stringify(await this.govVault.userInfo(carol)));
        console.log('VALUE carol       = %s', String(await this.value.balanceOf(carol)));
        console.log('gvVALUE carol     = %s', String(await this.govVault.balanceOf(carol)));
        console.log('VALUE govVault    = %s', String(await this.value.balanceOf(this.govVault.address)));
        console.log('gvVALUE govVault  = %s', String(await this.govVault.balanceOf(this.govVault.address)));

        console.log('\n===== AFTER carol withdrawAll');
        await this.govVault.getRewardAndDepositAll(0x0, {from: carol});
        await this.govVault.unstake(1000, 0x0, {from: carol});
        await this.govVault.approve(this.govVault.address, '981', {from: carol});
        await this.govVault.depositShares(981, bob, 0x0, {from: carol});
        await this.govVault.withdrawAll(0x0, {from: carol});
        // await this.govVault.withdraw(981, 0x0, {from: carol});
        console.log('VALUE carol   = %s', String(await this.value.balanceOf(carol)));
        console.log('gvVALUE carol = %s', String(await this.govVault.balanceOf(carol)));
        console.log('vUSD carol    = %s', String(await this.vUSD.balanceOf(carol)));
        console.log('vETH carol    = %s', String(await this.vETH.balanceOf(carol)));
        console.log('VALUE govVault       = %s', String(await this.value.balanceOf(this.govVault.address)));
        console.log('gvVALUE govVault     = %s', String(await this.govVault.balanceOf(this.govVault.address)));
        console.log('getPricePerFullShare = %s', String(await this.govVault.getPricePerFullShare()));

        console.log('\n===== AFTER bob withdraw');
        await this.govVault.withdraw(50, 0x0, {from: bob});
        console.log('VALUE bob   = %s', String(await this.value.balanceOf(bob)));
        console.log('gvVALUE bob = %s', String(await this.govVault.balanceOf(bob)));
        console.log('vUSD bob    = %s', String(await this.vUSD.balanceOf(bob)));
        console.log('vETH bob    = %s', String(await this.vETH.balanceOf(bob)));
        console.log('VALUE govVault       = %s', String(await this.value.balanceOf(this.govVault.address)));
        console.log('gvVALUE govVault     = %s', String(await this.govVault.balanceOf(this.govVault.address)));
        console.log('getPricePerFullShare = %s', String(await this.govVault.getPricePerFullShare()));
    });
});
