const { defaultAbiCoder } = require("@ethersproject/abi");
const testcases = require("@ethersproject/testcases");
const { expect, should } = require("chai");
const { ethers, network } = require("hardhat");
const { waffle } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
require("@ethersproject/bignumber");
const provider = waffle.provider;

describe("Test all contracts working together", () => {
  let strategyFactory;
  let strategyContract;
  let controllerFactory;
  let controllerContract;
  let vaultFactory;
  let vaultContract;
  let strategistFactory;
  let strategistContract;

  let dore, mifa, sola, tido;

  let DAI = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
    USDC = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
    USDT = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
    MATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    WETH = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";

  before(async () => {
    [dore, mifa, sola, tido] = await ethers.getSigners();

    signerArray = [dore, mifa, sola, tido];

    controllerFactory = await ethers.getContractFactory(
      "BasicForceStrategyController"
    );
    vaultFactory = await ethers.getContractFactory("fam3CRVVault");
    strategyFactory = await ethers.getContractFactory("fam3CRVStrategy");
    strategistFactory = await ethers.getContractFactory("fam3CRVStrategist");

    controllerContract = await controllerFactory.deploy(dore.address, DAI);

    vaultContract = await vaultFactory.deploy(controllerContract.address);

    let overrides = {
      gasLimit: ethers.utils.parseUnits("12450000", "wei"),
    };

    strategyContract = await strategyFactory.deploy(
      controllerContract.address,
      "0xd05e3E715d945B59290df0ae8eF85c1BdB684744",
      ethers.utils.parseEther("0.99"),
      ethers.utils.parseEther("0.99"),
      ethers.utils.parseEther("0.99"),
      overrides
    );

    strategistContract = await strategistFactory.deploy(
      strategyContract.address,
      dore.address,
      ethers.utils.parseEther("90000000"), // high value but we can turn it down
      ethers.utils.parseUnits("43200", "wei"),
      ethers.utils.parseUnits("720", "wei"),
      ethers.utils.parseEther("0.75")
    );

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
  });

  describe("Start of Tests", async () => {
    it("Controller should add vault and strategy", async () => {
      await controllerContract.setVault(USDC, vaultContract.address);
      await controllerContract.setVault(DAI, vaultContract.address);
      await controllerContract.approveStrategy(USDC, strategyContract.address);
      await controllerContract.approveStrategy(DAI, strategyContract.address);
      await controllerContract.setStrategy(DAI, strategyContract.address);
      await controllerContract.setStrategy(USDC, strategyContract.address);
    });

    it("Controller should setStrategist for Strategy successfully, and strategist should initialize values", async () => {
        await controllerContract.setStrategyStrategist(USDC, strategistContract.address);
        await controllerContract.setStrategyStrategist(DAI, strategistContract.address);
        await strategistContract.setInitialValues();
    });

    let res;

    it("our wallet should swap for USDC", async () => {
      let overrides = {
        value: ethers.utils.parseEther("1000"),
      };

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

    it("should deposit into vault", async () => {
        await USDCContract.approve(
          vaultContract.address,
          ethers.utils.parseEther("500000000")
        );
        await USDCContract.approve(
          controllerContract.address,
          ethers.utils.parseEther("500000000")
        );
      await expect(strategyContract.deposit(res, USDC)).to.be.reverted;
      await expect(controllerContract.deposit(res, USDC)).to.be.reverted;

      const depoTx = await vaultContract.deposit(res, USDC);
      let { events } = await depoTx.wait();
      sharesMinted = events.find(({ event }) => event == "FundsDeposited").args
        .sharesMinted;

      let currentBalance = await strategyContract.balanceOfUser(
        sharesMinted,
        USDCContract.address
      );
      console.log("CURRENT USDC BALANCE: ", currentBalance.toString());
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

    it("Should withdraw from curve and give back half of the balance", async () => {
      sharesMinted = sharesMinted.div("2");
      await expect(vaultContract.withdraw(sharesMinted, DAI, dore.address, ethers.utils.parseEther("0.99"))).to.be.reverted;
      const withTx = await vaultContract.withdraw(sharesMinted, USDC, dore.address, ethers.utils.parseEther("0.99"));

      let { events } = await withTx.wait();
      let sharesBurned = events.find(({ event }) => event == "FundsWithdrawn").args
        .sharesBurned;

       let fundsReceived = events.find(({ event }) => event == "FundsWithdrawn").args
        .fundsReceived;

      console.log("SHARES BURNED: ", sharesBurned.toString(), "FUNDS RECEIVED: ", fundsReceived.toString());
    });

    // apy is display as: apy%e25
  it("Iterate and calculate apy each step + deposit ", async () => {
    for (let i = 0; i < 15; i++) {
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
        const depoTx = await vaultContract.deposit(
          ethers.utils.parseUnits("200", "mwei"),
          USDC
        );
      }

      await strategistContract.ping();
      const result = await strategistContract.calculateAPY(
        "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171", // curve lp
        ethers.utils.parseUnits("43200", "wei"),
        ethers.utils.parseUnits("720", "wei")
      );

      console.log(result.toString());
    }
  });

    it("Should withdraw everything and tell me my balance", async () =>  {
      const withTx = await vaultContract.withdraw(await vaultContract.balanceOf(dore.address), USDC, dore.address, ethers.utils.parseEther("0.99"));
      let { events } = await withTx.wait();
      let sharesBurned = events.find(({ event }) => event == "FundsWithdrawn").args
        .sharesBurned;
       let fundsReceived = events.find(({ event }) => event == "FundsWithdrawn").args
        .fundsReceived;
      console.log("SHARES BURNED: ", sharesBurned.toString(), "FUNDS RECEIVED: ", fundsReceived.toString());
    });


  });
});
