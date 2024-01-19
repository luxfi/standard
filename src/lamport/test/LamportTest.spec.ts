// import chai, { expect } from 'chai'
// import chaiAsPromised from 'chai-as-promised'
// chai.use(chaiAsPromised)
// const LamportTest = artifacts.require('LamportTest')
// import { ethers } from 'ethers';
// import { loremIpsum } from "lorem-ipsum"
// import {LamportKeyPair, Sig, PubPair} from "../offchain/Types"
// import KeyTracker from "../offchain/KeyTracker"
// import {hash, hash_b, sign_hash, verify_signed_hash} from "../offchain/functions"

// const ITERATIONS = 3

// contract('LamportTest test', (accounts: string[]) => {
//     it('can broadcast message via broadcast2', async () => {
//         console.log(`hash_b(0): ${hash_b('0x00')}`)
//         const _contract: ethers.Contract = await LamportTest.new()
//         const k: KeyTracker = new KeyTracker()
//         await _contract.init(k.currentKeyPair().pub)

//         const provider = ethers.getDefaultProvider(`http://127.0.0.1:7545`)
//         const b1 = await provider.getBalance(accounts[0])
//         console.log(`balance before: ${b1.toString()}`)

//         for (let i = 0; i < ITERATIONS; i++) {
//             const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
//             const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

//             {
//                 const expectedPub: LamportKeyPair = await _contract.getPublicKey()
//                 expect(current_keys.pub).to.deep.equal(expectedPub)
//             }

//             const messageToBroadcast = loremIpsum()
//             const packed = ethers.utils.solidityPack(['string', 'bytes[2][256]'], [messageToBroadcast, next_keys.pub])
//             const callhash = hash_b(packed)
//             const sig = sign_hash(callhash, current_keys.pri)

//             const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
//             expect(is_valid_sig).to.be.true

//             await _contract.broadcast(
//                 messageToBroadcast,
//                 next_keys.pub,
//                 sig.map(s => `0x${s}`),
//                 { from: accounts[0] })
//         }

//         const b2 = await provider.getBalance(accounts[0])
//         console.log(`balance after: ${b2.toString()}`)

//         const b_delta = b1.sub(b2)
//         console.log(`balance delta: ${b_delta.toString()}`)

//         const datum = {
//             ts: Math.floor(Date.now() / 1000),
//             avg_gas: b_delta.div(ITERATIONS).toString(),
//             iterations: ITERATIONS,
//         }

//         // read 'gas_data.json'
//         const fs = require('fs');
//         const gas_data = JSON.parse(fs.readFileSync('gas_data.json', 'utf8'))
//         gas_data.push(datum)

//         // write 'gas_data.json'
//         fs.writeFileSync('gas_data.json', JSON.stringify(gas_data, null, 2), 'utf8')
//     });

//     it('can broadcast from any EC wallet so long as we provide valid lamport sig', async () => {
//         const _contract: ethers.Contract = await LamportTest.new()
//         const k: KeyTracker = new KeyTracker()
//         await _contract.init(k.currentKeyPair().pub)

//         for (let i = 0; i < ITERATIONS; i++) {
//             const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
//             const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

//             {
//                 const expectedPub: LamportKeyPair = await _contract.getPublicKey()
//                 expect(current_keys.pub).to.deep.equal(expectedPub)
//             }

//             const messageToBroadcast = loremIpsum()
//             const packed = ethers.utils.solidityPack(['string', 'bytes[2][256]'], [messageToBroadcast, next_keys.pub])
//             const callhash = hash_b(packed)
//             const sig = sign_hash(callhash, current_keys.pri)

//             const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
//             expect(is_valid_sig).to.be.true

//             await _contract.broadcast(
//                 messageToBroadcast,
//                 next_keys.pub,
//                 sig.map(s => `0x${s}`),
//                 { from: accounts[i] })
//         }
//     })

//     it('cannot broadcast if message is altered', async () => {
//         const _contract: ethers.Contract = await LamportTest.new()
//         const k: KeyTracker = new KeyTracker()
//         await _contract.init(k.currentKeyPair().pub)

//         const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
//         const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

//         {
//             const expectedPub: LamportKeyPair = await _contract.getPublicKey()
//             expect(current_keys.pub).to.deep.equal(expectedPub)
//         }

//         const messageToBroadcast = loremIpsum()
//         const packed = ethers.utils.solidityPack(['string', 'bytes[2][256]'], [messageToBroadcast, next_keys.pub])
//         const callhash = hash_b(packed)
//         const sig = sign_hash(callhash, current_keys.pri)

//         let failed = false
//         await _contract.broadcast(
//             `_change_${messageToBroadcast}`,
//             next_keys.pub,
//             sig.map(s => `0x${s}`),
//             { from: accounts[0] })
//             .catch(() => failed = true)
//         expect(failed).to.be.true
//     })

//     it('cannot broadcast if signature is altered', async () => {
//         const _contract: ethers.Contract = await LamportTest.new()
//         const k: KeyTracker = new KeyTracker()
//         await _contract.init(k.currentKeyPair().pub)

//         const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
//         const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

//         {
//             const expectedPub: LamportKeyPair = await _contract.getPublicKey()
//             expect(current_keys.pub).to.deep.equal(expectedPub)
//         }

//         const messageToBroadcast = loremIpsum()
//         const packed = ethers.utils.solidityPack(['string', 'bytes[2][256]'], [messageToBroadcast, next_keys.pub])
//         const callhash = hash_b(packed)
//         const sig = sign_hash(callhash, current_keys.pri)

//         const altered_sig: Sig = sig.map((s, i) => {
//             if (i === 0)
//                 return '0'.repeat(s.length)
//             return s
//         })

