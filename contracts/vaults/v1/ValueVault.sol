// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./strategies/IStrategy.sol";
import "../ValueVaultMaster.sol";

contract ValueVault is ERC20 {
    using SafeMath for uint256;

    address public governance;

    mapping (address => uint256) public lockedAmount;

    IStrategy[] public strategies;

    uint256[] public strategyPreferredOrders;

    ValueVaultMaster public valueVaultMaster;

    constructor (ValueVaultMaster _valueVaultMaster, string memory _name, string memory _symbol) ERC20(_name, _symbol) public  {
        valueVaultMaster = _valueVaultMaster;
        governance = tx.origin;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategies(IStrategy[] memory _strategies) public {
        require(msg.sender == governance, "!governance");
        delete strategies;
        for (uint256 i = 0; i < _strategies.length; ++i) {
            strategies.push(_strategies[i]);
        }
    }

    function setStrategyPreferredOrders(uint256[] memory _strategyPreferredOrders) public {
        require(msg.sender == governance, "!governance");
        delete strategyPreferredOrders;
        for (uint256 i = 0; i < _strategyPreferredOrders.length; ++i) {
            strategyPreferredOrders.push(_strategyPreferredOrders[i]);
        }
    }

    function getStrategyCount() public view returns(uint count) {
        return strategies.length;
    }

    function depositAvailable() public view returns(bool) {
        if (strategies.length == 0) return false;
        for (uint256 i = 0; i < strategies.length; ++i) {
            IStrategy strategy = strategies[i];
            uint256 quota = valueVaultMaster.strategyQuota(address(strategy));
            if (quota == 0 || strategy.balanceOf(address(this)) < quota) {
                return true;
            }
        }
        return false;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by ValueVaultBank.
    function mintByBank(IERC20 _token, address _to, uint256 _amount) public {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");

        _deposit(_token, _amount);
        if (_amount > 0) {
            _mint(_to, _amount);
        }
    }

    // Must only be called by ValueVaultBank.
    function burnByBank(IERC20 _token, address _account, uint256 _amount) public {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");

        uint256 balance = balanceOf(_account);
        require(lockedAmount[_account] + _amount <= balance, "Vault: burn too much");

        _withdraw(_token, _amount);
        _burn(_account, _amount);
    }

    // Any user can transfer to another user.
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        uint256 balance = balanceOf(_msgSender());
        require(lockedAmount[_msgSender()] + _amount <= balance, "transfer: <= balance");

        _transfer(_msgSender(), _to, _amount);

        return true;
    }

    function _deposit(IERC20 _token, uint256 _amount) internal {
        require(strategies.length > 0, "no strategies");
        if (strategyPreferredOrders.length == 0 || strategyPreferredOrders.length != strategies.length) {
            for (uint256 i = 0; i < strategies.length; ++i) {
                IStrategy strategy = strategies[i];
                uint256 quota = valueVaultMaster.strategyQuota(address(strategy));
                if (quota == 0 || strategy.balanceOf(address(this)) < quota) {
                    _token.transfer(address(strategy), _amount);
                    strategy.deposit(address(this), _amount);
                    return;
                }
            }
        } else {
            for (uint256 i = 0; i < strategies.length; ++i) {
                IStrategy strategy = strategies[strategyPreferredOrders[i]];
                uint256 quota = valueVaultMaster.strategyQuota(address(strategy));
                if (quota == 0 || strategy.balanceOf(address(this)) < quota) {
                    _token.transfer(address(strategy), _amount);
                    strategy.deposit(address(this), _amount);
                    return;
                }
            }
        }
        revert("Exceeded quota");
    }

    function _withdraw(IERC20 _token, uint256 _amount) internal {
        require(strategies.length > 0, "no strategies");
        if (strategyPreferredOrders.length == 0 || strategyPreferredOrders.length != strategies.length) {
            for (uint256 i = strategies.length; i >= 1; --i) {
                IStrategy strategy = strategies[i - 1];
                uint256 bal = strategy.balanceOf(address(this));
                if (bal > 0) {
                    strategy.withdraw(address(this), (bal > _amount) ? _amount : bal);
                    _token.transferFrom(address(strategy), valueVaultMaster.bank(), _token.balanceOf(address(strategy)));
                    if (_token.balanceOf(valueVaultMaster.bank()) >= _amount) break;
                }
            }
        } else {
            for (uint256 i = strategies.length; i >= 1; --i) {
                IStrategy strategy = strategies[strategyPreferredOrders[i - 1]];
                uint256 bal = strategy.balanceOf(address(this));
                if (bal > 0) {
                    strategy.withdraw(address(this), (bal > _amount) ? _amount : bal);
                    _token.transferFrom(address(strategy), valueVaultMaster.bank(), _token.balanceOf(address(strategy)));
                    if (_token.balanceOf(valueVaultMaster.bank()) >= _amount) break;
                }
            }
        }
    }

    function harvestAllStrategies(uint256 _bankPoolId) external {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategies[i].harvest(_bankPoolId);
        }
    }

    function harvestStrategy(IStrategy _strategy, uint256 _bankPoolId) external {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");
        _strategy.harvest(_bankPoolId);
    }

    function withdrawStrategy(IStrategy _strategy, uint256 amount) external {
        require(msg.sender == governance, "!governance");
        _strategy.withdraw(address(this), amount);
    }

    function claimStrategy(IStrategy _strategy) external {
        require(msg.sender == governance, "!governance");
        _strategy.claim(address(this));
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
