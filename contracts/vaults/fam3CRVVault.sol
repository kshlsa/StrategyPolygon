pragma solidity 0.6.12;

import {IERC20} from "../../dependencies/interfaces/IERC20.sol";
import {ERC20} from "../../dependencies/contracts/ERC20.sol";
import {IForceStrategyController} from "../../dependencies/interfaces/IForceStrategyController.sol";
import {IForceVault} from "../../dependencies/interfaces/IForceVault.sol";
import {SafeERC20} from "../../dependencies/libraries/SafeERC20.sol";

contract fam3CRVVault is ERC20, IForceVault {

    using SafeERC20 for IERC20;

    uint256 public constant UINT256_MAX_VALUE = 2**256 - 1;

    address public constant DAI =
        address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    address public constant USDC =
        address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    IForceStrategyController public Controller;
    
    bool public reentrancy = true;

    modifier noReentrancy {
        require(reentrancy, "no reentrancy");
        reentrancy = false;
        _;
        reentrancy = true;
    }

    constructor(address _controller)
        public
        ERC20("fam3CRVVault", "fam3CRV", 18)
    {
        Controller = IForceStrategyController(_controller);
        IERC20(DAI).safeApprove(_controller, UINT256_MAX_VALUE);
        IERC20(USDC).safeApprove(_controller, UINT256_MAX_VALUE);
    }

    event FundsDeposited(uint256 amountDeposited, uint256 sharesMinted, address token);

    function balanceOfUser(uint256 shares, address asset) external override view returns (uint256 result) {
        return Controller.balanceOfUser(shares,asset);
    }

    function deposit(uint256 _amount, address _token)
        external
        override
        noReentrancy
        returns (uint256)
    {
        IERC20(_token).safeTransferFrom(_msgSender(), address(Controller), _amount);
        uint256 sharesToMint = Controller.deposit(_amount, _token);
        _mint(_msgSender(), sharesToMint);
        emit FundsDeposited(_amount, sharesToMint, _token);
    }

    event FundsWithdrawn(uint256 sharesBurned, uint256 fundsReceived, address token);

    function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external override noReentrancy returns (uint256) {
	    require(balanceOf(_msgSender()) >= _amount, "cant burn more shares than you have");
	    _burn(_msgSender(), _amount);
	    uint256 fundsReceived = Controller.withdraw(_amount, _token, _recipient, _userSlippage);
	    emit FundsWithdrawn(_amount, fundsReceived, _token);
	    return fundsReceived;
    }

}
