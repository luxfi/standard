import type { BaseContract, BytesLike, FunctionFragment, Result, Interface, EventFragment, AddressLike, ContractRunner, ContractMethod, Listener } from "ethers";
import type { TypedContractEvent, TypedDeferredTopicFilter, TypedEventLog, TypedLogDescription, TypedListener, TypedContractMethod } from "../../common";
export interface SafeToL2SetupInterface extends Interface {
    getFunction(nameOrSignature: "_SELF" | "setupToL2"): FunctionFragment;
    getEvent(nameOrSignatureOrTopic: "ChangedMasterCopy"): EventFragment;
    encodeFunctionData(functionFragment: "_SELF", values?: undefined): string;
    encodeFunctionData(functionFragment: "setupToL2", values: [AddressLike]): string;
    decodeFunctionResult(functionFragment: "_SELF", data: BytesLike): Result;
    decodeFunctionResult(functionFragment: "setupToL2", data: BytesLike): Result;
}
export declare namespace ChangedMasterCopyEvent {
    type InputTuple = [singleton: AddressLike];
    type OutputTuple = [singleton: string];
    interface OutputObject {
        singleton: string;
    }
    type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
    type Filter = TypedDeferredTopicFilter<Event>;
    type Log = TypedEventLog<Event>;
    type LogDescription = TypedLogDescription<Event>;
}
export interface SafeToL2Setup extends BaseContract {
    connect(runner?: ContractRunner | null): SafeToL2Setup;
    waitForDeployment(): Promise<this>;
    interface: SafeToL2SetupInterface;
    queryFilter<TCEvent extends TypedContractEvent>(event: TCEvent, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    queryFilter<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    on<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    on<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    listeners<TCEvent extends TypedContractEvent>(event: TCEvent): Promise<Array<TypedListener<TCEvent>>>;
    listeners(eventName?: string): Promise<Array<Listener>>;
    removeAllListeners<TCEvent extends TypedContractEvent>(event?: TCEvent): Promise<this>;
    _SELF: TypedContractMethod<[], [string], "view">;
    setupToL2: TypedContractMethod<[
        l2Singleton: AddressLike
    ], [
        void
    ], "nonpayable">;
    getFunction<T extends ContractMethod = ContractMethod>(key: string | FunctionFragment): T;
    getFunction(nameOrSignature: "_SELF"): TypedContractMethod<[], [string], "view">;
    getFunction(nameOrSignature: "setupToL2"): TypedContractMethod<[l2Singleton: AddressLike], [void], "nonpayable">;
    getEvent(key: "ChangedMasterCopy"): TypedContractEvent<ChangedMasterCopyEvent.InputTuple, ChangedMasterCopyEvent.OutputTuple, ChangedMasterCopyEvent.OutputObject>;
    filters: {
        "ChangedMasterCopy(address)": TypedContractEvent<ChangedMasterCopyEvent.InputTuple, ChangedMasterCopyEvent.OutputTuple, ChangedMasterCopyEvent.OutputObject>;
        ChangedMasterCopy: TypedContractEvent<ChangedMasterCopyEvent.InputTuple, ChangedMasterCopyEvent.OutputTuple, ChangedMasterCopyEvent.OutputObject>;
    };
}
