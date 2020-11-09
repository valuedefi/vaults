import {ethers, deployments, getUnnamedAccounts} from 'hardhat';
import {expect} from '../chai-setup';

import {CurveContractV2, StableSwap3Pool} from '../../lib/3crv';
import {
    expandDecimals,
    expandDecimalsString,
    fromWei,
    getLatestBlock,
    maxUint256, mineBlocks,
    toWei,
    toWeiString
} from '../shared/utilities';
import {CurveTokenV1, StableSwapSusd} from '../../lib/susd';
import {MockErc20, ShareConverter, StableSwap3PoolConverter, ValueMultiVaultMaster, ValueMultiVaultBank, MultiStablesVault, MultiStablesVaultController} from '../../typechain';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {coins} from '../shared/coin';

describe('001_bank.test', function () {
    const MAX = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    const INIT_BALANCE = toWei('1000');

    let USDC: MockErc20;
    let USDT: MockErc20;
    let BUSD: MockErc20;
    let DAI: MockErc20;
    let SUSD: MockErc20;
    let TUSD: MockErc20;
    let HUSD: MockErc20;
    let VALUE: MockErc20;

    let BCRV: CurveTokenV1;
    let _3Crv: CurveContractV2;

    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let master: ValueMultiVaultMaster;
    let bank: ValueMultiVaultBank;
    let vault: MultiStablesVault;
    let controller: MultiStablesVaultController;

    let stableSwapConverter: StableSwap3PoolConverter;
    let shareConverter: ShareConverter;

    beforeEach(async () => {
        signers = await ethers.getSigners();
        await deployments.fixture(['ValueMultiVaultBank', 'ShareConverter', 'StableSwap3PoolConverter', 'MultiStablesVaultController']);

        USDC = await ethers.getContract('USDC') as MockErc20;
        USDT = await ethers.getContract('USDT') as MockErc20;
        BUSD = await ethers.getContract('BUSD') as MockErc20;
        DAI = await ethers.getContract('DAI') as MockErc20;
        SUSD = await ethers.getContract('SUSD') as MockErc20;
        TUSD = await ethers.getContract('TUSD') as MockErc20;
        HUSD = await ethers.getContract('HUSD') as MockErc20;
        VALUE = await ethers.getContract('VALUE') as MockErc20;
        _3Crv = await ethers.getContract('3Crv') as CurveContractV2;
        BCRV = await ethers.getContract('poolBUSDToken') as CurveTokenV1;

        stableSwapConverter = await ethers.getContract('StableSwap3PoolConverter') as StableSwap3PoolConverter;
        shareConverter = await ethers.getContract('ShareConverter') as ShareConverter;

        master = await ethers.getContract('ValueMultiVaultMaster') as ValueMultiVaultMaster;
        bank = await ethers.getContract('ValueMultiVaultBank') as ValueMultiVaultBank;
        vault = await ethers.getContract('MultiStablesVault') as MultiStablesVault;
        controller = await ethers.getContract('MultiStablesVaultController') as MultiStablesVaultController;

        deployer = signers[0];
        bob = signers[1];

        // prepare balances
        await DAI.mintTo(bob.address, INIT_BALANCE);
        await USDC.mintTo(bob.address, INIT_BALANCE);
        await USDT.mintTo(bob.address, INIT_BALANCE);
        await BUSD.mintTo(bob.address, INIT_BALANCE);

        // approve
        await DAI.connect(bob).approve(vault.address, MAX);
        await USDC.connect(bob).approve(vault.address, MAX);
        await USDT.connect(bob).approve(vault.address, MAX);
        await BUSD.connect(bob).approve(vault.address, MAX);
        await vault.connect(bob).approve(bank.address, MAX);

        // config vault master
        await master.setConvertSlippage(BUSD.address, 10);
        await master.addVault(vault.address);
        await master.setBank(vault.address, bank.address);

        // config bank
        const block = await getLatestBlock(ethers);
        await bank.addVaultRewardPool(vault.address, VALUE.address, block.number, block.number + 1000, toWei('0.2'));

        // config vault
        // setInputTokens: DAI, USDC, USDT, 3CRV, BUSD, sUSD, husd
        await vault.whitelistContract(bank.address);
        await vault.setInputTokens([DAI.address, USDC.address, USDT.address, _3Crv.address, BUSD.address, SUSD.address, HUSD.address]);
        await vault.setController(controller.address);
        await vault.setConverter(_3Crv.address, stableSwapConverter.address);
        await vault.setShareConverter(shareConverter.address);
        await vault.setMin(9500);
        await vault.setEarnLowerlimit(toWei(10));
        await vault.setCap(toWei(10000000));

        await VALUE.mintTo(bank.address, toWei('200'));
    });

    describe('bank should work', () => {
        it('constructor parameters should be correct', async () => {
            const vaultMaster = await bank.vaultMaster();
            expect(vaultMaster).is.eq(master.address);

            const valueToken = await bank.valueToken();
            expect(valueToken).is.eq(VALUE.address);

            const mbank = await master.bank(vault.address);
            expect(mbank).is.eq(bank.address);
        });

        it('cap()', async () => {
            const cap = await bank.cap(vault.address);
            expect(cap).is.eq(toWei('10000000'));
        });

        it('deposit 10 DAI - no stake', async () => {
            let _before = await vault.balanceOf(bob.address);
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('10'), 1, false, 0)
            let _after = await vault.balanceOf(bob.address);
            expect(_after.sub(_before)).to.gt(toWei('0.05'));
        });

        it('deposit 10 USDC - stake', async () => {
            let _before = await vault.balanceOf(bank.address);
            await bank.connect(bob).deposit(vault.address, USDC.address, expandDecimals('10', 6), 1, true, 0);
            let _after = await vault.balanceOf(bank.address);
            const _minted = _after.sub(_before);
            const userInfo = await bank.userInfo(vault.address, bob.address);
            expect(String(userInfo)).is.eq(_minted);
        });

        it('deposit 10 USDT - stake', async () => {
            let _before = await vault.balanceOf(bank.address);
            await bank.connect(bob).deposit(vault.address, USDT.address, expandDecimals('10', 6), 1, true, 0);
            let _after = await vault.balanceOf(bank.address);
            const _minted = _after.sub(_before);
            const userInfo = await bank.userInfo(vault.address, bob.address);
            expect(String(userInfo)).is.eq(_minted);
        });

        it('deposit 10 BUSD - stake and unstake', async () => {
            const _minted = toWeiString('9.963378549487725315');
            await expect(
                () => bank.connect(bob).deposit(vault.address, BUSD.address, toWei('10'), 1, true, 0),
            ).to.changeTokenBalance(vault, bank, _minted);
            const userInfo = await bank.userInfo(vault.address, bob.address);
            expect(String(userInfo)).is.eq(_minted);
            await expect(
                () => bank.connect(bob).unstake(vault.address, toWei('9'), 0),
            ).to.changeTokenBalance(vault, bob, toWeiString('9'));
        });

        it('withdraw', async () => {
            await bank.connect(bob).deposit(vault.address, BUSD.address, toWei('10'), 1, true, 0);
            await expect(async () => await expect(
                () => bank.connect(bob).withdraw(vault.address, toWei('5'), DAI.address, 1, 0),
            ).to.changeTokenBalance(DAI, bob, toWeiString('4.957833395625191274')))
                .to.changeTokenBalance(vault, bank, toWeiString('-5.0'));
        });

        it('exit', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('10'), 1, true, 0);
            await expect(async () => await expect(
                () => bank.connect(bob).exit(vault.address, DAI.address, 1, 0),
            ).to.changeTokenBalance(DAI, bob, toWeiString('9.984938977663551615')))
                .to.changeTokenBalance(vault, bank, toWeiString('-10.069861293384268054'));
        });

        it('withdraw_fee()', async () => {
            const withdraw_fee = await bank.withdraw_fee(vault.address, toWei(10));
            expect(withdraw_fee).is.eq(toWeiString('0'));
        });

        it('calc_token_amount_deposit()', async () => {
            let _dai = toWei(10);
            let _usdc = expandDecimals(10, coins["USDC"].decimal);
            let _usdt = expandDecimals(10, coins["USDT"].decimal);
            let _3crv = toWei(0);
            let _busd = toWei(10);
            let _susd = toWei(10);
            let _husd = expandDecimals(10, coins["HUSD"].decimal);
            let _amounts = [_dai, _usdc, _usdt, _3crv, _busd, _susd, _husd];
            const amount = await bank.calc_token_amount_deposit(vault.address, _amounts);
            expect(amount).is.gt(toWei('59.962'));
        });

        it('calc_token_amount_withdraw()', async () => {
            await bank.connect(bob).deposit(vault.address, BUSD.address, toWei('10'), 1, true, 0);
            const amount = await bank.calc_token_amount_withdraw(vault.address, toWei(10), DAI.address);
            expect(amount).is.lt(toWei('9.94'));
        });

        it('convert_rate()', async () => {
            const amount = await bank.convert_rate(vault.address, DAI.address, toWei(10));
            expect(amount).is.gt(toWei('10.071'));
        });

        it('exit should have some reward', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('10'), 1, true, 0);
            await mineBlocks(ethers, 10);
            await expect(
                () => bank.connect(bob).exit(vault.address, DAI.address, 1, 0),
            ).to.changeTokenBalance(VALUE, bob, toWeiString('2.199999999999999995'));
        });
    });
});
