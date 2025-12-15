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
Object.defineProperty(exports, "__esModule", { value: true });
exports.benchmark = exports.setupBenchmarkContracts = exports.configs = void 0;
const chai_1 = require("chai");
const hardhat_1 = __importStar(require("hardhat"));
const setup_1 = require("../../test/utils/setup");
const execution_1 = require("../../src/utils/execution");
const constants_1 = require("@ethersproject/constants");
const generateTarget = async (owners, threshold, guardAddress, logGasUsage, saltNumber) => {
    const fallbackHandler = await (0, setup_1.getTokenCallbackHandler)();
    const fallbackHandlerAddress = await fallbackHandler.getAddress();
    const signers = (await hardhat_1.ethers.getSigners()).slice(0, owners);
    const safe = await (0, setup_1.getSafeWithOwners)({
        owners: signers.map((owner) => owner.address),
        threshold,
        fallbackHandler: fallbackHandlerAddress,
        logGasUsage,
        saltNumber,
    });
    await (0, execution_1.executeContractCallWithSigners)(safe, safe, "setGuard", [guardAddress], signers);
    return safe;
};
exports.configs = [
    { name: "single owner", signers: 1, threshold: 1 },
    { name: "single owner and guard", signers: 1, threshold: 1, useGuard: true },
    { name: "2 out of 2", signers: 2, threshold: 2 },
    { name: "3 out of 3", signers: 3, threshold: 3 },
    { name: "3 out of 5", signers: 5, threshold: 3 },
];
const setupBenchmarkContracts = (benchmarkFixture, logGasUsage) => {
    return hardhat_1.deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const additions = benchmarkFixture ? await benchmarkFixture() : undefined;
        const guardFactory = await hardhat_1.default.ethers.getContractFactory("DelegateCallTransactionGuard");
        const guard = additions?.guard ?? (await guardFactory.deploy(constants_1.AddressZero));
        const guardAddress = await guard.getAddress();
        const targets = [];
        for (const config of exports.configs) {
            targets.push(await generateTarget(config.signers, config.threshold, config.useGuard ? guardAddress : constants_1.AddressZero, logGasUsage, hardhat_1.ethers.id(config.name)));
        }
        return { targets, additions };
    });
};
exports.setupBenchmarkContracts = setupBenchmarkContracts;
const benchmark = async (topic, benchmarks) => {
    const setupBenchmarks = await benchmarks();
    for (const benchmark of setupBenchmarks) {
        const { name, prepare, after, fixture } = benchmark;
        const contractSetup = (0, exports.setupBenchmarkContracts)(fixture);
        describe(`${topic} - ${name}`, function () {
            it("with an EOA", async function () {
                const contracts = await contractSetup();
                const [, , , , , user6] = await hardhat_1.ethers.getSigners();
                const tx = await prepare(contracts, user6.address, 0);
                if (tx.operation !== 0) {
                    this.skip();
                }
                await (0, execution_1.logGas)(name, user6.sendTransaction({
                    to: tx.to,
                    value: tx.value,
                    data: tx.data,
                }));
                if (after)
                    await after(contracts);
            });
            for (const i in exports.configs) {
                const config = exports.configs[i];
                it(`with a ${config.name} Safe`, async () => {
                    const contracts = await contractSetup();
                    const target = contracts.targets[i];
                    const targetAddress = await target.getAddress();
                    const nonce = await target.nonce();
                    const tx = await prepare(contracts, targetAddress, nonce);
                    const threshold = await target.getThreshold();
                    const signers = await hardhat_1.ethers.getSigners();
                    const sigs = await Promise.all(signers.slice(0, Number(threshold)).map(async (signer) => {
                        const targetAddress = await target.getAddress();
                        return await (0, execution_1.safeSignTypedData)(signer, targetAddress, tx);
                    }));
                    await (0, chai_1.expect)((0, execution_1.logGas)(name, (0, execution_1.executeTx)(target, tx, sigs))).to.emit(target, "ExecutionSuccess");
                    if (after)
                        await after(contracts);
                });
            }
        });
    }
};
exports.benchmark = benchmark;
