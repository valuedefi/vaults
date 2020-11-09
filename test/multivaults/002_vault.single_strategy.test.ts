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
import {
    MockErc20,
    ShareConverter,
    StableSwap3PoolConverter,
    ValueMultiVaultMaster,
    ValueMultiVaultBank,
    MultiStablesVault,
    MultiStablesVaultController,
    StrategyPickle3Crv,
    MockPickleJar,
    MockPickleMasterChef,
    MockUniswapRouter,
    MockConverter
} from '../../typechain';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {coins} from '../shared/coin';
import {BigNumber} from "ethers";

describe('002_vault.single_strategy.test', function () {
    const INIT_BALANCE = toWei('1000');

    let USDC: MockErc20;
    let USDT: MockErc20;
    let BUSD: MockErc20;
    let DAI: MockErc20;
    let SUSD: MockErc20;
    let TUSD: MockErc20;
    let HUSD: MockErc20;

    let WETH: MockErc20;
    let VALUE: MockErc20;
    let PICKLE: MockErc20;

    let BCRV: CurveTokenV1;
    let _3Crv: CurveContractV2;

    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let master: ValueMultiVaultMaster;
    let bank: ValueMultiVaultBank;
    let vault: MultiStablesVault;
    let controller: MultiStablesVaultController;
    let strategyPickl3Crv: StrategyPickle3Crv;

    let stableSwapConverter: StableSwap3PoolConverter;
    let shareConverter: ShareConverter;

    let P3CRV: MockPickleJar;
    let pickleMasterChef: MockPickleMasterChef;
    let unirouter: MockUniswapRouter;
    let mockconverter: MockConverter;

    before(async () => {
        signers = await ethers.getSigners();
        await deployments.fixture(['ValueMultiVaultBank', 'ShareConverter', 'StableSwap3PoolConverter', 'MultiStablesVaultController', 'StrategyPickle3Crv']);

        WETH = await ethers.getContract('WETH') as MockErc20;
        VALUE = await ethers.getContract('VALUE') as MockErc20;
        PICKLE = await ethers.getContract('PICKLE') as MockErc20;

        USDC = await ethers.getContract('USDC') as MockErc20;
        USDT = await ethers.getContract('USDT') as MockErc20;
        BUSD = await ethers.getContract('BUSD') as MockErc20;
        DAI = await ethers.getContract('DAI') as MockErc20;
        SUSD = await ethers.getContract('SUSD') as MockErc20;
        TUSD = await ethers.getContract('TUSD') as MockErc20;
        HUSD = await ethers.getContract('HUSD') as MockErc20;
        _3Crv = await ethers.getContract('3Crv') as CurveContractV2;
        BCRV = await ethers.getContract('poolBUSDToken') as CurveTokenV1;

        stableSwapConverter = await ethers.getContract('StableSwap3PoolConverter') as StableSwap3PoolConverter;
        shareConverter = await ethers.getContract('ShareConverter') as ShareConverter;

        master = await ethers.getContract('ValueMultiVaultMaster') as ValueMultiVaultMaster;
        bank = await ethers.getContract('ValueMultiVaultBank') as ValueMultiVaultBank;
        vault = await ethers.getContract('MultiStablesVault') as MultiStablesVault;
        controller = await ethers.getContract('MultiStablesVaultController') as MultiStablesVaultController;
        strategyPickl3Crv = await ethers.getContract('StrategyPickle3Crv') as StrategyPickle3Crv;

        P3CRV = await ethers.getContract('MockPickleJar') as MockPickleJar;
        pickleMasterChef = await ethers.getContract('MockPickleMasterChef') as MockPickleMasterChef;

        unirouter = await ethers.getContract('MockUniswapRouter') as MockUniswapRouter;
        mockconverter = await ethers.getContract('MockConverter') as MockConverter;

        deployer = signers[0];
        bob = signers[1];

        // prepare balances
        await DAI.mintTo(bob.address, INIT_BALANCE);
        await USDC.mintTo(bob.address, INIT_BALANCE);
        await USDT.mintTo(bob.address, INIT_BALANCE);
        await BUSD.mintTo(bob.address, INIT_BALANCE);

        // approve
        await DAI.connect(bob).approve(vault.address, maxUint256);
        await USDC.connect(bob).approve(vault.address, maxUint256);
        await USDT.connect(bob).approve(vault.address, maxUint256);
        await BUSD.connect(bob).approve(vault.address, maxUint256);
        await vault.connect(bob).approve(bank.address, maxUint256);

        // config vault master
        await master.setSlippage(BUSD.address, 10);
        await master.addVault(vault.address);
        await master.setBank(vault.address, bank.address);

        // config bank
        const block = await getLatestBlock(ethers);
        await bank.addVaultRewardPool(vault.address, VALUE.address, block.number, block.number + 10000, toWei('0.2'));
        await VALUE.mintTo(bank.address, toWei('2000'));

        // config vault
        // setInputTokens: DAI, USDC, USDT, 3CRV, BUSD, sUSD, husd
        await vault.whitelistContract(bank.address);
        await vault.setInputTokens([DAI.address, USDC.address, USDT.address, _3Crv.address, BUSD.address, SUSD.address, HUSD.address]);
        await vault.setController(controller.address);
        await vault.setConverter(_3Crv.address, stableSwapConverter.address);
        await vault.setShareConverter(shareConverter.address);
        //     uint public min = 9500;
        await vault.setMin(9500);
        //     uint public earnLowerlimit = 10 ether; // minimum to invest is 10 3CRV
        await vault.setEarnLowerlimit(toWei(10));
        //     uint totalDepositCap = 10000000 ether; // initial cap set at 10 million dollar
        await vault.setCap(toWei(10000000));

        // config controller
        await controller.approveStrategy(_3Crv.address, strategyPickl3Crv.address);
        await controller.setStrategyInfo(_3Crv.address, 0, strategyPickl3Crv.address, maxUint256, 100);
        await controller.setWantStrategyLength(_3Crv.address, 1);
        await controller.setShareConverter(shareConverter.address);
        await controller.setWantTokens([_3Crv.address]);

        // config strategy
        await strategyPickl3Crv.setUnirouter(unirouter.address);
        await strategyPickl3Crv.setPickleMasterChef(pickleMasterChef.address);

        // prepare balance for unirouter and mock converter & farms
        await PICKLE.mintTo(pickleMasterChef.address, INIT_BALANCE);
        await WETH.mintTo(unirouter.address, INIT_BALANCE);
        await PICKLE.mintTo(unirouter.address, INIT_BALANCE);
        await VALUE.mintTo(unirouter.address, INIT_BALANCE);
        await DAI.mintTo(unirouter.address, INIT_BALANCE);
        await USDT.mintTo(unirouter.address, INIT_BALANCE);
        await USDC.mintTo(unirouter.address, INIT_BALANCE);
    });

    describe('vault with 1 strategy should work', () => {
        it('view(s) should work', async () => {
            const getPricePerFullShare = await vault.getPricePerFullShare();
            expect(getPricePerFullShare).is.eq(toWeiString('1'));
        });

        it('deposit 1 DAI', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('1'), 1, true, 0);
            expect(await vault.totalSupply()).is.gt(toWei('1.006'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.006'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.eq(toWeiString('0'));
        });

        it('deposit 19 DAI: should forward to strategy', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('19'), 1, true, 0);
            expect(await vault.totalSupply()).is.gt(toWei('20.139'));
            expect(await vault.balance()).is.gt(toWei('20.139'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.006'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei('19.132'));
            expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('19.132'));
        });

        it('harvest by bank: should appreciate the sharePrice', async () => {
            const _before = await vault.getPricePerFullShare();
            expect(_before).is.gt(toWei('0.999'));
            await bank.harvestAllStrategies(vault.address, 0);
            const _after = await vault.getPricePerFullShare();
            expect(_after).is.gt(toWei('1.020'));
            expect(_after).is.gt(_before);
        });

        it('harvest by controller: should appreciate the sharePrice', async () => {
            const _before = await vault.getPricePerFullShare();
            await controller.harvestWant(_3Crv.address);
            const _after = await vault.getPricePerFullShare();
            expect(_after).is.gt(_before);
            expect(_after.sub(_before)).is.gt(toWei('0.040'));
        });

        it('exit: no more balance in strategy', async () => {
            const _beforeValue = await VALUE.balanceOf(bob.address);
            await expect(
                () => bank.connect(bob).exit(vault.address, DAI.address, 1, 0),
            ).to.changeTokenBalance(DAI, bob, toWeiString('21.184213918949726735'));
            const _afterValue = await VALUE.balanceOf(bob.address);
            expect(_afterValue.sub(_beforeValue)).is.gt(toWeiString('0.599'));
            expect(await vault.totalSupply()).is.eq(toWeiString('0'));
            const _left = toWeiString('0.021');
            expect(await vault.balance()).is.gt(_left); // withdraw_fee
            expect(await _3Crv.balanceOf(vault.address)).is.eq(toWeiString('0'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(_left);
            expect(await strategyPickl3Crv.balanceOf()).is.gt(_left);
        });

        it('rescue strange token and earn extra', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('20'), 1, true, 0);
            const _before = await vault.getPricePerFullShare();
            await HUSD.mintTo(strategyPickl3Crv.address, toWei(1));
            await expect(
                () => controller.inCaseStrategyGetStuck(strategyPickl3Crv.address, HUSD.address),
            ).to.changeTokenBalance(HUSD, vault, toWeiString(1));
            await vault.setConverterMap(HUSD.address, mockconverter.address);
            await DAI.transfer(stableSwapConverter.address, toWei(1000));
            await stableSwapConverter.convert(DAI.address, _3Crv.address, toWei(1000));
            await _3Crv.transfer(mockconverter.address, toWei(100));
            await vault.earnExtra(HUSD.address);
            const _after = await vault.getPricePerFullShare();
            expect(_after).is.gt(_before);
            expect(_after.sub(_before)).is.gt(toWei('0.024'));
        });

        it('depositAll', async () => {
            let _dai = toWei(10);
            let _usdc = expandDecimals(10, coins["USDC"].decimal);
            let _usdt = expandDecimals(10, coins["USDT"].decimal);
            let _3crv = toWei(0);
            let _busd = toWei(0);
            let _susd = toWei(0);
            let _husd = expandDecimals(0, coins["HUSD"].decimal);
            await bank.connect(bob).depositAll(vault.address, [_dai, _usdc, _usdt, _3crv, _busd, _susd, _husd], 1, true, 0);
            expect(await vault.totalSupply()).is.gt(toWei('49.413'));
            expect(await vault.balance()).is.gt(toWei('50.692'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.576'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei('49.115'));
            expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('49.115'));
        });
    });
});
