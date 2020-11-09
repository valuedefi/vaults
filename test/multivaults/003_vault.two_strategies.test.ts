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
    StableSwapBusdConverter,
    ValueMultiVaultMaster,
    ValueMultiVaultBank,
    MultiStablesVault,
    MultiStablesVaultController,
    StrategyPickle3Crv,
    MockPickleJar,
    MockPickleMasterChef,
    MockUniswapRouter,
    MockConverter,
    StrategyCurveBCrv,
    MockCurveGauge,
    MockCurveMinter,
} from '../../typechain';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {coins} from '../shared/coin';
import {BigNumber} from "ethers";

const verbose = process.env.VERBOSE;

describe('003_vault.two_strategies.test', function () {
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
    let CRV: MockErc20;

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
    let strategyCurveBCrv: StrategyCurveBCrv;

    let stableSwap3PoolConverter: StableSwap3PoolConverter;
    let stableSwapBusdConverter: StableSwapBusdConverter;
    let shareConverter: ShareConverter;

    let P3CRV: MockPickleJar;
    let pickleMasterChef: MockPickleMasterChef;
    let mockBCrvCurveGauge: MockCurveGauge;
    let mockCurveMinter: MockCurveMinter;
    let unirouter: MockUniswapRouter;
    let mockconverter: MockConverter;

    before(async () => {
        signers = await ethers.getSigners();
        await deployments.fixture(['ValueMultiVaultBank', 'ShareConverter', 'StableSwap3PoolConverter', 'StableSwapBusdConverter', 'MultiStablesVaultController', 'StrategyPickle3Crv', 'StrategyCurveBCrv']);

        WETH = await ethers.getContract('WETH') as MockErc20;
        VALUE = await ethers.getContract('VALUE') as MockErc20;
        PICKLE = await ethers.getContract('PICKLE') as MockErc20;
        CRV = await ethers.getContract('CRV') as MockErc20;

        USDC = await ethers.getContract('USDC') as MockErc20;
        USDT = await ethers.getContract('USDT') as MockErc20;
        BUSD = await ethers.getContract('BUSD') as MockErc20;
        DAI = await ethers.getContract('DAI') as MockErc20;
        SUSD = await ethers.getContract('SUSD') as MockErc20;
        TUSD = await ethers.getContract('TUSD') as MockErc20;
        HUSD = await ethers.getContract('HUSD') as MockErc20;
        _3Crv = await ethers.getContract('3Crv') as CurveContractV2;
        BCRV = await ethers.getContract('poolBUSDToken') as CurveTokenV1;

        stableSwap3PoolConverter = await ethers.getContract('StableSwap3PoolConverter') as StableSwap3PoolConverter;
        stableSwapBusdConverter = await ethers.getContract('StableSwapBusdConverter') as StableSwapBusdConverter;
        
        shareConverter = await ethers.getContract('ShareConverter') as ShareConverter;

        master = await ethers.getContract('ValueMultiVaultMaster') as ValueMultiVaultMaster;
        bank = await ethers.getContract('ValueMultiVaultBank') as ValueMultiVaultBank;
        vault = await ethers.getContract('MultiStablesVault') as MultiStablesVault;
        controller = await ethers.getContract('MultiStablesVaultController') as MultiStablesVaultController;
        strategyPickl3Crv = await ethers.getContract('StrategyPickle3Crv') as StrategyPickle3Crv;
        strategyCurveBCrv = await ethers.getContract('StrategyCurveBCrv') as StrategyCurveBCrv;

        P3CRV = await ethers.getContract('MockPickleJar') as MockPickleJar;
        pickleMasterChef = await ethers.getContract('MockPickleMasterChef') as MockPickleMasterChef;

        mockBCrvCurveGauge = await ethers.getContract('MockBCrvCurveGauge') as MockCurveGauge;
        mockCurveMinter = await ethers.getContract('MockCurveMinter') as MockCurveMinter;

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
        await master.addController(controller.address);
        await master.addStrategy(strategyPickl3Crv.address);
        await master.addStrategy(strategyCurveBCrv.address);

        // config bank
        const block = await getLatestBlock(ethers);
        await bank.addVaultRewardPool(vault.address, VALUE.address, block.number, block.number + 10000, toWei('0.2'));
        await VALUE.mintTo(bank.address, toWei('2000'));

        // config vault
        // setInputTokens: DAI, USDC, USDT, 3CRV, BUSD, sUSD, husd
        await vault.whitelistContract(bank.address);
        await vault.setInputTokens([DAI.address, USDC.address, USDT.address, _3Crv.address, BUSD.address, SUSD.address, HUSD.address]);
        await vault.setController(controller.address);
        await vault.setConverter(_3Crv.address, stableSwap3PoolConverter.address);
        await vault.setConverter(BCRV.address, stableSwapBusdConverter.address);
        await vault.setShareConverter(shareConverter.address);
        //     uint public min = 9500;
        await vault.setMin(9500);
        //     uint public earnLowerlimit = 10 ether; // minimum to invest is 10 3CRV
        await vault.setEarnLowerlimit(toWei(10));
        //     uint totalDepositCap = 10000000 ether; // initial cap set at 10 million dollar
        await vault.setCap(toWei(10000000));

        // config controller
        await controller.approveStrategy(_3Crv.address, strategyPickl3Crv.address);
        await controller.approveStrategy(BCRV.address, strategyCurveBCrv.address);
        await controller.setStrategyInfo(_3Crv.address, 0, strategyPickl3Crv.address, maxUint256, 100);
        await controller.setStrategyInfo(BCRV.address, 0, strategyCurveBCrv.address, maxUint256, 100);
        await controller.setWantStrategyLength(_3Crv.address, 1);
        await controller.setWantStrategyLength(BCRV.address, 1);
        await controller.setShareConverter(shareConverter.address);
        await controller.setWantTokens([_3Crv.address, BCRV.address]);

        // config strategyPickl3Crv
        await strategyPickl3Crv.setUnirouter(unirouter.address);
        await strategyPickl3Crv.setPickleMasterChef(pickleMasterChef.address);

        // config strategyCurveBCrv
        await strategyCurveBCrv.setUnirouter(unirouter.address);

        // prepare balance for unirouter and mock converter & farms
        await PICKLE.mintTo(pickleMasterChef.address, INIT_BALANCE);
        await WETH.mintTo(unirouter.address, INIT_BALANCE);
        await PICKLE.mintTo(unirouter.address, INIT_BALANCE);
        await VALUE.mintTo(unirouter.address, INIT_BALANCE);
        await CRV.mintTo(unirouter.address, INIT_BALANCE);
        await DAI.mintTo(unirouter.address, INIT_BALANCE);
        await USDT.mintTo(unirouter.address, INIT_BALANCE);
        await USDC.mintTo(unirouter.address, INIT_BALANCE);
        await CRV.mintTo(mockCurveMinter.address, INIT_BALANCE);
    });

    describe('vault with 2 strategies (strategyPickl3Crv and strategyCurveBCrv) should work', () => {
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

        it('deposit 19 DAI: should forward to default strategy (strategyPickl3Crv)', async () => {
            await bank.connect(bob).deposit(vault.address, DAI.address, toWei('19'), 1, true, 0);
            expect(await vault.totalSupply()).is.gt(toWei('20.139'));
            expect(await vault.balance()).is.gt(toWei('20.139'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.006'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei('19.132'));
            expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('19.132'));
        });

        it('deposit 40 USDC: should forward to another want strategy (strategyCurveBCrv)', async () => {
            let _usdc = expandDecimals(40, coins["USDC"].decimal);
            await vault.setInput2Want(USDC.address, BCRV.address); // so from now on: deposit USDC will forward to BCRV strategy
            await bank.connect(bob).deposit(vault.address, USDC.address, _usdc, 1, true, 0);
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault balance_to_sell() = ', fromWei(await vault.balance_to_sell()));
                console.log('vault _3Crv         = ', fromWei(await _3Crv.balanceOf(vault.address)));
                console.log('vault BCRV          = ', fromWei(await BCRV.balanceOf(vault.address)));
                console.log('controller balanceOf(_3Crv, 0)= ', fromWei(await controller.balanceOf(_3Crv.address, false)));
                console.log('controller balanceOf(_3Crv, 1)= ', fromWei(await controller.balanceOf(_3Crv.address, true)));
                console.log('strategyPickl3Crv balanceOf() = ', fromWei(await strategyPickl3Crv.balanceOf()));
                console.log('strategyCurveBCrv balanceOf() = ', fromWei(await strategyCurveBCrv.balanceOf()));
            }
            expect(await vault.totalSupply()).is.gt(toWei('60.0184'));
            expect(await vault.balance()).is.gt(toWei('60.0184'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.0069'));
            expect(await BCRV.balanceOf(vault.address)).is.eq(toWei('0'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei('59.0114'));
            expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('19.1327'));
            expect(await strategyCurveBCrv.balanceOf()).is.gt(toWei('39.9394'));
        });

        it('withdraw 30 shares: should withdraw from strategyCurveBCrv', async () => {
            await vault.setAllowWithdrawFromOtherWant(USDC.address, true); // so from now on: withdraw USDC will get from strategyCurveBCrv if balance is enough
            await bank.connect(bob).withdraw(vault.address, toWei(30), USDC.address, 1, 0);
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault balance_to_sell() = ', fromWei(await vault.balance_to_sell()));
                console.log('vault _3Crv         = ', fromWei(await _3Crv.balanceOf(vault.address)));
                console.log('vault BCRV          = ', fromWei(await BCRV.balanceOf(vault.address)));
                console.log('controller balanceOf(_3Crv, 0)= ', fromWei(await controller.balanceOf(_3Crv.address, false)));
                console.log('controller balanceOf(_3Crv, 1)= ', fromWei(await controller.balanceOf(_3Crv.address, true)));
                console.log('strategyPickl3Crv balanceOf() = ', fromWei(await strategyPickl3Crv.balanceOf()));
                console.log('strategyCurveBCrv balanceOf() = ', fromWei(await strategyCurveBCrv.balanceOf()));
            }
            expect(await vault.totalSupply()).is.gt(toWei('30.0184'));
            expect(await vault.balance()).is.gt(toWei('30.0639'));
            expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.0069'));
            expect(await BCRV.balanceOf(vault.address)).is.eq(toWei('0'));
            expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei(' 29.0569'));
            expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('19.1327'));
            expect(await strategyCurveBCrv.balanceOf()).is.gt(toWei('9.9392'));
        });

        it('harvest by controller: should appreciate the sharePrice', async () => {
            const _before = await vault.getPricePerFullShare();
            await controller.harvestAllStrategies();
            const _after = await vault.getPricePerFullShare();
            if (verbose) {
                console.log('sharePrice _before = ', fromWei(_before));
                console.log('sharePrice _after  = ', fromWei(_after));
            }
            expect(_after).is.gt(_before);
            expect(_after.sub(_before)).is.gt(toWei('0.7263'));
        });

        it('exit: no more balance in strategy', async () => {
            const _beforeValue = await VALUE.balanceOf(bob.address);
            await expect(
                () => bank.connect(bob).exit(vault.address, DAI.address, 1, 0),
            ).to.changeTokenBalance(DAI, bob, toWeiString('51.428352768607094834'));
            const _afterValue = await VALUE.balanceOf(bob.address);
            expect(_afterValue.sub(_beforeValue)).is.gt(toWeiString('0.399'));
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault balance_to_sell() = ', fromWei(await vault.balance_to_sell()));
                console.log('vault _3Crv         = ', fromWei(await _3Crv.balanceOf(vault.address)));
                console.log('vault BCRV          = ', fromWei(await BCRV.balanceOf(vault.address)));
                console.log('controller balanceOf(_3Crv, 0)= ', fromWei(await controller.balanceOf(_3Crv.address, false)));
                console.log('controller balanceOf(_3Crv, 1)= ', fromWei(await controller.balanceOf(_3Crv.address, true)));
                console.log('strategyPickl3Crv balanceOf() = ', fromWei(await strategyPickl3Crv.balanceOf()));
                console.log('strategyCurveBCrv balanceOf() = ', fromWei(await strategyCurveBCrv.balanceOf()));
            }
            expect(await vault.totalSupply()).is.eq(toWeiString('0'));
            const _left = toWeiString('0.0522');
            expect(await vault.balance()).is.gt(_left); // withdraw_fee
            expect(await _3Crv.balanceOf(vault.address)).is.gt(_left);
            expect(await controller.balanceOf(_3Crv.address, false)).is.eq(toWei('0'));
            expect(await strategyPickl3Crv.balanceOf()).is.eq(toWei('0'));
        });

        it('deposit 100 USDT and 100 USDC: and switch fund', async () => {
            let _usdt = expandDecimals(100, coins["USDT"].decimal);
            let _usdc = expandDecimals(100, coins["USDC"].decimal);
            await bank.connect(bob).deposit(vault.address, USDT.address, _usdt, 1, true, 0);
            await bank.connect(bob).deposit(vault.address, USDC.address, _usdc, 1, true, 0);
            let _bcrvStratBal = await strategyCurveBCrv.balanceOf();
            if (verbose) {
                console.log('Before switchFund.......');
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault balance_to_sell() = ', fromWei(await vault.balance_to_sell()));
                console.log('vault _3Crv         = ', fromWei(await _3Crv.balanceOf(vault.address)));
                console.log('vault BCRV          = ', fromWei(await BCRV.balanceOf(vault.address)));
                console.log('controller _3Crv    = ', fromWei(await _3Crv.balanceOf(controller.address)));
                console.log('controller BCRV     = ', fromWei(await BCRV.balanceOf(controller.address)));
                console.log('controller balanceOf(_3Crv, 0)= ', fromWei(await controller.balanceOf(_3Crv.address, false)));
                console.log('controller balanceOf(_3Crv, 1)= ', fromWei(await controller.balanceOf(_3Crv.address, true)));
                console.log('strategyPickl3Crv balanceOf() = ', fromWei(await strategyPickl3Crv.balanceOf()));
                console.log('strategyCurveBCrv balanceOf() = ', fromWei(await strategyCurveBCrv.balanceOf()));
            }
            await controller.switchFund(strategyCurveBCrv.address, strategyPickl3Crv.address, _bcrvStratBal);
            if (verbose) {
                console.log('After switchFund.......');
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault balance_to_sell() = ', fromWei(await vault.balance_to_sell()));
                console.log('vault _3Crv         = ', fromWei(await _3Crv.balanceOf(vault.address)));
                console.log('vault BCRV          = ', fromWei(await BCRV.balanceOf(vault.address)));
                console.log('controller _3Crv    = ', fromWei(await _3Crv.balanceOf(controller.address)));
                console.log('controller BCRV     = ', fromWei(await BCRV.balanceOf(controller.address)));
                console.log('controller balanceOf(_3Crv, 0)= ', fromWei(await controller.balanceOf(_3Crv.address, false)));
                console.log('controller balanceOf(_3Crv, 1)= ', fromWei(await controller.balanceOf(_3Crv.address, true)));
                console.log('strategyPickl3Crv balanceOf() = ', fromWei(await strategyPickl3Crv.balanceOf()));
                console.log('strategyCurveBCrv balanceOf() = ', fromWei(await strategyCurveBCrv.balanceOf()));
            }
            // expect(await vault.totalSupply()).is.gt(toWei('60.0184'));
            // expect(await vault.balance()).is.gt(toWei('60.0184'));
            // expect(await _3Crv.balanceOf(vault.address)).is.gt(toWei('1.0069'));
            // expect(await BCRV.balanceOf(vault.address)).is.eq(toWei('0'));
            // expect(await controller.balanceOf(_3Crv.address, false)).is.gt(toWei('59.0114'));
            // expect(await strategyPickl3Crv.balanceOf()).is.gt(toWei('19.1327'));
            // expect(await strategyCurveBCrv.balanceOf()).is.gt(toWei('39.9394'));
        });
    });
});
