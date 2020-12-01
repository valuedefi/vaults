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
    TToken, TTokenFactory,
    SushiswapLpPairConverter, SushiswapLpPairConverterFactory,
    CompositeVaultMaster, CompositeVaultMasterFactory,
    CompositeVaultBank, CompositeVaultBankFactory,
    CompositeVaultSlpEthUsdc, CompositeVaultSlpEthUsdcFactory,
    CompositeVaultController, CompositeVaultControllerFactory,
    StrategySushiEthUsdc, StrategySushiEthUsdcFactory,
    MockUniswapRouter, MockUniswapRouterFactory,
    MockUniswapV2Pair, MockUniswapV2PairFactory,
    AttackingContract, AttackingContractFactory,
    MockSushiMasterChef, MockSushiMasterChefFactory,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {coins} from "../shared/coin";
import {UniswapV2Pair, UniswapV2PairFactory} from "../../lib/uniswap/types";
import {IUniswapRouter} from "../../typechain/IUniswapRouter";
import {SushiMasterChef} from "../../typechain/SushiMasterChef";

const verbose = process.env.VERBOSE;

const INIT_BALANCE = toWei('1000');

describe('001_vault.strategy_slp.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let valueToken: TToken;
    let wethToken: TToken;
    let usdcToken: TToken;
    let sushiToken: TToken;

    let uniUSDC_ETH: UniswapV2Pair;
    let slpUSDC_ETH: UniswapV2Pair;

    let uniswapRouter: IUniswapRouter;
    let sushiswapRouter: IUniswapRouter;
    let sushiswapLpPairConverter: SushiswapLpPairConverter;

    let sushiMasterChef: MockSushiMasterChef;

    let vmaster: CompositeVaultMaster;
    let bank: CompositeVaultBank;
    let vault: CompositeVaultSlpEthUsdc;
    let controller: CompositeVaultController;
    let strategySushiEthUsdc: StrategySushiEthUsdc;

    let attackContract: AttackingContract;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];

        await deployments.fixture(['vault_slp']);

        valueToken = await ethers.getContract(coins.VALUE.symbol) as TToken;
        wethToken = await ethers.getContract(coins.WETH.symbol) as TToken;
        usdcToken = await ethers.getContract(coins.USDC.symbol) as TToken;
        sushiToken = await ethers.getContract(coins.SUSHI.symbol) as TToken;

        const uniFactory = await ethers.getContract('UniswapFactory');
        uniUSDC_ETH = await UniswapV2PairFactory.connect( await uniFactory.getPair(usdcToken.address, wethToken.address),deployer);
        const sushiFactory = await ethers.getContract('SushiswapFactory');
        slpUSDC_ETH = await UniswapV2PairFactory.connect(await sushiFactory.getPair(usdcToken.address, wethToken.address),deployer);

        uniswapRouter = await ethers.getContract('UniswapRouter') as IUniswapRouter;
        sushiswapRouter = await ethers.getContract('SushiswapRouter') as IUniswapRouter;

        sushiMasterChef = await ethers.getContract('MockSushiMasterChef') as MockSushiMasterChef;

        vmaster = await ethers.getContract('CompositeVaultMaster') as CompositeVaultMaster;
        bank = await ethers.getContract('CompositeVaultBank') as CompositeVaultBank;

        vault = await ethers.getContract('CompositeVaultSlpEthUsdc') as CompositeVaultSlpEthUsdc;
        controller = await ethers.getContract('CompositeVaultController') as CompositeVaultController;

        sushiswapLpPairConverter = await ethers.getContract('SushiswapLpPairConverter') as SushiswapLpPairConverter;
        strategySushiEthUsdc = await ethers.getContract('StrategySushiEthUsdc') as StrategySushiEthUsdc;

        attackContract = await new AttackingContractFactory(deployer).deploy();

        // config bank
        await bank.addPool(vault.address, valueToken.address, 1, 1000, toWei(1), 10);

        // prepare balances
        await slpUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await uniUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(attackContract.address, INIT_BALANCE);
        await uniUSDC_ETH.transfer(attackContract.address, INIT_BALANCE);

        // approve
        await slpUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await uniUSDC_ETH.connect(bob).approve(bank.address, maxUint256);
        await vault.connect(bob).approve(bank.address, maxUint256);

        // prepare balance for unirouter and mock converter & farms
        await sushiToken.transfer(sushiMasterChef.address, INIT_BALANCE);
    })

    describe('vault should work', () => {
        it('constructor parameters should be correct', async () => {
            const vaultMaster = await vault.getVaultMaster();
            expect(vaultMaster).is.eq(vmaster.address);

            const token = await vault.token();
            expect(token).is.eq(slpUSDC_ETH.address);
        });

        it('cap()', async () => {
            const cap = await vault.cap();
            expect(cap).is.eq(toWei('0'));
        });

        it('not allow contract', async () => {
            await expect(attackContract.connect(bob).depositFor(vault.address, attackContract.address, attackContract.address, slpUSDC_ETH.address, toWei('10'), 1)).to.be.revertedWith('contract not support');
            await expect(attackContract.connect(bob).addLiquidityFor(vault.address, attackContract.address, attackContract.address, toWei('10'), toWei('10'), 1)).to.be.revertedWith('contract not support');
        });

        it('allow contract', async () => {
            await vault.setAcceptContractDepositor(true);
            await bank.setAcceptContractDepositor(true);
            await expect(attackContract.connect(bob).depositFor(vault.address, attackContract.address, attackContract.address, slpUSDC_ETH.address, toWei('10'), 1)).to.be.revertedWith('SafeERC20: low-level call failed');
            await expect(attackContract.connect(bob).addLiquidityFor(vault.address, attackContract.address, attackContract.address, toWei('10'), toWei('10'), 1)).to.be.revertedWith('SafeERC20: low-level call failed');
        });

        it('bob deposit 10 SLP: start farming sushi', async () => {
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, true, 0);
            if (verbose) {
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf() = ', fromWei(await strategySushiEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
        });

        it('harvest by bank: should appreciate the sharePrice', async () => {
            let _before = await vault.getPricePerFullShare();
            expect(_before).is.gt(toWei('0.999'));
            await bank.harvestAllStrategies(vault.address, 0);
            if (verbose) {
                console.log('AFTER harvest ============');
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf() = ', fromWei(await strategySushiEthUsdc.balanceOf()));
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
                console.log('vault SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf() = ', fromWei(await strategySushiEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
            let _after2 = await vault.getPricePerFullShare();
            expect(_after2).is.gt(toWei('1.000'));
            expect(_after2).is.gt(_after1);
        });

        it('harvest by controller: should appreciate the sharePrice', async () => {
            const _before = await vault.getPricePerFullShare();
            await controller.harvestStrategy(strategySushiEthUsdc.address);
            const _after = await vault.getPricePerFullShare();
            expect(_after).is.gt(_before);
            expect(_after.sub(_before)).is.gt(toWei('0.007'));
        });

        it('bob exit: clear all balance', async () => {
            if (verbose) {
                console.log('BEFORE exit ============');
                console.log('bob SLP                 = ', fromWei(await slpUSDC_ETH.balanceOf(bob.address)));
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf() = ', fromWei(await strategySushiEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
            await bank.connect(bob).exit(vault.address, slpUSDC_ETH.address, 1, 0);
            if (verbose) {
                console.log('AFTER exit ============');
                console.log('bob SLP                 = ', fromWei(await slpUSDC_ETH.balanceOf(bob.address)));
                console.log('vault totalSupply()     = ', fromWei(await vault.totalSupply()));
                console.log('vault balance()         = ', fromWei(await vault.balance()));
                console.log('vault SLP               = ', fromWei(await slpUSDC_ETH.balanceOf(vault.address)));
                console.log('controller balanceOf    = ', fromWei(await controller.balanceOf()));
                console.log('strategySushiEthUsdc balanceOf() = ', fromWei(await strategySushiEthUsdc.balanceOf()));
                console.log('vault.getPricePerFullShare()     = ', fromWei(await vault.getPricePerFullShare()));
            }
        });
    });
});
