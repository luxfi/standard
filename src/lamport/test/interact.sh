import { ethers } from "ethers"
import * as fs from 'fs'
import { hash_b, sign_hash, verify_signed_hash } from "../offchain/functions"
import KeyTracker from "../offchain/KeyTracker"
import { loremIpsum } from "lorem-ipsum"
import * as dotenv from 'dotenv'
dotenv.config()
// const pri = fs.readFileSync(".secret", "utf8")
const pri = process.env.PK_LUX_TEST
// const c_address = `0xCb3F2F2F5ca825cC4cB01F535763Fa864aC35335`
// const c_address = `0x9684093070A02Ea5AFb57782C04d37d26C202C52`
const c_address = `0x22FeD2981Ed73e4FD21c7BFE3921264200B49dC3`

const abi = [
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": false,
                "internalType": "string",
                "name": "message",
                "type": "string",
            }
        ],
        "name": "Message",
        "type": "event"
    },
    {
        "inputs": [],
        "name": "getPublicKey",
        "outputs": [
            {
                "internalType": "bytes32[2][256]",
                "name": "",
                "type": "bytes32[2][256]"
            }
        ],
        "stateMutability": "view",
        "type": "function",
        "constant": true
    },
    {
        "inputs": [],
        "name": "getTipJar",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function",
        "constant": true
    },
    {
        "inputs": [
            {
                "internalType": "bytes32[2][256]",
                "name": "firstPublicKey",
                "type": "bytes32[2][256]"
            }
        ],
        "name": "init",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "newTipJar",
                "type": "address"
            },
            {
                "internalType": "bytes32[2][256]",
                "name": "nextpub",
                "type": "bytes32[2][256]"
            },
            {
                "internalType": "bytes[256]",
                "name": "sig",
                "type": "bytes[256]"
            }
        ],
        "name": "change_tip_jar",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "string",
                "name": "messageToBroadcast",
                "type": "string"
            },
            {
                "internalType": "bytes32[2][256]",
                "name": "nextpub",
                "type": "bytes32[2][256]"
            },
            {
                "internalType": "bytes[256]",
                "name": "sig",
                "type": "bytes[256]",
            }
        ],
        "name": "broadcast",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    }
]

// const provider = ethers.getDefaultProvider(`https://rinkeby.infura.io/v3/${process.env.INFURA_KEY}`)
// const provider = ethers.getDefaultProvider(`https://polygon-rpc.com`)
const provider = ethers.getDefaultProvider(`https://rpc.api.moonbase.moonbeam.network`)
if (pri === undefined) 
    throw new Error("No private key found")
const signer = new ethers.Wallet(pri, provider)
const contract = new ethers.Contract(c_address, abi, signer);

(async () => {

    const k = await contract.getPublicKey()
    console.log(k)


    // generate a new keypair
    const kt: KeyTracker = KeyTracker.load("default")
    console.log(kt)
    const oldkeys = kt.currentKeyPair()
    
    for (let i = 0; i < 256; i++) {
        const local = oldkeys.pub[i]
        if (local[0] != k[i][0] || local[1] != k[i][1]) 
            throw new Error ("key mismatch")
    }

    // return 
    const newkeys = kt.getNextKeyPair()

    // await contract.init(oldkeys.pub, {
    //     gasPrice: ethers.utils.parseUnits('60', 'gwei'),
    // })

    kt.save(true)

    // return
    const message = `Hello, World! ${loremIpsum()}`
    const packed = ethers.utils.solidityPack(['string', 'bytes[2][256]'], [message, newkeys.pub])
    const h = hash_b(packed)
    const sig = sign_hash(h, oldkeys.pri)

    // verify locally
    const verified = verify_signed_hash(h, sig, oldkeys.pub)
    console.log("verified locally", verified)

    // broadcast message 
    const tx = await contract.broadcast(message, newkeys.pub, sig.map(s => `0x${s}`), {
        gasPrice: ethers.utils.parseUnits('35', 'gwei'),
    })
    console.log("broadcast tx", tx)

    const result = await tx.wait()
    console.log("broadcast result", result)
})()

