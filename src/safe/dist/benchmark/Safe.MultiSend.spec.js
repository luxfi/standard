"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const chai_1 = require("chai");
const hardhat_1 = require("hardhat");
const setup_1 = require("./utils/setup");
const multisend_1 = require("../src/utils/multisend");
(0, setup_1.benchmark)("MultiSend", async () => {
    const [, , , , user5] = await hardhat_1.ethers.getSigners();
    return [
        {
            name: "multiple ERC20 transfers",
            prepare: async (contracts, target, nonce) => {
                const token = contracts.additions.token;
                const multiSend = contracts.additions.multiSend;
                await token.transfer(target, 1500);
                const transfer = {
                    to: await token.getAddress(),
                    value: 0,
                    data: token.interface.encodeFunctionData("transfer", [user5.address, 500]),
                    operation: 0,
                };
                return (0, multisend_1.buildMultiSendSafeTx)(multiSend, [...Array(3)].map(() => transfer), nonce);
            },
            after: async (contracts) => {
                (0, chai_1.expect)(await contracts.additions.token.balanceOf(user5.address)).to.eq(1500n);
            },
            fixture: async () => {
                const multiSendFactory = await hardhat_1.ethers.getContractFactory("MultiSend");
                const multiSend = await multiSendFactory.deploy();
                const guardFactory = await hardhat_1.ethers.getContractFactory("DelegateCallTransactionGuard");
                const tokenFactory = await hardhat_1.ethers.getContractFactory("ERC20Token");
                return {
                    multiSend,
                    guard: await guardFactory.deploy(multiSend),
                    token: await tokenFactory.deploy(),
                };
            },
        },
    ];
});
