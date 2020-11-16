// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./strategies/IStrategyV2.sol";
import "../ValueVaultMaster.sol";

interface IValueVault {
    function getStrategyCount() external view returns(uint256);
    function depositAvailable() external view returns(bool);
    function mintByBank(IERC20 _token, address _to, uint256 _amount) external;
    function burnByBank(IERC20 _token, address _account, uint256 _amount) external;
    function harvestAllStrategies(uint256 _bankPoolId) external;
    function harvestStrategy(address _strategy, uint256 _bankPoolId) external;
}

contract ValueVaultV2 is IValueVault, ERC20 {
    using SafeMath for uint256;

    address public governance;

    IStrategyV2 public strategy;

    uint256[] public poolStrategyIds; // sorted by preference

    ValueVaultMaster public valueVaultMaster;

    constructor (ValueVaultMaster _valueVaultMaster, string memory _name, string memory _symbol) ERC20(_name, _symbol) public  {
        valueVaultMaster = _valueVaultMaster;
        governance = tx.origin;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setStrategy(IStrategyV2 _strategy) public {
        require(msg.sender == governance, "!governance");
        strategy = _strategy;
    }

    function setPoolStrategyIds(uint256[] memory _poolStrategyIds) public {
        require(msg.sender == governance, "!governance");
        delete poolStrategyIds;
        for (uint256 i = 0; i < _poolStrategyIds.length; ++i) {
            poolStrategyIds.push(_poolStrategyIds[i]);
        }
    }

    function getStrategyCount() public override view returns(uint count) {
        return poolStrategyIds.length;
    }

    function depositAvailable() public override view returns(bool) {
        if (poolStrategyIds.length == 0) return false;
        for (uint256 i = 0; i < poolStrategyIds.length; ++i) {
            uint256 _pid = poolStrategyIds[i];
            uint256 _quota = strategy.poolQuota(_pid);
            if (_quota == 0 || strategy.balanceOf(_pid) < _quota) {
                return true;
            }
        }
        return false;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by ValueVaultBank.
    function mintByBank(IERC20 _token, address _to, uint256 _amount) public override {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");

        _deposit(_token, _amount);
        if (_amount > 0) {
            _mint(_to, _amount);
        }
    }

    // Must only be called by ValueVaultBank.
    function burnByBank(IERC20 _token, address _account, uint256 _amount) public override {
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
        require(poolStrategyIds.length > 0, "no strategies");
        for (uint256 i = 0; i < poolStrategyIds.length; ++i) {
            uint256 _pid = poolStrategyIds[i];
            uint256 _quota = strategy.poolQuota(_pid);
            if (_quota == 0 || strategy.balanceOf(_pid) < _quota) {
                _token.transfer(address(strategy), _amount);
                strategy.deposit(_pid, _amount);
                return;
            }
        }
        revert("Exceeded quota");
    }

    function _withdraw(IERC20 _token, uint256 _amount) internal {
        require(poolStrategyIds.length > 0, "no strategies");
        for (uint256 i = poolStrategyIds.length; i >= 1; --i) {
            uint256 _pid = poolStrategyIds[i - 1];
            uint256 bal = strategy.balanceOf(_pid);
            if (bal > 0) {
                strategy.withdraw(_pid, (bal > _amount) ? _amount : bal);
                _token.transferFrom(address(strategy), valueVaultMaster.bank(), _token.balanceOf(address(strategy)));
                if (_token.balanceOf(valueVaultMaster.bank()) >= _amount) break;
            }
        }
    }

    function harvestAllStrategies(uint256 _bankPoolId) external override {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");
        for (uint256 i = 0; i < poolStrategyIds.length; ++i) {
            strategy.harvest(_bankPoolId, poolStrategyIds[i]);
        }
    }

    function harvestStrategy(address _strategy, uint256 _bankPoolId) external override {
        require(_msgSender() == valueVaultMaster.bank(), "not bank");
        IStrategyV2(_strategy).harvest(_bankPoolId, poolStrategyIds[0]); // always harvest the first pool
    }

    function harvestStrategy(uint256 _bankPoolId, uint256 _poolStrategyId) external {
        require(msg.sender == governance, "!governance");
        strategy.harvest(_bankPoolId, _poolStrategyId);
    }

    function withdrawStrategy(IStrategyV2 _strategy, uint256 _poolStrategyId, uint256 _amount) external {
        require(msg.sender == governance, "!governance");
        _strategy.withdraw(_poolStrategyId, _amount);
    }

    function claimStrategy(IStrategyV2 _strategy, uint256 _poolStrategyId) external {
        require(msg.sender == governance, "!governance");
        _strategy.claim(_poolStrategyId);
    }

    function forwardBetweenStrategies(IStrategyV2 _source, IStrategyV2 _dest, uint256 _amount) external {
        require(msg.sender == governance, "!governance");
        _source.forwardToAnotherStrategy(address(_dest), _amount);
    }

    /**
     * This function allows governance to take unsupported tokens out of the contract.
     * This is in an effort to make someone whole, should they seriously mess up.
     * There is no guarantee governance will vote to return these.
     * It also allows for removal of airdropped tokens.
     */
    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external {
        require(msg.sender == governance, "!governance");
        _token.transfer(_to, _amount);
    }

    event ExecuteTransaction(address indexed target, uint value, string signature, bytes data);

    function executeTransaction(address target, uint value, string memory signature, bytes memory data) public returns (bytes memory) {
        require(msg.sender == governance, "!governance");

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Univ2ETHUSDCMultiPoolStrategy::executeTransaction: Transaction execution reverted.");

        emit ExecuteTransaction(target, value, signature, data);

        return returnData;
    }
}
