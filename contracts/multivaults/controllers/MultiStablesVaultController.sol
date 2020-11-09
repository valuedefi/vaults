// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../IMultiVaultStrategy.sol";
import "../IValueMultiVault.sol";
import "../IShareConverter.sol";

interface Converter {
    function convert(address) external returns (uint);
}

contract MultiStablesVaultController {
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

    IValueMultiVault public vault;

    address public basedWant;
    address[] public wantTokens; // sorted by preference

    // want => quota, length
    mapping(address => uint) public wantQuota;
    mapping(address => uint) public wantStrategyLength;

    // want => stratId => StrategyInfo
    mapping(address => mapping(uint => StrategyInfo)) public strategies;

    mapping(address => mapping(address => bool)) public approvedStrategies;

    mapping(address => bool) public investDisabled;
    IShareConverter public shareConverter; // converter for shares (3CRV <-> BCrv, etc ...)
    address public lazySelectedBestStrategy; // we pre-set the best strategy to avoid gas cost of iterating the array

    constructor(IValueMultiVault _vault) public {
        require(address(_vault) != address(0), "!_vault");
        vault = _vault;
        basedWant = vault.token();
        governance = msg.sender;
        strategist = msg.sender;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function approveStrategy(address _want, address _strategy) external {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_want][_strategy] = true;
    }

    function revokeStrategy(address _want, address _strategy) external {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_want][_strategy] = false;
    }

    function setWantQuota(address _want, uint _quota) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        wantQuota[_want] = _quota;
    }

    function setWantStrategyLength(address _want, uint _length) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        wantStrategyLength[_want] = _length;
    }

    // want => stratId => StrategyInfo
    function setStrategyInfo(address _want, uint _sid, address _strategy, uint _quota, uint _percent) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(approvedStrategies[_want][_strategy], "!approved");
        strategies[_want][_sid].strategy = _strategy;
        strategies[_want][_sid].quota = _quota;
        strategies[_want][_sid].percent = _percent;
    }

    function setShareConverter(IShareConverter _shareConverter) external {
        require(msg.sender == governance, "!governance");
        shareConverter = _shareConverter;
    }

    function setInvestDisabled(address _want, bool _investDisabled) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        investDisabled[_want] = _investDisabled;
    }

    function setWantTokens(address[] memory _wantTokens) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        delete wantTokens;
        uint _wlength = _wantTokens.length;
        for (uint i = 0; i < _wlength; ++i) {
            wantTokens.push(_wantTokens[i]);
        }
    }

    function getStrategyCount() external view returns(uint _strategyCount) {
        _strategyCount = 0;
        uint _wlength = wantTokens.length;
        for (uint i = 0; i < _wlength; i++) {
            _strategyCount = _strategyCount.add(wantStrategyLength[wantTokens[i]]);
        }
    }

    function wantLength() external view returns (uint) {
        return wantTokens.length;
    }

    function wantStrategyBalance(address _want) public view returns (uint) {
        uint _bal = 0;
        for (uint _sid = 0; _sid < wantStrategyLength[_want]; _sid++) {
            _bal = _bal.add(IMultiVaultStrategy(strategies[_want][_sid].strategy).balanceOf());
        }
        return _bal;
    }

    function want() external view returns (address) {
        if (lazySelectedBestStrategy != address(0)) {
            return IMultiVaultStrategy(lazySelectedBestStrategy).want();
        }
        uint _wlength = wantTokens.length;
        if (_wlength > 0) {
            if (_wlength == 1) {
                return wantTokens[0];
            }
            for (uint i = 0; i < _wlength; i++) {
                address _want = wantTokens[i];
                uint _bal = wantStrategyBalance(_want);
                if (_bal < wantQuota[_want]) {
                    return _want;
                }
            }
        }
        return basedWant;
    }

    function setLazySelectedBestStrategy(address _strategy) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        lazySelectedBestStrategy = _strategy;
    }

    function getBestStrategy(address _want) public view returns (address _strategy) {
        if (lazySelectedBestStrategy != address(0) && IMultiVaultStrategy(lazySelectedBestStrategy).want() == _want) {
            return lazySelectedBestStrategy;
        }
        uint _wantStrategyLength = wantStrategyLength[_want];
        _strategy = address(0);
        if (_wantStrategyLength == 0) return _strategy;
        uint _totalBal = wantStrategyBalance(_want);
        if (_totalBal == 0) {
            // first depositor, simply return the first strategy
            return strategies[_want][0].strategy;
        }
        uint _bestDiff = 201;
        for (uint _sid = 0; _sid < _wantStrategyLength; _sid++) {
            StrategyInfo storage sinfo = strategies[_want][_sid];
            uint _stratBal = IMultiVaultStrategy(sinfo.strategy).balanceOf();
            if (_stratBal < sinfo.quota) {
                uint _diff = _stratBal.add(_totalBal).mul(100).div(_totalBal).sub(sinfo.percent); // [100, 200] - [percent]
                if (_diff < _bestDiff) {
                    _bestDiff = _diff;
                    _strategy = sinfo.strategy;
                }
            }
        }
        if (_strategy == address(0)) {
            _strategy = strategies[_want][0].strategy;
        }
    }

    function earn(address _token, uint _amount) external {
        require(msg.sender == address(vault) || msg.sender == strategist || msg.sender == governance, "!strategist");
        address _strategy = getBestStrategy(_token);
        if (_strategy == address(0) || IMultiVaultStrategy(_strategy).want() != _token) {
            // forward to vault and then call earnExtra() by its governance
            IERC20(_token).safeTransfer(address(vault), _amount);
        } else {
            IERC20(_token).safeTransfer(_strategy, _amount);
            IMultiVaultStrategy(_strategy).deposit();
        }
    }

    function withdraw_fee(address _want, uint _amount) external view returns (uint) {
        address _strategy = getBestStrategy(_want);
        return (_strategy == address(0)) ? 0 : IMultiVaultStrategy(_strategy).withdrawFee(_amount);
    }

    function balanceOf(address _want, bool _sell) external view returns (uint _totalBal) {
        uint _wlength = wantTokens.length;
        if (_wlength == 0) {
            return 0;
        }
        _totalBal = 0;
        for (uint i = 0; i < _wlength; i++) {
            address wt = wantTokens[i];
            uint _bal = wantStrategyBalance(wt);
            if (wt != _want) {
                _bal = shareConverter.convert_shares_rate(wt, _want, _bal);
                if (_sell) {
                    _bal = _bal.mul(9998).div(10000); // minus 0.02% for selling
                }
            }
            _totalBal = _totalBal.add(_bal);
        }
    }

    function withdrawAll(address _strategy) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        // WithdrawAll sends 'want' to 'vault'
        IMultiVaultStrategy(_strategy).withdrawAll();
    }

    function inCaseTokensGetStuck(address _token, uint _amount) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        IERC20(_token).safeTransfer(address(vault), _amount);
    }

    function inCaseStrategyGetStuck(address _strategy, address _token) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        IMultiVaultStrategy(_strategy).withdraw(_token);
        IERC20(_token).safeTransfer(address(vault), IERC20(_token).balanceOf(address(this)));
    }

    function claimInsurance() external {
        require(msg.sender == governance, "!governance");
        vault.claimInsurance();
    }

    // note that some strategies do not allow controller to harvest
    function harvestStrategy(address _strategy) external {
        require(msg.sender == address(vault) || msg.sender == strategist || msg.sender == governance, "!strategist && !vault");
        IMultiVaultStrategy(_strategy).harvest(address(0));
    }

    function harvestWant(address _want) external {
        require(msg.sender == address(vault) || msg.sender == strategist || msg.sender == governance, "!strategist && !vault");
        uint _wantStrategyLength = wantStrategyLength[_want];
        address _firstStrategy = address(0); // to send all harvested WETH and proceed the profit sharing all-in-one here
        for (uint _sid = 0; _sid < _wantStrategyLength; _sid++) {
            StrategyInfo storage sinfo = strategies[_want][_sid];
            if (_firstStrategy == address(0)) {
                _firstStrategy = sinfo.strategy;
            } else {
                IMultiVaultStrategy(sinfo.strategy).harvest(_firstStrategy);
            }
        }
        if (_firstStrategy != address(0)) {
            IMultiVaultStrategy(_firstStrategy).harvest(address(0));
        }
    }

    function harvestAllStrategies() external {
        require(msg.sender == address(vault) || msg.sender == strategist || msg.sender == governance, "!strategist && !vault");
        uint _wlength = wantTokens.length;
        address _firstStrategy = address(0); // to send all harvested WETH and proceed the profit sharing all-in-one here
        for (uint i = 0; i < _wlength; i++) {
            address _want = wantTokens[i];
            uint _wantStrategyLength = wantStrategyLength[_want];
            for (uint _sid = 0; _sid < _wantStrategyLength; _sid++) {
                StrategyInfo storage sinfo = strategies[_want][_sid];
                if (_firstStrategy == address(0)) {
                    _firstStrategy = sinfo.strategy;
                } else {
                    IMultiVaultStrategy(sinfo.strategy).harvest(_firstStrategy);
                }
            }
        }
        if (_firstStrategy != address(0)) {
            IMultiVaultStrategy(_firstStrategy).harvest(address(0));
        }
    }

    function switchFund(IMultiVaultStrategy _srcStrat, IMultiVaultStrategy _destStrat, uint _amount) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _srcStrat.withdrawToController(_amount);
        address _srcWant = _srcStrat.want();
        address _destWant = _destStrat.want();
        if (_srcWant != _destWant) {
            _amount = IERC20(_srcWant).balanceOf(address(this));
            require(shareConverter.convert_shares_rate(_srcWant, _destWant, _amount) > 0, "rate=0");
            IERC20(_srcWant).safeTransfer(address(shareConverter), _amount);
            shareConverter.convert_shares(_srcWant, _destWant, _amount);
        }
        IERC20(_destWant).safeTransfer(address(_destStrat), IERC20(_destWant).balanceOf(address(this)));
        _destStrat.deposit();
    }

    function withdraw(address _want, uint _amount) external returns (uint _withdrawFee) {
        require(msg.sender == address(vault), "!vault");
        _withdrawFee = 0;
        uint _toWithdraw = _amount;
        uint _wantStrategyLength = wantStrategyLength[_want];
        uint _received;
        for (uint _sid = _wantStrategyLength; _sid > 0; _sid--) {
            StrategyInfo storage sinfo = strategies[_want][_sid - 1];
            IMultiVaultStrategy _strategy = IMultiVaultStrategy(sinfo.strategy);
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
        if (_toWithdraw > 0) {
            // still not enough, try to withdraw from other wants strategies
            uint _wlength = wantTokens.length;
            for (uint i = _wlength; i > 0; i--) {
                address wt = wantTokens[i - 1];
                if (wt != _want) {
                    (uint _wamt, uint _wdfee) = _withdrawOtherWant(_want, wt, _toWithdraw);
                    _withdrawFee = _withdrawFee.add(_wdfee);
                    if (_wamt >= _toWithdraw) {
                        return _withdrawFee;
                    }
                    _toWithdraw = _toWithdraw.sub(_wamt);
                }
            }
        }
        return _withdrawFee;
    }

    function _withdrawOtherWant(address _want, address _other, uint _amount) internal returns (uint _wantAmount, uint _withdrawFee) {
        // Check balance
        uint b = IERC20(_want).balanceOf(address(this));
        _withdrawFee = 0;
        if (b >= _amount) {
            _wantAmount = b;
        } else {
            uint _toWithdraw = _amount.sub(b);
            uint _toWithdrawOther = _toWithdraw.mul(101).div(100); // add 1% extra
            uint _otherBal = IERC20(_other).balanceOf(address(this));
            if (_otherBal < _toWithdrawOther) {
                uint _otherStrategyLength = wantStrategyLength[_other];
                for (uint _sid = _otherStrategyLength; _sid > 0; _sid--) {
                    StrategyInfo storage sinfo = strategies[_other][_sid - 1];
                    IMultiVaultStrategy _strategy = IMultiVaultStrategy(sinfo.strategy);
                    uint _stratBal = _strategy.balanceOf();
                    uint _needed = _toWithdrawOther.sub(_otherBal);
                    uint _wdamt = (_needed < _stratBal) ? _needed : _stratBal;
                    _strategy.withdrawToController(_wdamt);
                    _withdrawFee = _withdrawFee.add(_strategy.withdrawFee(_wdamt));
                    _otherBal = IERC20(_other).balanceOf(address(this));
                    if (_otherBal >= _toWithdrawOther) {
                        break;
                    }
                }
            }
            IERC20(_other).safeTransfer(address(shareConverter), _otherBal);
            shareConverter.convert_shares(_other, _want, _otherBal);
            _wantAmount = IERC20(_want).balanceOf(address(this));
        }
        IERC20(_want).safeTransfer(address(vault), _wantAmount);
    }
}
