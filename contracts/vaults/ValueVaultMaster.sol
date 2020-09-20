// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/*

Here we have a list of constants. In order to get access to an address
managed by ValueVaultMaster, the calling contract should copy and define
some of these constants and use them as keys.

Keys themselves are immutable. Addresses can be immutable or mutable.

a) Vault addresses are immutable once set, and the list may grow:

K_VAULT_WETH = 0;
K_VAULT_USDT_ETH_SUSHI_LP = 1;
K_VAULT_SOETH_ETH_UNI_V2_LP = 2;
K_VAULT_SODA_ETH_UNI_V2_LP = 3;
K_VAULT_GT = 4;
K_VAULT_GT_ETH_UNI_V2_LP = 5;


b) ValueMade token addresses are immutable once set, and the list may grow:

K_MADE_SOETH = 0;


c) Strategy addresses are mutable:

K_STRATEGY_CREATE_SODA = 0;
K_STRATEGY_EAT_SUSHI = 1;
K_STRATEGY_SHARE_REVENUE = 2;


d) Calculator addresses are mutable:

K_CALCULATOR_WETH = 0;

Solidity doesn't allow me to define global constants, so please
always make sure the key name and key value are copied as the same
in different contracts.
*/


/*
 * ValueVaultMaster manages all the vaults and strategies of our Value Vaults system.
 */
contract ValueVaultMaster {
    address public governance;

    address public bank;
    address public revenue;
    address public dev;

    address public govToken; // VALUE
    address public wETH;
    address public usdt; // we only used USDT to estimate APY

    address public govVaultProfitSharer;
    address public insuranceFund = 0xb7b2Ea8A1198368f950834875047aA7294A2bDAa; // set to Governance Multisig at start
    address public performanceReward = 0x7Be4D5A99c903C437EC77A20CB6d0688cBB73c7f; // set to deploy wallet at start

    uint256 public govVaultProfitShareFee = 670; // 6.7% | VIP-1 (https://yfv.finance/vip-vote/vip_1)
    uint256 public insuranceFee = 100; // 1%
    uint256 public performanceFee = 200; // 2%
    uint256 public burnFee = 0; // 0%
    uint256 public gasFee = 30; // 0.3%

    address public uniswapV2Factory;

    mapping(address => bool) public isVault;
    mapping(uint256 => address) public vaultByKey;

    mapping(address => bool) public isValueMade;
    mapping(uint256 => address) public valueMadeByKey;

    mapping(address => bool) public isStrategy;
    mapping(uint256 => address) public strategyByKey;

    mapping(address => bool) public isCalculator;
    mapping(uint256 => address) public calculatorByKey;

    constructor(
        address _govToken,
        address _wETH,
        address _usdt
    ) public {
        govToken = _govToken;
        wETH = _wETH;
        usdt = _usdt;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    // Immutable once set.
    function setBank(address _bank) external {
        require(msg.sender == governance, "!governance");
        require(bank == address(0));
        bank = _bank;
    }

    // Mutable in case we want to upgrade this module.  
    function setRevenue(address _revenue) external {
        require(msg.sender == governance, "!governance");
        revenue = _revenue;
    }

    // Mutable, in case governance want to upgrade VALUE to new version
    function setGovToken(address _govToken) external {
        require(msg.sender == governance, "!governance");
        govToken = _govToken;
    }

    // Mutable, in case Uniswap has changed or we want to switch to sushi.
    // The core systems (ie. ValueBank), don't rely on Uniswap, so there is no risk.
    function setUniswapV2Factory(address _uniswapV2Factory) external {
        require(msg.sender == governance, "!governance");
        uniswapV2Factory = _uniswapV2Factory;
    }

    // Immutable once added, and you can always add more.
    function addVault(uint256 _key, address _vault) external {
        require(msg.sender == governance, "!governance");
        require(vaultByKey[_key] == address(0), "vault: key is taken");

        isVault[_vault] = true;
        vaultByKey[_key] = _vault;
    }

    // Immutable once added, and you can always add more.
    function addValueMade(uint256 _key, address _valueMade) external {
        require(msg.sender == governance, "!governance");
        require(valueMadeByKey[_key] == address(0), "valueMade: key is taken");

        isValueMade[_valueMade] = true;
        valueMadeByKey[_key] = _valueMade;
    }

    // Mutable and removable.
    function addStrategy(uint256 _key, address _strategy) external {
        require(msg.sender == governance, "!governance");
        isStrategy[_strategy] = true;
        strategyByKey[_key] = _strategy;
    }

    function removeStrategy(uint256 _key) external {
        require(msg.sender == governance, "!governance");
        isStrategy[strategyByKey[_key]] = false;
        delete strategyByKey[_key];
    }

    function setGovVaultProfitSharer(address _govVaultProfitSharer) public {
        require(msg.sender == governance, "!governance");
        govVaultProfitSharer = _govVaultProfitSharer;
    }

    function setInsuranceFund(address _insuranceFund) public {
        require(msg.sender == governance, "!governance");
        insuranceFund = _insuranceFund;
    }

    function setPerformanceReward(address _performanceReward) public{
        require(msg.sender == governance, "!governance");
        performanceReward = _performanceReward;
    }

    function setGovVaultProfitShareFee(uint256 _govVaultProfitShareFee) public {
        require(msg.sender == governance, "!governance");
        govVaultProfitShareFee = _govVaultProfitShareFee;
    }

    function setPerformanceFee(uint256 _performanceFee) public {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    function setInsuranceFee(uint256 _insuranceFee) public {
        require(msg.sender == governance, "!governance");
        insuranceFee = _insuranceFee;
    }

    function setBurnFee(uint256 _burnFee) public {
        require(msg.sender == governance, "!governance");
        burnFee = _burnFee;
    }

    function setGasFee(uint256 _gasFee) public {
        require(msg.sender == governance, "!governance");
        gasFee = _gasFee;
    }
}
