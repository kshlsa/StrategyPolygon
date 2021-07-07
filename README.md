# Force DAO fam3CRVStrategy

## General

The idea for the working principle of the fam3CRVStrategy for Curve + AAVE is based on two states:

- 1. If the USDT borrow interest is not high enough, which the strategist judges, which is a contract that should be repeadetly pinged, it could also be
decided by a human or likewise, then the strategy deposits funds in Curve and farms Curve rewards + fees. 

- 2. Otherwise, it deposits borrowed USDT in AAVE, because this still nets a positive APY, and protects from high borrow interest on USDT.

The strategy allows users to deposit either DAI or USDC and withdraw either one of those. ERC20 tokens which represent ownership of underlying
collateral are minted exactly according to the change in collateral upon deposit into the contract. Governance may decide to regulate the MaxLTV
of the strategy contract, by communicating with the strategist contract. 

## Architecture

The architecture was loosely inspired by yearn v1 contracts, the user communicates with an ERC20-enabled vault, which communicates with a controller, which communicates with the strategy. This strategy also exchanges information with a strategist. A dedicated USDT strategy could be added separately to the controller, since the main strategy is concerned with USDC/DAI deposits due to the difference in actually borrowing the assets (assumed USDT insolvency risk).

## Safety
Users interact through the vault contract with the most critical strategy functions, the strategy communicates with the controller and with the strategist for critical functons. Thus, all exploits that could happen can be initiated:

- 1. Through external influences say through flash loans, which could have a negative impact while swapping/withdrawing. Note that due to the nature of polygon if slippages are set correctly harvest transactions shouldn't incur a serious loss due to the gas price for the reason that matic transactions are very cheap.

- 2. Through interactions with the vault contract.

- 3. Governance or strategist error.

### Detailed working principles

The fam3CRVStrategy contract operates either in the CONTRACTSTATEisincurve = true or CONTRACTSTATEisincurve = false state.
According to the state change, the harvest function calls at the end of the rewards claiming process either adjustLoanToValue with parameters
(slippages) or the overloaded variant (whichever one is considered to be overloaded) without parameters.

The version without parameters adjusts the loan to value for the USDT case, and the one with parameters adjust the Curve case.

Due to this, both the deposit (low level: takeDeposit) and withdraw (low level: takeWithdrawal) functions also direct the program flow into two directions depending on the value of CONTRACTSTATEisincurve variable. 

adjustLoanToValue works simply by checking if the LTV is higher or lower than the set MaxLTV and adjusting accordingly, while also depositing any extra
claimed rewards in either aave or curve.

The helper functions _withdrawUSDTFromCurve and _depositUSDTInCurve handle the curve logic return information necessary to mint shares/burn shares, which
is used for other calculations later.

The harvest functions first notes down the unclaimed rewards at a certain timestamp and keeps summing them until ping() from the strategist contract
isn't called and these values are consumed for APY estimations.

Attempting to calculate the APY we have found it approaches a value of 3.52% apy, since for some reason with our mainnet forking 
except at deposit no rewards accrue for the Curve pools / AAVE, the main test example displays this by depositing in the midst of a loop
and showing the moving average value (MAi = (Pricei + MAi-1)/2) jump. At the time of writing the curve pool base apy was floating around
3.44-3.48%, so we cannot confirm easily that this value which we have received, close to 3.52%, will follow the trend (so if it is a lucky error
or proper calculation, see APY calc method below).

### Yield

The yield can be calculated from AAVE and Curve information sources and will be approximately equal to them.
Slippages + state transitions can take toll on these, but due to low gas prices on MATIC we have given ourselves freedom to experiment
and tinker. 


## DOCS

### fam3CRVVault functions (IForceVault)

```
_amount - amount of shares to burn for withdrawal
_token - the token to be withdrawn
_recipient - the recipient of the withdrawn tokens
_userSlippage - the slippage the user would prefer
function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external returns (uint256);

_amount - the amount of tokens to withdraw
_token - the token to withdraw
function deposit(uint256 _amount, address _token) external returns (uint256);

_shares - the amount of shares to be recalculated into 
asset - the address of the asset
function balanceOfUser(uint256 shares, address asset) external view returns (uint256);
```

### BasicForceStrategyController functions (IForceStrategyController)

```
as above:
function deposit(uint256 _amount, address _token) external returns (uint256);
function withdraw(uint256 _amount, address _token, address _recipient, uint256 _userSlippage) external returns (uint256)

_tokenIndexer - the address the strategy is to be found by 
_strategist - set the strategist of this strategy
function setStrategyStrategist(address _tokenIndexer, address _strategist) external;

(both must be called, params self expl)
function approveStrategy(address _token, address _strategy) external;
function setStrategy(address _token, address _strategy) external;
```


## Team Members

h-ivor aka friΞd#8371 (on discord) = wrote the smart contracts and js scripts / tests
0xchampi = sidekick who found the bounty, offered mental support and attempted to set up a frontend xD

