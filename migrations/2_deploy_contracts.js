var SocialRecoveryWallet= artifacts.require("SocialRecoveryWallet");

module.exports = function(deployer) {
    const guardians = ["0x24d6fba577827a018a8a666eb04f1f0eb30559848ae51ceda426589d467e4527", "0x85c65152356d9cd1e88049680e1ebeeb4f7c3c89632795446af7fbe667b306e0"]; // 0x502... 0xf89...
    deployer.deploy(SocialRecoveryWallet,"0x96121a4f513ab387f4fb60555d9940d54fd9c710", guardians, [], 1,1,1);
};