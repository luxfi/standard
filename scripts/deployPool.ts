import { deployments, ethers } from 'hardhat'

async function main() {
  // Get current account
  const [signer] = await ethers.getSigners()

  // const Factory = await deployments.get('UniswapV2Factory')
  const Factory = await ethers.getContract('UniswapV2Factory')
  const Router = await ethers.getContract('UniswapV2Router02')
  const Savage = await ethers.getContract('Savage')
  const Z1 = await ethers.getContract('Z')
  const BNB = await ethers.getContract('B')

  console.log('Factory', Factory.address)
  console.log('Router', Router.address)
  console.log('Savage', Savage.address)
  console.log('Z1', Z1.address)
  console.log('BNB', BNB.address)

  const tril = ethers.utils.parseEther('1000000000000')
  const txn = await Factory.createPair(Z1.address, BNB.address);
  await txn.wait();

  const pair = await Factory.getPair(Z1.address, BNB.address);
  console.log('Pair', pair)

  const amountZoo = ethers.utils.parseUnits('2180913677.035819786465972231', 18)
  const amountBNB = ethers.utils.parseUnits('2019.717141295805250967', 18)
  const finalBNB  = ethers.utils.parseUnits('2010', 18)
  const amountIn  = tril
  const amountOutMin = ethers.utils.parseUnits('1990', 18)

  const amountToSender = amountZoo.add(amountIn)

  await BNB.mint(signer.address, amountBNB)
  await Z1.mint(signer.address, amountToSender);

  await BNB.approve(Router.address, amountBNB)
  await Z1.approve(Router.address, amountZoo)

  // Add liquidity
  await Router.addLiquidity(
    Z1.address,
    BNB.address,
    amountZoo, amountBNB,
    100, 100,
    signer.address,
    2e9
  )
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
