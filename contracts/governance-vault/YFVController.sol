pragma solidity 0.5.17;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
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

interface Strategy {
    function want() external view returns (address);
    function deposit() external;
    function withdraw(address) external;
    function withdraw(uint256) external;
    function withdrawAll() external returns (uint256);
    function balanceOf() external view returns (uint256);
}

interface Converter {
    function convert(address) external returns (uint256);
}

interface OneSplitAudit {
    function swap(
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata distribution,
        uint256 flags
    )
    external
    payable
    returns (uint256 returnAmount);

    function getExpectedReturn(
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 parts,
        uint256 flags // See constants in IOneSplit.sol
    )
    external
    view
    returns (
        uint256 returnAmount,
        uint256[] memory distribution
    );
}

contract YFVController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public governance;

    mapping(address => address) public vaults;
    mapping(address => address) public strategies;
    mapping(address => mapping(address => address)) public converters;

    uint256 public insuranceFee = 500; // 5% at start
    uint256 public performanceFee = 500; // 5% at start
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public onesplit = 0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e;
    address public yfvInsuranceFund = 0xb7b2Ea8A1198368f950834875047aA7294A2bDAa; // set to Governance Multisig at start
    address public performanceReward = 0x7Be4D5A99c903C437EC77A20CB6d0688cBB73c7f; // set to deploy wallet at start

    constructor() public {
        governance = tx.origin;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setYfvInsuranceFund(address _yfvInsuranceFund) public {
        require(msg.sender == governance, "!governance");
        yfvInsuranceFund = _yfvInsuranceFund;
    }

    function setPerformanceReward(address _performanceReward) public{
        require(msg.sender == governance, "!governance");
        performanceReward = _performanceReward;
    }

    function setInsuranceFee(uint256 _insuranceFee) public {
        require(msg.sender == governance, "!governance");
        require(_insuranceFee <= 1000, "_insuranceFee should be not over 10%");
        insuranceFee = _insuranceFee;
    }

    function setPerformanceFee(uint256 _performanceFee) public {
        require(msg.sender == governance, "!governance");
        require(_performanceFee <= 1000, "_performanceFee should be not over 10%");
        performanceFee = _performanceFee;
    }

    function setOneSplit(address _onesplit) public {
        require(msg.sender == governance, "!governance");
        onesplit = _onesplit;
    }

    function setVault(address _token, address _vault) public {
        require(msg.sender == governance, "!governance");
        vaults[_token] = _vault;
    }

    function setConverter(address _input, address _output, address _converter) public {
        require(msg.sender == governance, "!governance");
        converters[_input][_output] = _converter;
    }

    function setStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        address _current = strategies[_token];
        if (_current != address(0)) {
            Strategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }

    function doHardWork(address _token, uint256 _amount) public {
        address _strategy = strategies[_token];
        address _want = Strategy(_strategy).want();
        if (_want != _token) {
            address converter = converters[_token][_want];
            IERC20(_token).safeTransfer(converter, _amount);
            _amount = Converter(converter).convert(_strategy);
            IERC20(_want).safeTransfer(_strategy, _amount);
        } else {
            IERC20(_token).safeTransfer(_strategy, _amount);
        }
        Strategy(_strategy).deposit();
    }

    function balanceOf(address _token) external view returns (uint256) {
        return Strategy(strategies[_token]).balanceOf();
    }

    function withdrawAll(address _token) public {
        require(msg.sender == governance, "!governance");
        Strategy(strategies[_token]).withdrawAll();
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public {
        require(msg.sender == governance, "!governance");
        IERC20(_token).safeTransfer(governance, _amount);
    }

    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public {
        require(msg.sender == governance, "!governance");
        Strategy(_strategy).withdraw(_token);
    }

    function getExpectedReturn(address _strategy, address _token, uint256 parts) public view returns (uint256 expected) {
        uint256 _balance = IERC20(_token).balanceOf(_strategy);
        address _want = Strategy(_strategy).want();
        (expected,) = OneSplitAudit(onesplit).getExpectedReturn(_token, _want, _balance, parts, 0);
    }

    // Only allows to withdraw non-core strategy tokens ~ this is over and above normal yield
    function yearn(address _strategy, address _token, uint256 parts) public {
        // This contract should never have value in it, but just in case since this is a public call
        uint256 _before = IERC20(_token).balanceOf(address(this));
        Strategy(_strategy).withdraw(_token);
        uint256 _after = IERC20(_token).balanceOf(address(this));
        if (_after > _before) {
            uint256 _amount = _after.sub(_before);
            address _want = Strategy(_strategy).want();
            uint256[] memory _distribution;
            uint256 _expected;
            _before = IERC20(_want).balanceOf(address(this));
            IERC20(_token).safeApprove(onesplit, 0);
            IERC20(_token).safeApprove(onesplit, _amount);
            (_expected, _distribution) = OneSplitAudit(onesplit).getExpectedReturn(_token, _want, _amount, parts, 0);
            uint256 _returnAmount = OneSplitAudit(onesplit).swap(_token, _want, _amount, _expected, _distribution, 0);
            require(_returnAmount > 0, "!_returnAmount");
            _after = IERC20(_want).balanceOf(address(this));
            if (_after > _before) {
                _amount = _after.sub(_before);
                uint256 _insuranceFeeAmt = _amount.mul(insuranceFee).div(FEE_DENOMINATOR);
                uint256 _performanceRewardAmt = _amount.mul(performanceFee).div(FEE_DENOMINATOR);
                doHardWork(_want, _amount.sub(_insuranceFeeAmt).sub(_performanceRewardAmt));
                IERC20(_want).safeTransfer(yfvInsuranceFund, _insuranceFeeAmt);
                IERC20(_want).safeTransfer(performanceReward, _performanceRewardAmt);
            }
        }
    }

    function withdraw(address _token, uint256 _amount) public {
        require(msg.sender == vaults[_token], "!vault");
        Strategy(strategies[_token]).withdraw(_amount);
    }
}
