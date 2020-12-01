// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/IUniswapV2Router.sol";
import "../../interfaces/Balancer.sol";

import "../ILpPairConverter.sol";
import "../ICompositeVault.sol";
import "../IController.sol";
import "../IVaultMaster.sol";

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

abstract contract StrategyBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint;

    IUniswapV2Router public unirouter = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public valueLiquidEthValuePool = address(0xbd63d492bbb13d081D680CE1f2957a287FD8c57c);

    address public valueToken = address(0x49E833337ECe7aFE375e44F4E3e8481029218E5c);
    address public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public lpPair;
    address public token0;
    address public token1;

    address public farmingToken;

    uint public withdrawalFee = 0; // over 10000

    address public governance;
    address public timelock = address(0x105e62e4bDFA67BCA18400Cfbe2EAcD4D0Be080d);

    address public controller;
    address public strategist;

    address public converter;

    ICompositeVault public vault;
    IVaultMaster public vaultMaster;

    mapping(address => mapping(address => address[])) public uniswapPaths; // [input -> output] => uniswap_path
    mapping(address => mapping(address => address)) public vliquidPools; // [input -> output] => balancer_pool

    constructor(address _converter, address _farmingToken, address _weth, address _controller) public {
        ILpPairConverter _cvter = ILpPairConverter(_converter);
        lpPair = _cvter.lpPair();
        token0 = _cvter.token0();
        token1 = _cvter.token1();
        converter = _converter;
        farmingToken = _farmingToken;
        if (_weth != address(0)) weth = _weth;
        converter = _converter;
        controller = _controller;
        vault = ICompositeVault(IController(_controller).vault());
        require(address(vault) != address(0), "!vault");
        vaultMaster = IVaultMaster(vault.getVaultMaster());
        governance = msg.sender;
        strategist = msg.sender;

        IERC20(token0).safeApprove(address(unirouter), type(uint256).max);
        IERC20(token1).safeApprove(address(unirouter), type(uint256).max);
        if (farmingToken != token0 && farmingToken != token1) IERC20(farmingToken).safeApprove(address(unirouter), type(uint256).max);
        if (weth != token0 && weth != token1 && weth != farmingToken) IERC20(weth).safeApprove(address(unirouter), type(uint256).max);

        vliquidPools[weth][valueToken] = valueLiquidEthValuePool;
        IERC20(weth).safeApprove(address(valueLiquidEthValuePool), type(uint256).max);
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyStrategist() {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == address(controller) || msg.sender == strategist || msg.sender == governance, "!authorized");
        _;
    }

    function getName() public virtual pure returns (string memory);

    function approveForSpender(IERC20 _token, address _spender, uint _amount) external onlyGovernance {
        _token.safeApprove(_spender, _amount);
    }

    function setUnirouter(IUniswapV2Router _unirouter) external onlyGovernance {
        unirouter = _unirouter;
        IERC20(token0).safeApprove(address(unirouter), type(uint256).max);
        IERC20(token1).safeApprove(address(unirouter), type(uint256).max);
        if (farmingToken != token0 && farmingToken != token1) IERC20(farmingToken).safeApprove(address(unirouter), type(uint256).max);
        if (weth != token0 && weth != token1 && weth != farmingToken) IERC20(weth).safeApprove(address(unirouter), type(uint256).max);
    }

    function setUnirouterPath(address _input, address _output, address [] memory _path) public onlyStrategist {
        uniswapPaths[_input][_output] = _path;
    }

    function setBalancerPools(address _input, address _output, address _pool) public onlyStrategist {
        vliquidPools[_input][_output] = _pool;
        IERC20(_input).safeApprove(_pool, type(uint256).max);
    }

    function deposit() public virtual;

    function skim() external {
        IERC20(lpPair).safeTransfer(controller, IERC20(lpPair).balanceOf(address(this)));
    }

    function withdraw(IERC20 _asset) external onlyAuthorized returns (uint balance) {
        require(lpPair != address(_asset), "lpPair");

        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    function withdrawToController(uint _amount) external onlyAuthorized {
        require(controller != address(0), "!controller"); // additional protection so we don't burn the funds

        uint _balance = IERC20(lpPair).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        IERC20(lpPair).safeTransfer(controller, _amount);
    }

    function _withdrawSome(uint _amount) internal virtual returns (uint);

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external onlyAuthorized returns (uint) {
        uint _balance = IERC20(lpPair).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        IERC20(lpPair).safeTransfer(address(vault), _amount);
        return _amount;
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external onlyAuthorized returns (uint balance) {
        _withdrawAll();
        balance = IERC20(lpPair).balanceOf(address(this));
        IERC20(lpPair).safeTransfer(address(vault), balance);
    }

    function _withdrawAll() internal virtual;

    function claimReward() public virtual;

    function _swapTokens(address _input, address _output, uint256 _amount) internal {
        address _pool = vliquidPools[_input][_output];
        if (_pool != address(0)) { // use balancer/vliquid
            Balancer(_pool).swapExactAmountIn(_input, _amount, _output, 1, type(uint256).max);
        } else { // use Uniswap
            address[] memory path = uniswapPaths[_input][_output];
            if (path.length == 0) {
                // path: _input -> _output
                path = new address[](2);
                path[0] = _input;
                path[1] = _output;
            }
            unirouter.swapExactTokensForTokens(_amount, 1, path, address(this), now.add(1800));
        }
    }

    function _addLiquidity() internal {
        IERC20 _token0 = IERC20(token0);
        IERC20 _token1 = IERC20(token1);
        uint _amount0 = _token0.balanceOf(address(this));
        uint _amount1 = _token1.balanceOf(address(this));
        if (_amount0 > 0 && _amount1 > 0) {
            _token0.safeTransfer(converter, _amount0);
            _token1.safeTransfer(converter, _amount1);
            ILpPairConverter(converter).add_liquidity(address(this));
        }
    }

    function _buyWantAndReinvest() internal virtual;

    function harvest(address _mergedStrategy) external {
        require(msg.sender == controller || msg.sender == strategist || msg.sender == governance, "!authorized");
        claimReward();
        uint _farmingTokenBal = IERC20(farmingToken).balanceOf(address(this));
        if (_farmingTokenBal == 0) return;

        _swapTokens(farmingToken, weth, _farmingTokenBal);
        uint256 _wethBal = IERC20(weth).balanceOf(address(this));

        if (_wethBal > 0) {
            if (_mergedStrategy != address(0)) {
                require(vaultMaster.isStrategy(_mergedStrategy), "!strategy"); // additional protection so we don't burn the funds
                IERC20(weth).safeTransfer(_mergedStrategy, _wethBal); // forward WETH to one strategy and do the profit split all-in-one there (gas saving)
            } else {
                address _govVault = vaultMaster.govVault();
                address _insuranceFund = vaultMaster.insuranceFund(); // to pay back who lost due to flash-loan attack on Nov 14 2020
                address _performanceReward = vaultMaster.performanceReward();
                uint _govVaultProfitShareFee = vaultMaster.govVaultProfitShareFee();
                uint _insuranceFee = vaultMaster.insuranceFee();
                uint _gasFee = vaultMaster.gasFee();

                if (_govVaultProfitShareFee > 0 && _govVault != address(0)) {
                    address _valueToken = vaultMaster.valueToken();
                    uint _amount = _wethBal.mul(_govVaultProfitShareFee).div(10000);
                    _swapTokens(weth, _valueToken, _amount);
                    IERC20(_valueToken).safeTransfer(_govVault, IERC20(_valueToken).balanceOf(address(this)));
                }

                if (_insuranceFee > 0 && _insuranceFund != address(0)) {
                    uint256 _amount = _wethBal.mul(_insuranceFee).div(10000);
                    IERC20(weth).safeTransfer(_performanceReward, _amount);
                }

                if (_gasFee > 0 && _performanceReward != address(0)) {
                    uint256 _amount = _wethBal.mul(_gasFee).div(10000);
                    IERC20(weth).safeTransfer(_performanceReward, _amount);
                }

                _buyWantAndReinvest();
            }
        }
    }

    function balanceOfPool() public virtual view returns (uint);

    function balanceOf() public view returns (uint) {
        return IERC20(lpPair).balanceOf(address(this)).add(balanceOfPool());
    }

    function claimable_tokens() external virtual view returns (uint);

    function withdrawFee(uint _amount) external view returns (uint) {
        return _amount.mul(withdrawalFee).div(10000);
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function setTimelock(address _timelock) external {
        require(msg.sender == timelock, "!timelock");
        timelock = _timelock;
    }

    function setStrategist(address _strategist) external onlyGovernance {
        strategist = _strategist;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
        vault = ICompositeVault(IController(_controller).vault());
        require(address(vault) != address(0), "!vault");
        vaultMaster = IVaultMaster(vault.getVaultMaster());
    }

    function setConverter(address _converter) external {
        require(msg.sender == governance, "!governance");
        require(ILpPairConverter(_converter).lpPair() == lpPair, "!lpPair");
        require(ILpPairConverter(_converter).token0() == token0, "!token0");
        require(ILpPairConverter(_converter).token1() == token1, "!token1");
        converter = _converter;
    }

    function setWithdrawalFee(uint _withdrawalFee) external onlyGovernance {
        withdrawalFee = _withdrawalFee;
    }

    event ExecuteTransaction(address indexed target, uint value, string signature, bytes data);

    /**
     * @dev This is from Timelock contract.
     */
    function executeTransaction(address target, uint value, string memory signature, bytes memory data) public returns (bytes memory) {
        require(msg.sender == timelock, "!timelock");

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value : value}(callData);
        require(success, string(abi.encodePacked(getName(), "::executeTransaction: Transaction execution reverted.")));

        emit ExecuteTransaction(target, value, signature, data);

        return returnData;
    }
}
