const SocialRecoveryWallet = artifacts.require("SocialRecoveryWallet");

contract("SocialRecoveryWalletDeployment", async accounts => {

  it('Should deploy smart contract properly', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    assert(socialRecoveryWalletNew.address != '');
  });

  it('Should fail when changeSpenderRequest is not called by a Guardian', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    try{
      await socialRecoveryWalletNew.submitChangeSpenderRequest("0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261",{from: "0x9e4cbb7be000e2be521092811ce79555618b1c29"});
    }catch(e){
      assert(e.reason == 'not guardian')
    }
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() != "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261");
  });


  it('Should change spender correctly when changeSpenderRequest is called by a Guardian and threshold is respected', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    await socialRecoveryWalletNew.submitChangeSpenderRequest("0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261", { from: "0xafd66fa7dc129ce79cb04456821534d6d2c9d52c" });
    try{
      await socialRecoveryWalletNew.confirmChangeSpenderRequest(0, { from: "0xa432cf8da8be9172dc59ea53ea386966837e0c2a" });
    }catch(e){
      assert(e.reason == 'not guardian')
    }
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() == "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261");
  });


  it('Should not change spender when changeSpenderRequest is called by a Guardian but threshold is not respected', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    await socialRecoveryWalletNew.submitChangeSpenderRequest("0x51d36bc4670fc6035b3b700abf904ff8b279405e", { from: "0xafd66fa7dc129ce79cb04456821534d6d2c9d52c" });
    assert((await socialRecoveryWalletNew.spender.call()).toLowerCase() != "0x51d36bc4670fc6035b3b700abf904ff8b279405e");
  });

  it('Should fail when submitTransaction is not called by the spender', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address)
    try{
      await socialRecoveryWalletNew.submitTransaction("0x51d36bc4670fc6035b3b700abf904ff8b279405e", 10000000000, '0x',{from: "0x51d36bc4670fc6035b3b700abf904ff8b279405e"});
    }catch(e){
      assert(e.reason == 'not spender')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance);
  });
  
  it('Should fail when submitTransaction is called by the spender but is not confirmed by the guardians', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    
    let accounts = await web3.eth.getAccounts();
    await web3.eth.sendTransaction({to:socialRecoveryWalletNew.address, from:accounts[0], value: web3.utils.toWei('1')});
    
    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address);
    
    await socialRecoveryWalletNew.submitTransaction("0x51d36bc4670fc6035b3b700abf904ff8b279405e", 10000000000, '0x',{from: "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261"});
    try{
      await socialRecoveryWalletNew.executeTransaction(0,{from: "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261"});
    }catch(e){
      assert(e.reason == 'cannot execute tx')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance);
  });



  it('Should execute transaction when submitTransaction is called by the spender and is confirmed by the guardians', async () => {
    const socialRecoveryWalletNew = await SocialRecoveryWallet.deployed();
    
    let accounts = await web3.eth.getAccounts();
    let before_balance = await web3.eth.getBalance(socialRecoveryWalletNew.address);
    console.log(before_balance);
    
    await socialRecoveryWalletNew.submitTransaction("0x51d36bc4670fc6035b3b700abf904ff8b279405e", 10000000000, '0x',{from: "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261"});
    await socialRecoveryWalletNew.confirmTransaction(1,{from: "0xafd66fa7dc129ce79cb04456821534d6d2c9d52c"});

    try{
      await socialRecoveryWalletNew.executeTransaction(1,{from: "0x5186b30bf4c723fdc6aad80cdbfe95a0efc33261"});
    }catch(e){
      console.log(e.reason);
      assert(e.reason == 'cannot execute tx')
    }
    assert((await web3.eth.getBalance(socialRecoveryWalletNew.address)) == before_balance-10000000000);
  });


});