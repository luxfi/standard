"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const chai_1 = require("chai");
const hardhat_1 = require("hardhat");
const execution_1 = require("../src/utils/execution");
const setup_1 = require("./utils/setup");
(0, setup_1.benchmark)("ERC1155", async () => {
    const [, , , , user5] = await hardhat_1.ethers.getSigners();
    return [
        {
            name: "transfer",
            prepare: async (contracts, target, nonce) => {
                const token = contracts.additions.token;
                const tokenAddress = await token.getAddress();
                await token.mint(target, 23, 1337, "0x");
                const data = token.interface.encodeFunctionData("safeTransferFrom", [target, user5.address, 23, 500, "0x"]);
                return (0, execution_1.buildSafeTransaction)({ to: tokenAddress, data, safeTxGas: 1000000, nonce });
            },
            after: async (contracts) => {
                (0, chai_1.expect)(await contracts.additions.token.balanceOf(user5.address, 23)).to.eq(500n);
            },
            fixture: async () => {
                const tokenFactory = await hardhat_1.ethers.getContractFactory("ERC1155Token");
                return {
                    token: await tokenFactory.deploy(),
                };
            },
        },
    ];
});
