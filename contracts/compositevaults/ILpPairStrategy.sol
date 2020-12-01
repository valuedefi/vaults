// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ILpPairStrategy {
    function lpPair() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function deposit() external;
    function withdraw(address _asset) external;
    function withdraw(uint _amount) external returns (uint);
    function withdrawToController(uint _amount) external;
    function skim() external;
    function harvest(address _mergedStrategy) external;
    function withdrawAll() external returns (uint);
    function balanceOf() external view returns (uint);
    function withdrawFee(uint) external view returns (uint); // pJar: 0.5% (50/10000)
}
