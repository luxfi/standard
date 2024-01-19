export type LamportKeyPair = {
    pri: RandPair[],
    pub: PubPair[]
}

export type RandPair = [string, string]
export type PubPair = [string, string]

export type KeyPair = {
    pri: RandPair[],
    pub: PubPair[],
}

export type Sig = string[]
