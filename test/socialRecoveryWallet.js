const SocialRecoveryWallet = artifacts.require("SocialRecoveryWallet");

contract("SocialRecoveryWalletDeployment", async accounts => {

  it('Should deploy smart contract properly', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    console.log(socialRecoveryWalletNew.address);
    assert(socialRecoveryWalletNew.address != '');
  });

  it('Should change spender correctly when changeSpenderRequest is called by a Guardian and threshold is respected', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    await socialRecoveryWalletNew.submitChangeSpenderRequest("0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5", { from: "0xf8917156d89939248bc14fa3f1066f3dc64b29e1" });
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() == "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5".toLowerCase());
  });
});