//         let failed = false
//         await _contract.broadcast(
//             messageToBroadcast,
//             next_keys.pub,
//             altered_sig.map(s => `0x${s}`),
//             { from: accounts[0] })
//             .catch(() => failed = true)
//         expect(failed).to.be.true
//     })

//     it('can move to new tip jar', async () => {
//         const wallet_newTipJar = ethers.Wallet.createRandom()
//         const _contract: ethers.Contract = await LamportTest.new()
//         const k: KeyTracker = new KeyTracker()
//         await _contract.init(k.currentKeyPair().pub)

//         const tipjar_1 = await _contract.getTipJar()
//         console.log(`tipjar_1: ${tipjar_1}`)
//         expect(tipjar_1).to.equal(accounts[0])

//         const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
//         const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

//         const packed = ethers.utils.solidityPack(['address', 'bytes[2][256]'], [wallet_newTipJar.address, next_keys.pub])
//         const callhash = hash_b(packed)
//         const sig = sign_hash(callhash, current_keys.pri)
//         const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
//         console.log(`is_valid_sig: ${is_valid_sig}`)
//         expect(is_valid_sig).to.be.true

//         await _contract.change_tip_jar(wallet_newTipJar.address, next_keys.pub, sig.map(s => `0x${s}`), { from: accounts[0] })

//         const tipjar_2 = await _contract.getTipJar()
//         console.log(`tipjar_2: ${tipjar_2}`)
//         expect(tipjar_2).to.equal(wallet_newTipJar.address)
//     })

//     it.skip('death by ten thousand hashes.', async () => {
//         const _contract: ethers.Contract = await LamportTest.new()
//         console.log(`contract address: ${_contract.address}`)
//         await _contract.death_by_ten_thousand_hashes('0x123456789', 1_000)         
//         await _contract.death_by_ten_thousand_hashes('0x123456789', 10_000)         
//         await _contract.death_by_ten_thousand_hashes('0x123456789', 20_000)         
//     })

// })


// //////////////////////////////////////////////////////////////////////////////////////////////////////////
// LAMPORT TS IMPLEMENTATION. 
//////////////////////////////////////////////////////////////////////////////////////////////////////////

// type RandPair = [string, string]
// type PubPair = [string, string]

// type KeyPair = {
//     pri: RandPair[],
//     pub: PubPair[],
// }

// type Sig = string[]

// const hash = (input: string) => ethers.utils.keccak256(ethers.utils.toUtf8Bytes(input))
// const hash_b = (input: string) => ethers.utils.keccak256(input)

// derive public key from private key
// const pubFromPri = (pri: [string, string][]) => pri.map(p => ([hash_b(p[0]), hash_b(p[1])])) as PubPair[]

// function mk_key_pair(): KeyPair {
//     const mk_rand_num = () => randomBytes(32).toString('hex')
//     const mk_RandPair = () => ([mk_rand_num(), mk_rand_num()] as RandPair)
//     const mk_pri_key = () => Array.from({ length: 256 }, () => mk_RandPair()) as RandPair[]

//     const pri = mk_pri_key()
//     const pub = pubFromPri(pri.map(p => [`0x${p[0]}`, `0x${p[1]}`]))
//     return { pri, pub }
// }

// sanity check
// function is_private_key(key: RandPair[]): boolean {
//     if (key.length !== 256)
//         return false
//     return true
// }

// function sign_hash(hmsg: string, pri: RandPair[]): Sig {
//     if (!is_private_key(pri))
//         throw new Error('invalid private key')

//     const msg_hash_bin = new BigNumber(hmsg, 16).toString(2).padStart(256, '0')

//     if (msg_hash_bin.length !== 256)
//         throw new Error(`invalid message hash length: ${msg_hash_bin.length} --> ${msg_hash_bin}`)

//     const sig: Sig = ([...msg_hash_bin] as ('0' | '1')[]).map((el: '0' | '1', i: number) => pri[i][el])
//     return sig
// }

// function verify_signed_hash(hmsg: string, sig: Sig, pub: PubPair[]): boolean {
//     const msg_hash_bin = new BigNumber(hmsg, 16).toString(2).padStart(256, '0')
//     const pub_selection = ([...msg_hash_bin] as ('0' | '1')[]).map((way /** 'way' as in which way should we go through the public key */: '0' | '1', i: number) => pub[i][way])

//     for (let i = 0; i < pub_selection.length; i++)
//         if (pub_selection[i] !== hash_b(`0x${sig[i]}`))
//             return false

//     return true
// }

// type LamportKeyPair = {
//     pri: RandPair[],
//     pub: PubPair[]
// }

// easy key management and generation
// class KeyTracker {
//     privateKeys: RandPair[][] = []
//     publicKeys: PubPair[][] = []

//     getNextKeyPair(): LamportKeyPair {
//         const { pri, pub } = mk_key_pair()
//         this.privateKeys.push(pri)
//         this.publicKeys.push(pub)
//         return { pri, pub }
//     }

//     currentKeyPair(): LamportKeyPair {
//         if (this.privateKeys.length == 0)
//             return this.getNextKeyPair()
//         return {
//             pri: this.privateKeys[this.privateKeys.length - 1],
//             pub: this.publicKeys[this.publicKeys.length - 1]
//         }
//     }

//     previousKeyPair(): LamportKeyPair {
//         if (this.privateKeys.length < 2)
//             throw new Error('no previous key pair')
//         return { pri: this.privateKeys[this.privateKeys.length - 2], pub: this.publicKeys[this.publicKeys.length - 2] }
//     }
// }
//////////////////////////////////////////////////////////////////////////////////////////////////////////