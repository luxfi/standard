import type { BaseContract, BigNumberish, FunctionFragment, Interface, EventFragment, AddressLike, ContractRunner, ContractMethod, Listener } from "ethers";
import type { TypedContractEvent, TypedDeferredTopicFilter, TypedEventLog, TypedLogDescription, TypedListener } from "../../common";
export interface NativeCurrencyPaymentFallbackInterface extends Interface {
    getEvent(nameOrSignatureOrTopic: "SafeReceived"): EventFragment;
}
export declare namespace SafeReceivedEvent {
    type InputTuple = [sender: AddressLike, value: BigNumberish];
    type OutputTuple = [sender: string, value: bigint];
    interface OutputObject {
        sender: string;
        value: bigint;
    }
    type Event = TypedContractEvent<InputTuple, OutputTuple, OutputObject>;
    type Filter = TypedDeferredTopicFilter<Event>;
    type Log = TypedEventLog<Event>;
    type LogDescription = TypedLogDescription<Event>;
}
export interface NativeCurrencyPaymentFallback extends BaseContract {
    connect(runner?: ContractRunner | null): NativeCurrencyPaymentFallback;
    waitForDeployment(): Promise<this>;
    interface: NativeCurrencyPaymentFallbackInterface;
    queryFilter<TCEvent extends TypedContractEvent>(event: TCEvent, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    queryFilter<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, fromBlockOrBlockhash?: string | number | undefined, toBlock?: string | number | undefined): Promise<Array<TypedEventLog<TCEvent>>>;
    on<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    on<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(event: TCEvent, listener: TypedListener<TCEvent>): Promise<this>;
    once<TCEvent extends TypedContractEvent>(filter: TypedDeferredTopicFilter<TCEvent>, listener: TypedListener<TCEvent>): Promise<this>;
    listeners<TCEvent extends TypedContractEvent>(event: TCEvent): Promise<Array<TypedListener<TCEvent>>>;
    listeners(eventName?: string): Promise<Array<Listener>>;
    removeAllListeners<TCEvent extends TypedContractEvent>(event?: TCEvent): Promise<this>;
    getFunction<T extends ContractMethod = ContractMethod>(key: string | FunctionFragment): T;
    getEvent(key: "SafeReceived"): TypedContractEvent<SafeReceivedEvent.InputTuple, SafeReceivedEvent.OutputTuple, SafeReceivedEvent.OutputObject>;
    filters: {
        "SafeReceived(address,uint256)": TypedContractEvent<SafeReceivedEvent.InputTuple, SafeReceivedEvent.OutputTuple, SafeReceivedEvent.OutputObject>;
        SafeReceived: TypedContractEvent<SafeReceivedEvent.InputTuple, SafeReceivedEvent.OutputTuple, SafeReceivedEvent.OutputObject>;
    };
}
