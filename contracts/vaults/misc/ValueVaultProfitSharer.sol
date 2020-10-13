// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ValueLiquidityToken.sol";

interface IERC20Burnable {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function burn(uint amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IGovVault {
    function make_profit(uint256 amount) external;
    function addValueReward(uint256 _amount) external;
}

contract ValueVaultProfitSharer {
    using SafeMath for uint256;

    address public governance;

    ValueLiquidityToken public valueToken;
    IERC20Burnable public yfvToken; 

    address public govVault; // YFV -> VALUE, vUSD, vETH and 6.7% profit from Value Vaults
    address public insuranceFund = 0xb7b2Ea8A1198368f950834875047aA7294A2bDAa; // set to Governance Multisig at start
    address public performanceReward = 0x7Be4D5A99c903C437EC77A20CB6d0688cBB73c7f; // set to deploy wallet at start

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public insuranceFee = 0; // 0% at start and can be set by governance decision
    uint256 public performanceFee = 0; // 0% at start and can be set by governance decision
    uint256 public burnFee = 0; // 0% at start and can be set by governance decision

    constructor(ValueLiquidityToken _valueToken, IERC20Burnable _yfvToken) public {
        valueToken = _valueToken;
        yfvToken = _yfvToken;
        yfvToken.approve(address(valueToken), type(uint256).max);
        governance = tx.origin;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setGovVault(address _govVault) public {
        require(msg.sender == governance, "!governance");
        govVault = _govVault;
    }

    function setInsuranceFund(address _insuranceFund) public {
        require(msg.sender == governance, "!governance");
        insuranceFund = _insuranceFund;
    }

    function setPerformanceReward(address _performanceReward) public{
        require(msg.sender == governance, "!governance");
        performanceReward = _performanceReward;
    }

    function setInsuranceFee(uint256 _insuranceFee) public {
        require(msg.sender == governance, "!governance");
        insuranceFee = _insuranceFee;
    }

    function setPerformanceFee(uint256 _performanceFee) public {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    function setBurnFee(uint256 _burnFee) public {
        require(msg.sender == governance, "!governance");
        burnFee = _burnFee;
    }

    function shareProfit() public returns (uint256 profit) {
        if (govVault != address(0)) {
            profit = yfvToken.balanceOf(address(this));
            if (profit > 0) {
                if (performanceReward != address(0) && performanceFee > 0) {
                    uint256 _performanceFee = profit.mul(performanceFee).div(FEE_DENOMINATOR);
                    yfvToken.transfer(performanceReward, _performanceFee);
                }
                if (insuranceFund != address(0) && insuranceFee > 0) {
                    uint256 _insuranceFee = profit.mul(insuranceFee).div(FEE_DENOMINATOR);
                    yfvToken.transfer(insuranceFund, _insuranceFee);
                }
                if (burnFee > 0) {
                    uint256 _burnFee = profit.mul(burnFee).div(FEE_DENOMINATOR);
                    yfvToken.burn(_burnFee);
                }
                uint256 balanceLeft = yfvToken.balanceOf(address(this));
                valueToken.deposit(balanceLeft);
                valueToken.approve(govVault, 0);
                valueToken.approve(govVault, balanceLeft);
                IGovVault(govVault).make_profit(balanceLeft);
            }
        }
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract.
     * This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these.
     * It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(to, amount);
    }
}
