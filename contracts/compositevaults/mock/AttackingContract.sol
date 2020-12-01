// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../ILpPairConverter.sol";
import "../ICompositeVault.sol";
import "../ILpPairConverter.sol";

interface Bank {
    function deposit(address _vault, address _input, uint _amount, uint _min_mint_amount, bool _isStake, uint8 _flag) external;
    function addLiquidity(address _vault, uint _amount0, uint _amount1, uint _min_mint_amount, bool _isStake, uint8 _flag) external;
}

interface Vault {
    function depositFor(address _account, address _to, address _input, uint _amount, uint _min_mint_amount) external;
    function addLiquidityFor(address _account, address _to, uint _amount0, uint _amount1, uint _min_mint_amount) external;
}

contract AttackingContract {
    using SafeERC20 for IERC20;

    function deposit(address _bank, address _vault, address _input, uint _amount, uint _min_mint_amount, bool _isStake) external {
        IERC20(_input).safeIncreaseAllowance(_bank, _amount);

        Bank(_bank).deposit(_vault, _input, _amount, _min_mint_amount, _isStake, uint8(0));
    }

    function addLiquidity(address _bank, address _vault, uint _amount0, uint _amount1, uint _min_mint_amount, bool _isStake) external {

        ILpPairConverter _cnvrt = ILpPairConverter(ICompositeVault(_vault).getConverter());
        address _token0 = _cnvrt.token0();
        address _token1 = _cnvrt.token1();

        IERC20(_token0).safeIncreaseAllowance(_bank, _amount0);
        IERC20(_token1).safeIncreaseAllowance(_bank, _amount1);

        Bank(_bank).addLiquidity(_vault, _amount0, _amount1, _min_mint_amount, _isStake, uint8(0));
    }

    function depositFor(address _vault, address _account, address _to, address _input, uint _amount, uint _min_mint_amount) external {
        Vault(_vault).depositFor(_account, _to, _input, _amount, _min_mint_amount);
    }

    function addLiquidityFor(address _vault, address _account, address _to, uint _amount0, uint _amount1, uint _min_mint_amount) external {
        Vault(_vault).addLiquidityFor(_account, _to, _amount0, _amount1, _min_mint_amount);
    }
}
