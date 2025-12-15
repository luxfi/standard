"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const setup_1 = require("./utils/setup");
const contractSetup = (0, setup_1.setupBenchmarkContracts)(undefined, true);
describe("Safe", () => {
    it("creation", async () => {
        await contractSetup();
    });
});
