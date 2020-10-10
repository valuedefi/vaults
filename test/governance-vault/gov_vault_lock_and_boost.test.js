const {expectRevert, time} = require('@openzeppelin/test-helpers');

const ValueLiquidityToken = artifacts.require('ValueLiquidityToken');
const ValueGovernanceVault = artifacts.require('ValueGovernanceVault');
const YFVReferral = artifacts.require('YFVReferral');
const MockERC20 = artifacts.require('MockERC20');

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';

contract('gov_vault_lock_and_boost.test', ([alice, bob, carol, david, insuranceFund, minter]) => {
    beforeEach(async () => {
        this.vUSD = await MockERC20.new('Value USD', 'vUSD', 9, 10000000, {from: alice});
        this.vETH = await MockERC20.new('Value ETH', 'vETH', 9, 10000000, {from: alice});
        this.yfv = await MockERC20.new('YFValue', 'YFV', 18, 40000000, {from: alice});
        this.value = await ValueLiquidityToken.new(this.yfv.address, 2370000, {from: alice});
        await this.yfv.approve(this.value.address, '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', {from: alice});
        await this.value.deposit(20000000, {from: alice});
    });

    it('should work', async () => {
        this.govVault = await ValueGovernanceVault.new(this.yfv.address, this.value.address, this.vUSD.address, this.vETH.address, 100, 500, 0);
        await this.value.addMinter(this.govVault.address, {from: alice});
        await this.vUSD.addMinter(this.govVault.address, {from: alice});
        await this.vETH.addMinter(this.govVault.address, {from: alice});
        await this.value.transfer(bob, '1000');
        await this.value.transfer(carol, '1000');
        await this.value.transfer(david, '1000');
        await this.value.approve(this.govVault.address, '2000', {from: bob});
        await this.value.approve(this.govVault.address, '2000', {from: carol});
        await this.value.approve(this.govVault.address, '2000', {from: david});
        await this.govVault.deposit(1000, ADDRESS_ZERO, 0x0, {from: bob});
        await this.govVault.deposit(1000, ADDRESS_ZERO, 0x0, {from: carol});
        await this.govVault.deposit(1000, ADDRESS_ZERO, 0x0, {from: david});
        assert.equal(String(await this.govVault.totalSupply()), '3000');
        assert.equal(String(await this.govVault.balanceOf(this.govVault.address)), '3000');
        assert.equal(String(await this.govVault.balanceOf(bob)), '0');
        assert.equal(String(await this.govVault.balanceOf(carol)), '0');
        assert.equal(String(await this.govVault.balanceOf(david)), '0');
        console.log('\n===== BEFORE LOCK');
        for (let i = 1; i <= 10; i++) {
            await time.advanceBlock();
            console.log('latestBlock=%s', await time.latestBlock());
            console.log('--> pendingValue(bob) = %s', String(await this.govVault.pendingValue(bob)));
            console.log('--> pendingValue(carol) = %s', String(await this.govVault.pendingValue(carol)));
            console.log('--> pendingValue(david) = %s', String(await this.govVault.pendingValue(david)));
        }
        await this.govVault.lockShares('1000', '7', 0x0, {from: carol});
        await this.govVault.lockShares('300', '150', 0x0, {from: david});
        console.log('===== AFTER LOCK');
        for (let i = 1; i <= 10; i++) {
            await time.advanceBlock();
            console.log('latestBlock=%s', await time.latestBlock());
            console.log('--> pendingValue(bob) = %s', String(await this.govVault.pendingValue(bob)));
            console.log('--> pendingValue(carol) = %s', String(await this.govVault.pendingValue(carol)));
            console.log('--> pendingValue(david) = %s', String(await this.govVault.pendingValue(david)));
        }
        await this.govVault.withdrawAll(0x0, {from: bob});
        await this.govVault.withdrawAll(0x0, {from: carol});
        await expectRevert(
            this.govVault.unstake(701, 0x0, {from: david}),
            'stakedBal-locked < _amount',
        );
        await this.govVault.unstake(700, 0x0, {from: david});
        await this.govVault.withdraw(687, 0x0, {from: david});
        console.log('\n===== AFTER WITHDRAWALL');
        console.log('VALUE bob     = %s', String(await this.value.balanceOf(bob)));
        console.log('VALUE carol   = %s', String(await this.value.balanceOf(carol)));
        console.log('VALUE david   = %s', String(await this.value.balanceOf(david)));
        console.log('--> userInfo(bob)    = %s', JSON.stringify(await this.govVault.userInfo(bob)));
        console.log('--> userInfo(carol)  = %s', JSON.stringify(await this.govVault.userInfo(carol)));
        console.log('--> userInfo(david)  = %s', JSON.stringify(await this.govVault.userInfo(david)));
    });
});
