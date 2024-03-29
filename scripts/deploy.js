// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { formatBytes32String, parseBytes32String } = require("ethers/lib/utils");
const hre = require("hardhat");

async function main() {
  // const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  // const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  // const unlockTime = currentTimestampInSeconds + ONE_YEAR_IN_SECS;

  // const lockedAmount = hre.ethers.utils.parseEther("1");

  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  // const Fraction = await hre.ethers.getContractFactory("Fraction");
  // const fraction = await Fraction.deploy(
  //   '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e'
  //   );

  // const res = await fraction.deployed();

  // console.log(`Fraction contract deployed on ${res.address}`);

  const Marketplace = await hre.ethers.getContractFactory('Marketplace');
  const marketplace = await Marketplace.deploy('0xd1EB66A13126459677b98cc0E87357d4E86401aa');

  const marketplaceRes = await marketplace.deployed();

  console.log(`Marketplace contract deployed on ${marketplaceRes.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
