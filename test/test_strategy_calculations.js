const { defaultAbiCoder } = require("@ethersproject/abi");
const testcases = require("@ethersproject/testcases");
const { expect, should } = require("chai");
const { ethers, network } = require("hardhat");
const { waffle } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
require("@ethersproject/bignumber");
const provider = waffle.provider;

describe("Test strategist calculations", function () {
  let testseed =
    "0x01f5bced59dec48e362f2c45b5de68b9fd6c92c6634f44d6d40aab69056506f0e35524a518034ddc1192e1deefacd32c1ed3e231231238ed8e7e54c49a5d0998";

  // self explanatory
  let strategyFactory;
  let strategyContract;

  // addresses which will interact
  let dore, mifa, sola, tido;

  let DAI = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
    USDC = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
    USDT = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
    MATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    WETH = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";

  before(async function () {
    [dore, mifa, sola, tido] = await ethers.getSigners();
    signerArray = [dore, mifa, sola, tido];

    strategyFactory = await ethers.getContractFactory("fam3CRVStrategy");
    strategistFactory = await ethers.getContractFactory("fam3CRVStrategist");

    strategyContract = await strategyFactory.deploy(
      dore.address,
      "0xd05e3E715d945B59290df0ae8eF85c1BdB684744",
      ethers.utils.parseEther("0.99"),
      ethers.utils.parseEther("0.99"),
      ethers.utils.parseEther("0.99")
    );

    strategistContract = await strategistFactory.deploy(
      strategyContract.address,
      dore.address,
      ethers.utils.parseEther("90000000"), // keep high while testing the turn it down
      ethers.utils.parseUnits("43200", "wei"),
      ethers.utils.parseUnits("720", "wei"),
      ethers.utils.parseEther("0.75")
    );

    await strategyContract.assignNewStrategist(strategistContract.address);

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });
    await network.provider.request({
      method: "evm_increaseTime",
      params: [50],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    await strategistContract.setInitialValues();

    let overrides = {
      gasLimit: ethers.utils.parseUnits("12450000", "wei"),
    };

    SushiswapRouter = await ethers.getContractAt(
      "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol:IUniswapV2Router02",
      "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506"
    );

    DAIContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      DAI
    );
    USDTContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      USDT
    );
    USDCContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      USDC
    );
    MATICContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      MATIC
    );
    WETHContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      WETH
    );

    CLPContract = await ethers.getContractAt(
      "/dependencies/interfaces/IERC20.sol:IERC20",
      "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171"
    );

    IncentivesController = await ethers.getContractAt(
      "@aave/protocol-v2/contracts/interfaces/IAaveIncentivesController.sol:IAaveIncentivesController",
      "0x357D51124f59836DeD84c8a1730D72B749d8BC23"
    );
  });

  describe("let's go", async () => {
    let overrides = {
      value: ethers.utils.parseEther("1000"),
    };

    let res;

    it("our wallet should swap for USDC", async () => {
      //await expect(
      //  ).to.changeEtherBalance(balanceBefore.sub(ethers.utils.parseEther("2")));

      await SushiswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens(
        ethers.utils.parseUnits("1000", "mwei"),
        [MATIC, USDC],
        dore.address,
        BigNumber.from("19000000000000"),
        overrides
      );

      res = await USDCContract.balanceOf(dore.address);

      console.log("USDC BALANCE: ", res.toString());
    });

    let sharesMinted;

    it("we should read out a first apy value based on the sole virtual price increase", async () => {
      await network.provider.request({
        method: "evm_mine",
        params: [],
      });
      await network.provider.request({
        method: "evm_increaseTime",
        params: [50],
      });
      await network.provider.request({
        method: "evm_mine",
        params: [],
      });

      await strategistContract.ping();

      const result = await strategistContract.calculateAPY(
        "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171",
        ethers.utils.parseUnits("43200", "wei"),
        ethers.utils.parseUnits("720", "wei")
      );

      console.log(result.toString());
    });

    it("should successfully deposit into vault (into curve)", async function () {
      await USDCContract.transfer(strategyContract.address, res);
      const depoTx = await strategyContract.takeDeposit(res, USDC);

      let { events } = await depoTx.wait();
      sharesMinted = events.find(({ event }) => event == "AssetDeposited").args
        .sharesMinted;

      let currentBalance = await strategyContract.balanceOfUser(
        sharesMinted,
        USDCContract.address
      );
      console.log("CURRENT DAI BALANCE: ", currentBalance.toString());
    });

    it("should test apy calculation and harvesting", async () => {
      await network.provider.request({
        method: "evm_mine",
        params: [],
      });
      await network.provider.request({
        method: "evm_increaseTime",
        params: [50],
      });
      await network.provider.request({
        method: "evm_mine",
        params: [],
      });
      await network.provider.request({
        method: "evm_mine",
        params: [],
      });

      await strategistContract.ping();
      const result = await strategistContract.calculateAPY(
        "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171",
        ethers.utils.parseUnits("43200", "wei"),
        ethers.utils.parseUnits("720", "wei")
      );

      console.log(result.toString());
    });

    it("should successfully withdraw from Curve", async () => {
      sharesMinted = sharesMinted.div("2");

      const withTx = await strategyContract.takeWithdraw(
        sharesMinted,
        USDC,
        dore.address,
        ethers.utils.parseEther("0.99")
      );

      console.log(
        "CURRENT ACCOUNT BALANCE: %s",
        (await USDCContract.balanceOf(dore.address)).toString()
      );
      let currentBalance = await strategyContract.balanceOfUser(
        sharesMinted,
        USDCContract.address
      );
      console.log(
        "CURRENT USDC BALANCE: ",
        await currentBalance.toString(),
        " ",
        await USDCContract.balanceOf(dore.address)
      );
    });

    it("should test apy calculation and harvesting", async () => {
      for (let i = 0; i < 50; i++) {
        await network.provider.request({
          method: "evm_mine",
          params: [],
        });
        await network.provider.request({
          method: "evm_increaseTime",
          params: [50],
        });
        await network.provider.request({
          method: "evm_mine",
          params: [],
        });
        await network.provider.request({
          method: "evm_mine",
          params: [],
        });

        if (i == 10) {
          await USDCContract.transfer(
            strategyContract.address,
            ethers.utils.parseUnits("200", "mwei")
          );
          const depoTx = await strategyContract.takeDeposit(
            ethers.utils.parseUnits("200", "mwei"),
            USDC
          );
        }

        await strategistContract.ping();
        const result = await strategistContract.calculateAPY(
          "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171",
          ethers.utils.parseUnits("43200", "wei"),
          ethers.utils.parseUnits("720", "wei")
        );

        console.log(result.toString());
      }
    });

    it("should try a contract state switch", async () => {
      await strategistContract.borrowInterestThresholdModify(
        ethers.utils.parseEther("10000000")
      );

      let LTV, FreeCollateral, Debt;
      [LTV, FreeCollateral, Debt] = await strategyContract.getDebtData();
      console.log(
        "LTV: ",
        LTV.toString(),
        " FREECOLLAT : ",
        FreeCollateral.toString(),
        " DEBT: ",
        Debt.toString()
      );

      await strategistContract.ping();

      [LTV, FreeCollateral, Debt] = await strategyContract.getDebtData();
      console.log(
        "LTV: ",
        LTV.toString(),
        " FREECOLLAT : ",
        FreeCollateral.toString(),
        " DEBT: ",
        Debt.toString()
      );

      console.log(
        (await strategyContract.calculateSushiTokenPrice(WETH, DAI)).toString()
      );
    });
  });

  it("should test apy calculation and harvesting", async () => {
    await network.provider.request({
      method: "evm_mine",
      params: [],
    });
    await network.provider.request({
      method: "evm_increaseTime",
      params: [50],
    });
    await network.provider.request({
      method: "evm_mine",
      params: [],
    });
    await network.provider.request({
      method: "evm_mine",
      params: [],
    });

    await strategistContract.ping();
    const result = await strategistContract.calculateAPY(
      "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171",
      ethers.utils.parseUnits("43200", "wei"),
      ethers.utils.parseUnits("720", "wei")
    );

    console.log(result.toString());
  });
});
