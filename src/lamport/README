# @luxdefi/lamport

A library for verifying Lamport Signatures from within an Ethereum EVM smart
contract. Written in Solidity. This library is part of an ongoing effort by
Lux Network to ensure that blockchain technology continues to be viable in the
face of Quantum Computing.

## Important files:
1. LamportBase.sol - an abstract contract that contains logic for effective ownership of a contract secured by a Lamport Signature
2. LamportTest2.sol - a contract that inherits from LamportBase. An example of how to use the library to secure ownership of a contract

## How to use:
1. Inherit from LamportBase.sol
2. use the `onlyLamportOwner` modifier on any function that you want to be secured by a Lamport Signature
3. correctly pass the paramerters to the modifier. Take special note of the fact that all the relevent parameters (except the next pkh) must be combined using abi.encodePacked() before being passed to the modifier. Please look at `broadcastWithNumberAndAddress` in LamportTest2.sol for an example of how to do this.
4. remember! Any parameters not included in the signed hash would be left vulnrable to quantum attacks and thus could be altered before being written to the blockchain. I recommend that you include all parameters in the signed hash. The modifier will handle packing your `nextPKH` with your already packed parameters before hashing and passing to `verify_u256`. `currentpub` does not need to be signed. It is already secured by the hash `pkh`.


## To run the tests:
    bash test.sh
