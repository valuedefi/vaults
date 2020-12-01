// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ValueMinorPool {
    function depositOnBehalf(address farmer, uint256 _pid, uint256 _amount, address _referrer) external;
    function withdrawOnBehalf(address farmer, uint256 _pid, uint256 _amount) external;
    function pendingValue(uint256 _pid, address _user) public view returns (uint256);
    function userInfo(uint _pid, address _user) external view returns (uint amount, uint rewardDebt, uint accumulatedStakingPower);
    function emergencyWithdraw(uint _pid) external;
}
