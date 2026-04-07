module.exports = {
  networks: {
    mainnet: {
      privateKey: process.env.PRIVATE_KEY,
      fullHost: "https://api.trongrid.io",
      network_id: "1",
    },
    shasta: {
      privateKey: process.env.PRIVATE_KEY,
      fullHost: "https://api.shasta.trongrid.io",
      network_id: "2",
    },
    nile: {
      privateKey: process.env.PRIVATE_KEY,
      fullHost: "https://nile.trongrid.io",
      network_id: "3",
    },
  },
  compilers: {
    solc: {
      version: "0.8.20",
    },
  },
};
