import type { BaseContract, BytesLike, FunctionFragment, Result, Interface, EventFragment, ContractRunner, ContractMethod, Listener } from "ethers";
import type { TypedContractEvent, TypedDeferredTopicFilter, TypedEventLog, TypedLogDescription, TypedListener, TypedContractMethod } from "../../common";
export interface SignMessageLibInterface extends Interface {
    getFunction(nameOrSignature: "getMessageHash" | "signMessage"): FunctionFragment;
    getEvent(nameOrSignatureOrTopic: "SignMsg"): EventFragment;
    encodeFunctionData(functionFragment: "getMessageHash", values: [BytesLike]): string;
    encodeFunctionData(functionFragment: "signMessage", values: [BytesLike]): string;
    decodeFunctionResult(functionFragment: "getMessageHash", data: BytesLike): Result;
    decodeFunctionResult(functionFragment: "signMessage", data: BytesLike): Result;
}
export declare namespace SignMsgEvent {
    type InputTuple = [msgHash: BytesLike];
    type OutputTuple = [msgHash: string];
    interface OutputObject {
        msgHash: string;
    }
    type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
    type Filter = TypedDeferredTopicFilter<Event>;
    type Log = TypedEventLog<Event>;
    type LogDescription = TypedLogDescription<Event>;
}
export interface SignMessageLib extends BaseContract {
    connect(runner?: ContractRunner | null): SignMessageLib;
    waitForDeployment(): Promise<this>;
    interface: SignMessageLibInterface;
    queryFilter<TCEvent extends TypedContractEvent>(event: TCEvent, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    queryFilter<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    on<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    on<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    listeners<TCEvent extends TypedContractEvent>(event: TCEvent): Promise<Array<TypedListener<TCEvent>>>;
    listeners(eventName?: string): Promise<Array<Listener>>;
    removeAllListeners<TCEvent extends TypedContractEvent>(event?: TCEvent): Promise<this>;
    getMessageHash: TypedContractMethod<[message: BytesLike], [string], "view">;
    signMessage: TypedContractMethod<[_data: BytesLike], [void], "nonpayable">;
    getFunction<T extends ContractMethod = ContractMethod>(key: string | FunctionFragment): T;
    getFunction(nameOrSignature: "getMessageHash"): TypedContractMethod<[message: BytesLike], [string], "view">;
    getFunction(nameOrSignature: "signMessage"): TypedContractMethod<[_data: BytesLike], [void], "nonpayable">;
    getEvent(key: "SignMsg"): TypedContractEvent<SignMsgEvent.InputTuple, SignMsgEvent.OutputTuple, SignMsgEvent.OutputObject>;
    filters: {
        "SignMsg(bytes32)": TypedContractEvent<SignMsgEvent.InputTuple, SignMsgEvent.OutputTuple, SignMsgEvent.OutputObject>;
        SignMsg: TypedContractEvent<SignMsgEvent.InputTuple, SignMsgEvent.OutputTuple, SignMsgEvent.OutputObject>;
    };
}
