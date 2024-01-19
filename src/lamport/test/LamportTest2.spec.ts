declare var artifacts: any
declare var contract: any

import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
chai.use(chaiAsPromised)
const LamportTest = artifacts.require('LamportTest2')
import { ethers } from 'ethers';
import { loremIpsum } from "lorem-ipsum"
import { LamportKeyPair, Sig, PubPair } from "../offchain/Types"
import KeyTracker from "../offchain/KeyTracker"
import { hash, hash_b, sign_hash, verify_signed_hash } from "../offchain/functions"

const ITERATIONS = 3

contract('LamportTest2 test', (accounts: string[]) => {
    it('can broadcast message via broadcast2', async () => {
        console.log(`hash_b(0): ${hash_b('0x00')}`)
        const _contract: ethers.Contract = await LamportTest.new()
        const k: KeyTracker = new KeyTracker()

        await _contract.init(k.pkh)

        const provider = ethers.getDefaultProvider(`http://127.0.0.1:7545`)
        const b1 = await provider.getBalance(accounts[0])
        console.log(`balance before: ${b1.toString()}`)

        for (let i = 0; i < ITERATIONS; i++) {
            const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
            const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

            {
                const expectedPKH: LamportKeyPair = await _contract.getPKH()
                expect(KeyTracker.pkhFromPublicKey(current_keys.pub)).to.deep.equal(expectedPKH)
            }

            const nextpkh = KeyTracker.pkhFromPublicKey(next_keys.pub)

            const messageToBroadcast = loremIpsum()
            // const packed = ethers.utils.solidityPack(['string', 'bytes32'], [messageToBroadcast, nextpkh])

            const packed_old = ethers.utils.solidityPack(['string', 'bytes32'], [messageToBroadcast, nextpkh])
            const packed = (() => {
                const temp = ethers.utils.solidityPack(['string'], [messageToBroadcast])
                return ethers.utils.solidityPack(['bytes', 'bytes32'], [temp, nextpkh])
            })()
            expect(packed).to.deep.equal(packed_old)

            const callhash = hash_b(packed)
            const sig = sign_hash(callhash, current_keys.pri)

            const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
            expect(is_valid_sig).to.be.true

            console.log(`sig is valid`)

            await _contract.broadcast(
                messageToBroadcast,
                current_keys.pub,
                nextpkh,
                sig.map(s => `0x${s}`),
                { from: accounts[0] })
        }

        const b2 = await provider.getBalance(accounts[0])
        console.log(`balance after: ${b2.toString()}`)

        const b_delta = b1.sub(b2)
        console.log(`balance delta: ${b_delta.toString()}`)

        const datum = {
            ts: Math.floor(Date.now() / 1000),
            avg_gas: b_delta.div(ITERATIONS).toString(),
            iterations: ITERATIONS,
        }

        // read 'gas_data.json'
        const fs = require('fs');
        const gas_data = JSON.parse(fs.readFileSync('gas_data2.json', 'utf8'))
        gas_data.push(datum)

        // write 'gas_data.json'
        fs.writeFileSync('gas_data.json', JSON.stringify(gas_data, null, 2), 'utf8')
    });






    it('broadcastWithNumber', async () => {
        const _contract: ethers.Contract = await LamportTest.new()
        const k: KeyTracker = new KeyTracker()
        await _contract.init(k.pkh)

        for (let i = 0; i < ITERATIONS; i++) {
            const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
            const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

            {
                const expectedPKH: LamportKeyPair = await _contract.getPKH()
                expect(KeyTracker.pkhFromPublicKey(current_keys.pub)).to.deep.equal(expectedPKH)
            }

            const nextpkh = KeyTracker.pkhFromPublicKey(next_keys.pub)

            const messageToBroadcast = loremIpsum()
            const numToBroadcast = Math.floor(Math.random() * 1000000)

            const packed = (() => {
                const temp = ethers.utils.solidityPack(['string', 'uint256'], [messageToBroadcast, numToBroadcast])
                return ethers.utils.solidityPack(['bytes', 'bytes32'], [temp, nextpkh])
            })()

            const callhash = hash_b(packed)
            const sig = sign_hash(callhash, current_keys.pri)

            const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
            expect(is_valid_sig).to.be.true

            console.log(`sig is valid`)

            await _contract.broadcastWithNumber(
                messageToBroadcast,
                numToBroadcast,
                current_keys.pub,
                nextpkh,
                sig.map(s => `0x${s}`),
                { from: accounts[0] })
        }
 
    })








it ('broadcastWithNumberAndAddress', async () => {

      const _contract: ethers.Contract = await LamportTest.new()
        const k: KeyTracker = new KeyTracker()
        await _contract.init(k.pkh)

        for (let i = 0; i < ITERATIONS; i++) {
            const current_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.currentKeyPair()))
            const next_keys: LamportKeyPair = JSON.parse(JSON.stringify(k.getNextKeyPair()))

            {
                const expectedPKH: LamportKeyPair = await _contract.getPKH()
                expect(KeyTracker.pkhFromPublicKey(current_keys.pub)).to.deep.equal(expectedPKH)
            }

            const nextpkh = KeyTracker.pkhFromPublicKey(next_keys.pub)

            const messageToBroadcast = loremIpsum()
            const numToBroadcast = Math.floor(Math.random() * 1000000)
            const addressToBroadcast = accounts[numToBroadcast % accounts.length ] // randomish address

            const packed = (() => {
                const temp = ethers.utils.solidityPack(['string', 'uint256', 'address'], [messageToBroadcast, numToBroadcast, addressToBroadcast])
                return ethers.utils.solidityPack(['bytes', 'bytes32'], [temp, nextpkh])
            })()

            const callhash = hash_b(packed)
            const sig = sign_hash(callhash, current_keys.pri)

            const is_valid_sig = verify_signed_hash(callhash, sig, current_keys.pub)
            expect(is_valid_sig).to.be.true

            console.log(`sig is valid`)

            await _contract.broadcastWithNumberAndAddress(
                messageToBroadcast,
                numToBroadcast,
                addressToBroadcast,
                current_keys.pub,
                nextpkh,
                sig.map(s => `0x${s}`),
                { from: accounts[0] })
        }

    
})













    it.skip('curious', async () => {
        const a = ethers.utils.solidityPack(['string', 'string', 'string'], ['a', 'b', 'c'])
        console.log(a)

        const b = (() => {
            const temp = ethers.utils.solidityPack(['string'], ['a'])
            return ethers.utils.solidityPack(['bytes', 'string', 'string'], [temp, 'b', 'c'])
        })()
        console.log(b)
    })
})
