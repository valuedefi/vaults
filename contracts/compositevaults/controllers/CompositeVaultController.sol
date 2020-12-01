// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../ILpPairStrategy.sol";
import "../ICompositeVault.sol";

interface Converter {
    function convert(address) external returns (uint);
}

contract CompositeVaultController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint;

    address public governance;
    address public strategist;

    struct StrategyInfo {
        address strategy;
        uint quota; // set = 0 to disable
        uint percent;
    }

    ICompositeVault public vault;
    string public name = "CompositeVaultController:[To_replaced_by_lp_symbol]";

    address public want;
    uint public strategyLength;

    // stratId => StrategyInfo
    mapping(uint => StrategyInfo) public strategies;

    mapping(address => bool) public approvedStrategies;

    bool public investDisabled;

    address public lazySelectedBestStrategy; // we pre-set the best strategy to avoid gas cost of iterating the array

    constructor(ICompositeVault _vault) public {
        require(address(_vault) != address(0), "!_vault");
        vault = _vault;
        want = vault.token();
        governance = msg.sender;
        strategist = msg.sender;
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
        require(msg.sender == address(vault) || msg.sender == strategist || msg.sender == governance, "!authorized");
        _;
    }

    function setName(string memory _name) external onlyGovernance {
        name = _name;
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function setStrategist(address _strategist) external onlyGovernance {
        strategist = _strategist;
    }

    function approveStrategy(address _strategy) external onlyGovernance {
        approvedStrategies[_strategy] = true;
    }

    function revokeStrategy(address _strategy) external onlyGovernance {
        approvedStrategies[_strategy] = false;
    }

    function setStrategyLength(uint _length) external onlyStrategist {
        strategyLength = _length;
    }

    // stratId => StrategyInfo
    function setStrategyInfo(uint _sid, address _strategy, uint _quota, uint _percent) external onlyStrategist {
        require(approvedStrategies[_strategy], "!approved");
        strategies[_sid].strategy = _strategy;
        strategies[_sid].quota = _quota;
        strategies[_sid].percent = _percent;
    }

    function setInvestDisabled(bool _investDisabled) external onlyStrategist {
        investDisabled = _investDisabled;
    }

    function setLazySelectedBestStrategy(address _strategy) external onlyStrategist {
        require(approvedStrategies[_strategy], "!approved");
        require(ILpPairStrategy(_strategy).lpPair() == want, "!want");
        lazySelectedBestStrategy = _strategy;
    }

    function getStrategyCount() external view returns(uint _strategyCount) {
        _strategyCount = strategyLength;
    }

    function getBestStrategy() public view returns (address _strategy) {
        if (lazySelectedBestStrategy != address(0)) {
            return lazySelectedBestStrategy;
        }
        _strategy = address(0);
        if (strategyLength == 0) return _strategy;
        uint _totalBal = balanceOf();
        if (_totalBal == 0) return strategies[0].strategy; // first depositor, simply return the first strategy
        uint _bestDiff = 201;
        for (uint _sid = 0; _sid < strategyLength; _sid++) {
            StrategyInfo storage sinfo = strategies[_sid];
            uint _stratBal = ILpPairStrategy(sinfo.strategy).balanceOf();
            if (_stratBal < sinfo.quota) {
                uint _diff = _stratBal.add(_totalBal).mul(100).div(_totalBal).sub(sinfo.percent); // [100, 200] - [percent]
                if (_diff < _bestDiff) {
                    _bestDiff = _diff;
                    _strategy = sinfo.strategy;
                }
            }
        }
        if (_strategy == address(0)) {
            _strategy = strategies[0].strategy;
        }
    }

    function earn(address _token, uint _amount) external onlyAuthorized {
        address _strategy = getBestStrategy();
        if (_strategy == address(0) || ILpPairStrategy(_strategy).lpPair() != _token) {
            // forward to vault and then call earnExtra() by its governance
            IERC20(_token).safeTransfer(address(vault), _amount);
        } else {
            IERC20(_token).safeTransfer(_strategy, _amount);
            ILpPairStrategy(_strategy).deposit();
        }
    }

    function withdraw_fee(uint _amount) external view returns (uint) {
        address _strategy = getBestStrategy();
        return (_strategy == address(0)) ? 0 : ILpPairStrategy(_strategy).withdrawFee(_amount);
    }

    function balanceOf() public view returns (uint _totalBal) {
        for (uint _sid = 0; _sid < strategyLength; _sid++) {
            _totalBal = _totalBal.add(ILpPairStrategy(strategies[_sid].strategy).balanceOf());
        }
    }

    function withdrawAll(address _strategy) external onlyStrategist {
        // WithdrawAll sends 'want' to 'vault'
        ILpPairStrategy(_strategy).withdrawAll();
    }

    function inCaseTokensGetStuck(address _token, uint _amount) external onlyStrategist {
        IERC20(_token).safeTransfer(address(vault), _amount);
    }

    function inCaseStrategyGetStuck(address _strategy, address _token) external onlyStrategist {
        ILpPairStrategy(_strategy).withdraw(_token);
        IERC20(_token).safeTransfer(address(vault), IERC20(_token).balanceOf(address(this)));
    }

    // note that some strategies do not allow controller to harvest
    function harvestStrategy(address _strategy) external onlyAuthorized {
        ILpPairStrategy(_strategy).harvest(address(0));
    }

    function harvestAllStrategies() external onlyAuthorized {
        address _firstStrategy = address(0); // to send all harvested WETH and proceed the profit sharing all-in-one here
        for (uint _sid = 0; _sid < strategyLength; _sid++) {
            StrategyInfo storage sinfo = strategies[_sid];
            if (_firstStrategy == address(0)) {
                _firstStrategy = sinfo.strategy;
            } else {
                ILpPairStrategy(sinfo.strategy).harvest(_firstStrategy);
            }
        }
        if (_firstStrategy != address(0)) {
            ILpPairStrategy(_firstStrategy).harvest(address(0));
        }
    }

    function switchFund(ILpPairStrategy _srcStrat, ILpPairStrategy _destStrat, uint _amount) external onlyStrategist {
        require(approvedStrategies[address(_destStrat)], "!approved");
        require(_srcStrat.lpPair() == want, "!_srcStrat.lpPair");
        require(_destStrat.lpPair() == want, "!_destStrat.lpPair");
        _srcStrat.withdrawToController(_amount);
        IERC20(want).safeTransfer(address(_destStrat), IERC20(want).balanceOf(address(this)));
        _destStrat.deposit();
    }

    function withdraw(uint _amount) external onlyAuthorized returns (uint _withdrawFee) {
        _withdrawFee = 0;
        uint _toWithdraw = _amount;
        uint _received;
        for (uint _sid = strategyLength; _sid > 0; _sid--) {
            StrategyInfo storage sinfo = strategies[_sid - 1];
            ILpPairStrategy _strategy = ILpPairStrategy(sinfo.strategy);
            uint _stratBal = _strategy.balanceOf();
            if (_toWithdraw < _stratBal) {
                _received = _strategy.withdraw(_toWithdraw);
                _withdrawFee = _withdrawFee.add(_strategy.withdrawFee(_received));
                return _withdrawFee;
            }
            _received = _strategy.withdrawAll();
            _withdrawFee = _withdrawFee.add(_strategy.withdrawFee(_received));
            if (_received >= _toWithdraw) {
                return _withdrawFee;
            }
            _toWithdraw = _toWithdraw.sub(_received);
        }
        return _withdrawFee;
    }
}
