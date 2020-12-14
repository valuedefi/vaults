pragma solidity 0.5.17;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint256);
    function name() external view returns (string memory);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function burn(uint amount) external;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {codehash := extcodehash(account)}
        return (codehash != 0x0 && codehash != accountHash);
    }

    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success,) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {// Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IController {
    function vaults(address) external view returns (address);
    function yfvInsuranceFund() external view returns (address);
    function performanceReward() external view returns (address);
}

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint256) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/

interface IStandardFarmingPool {
    function withdraw(uint256) external;
    function getReward() external;
    function stake(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function exit() external;
    function earned(address) external view returns (uint256);
}

interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
    external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}


interface IVault {
    function make_profit(uint256 amount) external;
}

contract YFVStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public pool;
    address public output;
    string public getName;

    address constant public yfv = address(0x45f24BaEef268BB6d63AEe5129015d69702BCDfa);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 public performanceFee = 250; // 2.5%
    uint256 public insuranceFee = 100; // 1%
    uint256 public burnFee = 0; // 0%
    uint256 public gasFee = 100; // 1%
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public governance;
    address public controller;

    address public want;

    address[] public swapRouting;

    constructor(address _controller, address _output, address _pool, address _want) public {
        require(_controller != address(0), "!_controller");
        require(_output != address(0), "!_output");
        require(_pool != address(0), "!_pool");
        require(_want != address(0), "!_want");
        governance = tx.origin;
        controller = _controller;
        output = _output;
        pool = _pool;
        want = _want;
        getName = string(
            abi.encodePacked("yfv:Strategy:",
            abi.encodePacked(IERC20(want).name(),
            abi.encodePacked(":", IERC20(output).name())
            )
            ));
        init();
        // output -> weth -> yfv
        swapRouting = [output, weth, yfv];
    }

    function deposit() external {
        IERC20(want).safeApprove(pool, 0);
        IERC20(want).safeApprove(pool, IERC20(want).balanceOf(address(this)));
        IStandardFarmingPool(pool).stake(IERC20(want).balanceOf(address(this)));
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        IERC20(want).safeTransfer(_vault, _amount);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() public returns (uint256 balance) {
        require(msg.sender == controller || msg.sender == governance, "!controller");
        _withdrawAll();
        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);

    }

    function _withdrawAll() internal {
        IStandardFarmingPool(pool).exit();
    }

    function init() public {
        IERC20(output).safeApprove(unirouter, uint256(- 1));
    }

    // to switch to another pool
    function setNewPool(address _output, address _pool) public {
        require(msg.sender == governance, "!governance");
        require(_output != address(0), "!_output");
        require(_pool != address(0), "!_pool");
        harvest();
        withdrawAll();
        output = _output;
        pool = _pool;
        getName = string(
            abi.encodePacked("yfv:Strategy:",
            abi.encodePacked(IERC20(want).name(),
            abi.encodePacked(":", IERC20(output).name())
            )
            ));
    }

    function harvest() public {
        require(!Address.isContract(msg.sender), "!contract");
        IStandardFarmingPool(pool).getReward();
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        swap2yfv();

        uint256 b = IERC20(yfv).balanceOf(address(this));
        if (performanceFee > 0) {
            uint256 _performanceFee = b.mul(performanceFee).div(FEE_DENOMINATOR);
            IERC20(yfv).safeTransfer(IController(controller).performanceReward(), _performanceFee);
        }
        if (insuranceFee > 0) {
            uint256 _insuranceFee = b.mul(insuranceFee).div(FEE_DENOMINATOR);
            IERC20(yfv).safeTransfer(IController(controller).yfvInsuranceFund(), _insuranceFee);
        }
        if (burnFee > 0) {
            uint256 _burnFee = b.mul(burnFee).div(FEE_DENOMINATOR);
            IERC20(yfv).burn(_burnFee);
        }
        if (gasFee > 0) {
            uint256 _gasFee = b.mul(gasFee).div(FEE_DENOMINATOR);
            IERC20(yfv).safeTransfer(msg.sender, _gasFee);
        }

        IERC20(yfv).safeApprove(_vault, 0);
        IERC20(yfv).safeApprove(_vault, IERC20(yfv).balanceOf(address(this)));
        IVault(_vault).make_profit(IERC20(yfv).balanceOf(address(this)));
    }

    function swap2yfv() internal {
        // path: output -> eth -> yfv
        // swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline)
        IUniswapRouter(unirouter).swapExactTokensForTokens(IERC20(output).balanceOf(address(this)), 1, swapRouting, address(this), now.add(1800));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        IStandardFarmingPool(pool).withdraw(_amount);
        return _amount;
    }

    function balanceOf() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this)).add(IStandardFarmingPool(pool).balanceOf(address(this)));
    }

    function balanceOfPendingReward() public view returns (uint256){
        return IStandardFarmingPool(pool).earned(address(this));
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setPerformanceFee(uint256 _performanceFee) public {
        require(msg.sender == governance, "!governance");
        require(_performanceFee <= 2000, "_performanceFee should be not over 20%");
        performanceFee = _performanceFee;
    }

    function setInsuranceFee(uint256 _insuranceFee) public {
        require(msg.sender == governance, "!governance");
        require(_insuranceFee <= 1000, "_insuranceFee should be not over 10%");
        insuranceFee = _insuranceFee;
    }

    function setBurnFee(uint256 _burnFee) public {
        require(msg.sender == governance, "!governance");
        require(_burnFee <= 500, "_burnFee should be not over 5%");
        burnFee = _burnFee;
    }

    function setGasFee(uint256 _gasFee) public {
        require(msg.sender == governance, "!governance");
        require(_gasFee <= 500, "_gasFee should be not over 5%");
        gasFee = _gasFee;
    }

    function setSwapRouting(address[] memory _path) public {
        require(msg.sender == governance, "!governance");
        require(_path.length >= 2, "_path.length is less than 2");
        swapRouting = _path;
    }
}
