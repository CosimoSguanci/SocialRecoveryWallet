const SocialRecoveryWallet = artifacts.require("SocialRecoveryWallet");

contract("SocialRecoveryWalletDeployment", async accounts => {

  it('Should deploy smart contract properly', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    assert(socialRecoveryWalletNew.address != '');
  });

  it('Should fail when changeSpenderRequest is not called by a Guardian', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    try {
      await socialRecoveryWalletNew.submitChangeSpenderRequest("0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5", { from: "0x96121a4f513ab387f4fb60555d9940d54fd9c710" });
    } catch (e) {
      assert(e.reason == 'not guardian')
    }
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() != "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5");
  });


  it('Should change spender correctly when changeSpenderRequest is called by a Guardian and threshold is respected', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    await socialRecoveryWalletNew.submitChangeSpenderRequest("0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5", { from: "0xf8917156d89939248bc14fa3f1066f3dc64b29e1" });
    try {
      await socialRecoveryWalletNew.confirmChangeSpenderRequest(0, { from: "0x50209fde76c6af7e498a83a0814c1d57dd74b0ba" });
    } catch (e) {
      assert(e.reason == 'not guardian')
    }
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() == "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5");
  });


  it('Should not change spender when changeSpenderRequest is called by a Guardian but threshold is not respected', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    await socialRecoveryWalletNew.submitChangeSpenderRequest("0x87a8ece4248732aeda6418d40ff7145cd2b17692", { from: "0xf8917156d89939248bc14fa3f1066f3dc64b29e1" });
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() != "0x87a8ece4248732aeda6418d40ff7145cd2b17692");
  });

  it('Should fail when submitTransaction is not called by the spender', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address)
    try {
      await socialRecoveryWalletNew.submitTransaction("0x87a8ece4248732aeda6418d40ff7145cd2b17692", 10000000000, '0x', { from: "0x87a8ece4248732aeda6418d40ff7145cd2b17692" });
    } catch (e) {
      assert(e.reason == 'not spender')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance);
  });

  it('Should fail when submitTransaction is called by the spender but is not confirmed by the guardians', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();

    let accounts = await web3.eth.getAccounts();
    await web3.eth.sendTransaction({ to: socialRecoveryWalletNew.address, from: accounts[0], value: web3.utils.toWei('1') });

    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address);

    await socialRecoveryWalletNew.submitTransaction("0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5", 10000000000, '0x', { from: "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5" });
    try {
      await socialRecoveryWalletNew.executeTransaction(0, { from: "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5" });
    } catch (e) {
      assert(e.reason == 'cannot execute tx')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance);
  });



  it('Should execute transaction when submitTransaction is called by the spender and is confirmed by the guardians', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();

    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address);

    await socialRecoveryWalletNew.submitTransaction("0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5", 10000000000, '0x', { from: "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5" });
    await socialRecoveryWalletNew.confirmTransaction(1, { from: "0xf8917156d89939248bc14fa3f1066f3dc64b29e1" });

    try {
      await socialRecoveryWalletNew.executeTransaction(1, { from: "0x2134f44b5d3d34f6fc35f47604aca51314c8e3a5" });
    } catch (e) {
      assert(e.reason == 'cannot execute tx')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance - 10000000000);
  });
});