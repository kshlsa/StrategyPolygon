pragma solidity 0.6.12;

interface IForceStrategyController {

    function deposit(uint256 _amount, address _token) external returns (uint256);

    function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external returns (uint256);

    function setRewards(address _rewards) external;

    function setGovernance(address _governance) external;

    function setVault(address _token, address _vault) external;

    function setStrategyStrategist(address _tokenIndexer, address _strategist)
        external;

    function setStrategy(address _token, address _strategy) external;

    function approveStrategy(address _token, address _strategy) external;

    function revokeStrategy(address _token, address _strategy) external;

    function balanceOf(address _tokenIndexer, address _tokenToBeChecked)
        external
        view
        returns (uint256);

    function withdrawAll(address _token) external;

    function balanceOfUser(uint256 shares, address asset) external view returns (uint256);
}
