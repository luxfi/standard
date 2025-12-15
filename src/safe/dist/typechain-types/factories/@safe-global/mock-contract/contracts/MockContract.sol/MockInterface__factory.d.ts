import { type ContractRunner } from "ethers";
import type { MockInterface, MockInterfaceInterface } from "../../../../../@safe-global/mock-contract/contracts/MockContract.sol/MockInterface";
export declare class MockInterface__factory {
    static readonly abi: readonly [{
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "response";
            readonly type: "bytes";
        }];
        readonly name: "givenAnyReturn";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "address";
            readonly name: "response";
            readonly type: "address";
        }];
        readonly name: "givenAnyReturnAddress";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bool";
            readonly name: "response";
            readonly type: "bool";
        }];
        readonly name: "givenAnyReturnBool";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "response";
            readonly type: "uint256";
        }];
        readonly name: "givenAnyReturnUint";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "givenAnyRevert";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "string";
            readonly name: "message";
            readonly type: "string";
        }];
        readonly name: "givenAnyRevertWithMessage";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "givenAnyRunOutOfGas";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "bytes";
            readonly name: "response";
            readonly type: "bytes";
        }];
        readonly name: "givenCalldataReturn";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "address";
            readonly name: "response";
            readonly type: "address";
        }];
        readonly name: "givenCalldataReturnAddress";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "bool";
            readonly name: "response";
            readonly type: "bool";
        }];
        readonly name: "givenCalldataReturnBool";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "bytes32";
            readonly name: "response";
            readonly type: "bytes32";
        }];
        readonly name: "givenCalldataReturnBytes32";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "uint256";
            readonly name: "response";
            readonly type: "uint256";
        }];
        readonly name: "givenCalldataReturnUint";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }];
        readonly name: "givenCalldataRevert";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }, {
            readonly internalType: "string";
            readonly name: "message";
            readonly type: "string";
        }];
        readonly name: "givenCalldataRevertWithMessage";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }];
        readonly name: "givenCalldataRunOutOfGas";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "bytes";
            readonly name: "response";
            readonly type: "bytes";
        }];
        readonly name: "givenMethodReturn";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "address";
            readonly name: "response";
            readonly type: "address";
        }];
        readonly name: "givenMethodReturnAddress";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "bool";
            readonly name: "response";
            readonly type: "bool";
        }];
        readonly name: "givenMethodReturnBool";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "bytes32";
            readonly name: "response";
            readonly type: "bytes32";
        }];
        readonly name: "givenMethodReturnBytes32";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "uint256";
            readonly name: "response";
            readonly type: "uint256";
        }];
        readonly name: "givenMethodReturnUint";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }];
        readonly name: "givenMethodRevert";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }, {
            readonly internalType: "string";
            readonly name: "message";
            readonly type: "string";
        }];
        readonly name: "givenMethodRevertWithMessage";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }];
        readonly name: "givenMethodRunOutOfGas";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "invocationCount";
        readonly outputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "call";
            readonly type: "bytes";
        }];
        readonly name: "invocationCountForCalldata";
        readonly outputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [{
            readonly internalType: "bytes";
            readonly name: "method";
            readonly type: "bytes";
        }];
        readonly name: "invocationCountForMethod";
        readonly outputs: readonly [{
            readonly internalType: "uint256";
            readonly name: "";
            readonly type: "uint256";
        }];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }, {
        readonly inputs: readonly [];
        readonly name: "reset";
        readonly outputs: readonly [];
        readonly stateMutability: "nonpayable";
        readonly type: "function";
    }];
    static createInterface(): MockInterfaceInterface;
    static connect(address: string, runner?: ContractRunner | null): MockInterface;
}
