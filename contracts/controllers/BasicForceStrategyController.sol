pragma solidity 0.6.12;

import {IERC20} from "../../dependencies/interfaces/IERC20.sol";
import {IForceStrategy} from "../../dependencies/interfaces/IForceStrategy.sol";
import {IForceStrategyController} from "../../dependencies/interfaces/IForceStrategyController.sol";
import {Context} from "../../dependencies/contracts/Context.sol";

contract BasicForceStrategyController is IForceStrategyController, Context {

    uint256 public constant UINT256_MAX_VALUE = 2**256 - 1;

    address public governance;
    address public rewards;

    mapping(address => address) public vaults;
    mapping(address => address) public strategies;
    mapping(address => mapping(address => bool)) public approvedStrategies;

    constructor(address _governance, address _rewards) public {
        governance = _governance;
        rewards = _rewards;
    }


    function deposit(uint256 _amount, address _token) external override returns (uint256) {
        require(_msgSender() == vaults[_token], "non-vaults cant't send requests");
        if(IERC20(_token).allowance(address(this), strategies[_token]) < UINT256_MAX_VALUE) {
            IERC20(_token).approve(strategies[_token], UINT256_MAX_VALUE);
        }
        IERC20(_token).transfer(strategies[_token], _amount);
        return IForceStrategy(strategies[_token]).deposit(_amount, _token);
    }

    function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external override returns (uint256) {
        require(_msgSender() == vaults[_token], "non-vaults cant't send requests");
        return IForceStrategy(strategies[_token]).withdraw(_amount, _token, _recipient, _userSlippage);
    }

    function balanceOfUser(uint256 shares, address _token) external override view returns (uint256 result) {
        require(_msgSender() == vaults[_token], "non-vaults cant't send requests");
        return IForceStrategy(strategies[_token]).balanceOfUser(shares, _token);
    }

    function setRewards(address _rewards) public override {
        require(_msgSender() == governance, "!governance");
        rewards = _rewards;
    }

    function setGovernance(address _governance) public override {
        require(_msgSender() == governance, "!governance");
        governance = _governance;
    }

    function setVault(address _token, address _vault) public override {
        require(msg.sender == governance, "!strategist");
        require(vaults[_token] == address(0), "vault");
        vaults[_token] = _vault;
    } 

    function setStrategyStrategist(address _tokenIndexer, address _strategist) public override {
        require(_msgSender() == governance, "!governance");
        IForceStrategy(strategies[_tokenIndexer]).setStrategist(_strategist);
    }

    function setStrategy(address _token, address _strategy) public override {
        require(msg.sender == governance, "!strategist");
        require(approvedStrategies[_token][_strategy] == true, "!approved");

        address _current = strategies[_token];
        if (_current != address(0)) {
            IForceStrategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }

    ////////// APPROVAL

    function approveStrategy(address _token, address _strategy) public override {
        require(_msgSender() == governance, "!governance");
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) public override {
        require(_msgSender() == governance, "!governance");
        approvedStrategies[_token][_strategy] = false;
    }

    ////////// GETTER

    function balanceOf(address _tokenIndexer, address _tokenToBeChecked) external override view returns (uint256) {
        return IForceStrategy(strategies[_tokenIndexer]).balanceOfStrategy(_tokenToBeChecked);
    }

    function withdrawAll(address _token) public override {
        require(msg.sender == governance, "!strategist");
        bool success = IForceStrategy(strategies[_token]).withdrawAll();
        require(success, "EMERGENCY, EMERGENCY, EMERGENCY WITHDRAW: OFFLINE");
    }
}
