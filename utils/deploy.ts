import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployOptions } from 'hardhat-deploy/types'

export type HRE = HardhatRuntimeEnvironment

export function Deploy(name: string, options: any = {}, fn?: any) {
  options = options || {}
  const dependencies = options.dependencies || []
  const libraries = options.libraries || []

  const func = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, ethers, getChainId, getNamedAccounts, upgrades } = hre
    const { deploy } = deployments
    const signers = await ethers.getSigners()

    // Fund all signers on hardnet network
    if (hre.network.name == 'hardhat') {
      await signers.map(async (s) => {
        await hre.network.provider.send('hardhat_setBalance', [s.address, '0x420000000000000000000'])
      })
    }

    // Use deployer named account to deploy contract
    const { deployer } = await getNamedAccounts()

    async function deployContract(args: any[] = []) {
      const libs = {}

      if (libraries != null) {
        for (const name of libraries) {
          console.log('deploy', name)
          libs[name] = (await deploy(name, { from: deployer })).address
        }
      }

      if (options.proxy) {
        const ProxyFactory = await ethers.getContractFactory(name)
        const tx = await upgrades.deployProxy(ProxyFactory, args, options.proxy)
        const artifact = await deployments.getArtifact(name)
        console.log(`deploying "${name}" (tx: ${tx.hash})...: deployed at ${tx.address}`)
        await deployments.save(name, { abi: artifact.abi, address: tx.address })
        return await tx
      }

      return await deploy(
        name,
        Object.assign({}, options, {
          from: deployer,
          args: args,
          libraries: libs,
          log: true,
        }),
      )
    }

    const deps = {}
    for (const dep of dependencies) {
      deps[dep] = await deployments.get(dep)
    }

    await fn({ ethers: ethers, getChainId, getNamedAccounts: getNamedAccounts, hre: hre, deploy: deployContract, deployments: deployments, deps: deps, signers: signers, upgrades: upgrades })

    // When live network, record the script as executed to prevent rexecution
    // return !useProxy
  }

  func.id = [name]
  func.tags = [name]
  func.dependencies = options.dependencies
  return func
}

// Tenderly verification
// let verification = await tenderly.verify({
//   name: contractName,
//   address: contractAddress,
//   network: targetNetwork,
// })
