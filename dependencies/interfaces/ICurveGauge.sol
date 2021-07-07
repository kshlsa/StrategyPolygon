pragma solidity 0.6.12;

interface ICurveGauge {
	function claim_rewards(address _addr, address _receiver) external;
	function claimable_reward(address _addr, address _token) external returns (uint256);
	function deposit(uint256 _value, address _addr, bool _claim_rewards) external;
	function withdraw(uint256 _value, bool _claim_rewards) external;
	function balanceOf(address arg0) external view returns (uint256);
}