// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import {ILendingPoolAddressesProvider} from "@aave/protocol-v2/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";
import {IPriceOracle} from "@aave/protocol-v2/contracts/interfaces/IPriceOracle.sol";

import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {IAaveIncentivesController} from "../../dependencies/interfaces/IAaveIncentivesController.sol";
import {SafeMath} from "../../dependencies/libraries/SafeMath.sol";
import {Context} from "../../dependencies/contracts/Context.sol";
import {IERC20} from "../../dependencies/interfaces/IERC20.sol";
import {ICurvePool} from "../../dependencies/interfaces/ICurvePool.sol";
import {IAaveProtocolDataProvider} from "../../dependencies/interfaces/IAaveProtocolDataProvider.sol";
import {ICurveGauge} from "../../dependencies/interfaces/ICurveGauge.sol";

import {IForceStrategy} from "../../dependencies/interfaces/IForceStrategy.sol";
import "hardhat/console.sol";

contract fam3CRVStrategy is Context, IForceStrategy {
    using SafeMath for uint256;
    using SafeMath for uint112;

    // For infinite approval
    uint256 public constant UINT256_MAX_VALUE = 2**256 - 1;

    // Coin addresses to be used throughout the file
    address public constant DAI =
        address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    address public constant USDT =
        address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
    address public constant USDC =
        address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address public constant CRV =
        address(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    address public constant WETH =
        address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address public constant MATIC =
        address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    // This maps the coinAddresses within Curve Pools to the respective index and memorizes the usdtIndex
    mapping(uint8 => address) coinAddresses;
    uint8 public usdtIndex;

    // Curve Contracts
    ICurvePool public CurvePool;
    ICurveGauge public CurveGauge;

    // Aave Contracts
    ILendingPoolAddressesProvider public LendingPoolAP;
    ILendingPool public LendingPool;
    IPriceOracle public PriceOracle;
    IAaveProtocolDataProvider public ProtocolDataProvider;
    IAaveIncentivesController public IncentivesController;

    // Sushi Contracts
    IUniswapV2Router02 public SushiswapRouter;
    IUniswapV2Factory public SushiswapFactory;

    /**
    These will:
    hAddressHelper -> hold addresses that we need to calculate tokens for harvest operations or other operations
    slippageHelper -> hold the slippages that we need for deposits, compounds etc.
     */
    harvestAddressHelper public hAddressHelper;
    slippageHelper public slipHelper;

    struct rewardInfo {
        uint256 maticClaimed;
        uint256 crvClaimed;
        uint256 timestamp;
    }

    struct uniPairHelper {
        IUniswapV2Pair CRVWETHPair;
        IUniswapV2Pair USDTWETHPair;
        IUniswapV2Pair MATICWETHPair;
    }

    struct harvestAddressHelper {
        address aTokenUSDC;
        address aTokenUSDT;
        address aTokenDAI;
        address debtATokenUSDT;
        address curveLPToken;
    }

    struct slippageHelper {
        uint256 curveDepositSlippage;
        uint256 curveWithdrawSlippage;
        uint256 loanToValueAdjustmentSlippage;
        uint256 harvestSwappingSlippage;
    }

    rewardInfo public sinceLastClaim;

    // no governance since governance is handled outside by controller/vault, by controlling the strategist
    address public strategist;
    address public controller;

    // for calculations
    uint256 public MaxLTV;

    // to save amount of coins deposited
    mapping(address => uint256) public deposited;

    // to know which state the contract is in
    bool public CONTRACTSTATEisincurve = true;

    /**
    @notice Constructor.
    @param _controller controller address
    @param _LendingPoolAP the lending pool address provider address on polygon
    @param _harvestSwappingSlippage <1e18 (eg 0.99e18) slippage for swapping during harvesting
    @param _curveDepositSlippage same as above for deposit
    @param _curveWithdrawSlippage same as above for withdrawing
    */
    constructor(
        address _controller,
        address _LendingPoolAP,
        uint256 _harvestSwappingSlippage,
        uint256 _curveDepositSlippage,
        uint256 _curveWithdrawSlippage
    ) public {
        LendingPoolAP = ILendingPoolAddressesProvider(_LendingPoolAP);
        LendingPool = ILendingPool(LendingPoolAP.getLendingPool());
        PriceOracle = IPriceOracle(LendingPoolAP.getPriceOracle());
        controller = _controller;
        strategist = msg.sender;

        slipHelper.harvestSwappingSlippage = _harvestSwappingSlippage;
        slipHelper.curveDepositSlippage = _curveDepositSlippage;
        slipHelper.curveWithdrawSlippage = _curveWithdrawSlippage;

        ProtocolDataProvider = IAaveProtocolDataProvider(
            0x7551b5D2763519d4e37e8B81929D336De671d46d
        );

        CurvePool = ICurvePool(0x445FE580eF8d70FF569aB36e80c647af338db351);
        CurveGauge = ICurveGauge(0x19793B454D3AfC7b454F206Ffe95aDE26cA6912c);

        IncentivesController = IAaveIncentivesController(
            0x357D51124f59836DeD84c8a1730D72B749d8BC23
        );

        SushiswapRouter = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );
        SushiswapFactory = IUniswapV2Factory(
            0xc35DADB65012eC5796536bD9864eD8773aBc74C4
        );

        hAddressHelper.curveLPToken = CurvePool.lp_token();

        (hAddressHelper.aTokenUSDC, , ) = ProtocolDataProvider
        .getReserveTokensAddresses(USDC);
        (
            hAddressHelper.aTokenUSDT,
            ,
            hAddressHelper.debtATokenUSDT
        ) = ProtocolDataProvider.getReserveTokensAddresses(USDT);
        (hAddressHelper.aTokenDAI, , ) = ProtocolDataProvider
        .getReserveTokensAddresses(DAI);

        for (uint8 i = 0; i < 3; i++) {
            coinAddresses[i] = CurvePool.underlying_coins(i);
            if (coinAddresses[i] == USDT) {
                usdtIndex = i;
            }
        }

        IERC20(USDT).approve(address(CurvePool), UINT256_MAX_VALUE);
        IERC20(USDC).approve(address(LendingPool), UINT256_MAX_VALUE);
        IERC20(DAI).approve(address(LendingPool), UINT256_MAX_VALUE);
        IERC20(USDT).approve(address(LendingPool), UINT256_MAX_VALUE);
        IERC20(CRV).approve(address(SushiswapRouter), UINT256_MAX_VALUE);
        IERC20(MATIC).approve(address(SushiswapRouter), UINT256_MAX_VALUE);
        IERC20(hAddressHelper.curveLPToken).approve(
            address(CurveGauge),
            UINT256_MAX_VALUE
        );
    }

    /////////////////////////////////////GOVERNANCE////////////////////////////////////////////

    modifier onlyStrategist() {
        require(_msgSender() == strategist, "sender not strat");
        _;
    }

    modifier onlyController() {
        require(_msgSender() == controller, "sender not controller");
        _;
    }

    event ContractStateUpdated(string state);

    /**
    @notice This should update the contract state to the state which the strategist deems necessary, if switching from curve state withdraw all funds, repay, borrow USDT and deposit into AAVE
    */
    function contractStateUpdate() external onlyStrategist {
        CONTRACTSTATEisincurve = !CONTRACTSTATEisincurve;
        string memory toEmit = CONTRACTSTATEisincurve
            ? "USDT in Curve"
            : "USDT in AAVE";
        emit ContractStateUpdated(toEmit);
        if (!CONTRACTSTATEisincurve) {
            _withdrawAll(address(this), false);
            uint256 balanceOfUSDT = IERC20(USDT).balanceOf(address(this));
            LendingPool.deposit(
                USDT,
                IERC20(USDT).balanceOf(address(this)),
                address(this),
                0
            );
            deposited[USDT] = balanceOfUSDT;
        } else {
            LendingPool.withdraw(USDT, type(uint256).max, address(this));
            deposited[USDT] = 0;
            _harvest();
        }
    }

    event MaxLTVModified(uint256 newMaxLTV);

    /**
    @param _newMaxLTV should be <1e18 eg 0.75e18
     */
    function ModifyMaxLTV(uint256 _newMaxLTV) external onlyStrategist {
        MaxLTV = _newMaxLTV;
        emit MaxLTVModified(MaxLTV);
    }

    event NewStrategistAssigned(address strategist);

    function assignNewStrategist(address _newStrategist) public onlyController {
        strategist = _newStrategist;
        emit NewStrategistAssigned(strategist);
    }

    //////////////////////////////////Getters///////////////////////////////////////////////

    function getName() external pure returns (string memory) {
        return "fam3CRVStrategy";
    }

    function getDebtData()
        public
        view
        returns (
            uint256 LTV,
            uint256 totalCollateralETH,
            uint256 totalDebtETH
        )
    {
        (totalCollateralETH, totalDebtETH, , , , ) = LendingPool
        .getUserAccountData(address(this));
        if (totalCollateralETH != 0) {
            LTV = totalDebtETH.mul(1e18).div(totalCollateralETH);
        } else {
            LTV = 0;
        }
        return (LTV, totalCollateralETH, totalDebtETH);
    }

    function getVariableBorrowRateOfAsset(address _asset)
        external
        view
        returns (uint256)
    {
        (, , , , uint256 variableBorrowRate, , , , , ) = ProtocolDataProvider
        .getReserveData(_asset);
        return variableBorrowRate;
    }

    /////////////////////// INTERFACE FUNCTIONS (except getter)

    function deposit(uint256 _amount, address _token)
        external
        override
        returns (uint256 sharesToMint)
    {
        return takeDeposit(_amount, _token);
    }

    function withdraw(
        uint256 _amount,
        address _token,
        address _recipient,
        uint256 _userSlippage
    ) external override returns (uint256 resultData) {
        return takeWithdraw(_amount, _token, _recipient, _userSlippage);
    }

    function balanceOfStrategy(address _token)
        external
        view
        override
        returns (uint256)
    {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        return balance;
    }

    function balanceOfUser(uint256 shares, address asset)
        public
        view
        override
        returns (uint256 result)
    {
        shares = shares.mul(1e18);
        shares = shares.div(deposited[address(this)]);

        if (CONTRACTSTATEisincurve) {
            shares = shares.mul(CurveGauge.balanceOf(address(this)));
            shares = shares.div(1e18);
            result = CurvePool.calc_withdraw_one_coin(shares, usdtIndex);
        } else {
            result = deposited[USDT].mul(shares).div(1e18);
        }

        result = result.mul(PriceOracle.getAssetPrice(USDT));
        result = result.div(MaxLTV);
        result = result.mul(1e18);
        result = result.div(PriceOracle.getAssetPrice(asset));

        return result;
    }

    function withdrawAll() external override returns (bool success) {
        require(_msgSender() == controller, "sender not controller");
        _withdrawAll(controller, true);
        return true;
    }

    function setStrategist(address _newStrategist)
        external
        override
        returns (bool success)
    {
        require(_msgSender() == controller, "sender not controller");
        assignNewStrategist(_newStrategist);
        return true;
    }

    /////////////////////////////////////////////////////////////////////////////////

    event AssetDeposited(uint256 sharesMinted, address token);

    function takeDeposit(uint256 _amount, address _token)
        public
        onlyController
        returns (uint256 sharesToMint)
    {
        require(
            IERC20(_token).balanceOf(address(this)) >= _amount,
            "didnt receive enough tokens"
        );
        require(_token != USDT, "USDC/DAI ONLY");

        (, uint256 formerCollateralETH, ) = getDebtData();

        if (deposited[_token] == 0) {
            deposited[_token] = _amount;
        } else {
            deposited[_token] = _amount + deposited[_token];
        }

        LendingPool.deposit(_token, _amount, address(this), 0);
        sharesToMint = _calculateSharesToMint(formerCollateralETH);

        _harvest();

        emit AssetDeposited(sharesToMint, _token);

        if (deposited[address(this)] == 0) {
            deposited[address(this)] = sharesToMint;
        } else {
            deposited[address(this)] = sharesToMint + deposited[address(this)];
        }

        return sharesToMint;
    }

    event AssetWithdrawn(uint256 amount, address token);

    function takeWithdraw(
        uint256 _amountShares,
        address _token,
        address _recipient,
        uint256 _userSlippage
    ) public onlyController returns (uint256 receivedUSD) {
        require(_token != USDT, "STRATEGY DOES NOT HOLD USDT");
        (uint256 LTV, , uint256 formerDebt) = getDebtData();

        require(deposited[address(this)] >= _amountShares, "no shares to burn");
        deposited[address(this)] -= _amountShares;
        console.log("here");
        uint256 USDTToWithdraw = _amountShares.mul(LTV).div(1e12).div(
            PriceOracle.getAssetPrice(USDT)
        );

        console.log("here");

        if (CONTRACTSTATEisincurve) {
            (, uint256 result) = _withdrawUSDTFromCurve(
                USDTToWithdraw,
                _userSlippage
            );
            console.log("here");
            require(
                IERC20(USDT).balanceOf(address(this)) >=
                    USDTToWithdraw.mul(95).div(100),
                "didn't receive USDT"
            );

            LendingPool.repay(USDT, result, 2, address(this));
        } else {
            console.log("here1");
            if (deposited[USDT] >= USDTToWithdraw) {
                console.log("HEREEE %s", deposited[USDT]);
                USDTToWithdraw = deposited[USDT];
                LendingPool.withdraw(USDT, deposited[USDT], address(this));
            } else {
                LendingPool.withdraw(USDT, USDTToWithdraw, address(this));
            }
            LendingPool.repay(USDT, USDTToWithdraw, 2, address(this));
        }

        console.log("here");

        uint256 debt;

        (LTV, , debt) = getDebtData();

        console.log("here");

        uint256 decimals = IERC20(_token).decimals();

        console.log("here");

        receivedUSD = formerDebt
        .sub(debt)
        .mul(10**decimals)
        .div(PriceOracle.getAssetPrice(_token))
        .mul(1e18)
        .div(MaxLTV);

        console.log("here");

        require(deposited[_token] >= receivedUSD, "not enough token in aave");
        console.log("here");
        deposited[_token].sub(receivedUSD);
        console.log("here");
        LendingPool.withdraw(_token, receivedUSD, _recipient);

        emit AssetWithdrawn(receivedUSD, _token);
        console.log("here");
        _harvest();
        console.log("here");
        return receivedUSD;
    }

    event Harvest(uint256 harvested);

    function harvest() public returns (uint256 harvested) {
        harvested = _harvest();
        emit Harvest(harvested);

        return harvested;
    }

    /**
    OPTIMISTICALLY ASSUMING WE WILL BE WHITELISTED FOR MATIC REWARDS
     */
    function _harvest() internal returns (uint256 harvested) {
        noteRewards();
        console.log("here");
        address[] memory pathArgs = new address[](3);
        pathArgs[0] = CRV;
        pathArgs[1] = WETH;
        pathArgs[2] = USDT;
        console.log("here");
        harvested = 0;

        CurveGauge.claim_rewards(address(this), address(this));
        console.log("here");
        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        uint256 amountOut;
        console.log("here");
        if (crvBalance > 0) {
            amountOut = calculateSushiTokenPrice(WETH, CRV).mul(crvBalance).div(
                1e18
            );

            amountOut = calculateSushiTokenPrice(USDT, WETH).mul(amountOut).div(
                1e18
            );

            if (amountOut > 0) {
                SushiswapRouter
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    crvBalance,
                    amountOut.mul(slipHelper.harvestSwappingSlippage).div(1e18), // Mind the div 1e18!!! slippage < 1e18
                    pathArgs,
                    address(this),
                    block.timestamp + 3 minutes
                );
            }
        }
        console.log("here");
        address[] memory addressArgs = new address[](4);
        addressArgs[0] = hAddressHelper.aTokenUSDC;
        addressArgs[1] = hAddressHelper.aTokenUSDT;
        addressArgs[2] = hAddressHelper.aTokenDAI;
        addressArgs[3] = hAddressHelper.debtATokenUSDT;
        console.log("here");
        IncentivesController.claimRewards(
            addressArgs,
            crvBalance,
            address(this)
        );
        console.log("here");
        crvBalance = IERC20(MATIC).balanceOf(address(this));
        console.log("here");
        require(
            IERC20(MATIC).balanceOf(address(this)) >= 0,
            "no matic rewards have been claimed?"
        );
        console.log("here");
        pathArgs[0] = MATIC;
        console.log("here");
        if (crvBalance > 0) {
            amountOut = calculateSushiTokenPrice(WETH, MATIC)
            .mul(crvBalance)
            .div(1e18);
            console.log("here");
            amountOut = calculateSushiTokenPrice(USDT, WETH).mul(amountOut).div(
                1e18
            );
            console.log("here");
            if (amountOut > 0) {
                SushiswapRouter
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    crvBalance,
                    amountOut.mul(slipHelper.harvestSwappingSlippage).div(1e18),
                    pathArgs,
                    address(this),
                    block.timestamp + 3 minutes
                );
            }
        }
        console.log("here");
        if (CONTRACTSTATEisincurve) {
            _adjustLoanToValue(
                slipHelper.curveDepositSlippage,
                slipHelper.curveWithdrawSlippage
            );
        } else {
            _adjustLoanToValue();
        }
        console.log("here");
        return harvested;
    }

    event USDTDeposited(uint256 minimum, uint256 deposited);

    function _depositUSDTInCurve(uint256 _amount, uint256 _slippage)
        internal
        returns (uint256 minimumAmountOfLPT, uint256 result)
    {
        console.log("here");
        uint256[3] memory inputArray;
        inputArray[0] = 0;
        inputArray[1] = 0;
        inputArray[2] = 0;
        inputArray[usdtIndex] = _amount;
        console.log("here");
        uint256 amountOfLPT = CurvePool.calc_token_amount(inputArray, true);
        console.log("here");
        minimumAmountOfLPT = amountOfLPT.mul(_slippage).div(1e18);
        console.log("here");
        result = CurvePool.add_liquidity(inputArray, minimumAmountOfLPT, true);
        console.log("here");
        deposited[hAddressHelper.curveLPToken] = CurveGauge.balanceOf(
            address(this)
        );
        console.log("here");
        CurveGauge.deposit(
            IERC20(hAddressHelper.curveLPToken).balanceOf(address(this)),
            address(this),
            true
        );
        console.log("here");
        emit USDTDeposited(minimumAmountOfLPT, result);
        return (minimumAmountOfLPT, result);
    }

    event USDTWithdrawn(uint256 minimum, uint256 deposited);

    function _withdrawUSDTFromCurve(uint256 _amount, uint256 _slippage)
        internal
        returns (uint256 minimumAmountOfTokens, uint256 result)
    {
        console.log("here");
        uint256[3] memory inputArray;
        inputArray[0] = 0;
        inputArray[1] = 0;
        inputArray[2] = 0;
        inputArray[usdtIndex] = _amount;
        console.log("here");
        minimumAmountOfTokens = CurvePool.calc_token_amount(inputArray, false);
        console.log("here");
        if (CurveGauge.balanceOf(address(this)) < minimumAmountOfTokens) {
            minimumAmountOfTokens = CurveGauge.balanceOf(address(this));
            CurveGauge.withdraw(minimumAmountOfTokens, true);
        } else {
            CurveGauge.withdraw(minimumAmountOfTokens, true);
        }
        console.log("here");
        _amount = _amount.mul(slipHelper.curveWithdrawSlippage).div(1e18);
        console.log("here");
        deposited[hAddressHelper.curveLPToken] = CurveGauge.balanceOf(
            address(this)
        );
        console.log("here");
        result = CurvePool.remove_liquidity_one_coin(
            minimumAmountOfTokens,
            usdtIndex,
            _amount,
            true
        );
        console.log("here");
        require(
            result >= inputArray[usdtIndex].mul(_slippage).div(1e18),
            "result is smaller than slippage allows"
        );
        console.log("here");
        emit USDTWithdrawn(minimumAmountOfTokens, result);
        return (minimumAmountOfTokens, result);
    }

    function convertFromDepositedToUSDT(uint256 amount, address token)
        public
        view
        returns (uint256)
    {
        return
            amount
                .mul(PriceOracle.getAssetPrice(token))
                .mul(MaxLTV)
                .div(1e18)
                .div(PriceOracle.getAssetPrice(USDT));
    }

    function _withdrawAll(address to, bool _withdraw)
        internal
        returns (uint256 result)
    {
        CurveGauge.withdraw(CurveGauge.balanceOf(address(this)), true);

        uint256 minAmountToReceive = CurvePool
        .calc_withdraw_one_coin(
            IERC20(hAddressHelper.curveLPToken).balanceOf(address(this)),
            usdtIndex
        ).mul(slipHelper.curveWithdrawSlippage)
        .div(1e18);

        result = CurvePool.remove_liquidity_one_coin(
            IERC20(hAddressHelper.curveLPToken).balanceOf(address(this)),
            usdtIndex,
            minAmountToReceive,
            true
        );

        console.log("ERRRRROEO");

        if (_withdraw) {
            LendingPool.repay(USDT, result, 2, address(this));

            LendingPool.withdraw(DAI, type(uint256).max, to);

            (, uint256 freeCollateral, ) = getDebtData();

            if (freeCollateral > 0) {
                LendingPool.withdraw(USDC, type(uint256).max, to);
            }
        }

        return result;
    }

    function _calculateSharesToMint(uint256 formerETHCollateral)
        internal
        view
        returns (uint256 shares)
    {
        (, uint256 totalCollateralETH, ) = getDebtData();
        return totalCollateralETH.sub(formerETHCollateral);
    }

    event IncreasedLTV(uint256, uint256);
    event LoweredLTV(uint256, uint256);

    /**
    @notice adjustLoanToValue with arguments for non-USDT mode
     */
    function _adjustLoanToValue(
        uint256 slippageIncrease,
        uint256 slippageDecrease
    ) internal returns (uint256 result) {
        (
            uint256 LTV,
            uint256 totalCollateralETH,
            uint256 totalDebtETH
        ) = getDebtData();

        result = 0;

        if (LTV.mul(101).div(100) < MaxLTV) {
            uint256 amountToBorrow = MaxLTV
            .sub(LTV)
            .mul(totalCollateralETH)
            .mul(10**6)
            .div(1e18)
            .div(PriceOracle.getAssetPrice(USDT));

            if (amountToBorrow > 0) {
                LendingPool.borrow(USDT, amountToBorrow, 2, 0, address(this));

                (LTV, , totalDebtETH) = getDebtData();

                require(
                    LTV >= MaxLTV.mul(98).div(100), // 2% tolerance
                    "altv incr nenough"
                );

                uint256 minimumAmountOfTokens;

                (minimumAmountOfTokens, result) = _depositUSDTInCurve(
                    amountToBorrow,
                    slippageIncrease
                );

                emit IncreasedLTV(minimumAmountOfTokens, result);
            }
        } else if (LTV > MaxLTV.mul(101).div(100)) {
            uint256 amountToRepay = LTV
            .sub(MaxLTV)
            .mul(totalCollateralETH)
            .mul(10**6)
            .div(1e18)
            .div(PriceOracle.getAssetPrice(USDT));

            if (amountToRepay > 0) {
                uint256 minAmount;

                (minAmount, result) = _withdrawUSDTFromCurve(
                    amountToRepay,
                    slippageDecrease
                );

                LendingPool.repay(USDT, result, 2, address(this));

                (LTV, , ) = getDebtData();

                require(LTV <= MaxLTV.mul(102).div(100), "altv decr noe");

                emit LoweredLTV(minAmount, result);
            }
        }

        uint256 USDTBalance = IERC20(USDT).balanceOf(address(this));
        uint256 result2 = 0;

        // deposit rest of balance that is available
        if (USDTBalance > 0) {
            (, result2) = _depositUSDTInCurve(USDTBalance, slippageIncrease);
        }

        return (result + result2);
    }

    /**
    @notice adjustLoanToValue USDT mode, here it reconfigures the LTV for USDT deposits if governance decides to change MaxLTV
     USDT deposits do not increase collateral
     */
    function _adjustLoanToValue() internal returns (uint256 result) {
        (
            uint256 LTV,
            uint256 totalCollateralETH,
            uint256 totalDebtETH
        ) = getDebtData();

        result = 0;

        if (LTV.mul(101).div(100) < MaxLTV) {
            uint256 amountToBorrow = MaxLTV
            .sub(LTV)
            .mul(totalCollateralETH)
            .mul(10**6)
            .div(1e18)
            .div(PriceOracle.getAssetPrice(USDT));

            LendingPool.borrow(USDT, amountToBorrow, 2, 0, address(this));

            (LTV, , ) = getDebtData();

            require(LTV >= MaxLTV.mul(99).div(100), "0altv incr noe");

            deposited[USDT] = deposited[USDT].add(amountToBorrow);
            console.log("ELLOEOOEO");
            LendingPool.deposit(USDT, amountToBorrow, address(this), 0);

            console.log("tssssss %s", amountToBorrow);

            result = amountToBorrow;
            emit IncreasedLTV(result, result);
        } else if (LTV > MaxLTV.mul(101).div(100)) {
            uint256 amountToRepay = LTV
            .sub(MaxLTV)
            .mul(totalCollateralETH)
            .mul(10**6)
            .div(1e18)
            .div(PriceOracle.getAssetPrice(USDT));

            LendingPool.withdraw(USDT, amountToRepay, address(this));

            (, totalCollateralETH, totalDebtETH) = getDebtData();

            LendingPool.repay(USDT, amountToRepay, 2, address(this));

            require(LTV <= MaxLTV.mul(102).div(100), "0altv decr noe");

            result = amountToRepay;
            emit LoweredLTV(result, result);
        }

        uint256 USDTBalance = IERC20(USDT).balanceOf(address(this));

        if (USDTBalance > 0) {
            deposited[USDT] = deposited[USDT].add(USDTBalance);
            LendingPool.deposit(USDT, USDTBalance, address(this), 0);
        }

        return result;
    }

    ///////////////////////////////// HELPERS

    function calculateSushiTokenPrice(address _forSwap, address _toSwap)
        public
        view
        returns (uint256)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(
            SushiswapFactory.getPair(_forSwap, _toSwap)
        );
        (uint112 reserves0, uint112 reserves1, ) = pair.getReserves();

        uint256 price = (pair.token0() == _forSwap)
            ? reserves0.mul(1e18).div(reserves1)
            : reserves1.mul(1e18).div(reserves0);

        return price;
    }

    function noteRewards() internal returns (uint256) {
        sinceLastClaim.maticClaimed += CurveGauge.claimable_reward(
            address(this),
            MATIC
        );
        sinceLastClaim.maticClaimed += IncentivesController
        .getUserUnclaimedRewards(address(this));
        sinceLastClaim.crvClaimed += CurveGauge.claimable_reward(
            address(this),
            CRV
        );
        if (sinceLastClaim.timestamp == 0) {
            sinceLastClaim.timestamp = block.timestamp;
        }
    }

    function resetToZero() external onlyStrategist {
        sinceLastClaim.maticClaimed = 0;
        sinceLastClaim.crvClaimed = 0;
        sinceLastClaim.timestamp = 0;
    }
}
