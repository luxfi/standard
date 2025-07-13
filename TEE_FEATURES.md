# TEE Features - Regenesis Branch

This branch includes support for:

## Trusted Execution Environments
- Intel SGX
- AMD SEV-SNP
- Intel TDX
- NVIDIA GPU Confidential Computing (Blackwell)

## Phala-inspired Architecture
- pRuntime integration
- Worker attestation
- Confidential smart contracts
- GPU-accelerated confidential compute

## Testing with Stack
Use the Lux Stack to test all TEE features:
```bash
cd ../stack
./lux start multichain
```
