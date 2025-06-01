import { defineChain } from "viem";

export const flowTestnet = defineChain({
  id: 545, // Flow EVM Testnet Chain ID
  name: "Flow EVM Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Flow",
    symbol: "FLOW",
  },
  rpcUrls: {
    default: {
      http: ["https://testnet.evm.nodes.onflow.org"], // Official Flow EVM RPC
    },
  },
  blockExplorers: {
    default: {
      name: "Flow Testnet Explorer",
      url: "https://evm-testnet.flowscan.io", // FlowScan explorer
      apiUrl: "https://evm-testnet.flowscan.io/api",
    },
  },
  testnet: true,
});
