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
    StrategyBalancerEthUsdc, StrategyBalancerEthUsdcFactory,
    MockLpPairConverter, MockLpPairConverterFactory, SushiswapLpPairConverter, StrategySushiEthUsdc,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {Balancer} from '../../typechain/Balancer';
import {coins} from "../shared/coin";
import {UniswapV2Pair, UniswapV2PairFactory} from "../../lib/uniswap/types";
import {IUniswapRouter} from "../../typechain/IUniswapRouter";
import {ILpPairConverter} from "../../typechain/ILpPairConverter";

const verbose = process.env.VERBOSE;

const INIT_BALANCE = toWei('1000');

describe('001_vault.strategy_bpt.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let valueToken: TToken;
    let wethToken: TToken;
    let usdcToken: TToken;
    let balToken: TToken;

    let uniUSDC_ETH: UniswapV2Pair;
    let slpUSDC_ETH: UniswapV2Pair;
    let bptUSDC_ETH: UniswapV2Pair;

    let uniswapRouter: IUniswapRouter;
    let balswapRouter: IUniswapRouter;
    let balancerLpPairConverter: ILpPairConverter;

    let vmaster: CompositeVaultMaster;
    let bank: CompositeVaultBank;
    let vault: CompositeVaultSlpEthUsdc;
    let controller: CompositeVaultController;
    let strategyBalancerEthUsdc: StrategyBalancerEthUsdc;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];

        await deployments.fixture(['vault_balancer']);

        valueToken = await ethers.getContract(coins.VALUE.symbol) as TToken;
        wethToken = await ethers.getContract(coins.WETH.symbol) as TToken;
        usdcToken = await ethers.getContract(coins.USDC.symbol) as TToken;
        balToken = await ethers.getContract(coins.BAL.symbol) as TToken;

        const uniFactory = await ethers.getContract('UniswapFactory');
        uniUSDC_ETH = await UniswapV2PairFactory.connect( await uniFactory.getPair(usdcToken.address, wethToken.address),deployer);
        const sushiFactory = await ethers.getContract('SushiswapFactory');
        slpUSDC_ETH = await UniswapV2PairFactory.connect(await sushiFactory.getPair(usdcToken.address, wethToken.address),deployer);
        bptUSDC_ETH = await ethers.getContract('bptUSDC_ETH') as UniswapV2Pair;

        uniswapRouter = await ethers.getContract('UniswapRouter') as IUniswapRouter;

        vmaster = await ethers.getContract('CompositeVaultMaster') as CompositeVaultMaster;
        bank = await ethers.getContract('CompositeVaultBank') as CompositeVaultBank;

        vault = await ethers.getContract('CompositeVaultBalancerEthUsdc') as CompositeVaultSlpEthUsdc;
        controller = await ethers.getContract('CompositeVaultControllerBalancerEthUsdc') as CompositeVaultController;

        balancerLpPairConverter = await ethers.getContract('SushiswapLpPairConverterBalancerEthUsdc') as ILpPairConverter;
        strategyBalancerEthUsdc = await ethers.getContract('StrategyBalancerEthUsdc') as StrategyBalancerEthUsdc;

        // config bank
        await bank.addPool(vault.address, valueToken.address, 1, 1000, toWei(1), 10);

        // prepare balances
        await uniUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await bptUSDC_ETH.transfer(bob.address, toWei(50));

        // approve
        await uniUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await slpUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await bptUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await vault.connect(bob).approve(bank.address, maxUint256);

        await usdcToken.transfer(balancerLpPairConverter.address, toWei(500));
        await wethToken.transfer(balancerLpPairConverter.address, INIT_BALANCE);
        await bptUSDC_ETH.transfer(balancerLpPairConverter.address, toWei(40));
    })

    describe('vault should work', () => {
        it('bob deposit 10 BPT: start farming bal', async () => {
            await bank.connect(bob).deposit(vault.address, bptUSDC_ETH.address, toWei('10'), 1, true, 0);
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
        });

        it('harvest by controller: should not appreciate the sharePrice (no BAL claim yet)', async () => {
            const _before = await vault.getPricePerFullShare();
            await controller.harvestStrategy(strategyBalancerEthUsdc.address);
            const _after = await vault.getPricePerFullShare();
            expect(_after).is.eq(_before);
        });

        it('harvest by bank: should appreciate the sharePrice (claim BAL first)', async () => {
            let _before = await vault.getPricePerFullShare();
            expect(_before).is.gt(toWei('0.999'));
            await balToken.mintTo(strategyBalancerEthUsdc.address, toWei('1'));
            await bank.harvestAllStrategies(vault.address, 0);
            if (verbose) {
                console.log('AFTER harvest ============');
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
                console.log('govVault VALUE          = ', fromWei(await valueToken.balanceOf(await vmaster.govVault())));
                console.log('performanceReward WETH  = ', fromWei(await wethToken.balanceOf(await vmaster.performanceReward())));
            }
            let _after1 = await vault.getPricePerFullShare();
            expect(_after1).is.gt(toWei('1.000'));
            expect(_after1).is.gt(_before);
            await mineBlocks(ethers, 10);
            if (verbose) {
                console.log('AFTER harvest 10 blocks ============');
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
            let _after2 = await vault.getPricePerFullShare();
            expect(_after2).is.gt(toWei('1.000'));
            expect(_after2).is.gt(_after1);
        });

        it('bob exit: clear all balance', async () => {
            if (verbose) {
                console.log('BEFORE exit ============');
                console.log('bob SLP                 = ', fromWei(await bptUSDC_ETH.balanceOf(bob.address)));
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
            await bank.connect(bob).exit(vault.address, bptUSDC_ETH.address, 1, 0);
            if (verbose) {
                console.log('AFTER exit ============');
                console.log('bob SLP                 = ', fromWei(await bptUSDC_ETH.balanceOf(bob.address)));
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
        });

        it('bob deposit 10 SLP: convert to BPT and start farming bal', async () => {
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, true, 0);
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await bptUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategyBalancerEthUsdc balanceOf() = ', fromWei(await strategyBalancerEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
        });
    });
});
