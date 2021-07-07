pragma solidity 0.6.12;

import {fam3CRVStrategy} from "../strategies/fam3CRVStrategy.sol";
import {Context} from "../../dependencies/contracts/Context.sol";
import {ICurvePool} from "../../dependencies/interfaces/ICurvePool.sol";
import {ICurveGauge} from "../../dependencies/interfaces/ICurveGauge.sol";

import {Math} from "../../dependencies/libraries/Math.sol";
import {SafeMath} from "../../dependencies/libraries/SafeMath.sol";
import {ABDKMath64x64} from "../../dependencies/libraries/ABDKMath64x64.sol";

import {IAaveIncentivesController} from "../../dependencies/interfaces/IAaveIncentivesController.sol";
import "hardhat/console.sol";

contract fam3CRVStrategist is Context {
    using Math for uint256;
    using SafeMath for uint256;

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

    fam3CRVStrategy public strategy;
    address public governance;

    uint256 public borrowInterestThreshold;
    bool statePingDisabled = false;

    mapping(address => uint256) formerPrices;
    mapping(address => uint256) formerTimestamps;
    mapping(address => uint256[]) averageRatioChanges;

    ICurvePool public CurvePool;
    ICurveGauge public CurveGauge;
    IAaveIncentivesController public IncentivesController;

    uint256 public timeBetweenCompounds;
    uint256 public numberOfCompounds;
    uint256 public MaxLTV;

    constructor(
        address _strategy,
        address _governance,
        uint256 _borrowInterestThreshold,
        uint256 _timeBetweenCompounds,
        uint256 _numberOfCompounds,
        uint256 _MaxLTV
    ) public {
        strategy = fam3CRVStrategy(_strategy);
        governance = _governance;
        borrowInterestThreshold = _borrowInterestThreshold;

        CurvePool = ICurvePool(0x445FE580eF8d70FF569aB36e80c647af338db351);
        CurveGauge = ICurveGauge(0x19793B454D3AfC7b454F206Ffe95aDE26cA6912c);

        formerTimestamps[CurvePool.lp_token()] = block.timestamp;
        formerPrices[CurvePool.lp_token()] = CurvePool.get_virtual_price();

        IncentivesController = IAaveIncentivesController(
            0x357D51124f59836DeD84c8a1730D72B749d8BC23
        );

        timeBetweenCompounds = _timeBetweenCompounds;
        numberOfCompounds = _numberOfCompounds;

        MaxLTV = _MaxLTV;
    }

    function modifyMaxLTV(uint256 _MaxLTV) external {
        require(_msgSender() == governance, "you are not gov");
        MaxLTV = _MaxLTV;
        strategy.ModifyMaxLTV(MaxLTV);
        strategy.harvest();
    }

    function borrowInterestThresholdModify(uint256 _newThreshold) external {
        require(_msgSender() == governance, "you are not gov");
        borrowInterestThreshold = _newThreshold;
    }

    function disableStatePing() external {
        require(_msgSender() == governance, "you are not gov");
        statePingDisabled = true;
    }

    function ping() external {
        require(!statePingDisabled, "state ping disabled");
        calculateTotalRatioChange();
        strategy.resetToZero();
        uint256 APY = calculateAPY(CurvePool.lp_token(), 12 hours, 730);
        uint256 variabBorrowRate = strategy.getVariableBorrowRateOfAsset(USDT);

        if ((APY + borrowInterestThreshold) < variabBorrowRate) {
            if (strategy.CONTRACTSTATEisincurve()) {
                strategy.contractStateUpdate();
            }
        } else {
            if (!strategy.CONTRACTSTATEisincurve()) {
                strategy.contractStateUpdate();
            }
        }
        strategy.harvest();
    }

// if functionality undesired
   function normalPing() external {
       strategy.harvest();
   }

   function stateChange() external {
       require(governance == _msgSender(), "not governance");
       strategy.contractStateUpdate();
   }

    ///// CALC

    function _naive_pow_normalized(uint256 num, uint256 n)
        internal
        pure
        returns (uint256)
    {
        int128 number = int128(((1 << 64) * num) / 1e18);
        number = ABDKMath64x64.pow(number, n);
        //        num = ABDKMath64x64.toUInt(number);
        return uint256(((number * 1e15) >> 64) * 1e3);
    }

    // base apy expressed as (1 + apy in ratio)e18
    function calculateAPY(
        address _asset,
        uint256 _time,
        uint256 compounds
    ) public view returns (uint256) {
        uint256 APY = _naive_pow_normalized(
            (1e18 +
                averageRatioChanges[_asset][
                    averageRatioChanges[_asset].length - 1
                ]
                .mul(_time)
                .div(compounds)),
            compounds
        );

        return APY.sub(1e18).mul(1e12);
    }

    function calculateTotalRatioChange() public returns (uint256) {
        (uint256 CRVRewards, uint256 MaticRewards, ) = strategy
        .sinceLastClaim();

        uint256 fromMatic = strategy
        .calculateSushiTokenPrice(WETH, MATIC)
        .mul(MaticRewards)
        .div(1e18);
        uint256 fromCRV = strategy
        .calculateSushiTokenPrice(WETH, CRV)
        .mul(CRVRewards)
        .div(1e18);
        uint256 fromAll = strategy
        .calculateSushiTokenPrice(USDC, WETH)
        .mul(fromCRV.add(fromMatic))
        .div(1e18);

        uint256[3] memory arrValues;
        arrValues[0] = 0;
        arrValues[1] = 0;
        arrValues[2] = 0;
        arrValues[strategy.usdtIndex()] = strategy.convertFromDepositedToUSDT(
            fromAll,
            USDC
        );

        fromAll = 0;

        uint256 depositedInCurve = CurveGauge.balanceOf(address(strategy));

        if (depositedInCurve > 0) {
            fromAll = CurvePool.calc_token_amount(arrValues, true);
            fromAll = fromAll.mul(1e18).div(depositedInCurve);
            console.log("ZERO? %s", fromAll);
        }

        fromAll = fromAll + CurvePool.get_virtual_price();

        console.log(
            "FA %s SITUATION %s",
            fromAll,
            strategy.CONTRACTSTATEisincurve()
        );

        setAverageVirtualPriceChange(CurvePool.lp_token(), fromAll);

        return
            averageRatioChanges[CurvePool.lp_token()][
                averageRatioChanges[CurvePool.lp_token()].length - 1
            ];
    }

    function calculateRatioChange(address _asset, uint256 currPrice)
        internal
        returns (uint256)
    {
        (, , uint256 timestamp) = strategy.sinceLastClaim();
        uint256 dt = (block.timestamp).sub(timestamp);
        uint256 r;
        if (currPrice > formerPrices[_asset]) {
            r = currPrice.mul(1e18).div(formerPrices[_asset]).sub(1e18);
        } else {
            r = formerPrices[_asset].mul(1e18).div(currPrice).sub(1e18);
        }
        uint256 rpdt = r.div(dt);
        return rpdt;
    }

    function setAverageVirtualPriceChange(address _asset, uint256 currPrice)
        internal
    {
        console.log("HERE %s", currPrice);
        averageRatioChanges[_asset].push(
            Math.average(
                averageRatioChanges[_asset][
                    averageRatioChanges[_asset].length - 1
                ],
                calculateRatioChange(_asset, currPrice)
            )
        );
        console.log("HERE %s", currPrice);
        formerPrices[_asset] = currPrice;
    }

    bool public onlyOnce = false;

    function setInitialValues() external {
        require(!onlyOnce, "onlyOnce");
        averageRatioChanges[CurvePool.lp_token()].push(
            calculateRatioChange(
                CurvePool.lp_token(),
                formerPrices[CurvePool.lp_token()]
            )
        );
        strategy.ModifyMaxLTV(MaxLTV);
        onlyOnce = true;
    }
}
