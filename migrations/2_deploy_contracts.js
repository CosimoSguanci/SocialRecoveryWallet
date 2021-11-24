var SocialRecoveryWallet= artifacts.require("SocialRecoveryWallet");

module.exports = function(deployer) {
    const guardians = ["0xf45df42b5796d1f462c88b50c55f3e5b3e8b8146b314cb6bdb8035d9446e0074", "0xa2047c42436e0fc4f226985e4ae3850e58ce802cfdf1aeae76b447e9b1b17c87"]; // 0x502... 0xf89...
    deployer.deploy(SocialRecoveryWallet,"0x9e4cbb7be000e2be521092811ce79555618b1c29", guardians, [], 1,2,1);
};