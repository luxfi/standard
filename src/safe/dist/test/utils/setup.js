"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deployContract = exports.compile = exports.getDelegateCaller = exports.getSafeProxyRuntimeCode = exports.getCompatFallbackHandler = exports.getTokenCallbackHandler = exports.getSafeWithSingleton = exports.getSafeWithOwners = exports.getSafeTemplate = exports.getMock = exports.safeMigrationContract = exports.migrationContract = exports.getCreateCall = exports.getMultiSendCallOnly = exports.getMultiSend = exports.getSimulateTxAccessor = exports.getFactoryAt = exports.getFactory = exports.getFactoryContract = exports.getSafeSingletonAt = exports.getSafeSingletonContractFactoryFromEnvVariable = exports.getSafeL2SingletonContractFactory = exports.getSafeL2SingletonContract = exports.getSafeSingletonContract = exports.getSafeSingletonContractFactory = exports.getSafeSingleton = exports.compatFallbackHandlerContract = exports.compatFallbackHandlerDeployment = exports.defaultTokenCallbackHandlerContract = exports.defaultTokenCallbackHandlerDeployment = void 0;
const hardhat_1 = __importStar(require("hardhat"));
const ethers_1 = require("ethers");
const constants_1 = require("@ethersproject/constants");
const solc_1 = __importDefault(require("solc"));
const execution_1 = require("../../src/utils/execution");
const config_1 = require("./config");
const numbers_1 = require("./numbers");
const defaultTokenCallbackHandlerDeployment = async () => {
    return await hardhat_1.deployments.get("TokenCallbackHandler");
};
exports.defaultTokenCallbackHandlerDeployment = defaultTokenCallbackHandlerDeployment;
const defaultTokenCallbackHandlerContract = async () => {
    return await hardhat_1.default.ethers.getContractFactory("TokenCallbackHandler");
};
exports.defaultTokenCallbackHandlerContract = defaultTokenCallbackHandlerContract;
const compatFallbackHandlerDeployment = async () => {
    return await hardhat_1.deployments.get("CompatibilityFallbackHandler");
};
exports.compatFallbackHandlerDeployment = compatFallbackHandlerDeployment;
const compatFallbackHandlerContract = async () => {
    return await hardhat_1.default.ethers.getContractFactory("CompatibilityFallbackHandler");
};
exports.compatFallbackHandlerContract = compatFallbackHandlerContract;
const getSafeSingleton = async () => {
    const SafeDeployment = await hardhat_1.deployments.get((0, config_1.safeContractUnderTest)());
    const Safe = await hardhat_1.default.ethers.getContractAt((0, config_1.safeContractUnderTest)(), SafeDeployment.address);
    return Safe;
};
exports.getSafeSingleton = getSafeSingleton;
const getSafeSingletonContractFactory = async () => {
    const safeSingleton = await hardhat_1.default.ethers.getContractFactory("Safe");
    return safeSingleton;
};
exports.getSafeSingletonContractFactory = getSafeSingletonContractFactory;
const getSafeSingletonContract = async () => {
    const safeSingletonDeployment = await hardhat_1.deployments.get("Safe");
    const Safe = await hardhat_1.default.ethers.getContractAt("Safe", safeSingletonDeployment.address);
    return Safe;
};
exports.getSafeSingletonContract = getSafeSingletonContract;
const getSafeL2SingletonContract = async () => {
    const safeSingletonDeployment = await hardhat_1.deployments.get("SafeL2");
    const Safe = await hardhat_1.default.ethers.getContractAt("SafeL2", safeSingletonDeployment.address);
    return Safe;
};
exports.getSafeL2SingletonContract = getSafeL2SingletonContract;
const getSafeL2SingletonContractFactory = async () => {
    const safeSingleton = await hardhat_1.default.ethers.getContractFactory("SafeL2");
    return safeSingleton;
};
exports.getSafeL2SingletonContractFactory = getSafeL2SingletonContractFactory;
const getSafeSingletonContractFactoryFromEnvVariable = async () => {
    if ((0, config_1.safeContractUnderTest)() === "SafeL2") {
        return await (0, exports.getSafeL2SingletonContractFactory)();
    }
    return await (0, exports.getSafeSingletonContractFactory)();
};
exports.getSafeSingletonContractFactoryFromEnvVariable = getSafeSingletonContractFactoryFromEnvVariable;
const getSafeSingletonAt = async (address) => {
    const safe = await hardhat_1.default.ethers.getContractAt((0, config_1.safeContractUnderTest)(), address);
    return safe;
};
exports.getSafeSingletonAt = getSafeSingletonAt;
const getFactoryContract = async () => {
    const factory = await hardhat_1.default.ethers.getContractFactory("SafeProxyFactory");
    return factory;
};
exports.getFactoryContract = getFactoryContract;
const getFactory = async () => {
    const FactoryDeployment = await hardhat_1.deployments.get("SafeProxyFactory");
    const Factory = await hardhat_1.default.ethers.getContractAt("SafeProxyFactory", FactoryDeployment.address);
    return Factory;
};
exports.getFactory = getFactory;
const getFactoryAt = async (address) => {
    const Factory = await hardhat_1.default.ethers.getContractAt("SafeProxyFactory", address);
    return Factory;
};
exports.getFactoryAt = getFactoryAt;
const getSimulateTxAccessor = async () => {
    const SimulateTxAccessorDeployment = await hardhat_1.deployments.get("SimulateTxAccessor");
    const SimulateTxAccessor = await hardhat_1.default.ethers.getContractAt("SimulateTxAccessor", SimulateTxAccessorDeployment.address);
    return SimulateTxAccessor;
};
exports.getSimulateTxAccessor = getSimulateTxAccessor;
const getMultiSend = async () => {
    const MultiSendDeployment = await hardhat_1.deployments.get("MultiSend");
    const MultiSend = await hardhat_1.default.ethers.getContractAt("MultiSend", MultiSendDeployment.address);
    return MultiSend;
};
exports.getMultiSend = getMultiSend;
const getMultiSendCallOnly = async () => {
    const MultiSendDeployment = await hardhat_1.deployments.get("MultiSendCallOnly");
    const MultiSend = await hardhat_1.default.ethers.getContractAt("MultiSendCallOnly", MultiSendDeployment.address);
    return MultiSend;
};
exports.getMultiSendCallOnly = getMultiSendCallOnly;
const getCreateCall = async () => {
    const CreateCallDeployment = await hardhat_1.deployments.get("CreateCall");
    const CreateCall = await hardhat_1.default.ethers.getContractAt("CreateCall", CreateCallDeployment.address);
    return CreateCall;
};
exports.getCreateCall = getCreateCall;
const migrationContract = async () => {
    return await hardhat_1.default.ethers.getContractFactory("Migration");
};
exports.migrationContract = migrationContract;
const safeMigrationContract = async () => {
    const SafeMigrationDeployment = await hardhat_1.deployments.get("SafeMigration");
    const SafeMigration = await hardhat_1.default.ethers.getContractAt("SafeMigration", SafeMigrationDeployment.address);
    return SafeMigration;
};
exports.safeMigrationContract = safeMigrationContract;
const getMock = async () => {
    const Mock = await hardhat_1.default.ethers.getContractFactory("MockContract");
    return await Mock.deploy();
};
exports.getMock = getMock;
const getSafeTemplate = async (saltNumber = (0, numbers_1.getRandomIntAsString)()) => {
    const singleton = await (0, exports.getSafeSingleton)();
    const singletonAddress = await singleton.getAddress();
    const factory = await (0, exports.getFactory)();
    const template = await factory.createProxyWithNonce.staticCall(singletonAddress, "0x", saltNumber);
    await factory.createProxyWithNonce(singletonAddress, "0x", saltNumber).then((tx) => tx.wait());
    const Safe = await (0, exports.getSafeSingletonContractFactoryFromEnvVariable)();
    return Safe.attach(template);
};
exports.getSafeTemplate = getSafeTemplate;
const getSafeWithOwners = async (safe) => {
    const { owners, threshold = owners.length, to = constants_1.AddressZero, data = "0x", fallbackHandler = constants_1.AddressZero, logGasUsage = false, saltNumber = (0, numbers_1.getRandomIntAsString)(), } = safe;
    const template = await (0, exports.getSafeTemplate)(saltNumber);
    await (0, execution_1.logGas)(`Setup Safe with ${owners.length} owner(s)${fallbackHandler && fallbackHandler !== constants_1.AddressZero ? " and fallback handler" : ""}`, template.setup(owners, threshold, to, data, fallbackHandler, constants_1.AddressZero, 0, constants_1.AddressZero), !logGasUsage);
    return template;
};
exports.getSafeWithOwners = getSafeWithOwners;
const getSafeWithSingleton = async (singleton, owners, saltNumber = (0, numbers_1.getRandomIntAsString)()) => {
    const factory = await (0, exports.getFactory)();
    const singletonAddress = await singleton.getAddress();
    const template = await factory.createProxyWithNonce.staticCall(singletonAddress, "0x", saltNumber);
    await factory.createProxyWithNonce(singletonAddress, "0x", saltNumber).then((tx) => tx.wait());
    const safeProxy = singleton.attach(template);
    await safeProxy.setup(owners, owners.length, constants_1.AddressZero, "0x", constants_1.AddressZero, constants_1.AddressZero, 0, constants_1.AddressZero);
    return safeProxy;
};
exports.getSafeWithSingleton = getSafeWithSingleton;
const getTokenCallbackHandler = async (address) => {
    const tokenCallbackHandler = await hardhat_1.default.ethers.getContractAt("TokenCallbackHandler", address || (await (0, exports.defaultTokenCallbackHandlerDeployment)()).address);
    return tokenCallbackHandler;
};
exports.getTokenCallbackHandler = getTokenCallbackHandler;
const getCompatFallbackHandler = async (address) => {
    const fallbackHandler = await hardhat_1.default.ethers.getContractAt("CompatibilityFallbackHandler", address || (await (0, exports.compatFallbackHandlerDeployment)()).address);
    return fallbackHandler;
};
exports.getCompatFallbackHandler = getCompatFallbackHandler;
const getSafeProxyRuntimeCode = async () => {
    const proxyArtifact = await hardhat_1.default.artifacts.readArtifact("SafeProxy");
    return proxyArtifact.deployedBytecode;
};
exports.getSafeProxyRuntimeCode = getSafeProxyRuntimeCode;
const getDelegateCaller = async () => {
    const DelegateCaller = await hardhat_1.default.ethers.getContractFactory("DelegateCaller");
    return await DelegateCaller.deploy();
};
exports.getDelegateCaller = getDelegateCaller;
const compile = async (source) => {
    const input = JSON.stringify({
        language: "Solidity",
        settings: {
            outputSelection: {
                "*": {
                    "*": ["abi", "evm.bytecode"],
                },
            },
        },
        sources: {
            "tmp.sol": {
                content: source,
            },
        },
    });
    const solcData = await solc_1.default.compile(input);
    const output = JSON.parse(solcData);
    if (!output["contracts"]) {
        console.log(output);
        throw Error("Could not compile contract");
    }
    const fileOutput = output["contracts"]["tmp.sol"];
    const contractOutput = fileOutput[Object.keys(fileOutput)[0]];
    const abi = contractOutput["abi"];
    const data = "0x" + contractOutput["evm"]["bytecode"]["object"];
    return {
        data: data,
        interface: abi,
    };
};
exports.compile = compile;
const deployContract = async (deployer, source) => {
    const output = await (0, exports.compile)(source);
    const transaction = await deployer.sendTransaction({ data: output.data, gasLimit: 6000000 });
    const receipt = await transaction.wait();
    if (!receipt?.contractAddress) {
        throw Error("Could not deploy contract");
    }
    return new ethers_1.Contract(receipt.contractAddress, output.interface, deployer);
};
exports.deployContract = deployContract;
