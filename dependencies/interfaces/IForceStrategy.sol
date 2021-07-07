pragma solidity 0.6.12;

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface IForceStrategy {
	  function deposit(uint256 _amount, address _token) external returns (uint256);
        function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external returns (uint256);
        function balanceOfStrategy(address _token) external view returns (uint256);
        function withdrawAll() external returns (bool);
        function setStrategist(address _newStrategist) external returns (bool);
        function balanceOfUser(uint256 shares, address asset) external view returns (uint256);
}