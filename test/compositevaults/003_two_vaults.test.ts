import {deployments, ethers} from 'hardhat';
import {expect} from '../chai-setup';

import {
    fromWei,
    toWei,
    toWeiString,
    mineBlocks,
    maxUint256,
    ADDRESS_ZERO
} from '../shared/utilities';

import {
    TToken,
    TTokenFactory,
    CompositeVaultMaster,
    CompositeVaultMasterFactory,
    CompositeVaultBank,
    CompositeVaultBankFactory,
    CompositeVaultSlpEthUsdc,
    CompositeVaultSlpEthUsdcFactory,
    CompositeVaultController,
    CompositeVaultControllerFactory,
    MockUniswapRouter,
    MockUniswapRouterFactory,
    MockUniswapV2Pair,
    MockUniswapV2PairFactory,
    StrategyBalancerEthUsdc,
    StrategyBalancerEthUsdcFactory,
    MockLpPairConverter,
    MockLpPairConverterFactory,
    MockSushiMasterChef,
    StrategySushiEthUsdc,
    SushiswapLpPairConverter,
    SushiswapLpPairConverterFactory,
    StrategySushiEthUsdcFactory,
    CompositeVaultBptEthUsdc,
    CompositeVaultBptEthUsdcFactory, MockSushiMasterChefFactory,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {Balancer} from '../../typechain/Balancer';
import {UniswapV2Pair, UniswapV2PairFactory} from "../../lib/uniswap/types";
import {IUniswapRouter} from "../../typechain/IUniswapRouter";
import {ILpPairConverter} from "../../typechain/ILpPairConverter";
import {coins} from "../shared/coin";

const verbose = process.env.VERBOSE;

const INIT_BALANCE = toWei('40');

describe('003_two_vaults.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let valueToken: TToken;
    let wethToken: TToken;
    let usdcToken: TToken;
    let sushiToken: TToken;
    let balToken: TToken;

    let uniUSDC_ETH: UniswapV2Pair;
    let slpUSDC_ETH: UniswapV2Pair;
    let bptUSDC_ETH: UniswapV2Pair;

    let uniswapRouter: IUniswapRouter;
    let sushiswapRouter: IUniswapRouter;
    let balswapRouter: IUniswapRouter;

    let sushiswapLpPairConverter: SushiswapLpPairConverter;
    let balancerLpPairConverter: ILpPairConverter;

    let sushiMasterChef: MockSushiMasterChef;

    let vmaster: CompositeVaultMaster;
    let bank: CompositeVaultBank;
    let vaultSlp: CompositeVaultSlpEthUsdc;
    let vaultBpt: CompositeVaultBptEthUsdc;
    let controllerSlp: CompositeVaultController;
    let controllerBpt: CompositeVaultController;
    let strategySushiEthUsdc: StrategySushiEthUsdc;
    let strategyBalancerEthUsdc: StrategyBalancerEthUsdc;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];

        await deployments.fixture(['vault_slp', 'vault_balancer']);

        valueToken = await ethers.getContract(coins.VALUE.symbol) as TToken;
        wethToken = await ethers.getContract(coins.WETH.symbol) as TToken;
        usdcToken = await ethers.getContract(coins.USDC.symbol) as TToken;
        sushiToken = await ethers.getContract(coins.SUSHI.symbol) as TToken;
        balToken = await ethers.getContract(coins.BAL.symbol) as TToken;

        const uniFactory = await ethers.getContract('UniswapFactory');
        uniUSDC_ETH = await UniswapV2PairFactory.connect(await uniFactory.getPair(usdcToken.address, wethToken.address), deployer);
        const sushiFactory = await ethers.getContract('SushiswapFactory');
        slpUSDC_ETH = await UniswapV2PairFactory.connect(await sushiFactory.getPair(usdcToken.address, wethToken.address), deployer);
        bptUSDC_ETH = await ethers.getContract('bptUSDC_ETH') as UniswapV2Pair;

        uniswapRouter = await ethers.getContract('UniswapRouter') as IUniswapRouter;
        sushiswapRouter = await ethers.getContract('SushiswapRouter') as IUniswapRouter;

        sushiMasterChef = await ethers.getContract('MockSushiMasterChef') as MockSushiMasterChef;

        vmaster = await ethers.getContract('CompositeVaultMaster') as CompositeVaultMaster;
        bank = await ethers.getContract('CompositeVaultBank') as CompositeVaultBank;

        vaultSlp = await ethers.getContract('CompositeVaultSlpEthUsdc') as CompositeVaultSlpEthUsdc;
        vaultBpt = await ethers.getContract('CompositeVaultBalancerEthUsdc') as CompositeVaultBptEthUsdc;

        controllerSlp = await ethers.getContract('CompositeVaultController') as CompositeVaultController;
        controllerBpt = await ethers.getContract('CompositeVaultControllerBalancerEthUsdc') as CompositeVaultController;

        sushiswapLpPairConverter = await ethers.getContract('SushiswapLpPairConverter') as SushiswapLpPairConverter;
        strategySushiEthUsdc = await ethers.getContract('StrategySushiEthUsdc') as StrategySushiEthUsdc;

        balancerLpPairConverter = await ethers.getContract('SushiswapLpPairConverterBalancerEthUsdc') as ILpPairConverter;
        strategyBalancerEthUsdc = await ethers.getContract('StrategyBalancerEthUsdc') as StrategyBalancerEthUsdc;

        // config bank
        await bank.addPool(vaultSlp.address, valueToken.address, 1, 1000, toWei(1), 10);
        await bank.addPool(vaultBpt.address, valueToken.address, 1, 1000, toWei(1), 10);


        // prepare balances
        await uniUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await bptUSDC_ETH.transfer(bob.address, INIT_BALANCE);

        // approve
        await uniUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await slpUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await bptUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await vaultSlp.connect(bob).approve(bank.address, maxUint256);
        await vaultBpt.connect(bob).approve(bank.address, maxUint256);

        await usdcToken.transfer(sushiswapLpPairConverter.address, toWei('300'));
        await wethToken.transfer(sushiswapLpPairConverter.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(sushiswapLpPairConverter.address, INIT_BALANCE);
        await bptUSDC_ETH.transfer(sushiswapLpPairConverter.address, toWei('20'));

        await usdcToken.transfer(balancerLpPairConverter.address, toWei('300'));
        await wethToken.transfer(balancerLpPairConverter.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(balancerLpPairConverter.address, INIT_BALANCE);
        await bptUSDC_ETH.transfer(balancerLpPairConverter.address, toWei('20'));
    })

    const getSlpBptBalance = async (address: string) => {
        return {
            slp : fromWei(await slpUSDC_ETH.balanceOf(address)),
            bpt : fromWei(await bptUSDC_ETH.balanceOf(address)),
        }
    };

    describe('calc_token_amount_deposit', () => {
        it('vaultBpt slpUSDC_ETH calc_token_amount_deposit', async () => {
            expect(await vaultBpt.calc_token_amount_deposit(slpUSDC_ETH.address,toWei('1'))).is.eq(toWei('4612.655994017694917706'))
        });
        it('vaultBpt uniUSDC_ETH calc_token_amount_deposit', async () => {
            expect(await vaultBpt.calc_token_amount_deposit(uniUSDC_ETH.address,toWei('1'))).is.eq(toWei('4612.655994017694917706'))
        });

        it('vaultSlp bptUSDC_ETH calc_token_amount_deposit', async () => {
            expect(await vaultSlp.calc_token_amount_deposit(bptUSDC_ETH.address,toWei('1'))).is.eq(toWei('0.000216794833886787'))
        });
        it('vaultSlp uniUSDC_ETH calc_token_amount_deposit', async () => {
            expect(await vaultSlp.calc_token_amount_deposit(uniUSDC_ETH.address,toWei('1'))).is.eq(toWei('0.999999999999963125'))
        });
    });

    describe('2 vaults should work', () => {
        it('bob deposit 20 BPT to both vaults: start farming SUSHI and BAL', async () => {
            await bank.connect(bob).depositMultiVault([vaultSlp.address, vaultBpt.address], bptUSDC_ETH.address, [toWei('10'), toWei('10')], [1, 1], true, 0);
            if (verbose) {
                console.log('vaultSlp totalSupply()     = ', fromWei(await vaultSlp.totalSupply()));
                console.log('vaultSlp balance()         = ', fromWei(await vaultSlp.balance()));
                console.log('vaultSlp SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vaultSlp.address)));
                console.log('controllerSlp balanceOf    = ', fromWei(await controllerSlp.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf()    = ', fromWei(await strategySushiEthUsdc.balanceOf()));
                console.log('vaultSlp.getPricePerFullShare()     = ', fromWei(await vaultSlp.getPricePerFullShare()));
                console.log('-----------------------------');
                console.log('vaultBpt totalSupply()     = ', fromWei(await vaultBpt.totalSupply()));
                console.log('vaultBpt balance()         = ', fromWei(await vaultBpt.balance()));
                console.log('vaultBpt BPT               = ', fromWei(await bptUSDC_ETH.balanceOf(vaultBpt.address)));
                console.log('controllerBpt balanceOf    = ', fromWei(await controllerBpt.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vaultBpt.getPricePerFullShare()     = ', fromWei(await vaultBpt.getPricePerFullShare()));
            }
        });


        it('withdraw in case of vault slp exchange token - SLP -> BPT)', async () => {
            await bank.connect(bob).deposit(vaultSlp.address, slpUSDC_ETH.address, toWei('10'), 1, false, 0);

            let {slp: beforeSlp, bpt: beforeBpt} = await getSlpBptBalance(bob.address);

            await bank.connect(bob).withdraw(vaultSlp.address, toWei('10'), bptUSDC_ETH.address, 1, 0);

            let {slp: afterSlp, bpt: afterBpt} = await getSlpBptBalance(bob.address);

            expect(beforeSlp).is.eq(afterSlp);
            expect(Number(afterBpt)).is.gt(Number(beforeBpt));
        });

        it('withdraw in case of vault slp exchange token - SLP <- BPT)', async () => {
            await bank.connect(bob).deposit(vaultSlp.address, bptUSDC_ETH.address, toWei('10'), 1, false, 0);

            let {slp: beforeSlp, bpt: beforeBpt} = await getSlpBptBalance(bob.address);

            await bank.connect(bob).withdraw(vaultSlp.address, toWei('0.002'), slpUSDC_ETH.address, 1, 0);

            let {slp: afterSlp, bpt: afterBpt} = await getSlpBptBalance(bob.address);

            expect(afterBpt).is.eq(beforeBpt);
            expect(Number(afterSlp)).is.gt(Number(beforeSlp));
        });

        it('withdraw in case of vault bpt exchange token - SLP <- BPT)', async () => {
            await bank.connect(bob).deposit(vaultBpt.address, bptUSDC_ETH.address, toWei('10'), 1, false, 0);

            let {slp: beforeSlp, bpt: beforeBpt} = await getSlpBptBalance(bob.address);

            await bank.connect(bob).withdraw(vaultBpt.address, toWei('10'), slpUSDC_ETH.address, 1, 0);

            let {slp: afterSlp, bpt: afterBpt} = await getSlpBptBalance(bob.address);

            expect(afterBpt).is.eq(beforeBpt);
            expect(Number(afterSlp)).is.gt(Number(beforeSlp));
        });

        it('withdraw in case of vault bpt exchange token - SLP -> BPT)', async () => {
            await bank.connect(bob).deposit(vaultBpt.address, slpUSDC_ETH.address, toWei('10'), 1, false, 0);

            let {slp: beforeSlp, bpt: beforeBpt} = await getSlpBptBalance(bob.address);

            await bank.connect(bob).withdraw(vaultBpt.address, toWei('1000'), bptUSDC_ETH.address, 1, 0);

            let {slp: afterSlp, bpt: afterBpt} = await getSlpBptBalance(bob.address);

            expect(afterSlp).is.eq(beforeSlp);
            expect(Number(afterBpt)).is.gt(Number(beforeBpt));
        });

    });
});
