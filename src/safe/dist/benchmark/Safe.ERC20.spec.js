"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const chai_1 = require("chai");
const hardhat_1 = require("hardhat");
const execution_1 = require("../src/utils/execution");
const setup_1 = require("./utils/setup");
(0, setup_1.benchmark)("ERC20", async () => {
    const [, , , , user5] = await hardhat_1.ethers.getSigners();
    return [
        {
            name: "transfer",
            prepare: async (contracts, target, nonce) => {
                const token = contracts.additions.token;
                const tokenAddress = await token.getAddress();
                await token.transfer(target, 1000);
                const data = token.interface.encodeFunctionData("transfer", [user5.address, 500]);
                return (0, execution_1.buildSafeTransaction)({ to: tokenAddress, data, safeTxGas: 1000000, nonce });
            },
            after: async (contracts) => {
                (0, chai_1.expect)(await contracts.additions.token.balanceOf(user5.address)).to.eq(500n);
            },
            fixture: async () => {
                const tokenFactory = await hardhat_1.ethers.getContractFactory("ERC20Token");
                return {
                    token: await tokenFactory.deploy(),
                };
            },
        },
    ];
});
