pragma solidity 0.6.12;

interface IForceVault {

function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external returns (uint256);
function deposit(uint256 _amount, address _token) external returns (uint256);
function balanceOfUser(uint256 shares, address asset) external view returns (uint256);


}