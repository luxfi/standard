"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.safeContractUnderTest = void 0;
const safeContractUnderTest = () => {
    switch (process.env.SAFE_CONTRACT_UNDER_TEST) {
        case "SafeL2":
            return "SafeL2";
        default:
            return "Safe";
    }
};
exports.safeContractUnderTest = safeContractUnderTest;
