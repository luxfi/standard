const LamportLib = artifacts.require("LamportLib");
const LamportTest = artifacts.require("LamportTest");
const LamportTest2 = artifacts.require("LamportTest2");

const local_test = false
const ropstenGas = 7000000
const rinkebyGas = 10000000
const standardGas = local_test ? ropstenGas : rinkebyGas;

const stdOptions = {
    gas: standardGas, 
    overwrite: true,
}

module.exports = async function (deployer) {
    await deployer.deploy(LamportLib, stdOptions);
    await deployer.link(LamportLib, LamportTest)
    await deployer.deploy(LamportTest, stdOptions)

    await deployer.link(LamportLib, LamportTest2)
    await deployer.deploy(LamportTest2, stdOptions)
}