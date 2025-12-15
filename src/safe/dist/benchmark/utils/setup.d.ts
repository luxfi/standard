import { BigNumberish } from "ethers";
import { SafeTransaction } from "../../src/utils/execution";
import { Safe, SafeL2 } from "../../typechain-types";
type SafeSingleton = Safe | SafeL2;
export interface Contracts {
    targets: SafeSingleton[];
    additions: any | undefined;
}
export declare const configs: ({
    name: string;
    signers: number;
    threshold: number;
    useGuard?: undefined;
} | {
    name: string;
    signers: number;
    threshold: number;
    useGuard: boolean;
})[];
export declare const setupBenchmarkContracts: (benchmarkFixture?: () => Promise<any>, logGasUsage?: boolean) => (options?: unknown) => Promise<{
    targets: SafeSingleton[];
    additions: any;
}>;
export interface Benchmark {
    name: string;
    prepare: (contracts: Contracts, target: string, nonce: BigNumberish) => Promise<SafeTransaction>;
    after?: (contracts: Contracts) => Promise<void>;
    fixture?: () => Promise<any>;
}
type BenchmarkWithSetup = () => Promise<Benchmark[]>;
export declare const benchmark: (topic: string, benchmarks: BenchmarkWithSetup) => Promise<void>;
export {};
