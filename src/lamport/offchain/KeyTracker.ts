import { RandPair, PubPair, LamportKeyPair } from "./Types"
import {mk_key_pair, hash_b } from "./functions"
import { ethers } from 'ethers'

// easy key management and generation
export default class KeyTracker {
    privateKeys: RandPair[][] = []
    publicKeys: PubPair[][] = []
    name: string

    /**
     * constructor
     * @author William Doyle 
     * @param _name the name used to differentiate this sequence of keys 
     */
    constructor (_name : string = 'default') {
        this.name = _name
    }

    static pkhFromPublicKey(pub: PubPair[]): string {

        return hash_b(ethers.utils.solidityPack(['bytes32[2][256]'], [pub])) 
    }

    get pkh () {
        return KeyTracker.pkhFromPublicKey(this.currentKeyPair().pub)
    }

    /**
     * save
     * @description saves the key tracker to disk
     * @author William Doyle 
     * @param trim wether or not to delete the oldest key pairs (keeps last 3)
     */
    save(trim : boolean = false) {
        const {_privateKeys, _publicKeys} = (() => {
            if (trim === false) 
                return { _privateKeys: this.privateKeys, _publicKeys: this.publicKeys }
            else {
                const _privateKeys = this.privateKeys.slice(-3)
                const _publicKeys = this.publicKeys.slice(-3)
                return { _privateKeys, _publicKeys }
            }
        })()

        const s = JSON.stringify({
            privateKeys: _privateKeys,
            publicKeys: _publicKeys,
            name: this.name
        }, null, 2)
        const fs = require('fs');
        fs.writeFileSync(`keys/${this.name}.json`, s)
    }

    /**
     * load
     * @author William Doyle
     * @description loads a key tracker from disk, and returns it
     * @param name the name of the key tracker to load
     */
    static load(name: string): KeyTracker {
        const fs = require('fs');
        const s = fs.readFileSync(`keys/${name}.json`, 'utf8')
        const rval = new KeyTracker()
        return Object.assign(rval, JSON.parse(s))
    }

    /**
     * getNextKeyPair
     * @author William Doyle
     * @description generates a new key pair, saves it to internal state, and returns it
     */
    getNextKeyPair(): LamportKeyPair {
        const { pri, pub } = mk_key_pair()
        this.privateKeys.push(pri)
        this.publicKeys.push(pub)
        return { pri, pub }
    }

    /**
     *  currentKeyPair
     *  @author William Doyle
     *  @description returns the current key pair, or creates a new one if there this is the first time this function has been called
     */
    currentKeyPair(): LamportKeyPair {
        if (this.privateKeys.length == 0)
            return this.getNextKeyPair()
        return {
            pri: this.privateKeys[this.privateKeys.length - 1],
            pub: this.publicKeys[this.publicKeys.length - 1]
        }
    }

    /**
     * previousKeyPair
     * @author William Doyle
     * @description returns the previous key pair, or throws an error if there is no previous key pair 
     */
    previousKeyPair(): LamportKeyPair {
        if (this.privateKeys.length < 2)
            throw new Error('no previous key pair')
        return { pri: this.privateKeys[this.privateKeys.length - 2], pub: this.publicKeys[this.publicKeys.length - 2] }
    }
}