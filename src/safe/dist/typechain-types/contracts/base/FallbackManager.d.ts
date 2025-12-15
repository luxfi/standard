import type { BaseContract, BytesLike, FunctionFragment, Result, Interface, EventFragment, AddressLike, ContractRunner, ContractMethod, Listener } from "ethers";
import type { TypedContractEvent, TypedDeferredTopicFilter, TypedEventLog, TypedLogDescription, TypedListener, TypedContractMethod } from "../../common";
export interface FallbackManagerInterface extends Interface {
    getFunction(nameOrSignature: "setFallbackHandler"): FunctionFragment;
    getEvent(nameOrSignatureOrTopic: "ChangedFallbackHandler"): EventFragment;
    encodeFunctionData(functionFragment: "setFallbackHandler", values: [AddressLike]): string;
    decodeFunctionResult(functionFragment: "setFallbackHandler", data: BytesLike): Result;
}
export declare namespace ChangedFallbackHandlerEvent {
    type InputTuple = [handler: AddressLike];
    type OutputTuple = [handler: string];
    interface OutputObject {
        handler: string;
    }
    type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
    type Filter = TypedDeferredTopicFilter<Event>;
    type Log = TypedEventLog<Event>;
    type LogDescription = TypedLogDescription<Event>;
}
export interface FallbackManager extends BaseContract {
    connect(runner?: ContractRunner | null): FallbackManager;
    waitForDeployment(): Promise<this>;
    interface: FallbackManagerInterface;
    queryFilter<TCEvent extends TypedContractEvent>(event: TCEvent, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    queryFilter<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    on<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    on<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    listeners<TCEvent extends TypedContractEvent>(event: TCEvent): Promise<Array<TypedListener<TCEvent>>>;
    listeners(eventName?: string): Promise<Array<Listener>>;
    removeAllListeners<TCEvent extends TypedContractEvent>(event?: TCEvent): Promise<this>;
    setFallbackHandler: TypedContractMethod<[
        handler: AddressLike
    ], [
        void
    ], "nonpayable">;
    getFunction<T extends ContractMethod = ContractMethod>(key: string | FunctionFragment): T;
    getFunction(nameOrSignature: "setFallbackHandler"): TypedContractMethod<[handler: AddressLike], [void], "nonpayable">;
    getEvent(key: "ChangedFallbackHandler"): TypedContractEvent<ChangedFallbackHandlerEvent.InputTuple, ChangedFallbackHandlerEvent.OutputTuple, ChangedFallbackHandlerEvent.OutputObject>;
    filters: {
        "ChangedFallbackHandler(address)": TypedContractEvent<ChangedFallbackHandlerEvent.InputTuple, ChangedFallbackHandlerEvent.OutputTuple, ChangedFallbackHandlerEvent.OutputObject>;
        ChangedFallbackHandler: TypedContractEvent<ChangedFallbackHandlerEvent.InputTuple, ChangedFallbackHandlerEvent.OutputTuple, ChangedFallbackHandlerEvent.OutputObject>;
    };
}
