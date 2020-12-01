import {ethers, deployments, getUnnamedAccounts, artifacts} from 'hardhat';
import {expect} from '../chai-setup';

import {
    fromWei,
    toWei,
    toWeiString,
    mineBlocks,
    mineBlockTimeStamp
} from '../shared/utilities';

import {
    TToken, TTokenFactory,
    SushiswapLpPairConverter, SushiswapLpPairConverterFactory,
    CompositeVaultMaster, CompositeVaultMasterFactory,
    CompositeVaultBank, CompositeVaultBankFactory,
    CompositeVaultSlpEthUsdc, CompositeVaultSlpEthUsdcFactory,
    CompositeVaultController, CompositeVaultControllerFactory,
    AttackingContract, AttackingContractFactory,
    MockUniswapRouter, MockUniswapRouterFactory,
    MockUniswapV2Pair, MockUniswapV2PairFactory,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';
import {coins} from "../shared/coin";
import {UniswapV2Pair, UniswapV2PairFactory} from "../../lib/uniswap/types";
import {IUniswapRouter} from "../../typechain/IUniswapRouter";

const verbose = process.env.VERBOSE;

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000';
const MAX = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const INIT_BALANCE = toWei('1000');

describe('000_bank.single_vault_no_controller.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;

    let valueToken: TToken;
    let wethToken: TToken;
    let usdcToken: TToken;

    let uniUSDC_ETH: UniswapV2Pair;
    let slpUSDC_ETH: UniswapV2Pair;

    let uniswapRouter: IUniswapRouter;
    let sushiswapRouter: IUniswapRouter;
    let sushiswapLpPairConverter: SushiswapLpPairConverter;

    let vmaster: CompositeVaultMaster;
    let bank: CompositeVaultBank;
    let vault: CompositeVaultSlpEthUsdc;
    let controller: CompositeVaultController;

    let attackContract: AttackingContract;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];

        await deployments.fixture(['vault_slp']);

        valueToken = await ethers.getContract(coins.VALUE.symbol) as TToken;
        wethToken = await ethers.getContract(coins.WETH.symbol) as TToken;
        usdcToken = await ethers.getContract(coins.USDC.symbol) as TToken;

        const uniFactory = await ethers.getContract('UniswapFactory');
        uniUSDC_ETH = await UniswapV2PairFactory.connect( await uniFactory.getPair(usdcToken.address, wethToken.address),deployer);
        const sushiFactory = await ethers.getContract('SushiswapFactory');
        slpUSDC_ETH = await UniswapV2PairFactory.connect(await sushiFactory.getPair(usdcToken.address, wethToken.address),deployer);

        uniswapRouter = await ethers.getContract('UniswapRouter') as IUniswapRouter;
        sushiswapRouter = await ethers.getContract('SushiswapRouter') as IUniswapRouter;

        vmaster = await ethers.getContract('CompositeVaultMaster') as CompositeVaultMaster;
        bank = await ethers.getContract('CompositeVaultBank') as CompositeVaultBank;

        vault = await ethers.getContract('CompositeVaultSlpEthUsdc') as CompositeVaultSlpEthUsdc;
        controller = await ethers.getContract('CompositeVaultController') as CompositeVaultController;

        sushiswapLpPairConverter = await ethers.getContract('SushiswapLpPairConverter') as SushiswapLpPairConverter;

        attackContract = await new AttackingContractFactory(deployer).deploy();

        // config bank
        await bank.addPool(vault.address, valueToken.address, 1, 1000, toWei(1), 10);

        // prepare balances
        await slpUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await uniUSDC_ETH.transfer(bob.address, INIT_BALANCE);
        await slpUSDC_ETH.transfer(attackContract.address, INIT_BALANCE);
        await uniUSDC_ETH.transfer(attackContract.address, INIT_BALANCE);

        // approve
        await slpUSDC_ETH.connect(bob).approve(bank.address, MAX);
        await uniUSDC_ETH.connect(bob).approve(bank.address, MAX);
        await vault.connect(bob).approve(bank.address, MAX);
    });

    describe('bank should work', () => {
        it('constructor parameters should be correct', async () => {
            const vaultMaster = await bank.vaultMaster();
            expect(vaultMaster).is.eq(vmaster.address);

            const mbank = await vmaster.bank(vault.address);
            expect(mbank).is.eq(bank.address);
        });

        it('cap()', async () => {
            const cap = await bank.cap(vault.address);
            expect(cap).is.eq(toWei('0'));
        });

        it('not allow contract', async () => {
            await expect(attackContract.deposit(bank.address, vault.address, slpUSDC_ETH.address, toWei('10'), 1, false)).to.be.revertedWith('contract not support');
            await expect(attackContract.addLiquidity(bank.address, vault.address, toWei('10'), toWei('10'), 1, false)).to.be.revertedWith('contract not support');
        });

        it('allow contract', async () => {
            await vault.setAcceptContractDepositor(true);
            await bank.setAcceptContractDepositor(true);
            await attackContract.deposit(bank.address, vault.address, slpUSDC_ETH.address, toWei('10'), 1, false);

            await wethToken.transfer(attackContract.address, toWei('10'));
            await usdcToken.transfer(attackContract.address, toWei('10'));

            await attackContract.addLiquidity(bank.address, vault.address, toWei('10'), toWei('10'), 1, false);
        });

        it('deposit 10 SLP - no stake', async () => {
            let _before = await vault.balanceOf(bob.address);
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, false, 0);
            let _after = await vault.balanceOf(bob.address);
            expect(_after.sub(_before)).to.eq(toWei('10'));
            const userInfo = await bank.userInfo(vault.address, bob.address);
            expect(userInfo[0]).to.eq(0);
        });

        it('deposit 10 SLP - stake', async () => {
            let _before = await vault.balanceOf(bob.address);
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, true, 0);
            let _after = await vault.balanceOf(bob.address);
            expect(_after.sub(_before)).to.eq(toWei('0'));
        });

        it('unstake 10 SLP', async () => {
            const userInfo = await bank.userInfo(vault.address, bob.address);
            const rewardPool = await bank.rewardPoolInfo(vault.address);
            if (verbose) {
                console.log('userInfo = %s', JSON.stringify(userInfo));
                console.log('rewardPool = %s', JSON.stringify(rewardPool));
            }
            expect(userInfo[0]).to.eq(toWei(10));
            await mineBlocks(ethers, 1);
            if (verbose) console.log('pendingReward = %s', fromWei(await bank.pendingReward(vault.address, bob.address)));
            await expect(bank.connect(bob).claimReward(vault.address, 0)).to.be.revertedWith('locked rewards');
            await expect(
                () => bank.connect(bob).unstake(vault.address, toWei('10'), 0)
            ).to.changeTokenBalance(valueToken, bob, toWeiString('0'));
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, true, 0);
            await mineBlocks(ethers, 10);
            expect(String(await bank.pendingReward(vault.address, bob.address))).to.eq(toWei('10'));
            await expect(
                () => bank.connect(bob).unstake(vault.address, toWei('10'), 0)
            ).to.changeTokenBalance(valueToken, bob, toWeiString('11'));
            expect(String(await bank.pendingReward(vault.address, bob.address))).to.eq(toWei('0'));
        });

        it('withdraw', async () => {
            await bank.connect(bob).deposit(vault.address, slpUSDC_ETH.address, toWei('10'), 1, true, 0);
            await bank.connect(bob).stakeVaultShares(vault.address, toWei('10'), 0);
            expect(String(await bank.shares_owner(vault.address, bob.address))).to.eq(toWei('40'));
            await vault.connect(bob).transfer(deployer.address, String(await vault.balanceOf(bob.address))); // send away all shares bob has
            let _beforeValue = await valueToken.balanceOf(bob.address);
            await bank.connect(bob).withdraw(vault.address, toWei('15'), slpUSDC_ETH.address, 1, 0);
            let _afterValue = await valueToken.balanceOf(bob.address);
            await expect(_afterValue.sub(_beforeValue)).is.eq(toWei('0'));
            expect(String(await bank.pendingReward(vault.address, bob.address))).to.eq(toWei('0'));
        });

        it('exit', async () => {
            let _beforeValue = await valueToken.balanceOf(bob.address);
            await mineBlocks(ethers, 10);
            await expect(
                () => bank.connect(bob).exit(vault.address, slpUSDC_ETH.address, 1, 0)
            ).to.changeTokenBalance(slpUSDC_ETH, bob, toWeiString('5'));
            let _afterValue = await valueToken.balanceOf(bob.address);
            await expect(_afterValue.sub(_beforeValue)).is.eq(toWei('11'));
        });
    });
});
