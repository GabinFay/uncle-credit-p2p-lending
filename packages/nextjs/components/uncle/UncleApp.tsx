"use client"

import { useState, useEffect } from "react"
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from "wagmi"
import { parseEther, formatEther } from "viem"
import { toast } from "react-hot-toast"
import LoanApplication from "./loan-application"
import LoanStatusScreen from "./loan-status-screen"
import CommunityVouchingScreen from "./community-vouching-screen"
import LoanSuccessScreen from "./loan-success-screen"
import VouchingSuccessScreen from "./vouching-success-screen"
import LoanDashboardScreen from "./loan-dashboard-screen"
import PaymentSuccessScreen from "./payment-success-screen"

interface Voucher {
  name: string
  amount: number
  avatarUrl?: string
}

type UserMode = "borrower" | "lender"

type ScreenState =
  | "MODE_SELECTION"
  | "LOAN_APPLICATION"
  | "LOAN_APPLICATION_SUCCESS"
  | "LOAN_STATUS"
  | "COMMUNITY_VOUCHING"
  | "VOUCHING_SUCCESS"
  | "LOAN_DASHBOARD"
  | "PAYMENT_SUCCESS"
  | "LENDER_DASHBOARD"
  | "TRANSACTION_PENDING"

interface UserLoanDetails {
  borrowerName: string
  originalLoanAmount: number
  amountActuallyFundedByVouchers: number
  totalPaidOnCurrentLoan: number
  currentScore: number
  remainingBalanceToRepay: number
  purpose: string
  vouchers: Voucher[]
  repaymentDays: number
  platformFeePercentage: number
  loanStatus: "pending_approval" | "awaiting_vouchers" | "active" | "completed" | "overdue" | "defaulted"
  loanRequestId?: string
}

interface Transaction {
  hash: string
  description: string
  status: "pending" | "success" | "failed"
  timestamp: number
  explorerUrl: string
  type: "loan_request" | "loan_offer" | "vouch" | "payment"
}

interface PendingTransaction {
  type: "loan_request" | "loan_offer" | "vouch" | "payment"
  description: string
  amount?: number
  purpose?: string
}

// Contract addresses
const P2P_LENDING_ADDRESS = process.env.NEXT_PUBLIC_P2PLENDING_CONTRACT_ADDRESS as `0x${string}`
const REPUTATION_ADDRESS = process.env.NEXT_PUBLIC_REPUTATION_CONTRACT_ADDRESS as `0x${string}`
const USER_REGISTRY_ADDRESS = process.env.NEXT_PUBLIC_USERREGISTRY_CONTRACT_ADDRESS as `0x${string}`
const WETH_ADDRESS = process.env.NEXT_PUBLIC_WETH_CONTRACT_ADDRESS as `0x${string}`

// Flow EVM Testnet explorer
const FLOW_EXPLORER_BASE = "https://evm-testnet.flowscan.io"

// WETH ABI (minimal)
const WETH_ABI = [
  {
    inputs: [],
    name: "deposit",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [{ name: "wad", type: "uint256" }],
    name: "withdraw",
    outputs: [],
    stateMutability: "nonpayable", 
    type: "function",
  },
  {
    inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
]

// Client-only wrapper to prevent hydration issues
const ClientOnlyUncleApp = () => {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted) {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-center p-6 text-center">
        <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-blue-600 mb-6"></div>
        <h1 className="text-2xl font-bold mb-4">Loading Uncle Credit...</h1>
      </div>
    )
  }

  return <UncleAppInternal />
}

const UncleAppInternal = () => {
  const { address: connectedAddress, isConnected, chain } = useAccount()
  const { writeContract, data: writeData, isPending: isWritePending, error: writeError } = useWriteContract()
  
  const [userMode, setUserMode] = useState<UserMode | null>(null)
  const [currentScreen, setCurrentScreen] = useState<ScreenState>("MODE_SELECTION")
  const [transactions, setTransactions] = useState<Transaction[]>([])
  const [currentTxHash, setCurrentTxHash] = useState<string | null>(null)
  const [pendingTransaction, setPendingTransaction] = useState<PendingTransaction | null>(null)
  const [userName, setUserName] = useState<string>("")
  const [isRegistering, setIsRegistering] = useState<boolean>(false)

  const [userLoanDetails, setUserLoanDetails] = useState<UserLoanDetails>({
    borrowerName: "User",
    originalLoanAmount: 0,
    amountActuallyFundedByVouchers: 0,
    totalPaidOnCurrentLoan: 0,
    currentScore: 0,
    remainingBalanceToRepay: 0,
    purpose: "",
    vouchers: [],
    repaymentDays: 7,
    platformFeePercentage: 5,
    loanStatus: "pending_approval",
  })

  // Clear any auto-connections on app start
  useEffect(() => {
    // Clear any stored wallet connection data only on client
    try {
      // Clear RainbowKit connection cache
      localStorage.removeItem('rainbow-kit-connections')
      localStorage.removeItem('wagmi.store')
      localStorage.removeItem('wagmi.cache')
      localStorage.removeItem('wagmi.wallet')
      localStorage.removeItem('wagmi.connected')
      
      // Clear any other wallet connection data
      localStorage.removeItem('walletconnect')
      localStorage.removeItem('WALLETCONNECT_DEEPLINK_CHOICE')
    } catch (error) {
      // Ignore localStorage errors in SSR
    }
  }, [])

  // Wait for transaction receipt
  const { isLoading: isTxLoading, isSuccess: isTxSuccess, isError: isTxError } = useWaitForTransactionReceipt({
    hash: currentTxHash as `0x${string}`,
  })

  // Read user's reputation score
  const { data: userScore } = useReadContract({
    address: REPUTATION_ADDRESS,
    abi: [
      {
        inputs: [{ name: "user", type: "address" }],
        name: "getReputationScore",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ],
    functionName: "getReputationScore",
    args: connectedAddress ? [connectedAddress] : undefined,
  })

  // Check if user is registered
  const { data: isUserRegistered, refetch: refetchRegistration } = useReadContract({
    address: USER_REGISTRY_ADDRESS,
    abi: [
      {
        inputs: [{ name: "_userAddress", type: "address" }],
        name: "isUserRegistered",
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
      },
    ],
    functionName: "isUserRegistered",
    args: connectedAddress ? [connectedAddress] : undefined,
  })

  // Read active loan offers (for lenders)
  const { data: loanOffers } = useReadContract({
    address: P2P_LENDING_ADDRESS,
    abi: [
      {
        inputs: [{ name: "user", type: "address" }],
        name: "getUserLoanOfferIds",
        outputs: [{ name: "", type: "bytes32[]" }],
        stateMutability: "view",
        type: "function",
      },
    ],
    functionName: "getUserLoanOfferIds",
    args: connectedAddress ? [connectedAddress] : undefined,
  })

  // Handle transaction state changes
  useEffect(() => {
    if (writeData && pendingTransaction) {
      const newTx: Transaction = {
        hash: writeData,
        description: pendingTransaction.description,
        status: "pending",
        timestamp: Date.now(),
        explorerUrl: `${FLOW_EXPLORER_BASE}/tx/${writeData}`,
        type: pendingTransaction.type,
      }
      setTransactions(prev => [newTx, ...prev])
      setCurrentTxHash(writeData)
      setCurrentScreen("TRANSACTION_PENDING")
      toast.loading("Transaction submitted to Flow testnet...", { id: writeData })
    }
  }, [writeData, pendingTransaction])

  useEffect(() => {
    if (isTxSuccess && currentTxHash && pendingTransaction) {
      setTransactions(prev => 
        prev.map(tx => 
          tx.hash === currentTxHash 
            ? { ...tx, status: "success" as const }
            : tx
        )
      )
      
      toast.success("Transaction confirmed on Flow!", { id: currentTxHash })
      
      // Handle different transaction types
      if (pendingTransaction.type === "loan_request") {
        setUserLoanDetails(prev => ({
          ...prev,
          originalLoanAmount: pendingTransaction.amount || 0,
          remainingBalanceToRepay: pendingTransaction.amount || 0,
          purpose: pendingTransaction.purpose || "",
          loanStatus: "awaiting_vouchers",
          currentScore: Number(userScore || 0),
        }))
        setCurrentScreen("LOAN_APPLICATION_SUCCESS")
      } else if (pendingTransaction.type === "loan_offer") {
        setCurrentScreen("LENDER_DASHBOARD")
      } else if (pendingTransaction.type === "vouch" && pendingTransaction.description.includes("Registering user")) {
        // User registration successful
        refetchRegistration()
        setIsRegistering(false)
        setCurrentScreen("MODE_SELECTION")
        toast.success("Registration successful! You can now create loans.")
      }
      
      setPendingTransaction(null)
      setCurrentTxHash(null)
    }
  }, [isTxSuccess, currentTxHash, pendingTransaction, userScore, refetchRegistration])

  useEffect(() => {
    if (isTxError && currentTxHash) {
      setTransactions(prev => 
        prev.map(tx => 
          tx.hash === currentTxHash 
            ? { ...tx, status: "failed" as const }
            : tx
        )
      )
      toast.error("Transaction failed!", { id: currentTxHash })
      setPendingTransaction(null)
      setCurrentTxHash(null)
      // Go back to previous screen
      if (userMode === "borrower") {
        setCurrentScreen("LOAN_APPLICATION")
      } else {
        setCurrentScreen("LENDER_DASHBOARD")
      }
    }
  }, [isTxError, currentTxHash, userMode])

  // Handle user registration
  const handleUserRegistration = async (name: string) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return
    }

    if (chain?.id !== 545) {
      toast.error("Please switch to Flow EVM Testnet (Chain ID: 545)")
      return
    }

    try {
      setIsRegistering(true)
      setPendingTransaction({
        type: "vouch", // Using vouch type for registration
        description: `Registering user: ${name}`,
      })

      await writeContract({
        address: USER_REGISTRY_ADDRESS,
        abi: [
          {
            inputs: [{ name: "_name", type: "string" }],
            name: "registerUser",
            outputs: [],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "registerUser",
        args: [name],
      })

    } catch (error) {
      console.error("Error registering user:", error)
      toast.error("Failed to register user. Please try again.")
      setPendingTransaction(null)
      setIsRegistering(false)
    }
  }

  // Handle loan submission - create a loan request
  const handleLoanSubmitted = async (amount: number, purpose: string) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return
    }

    if (chain?.id !== 545) {
      toast.error("Please switch to Flow EVM Testnet (Chain ID: 545)")
      return
    }

    try {
      setPendingTransaction({
        type: "loan_request",
        description: `Requesting ${amount} ETH loan for ${purpose}`,
        amount,
        purpose,
      })

      await writeContract({
        address: P2P_LENDING_ADDRESS,
        abi: [
          {
            inputs: [
              { name: "amount", type: "uint256" },
              { name: "token", type: "address" },
              { name: "proposedInterestRateBPS", type: "uint16" },
              { name: "proposedDurationSeconds", type: "uint256" },
              { name: "offeredCollateralAmount", type: "uint256" },
              { name: "collateralToken", type: "address" },
            ],
            name: "createLoanRequest",
            outputs: [{ name: "requestId", type: "bytes32" }],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "createLoanRequest",
        args: [
          parseEther(amount.toString()),
          WETH_ADDRESS, // WETH token address for Flow EVM Testnet
          500, // 5% interest rate in basis points
          BigInt(7 * 24 * 60 * 60), // 7 days duration in seconds
          BigInt(0), // no collateral offered
          "0x0000000000000000000000000000000000000000", // no collateral token
        ],
      })

    } catch (error) {
      console.error("Error creating loan request:", error)
      toast.error("Failed to create loan request. Please try again.")
      setPendingTransaction(null)
    }
  }

  // Handle creating a loan offer (lender flow)
  const handleCreateLoanOffer = async (amount: number, interestRate: number) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return
    }

    if (chain?.id !== 545) {
      toast.error("Please switch to Flow EVM Testnet (Chain ID: 545)")
      return
    }

    try {
      setPendingTransaction({
        type: "loan_offer",
        description: `Preparing loan offer: ${amount} ETH at ${interestRate}% APR`,
        amount,
      })

      // Step 1: Wrap ETH to WETH
      toast("Step 1/3: Wrapping ETH to WETH...")
      const wrapSuccess = await handleWrapETH(amount)
      if (!wrapSuccess) {
        setPendingTransaction(null)
        return
      }

      // Step 2: Approve WETH for P2P contract
      toast("Step 2/3: Approving WETH for lending contract...")
      const approveSuccess = await handleApproveWETH(amount)
      if (!approveSuccess) {
        setPendingTransaction(null)
        return
      }

      // Step 3: Create loan offer
      toast("Step 3/3: Creating loan offer...")
      setPendingTransaction({
        type: "loan_offer",
        description: `Creating loan offer: ${amount} WETH at ${interestRate}% APR`,
        amount,
      })

      await writeContract({
        address: P2P_LENDING_ADDRESS,
        abi: [
          {
            inputs: [
              { name: "amount", type: "uint256" },
              { name: "token", type: "address" },
              { name: "interestRateBPS", type: "uint16" },
              { name: "durationSeconds", type: "uint256" },
              { name: "requiredCollateralAmount", type: "uint256" },
              { name: "collateralToken", type: "address" },
            ],
            name: "createLoanOffer",
            outputs: [{ name: "offerId", type: "bytes32" }],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "createLoanOffer",
        args: [
          parseEther(amount.toString()),
          WETH_ADDRESS, // WETH token address for Flow EVM Testnet
          interestRate * 100, // convert to basis points
          BigInt(7 * 24 * 60 * 60), // 7 days duration
          BigInt(0), // no collateral required
          "0x0000000000000000000000000000000000000000", // no collateral token
        ],
      })

    } catch (error) {
      console.error("Error creating loan offer:", error)
      toast.error("Failed to create loan offer. Please try again.")
      setPendingTransaction(null)
    }
  }

  // Handle vouching action
  const handleVouchAction = async (vouchedForBorrowerName: string, vouchedAmount: number, message: string) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return
    }

    try {
      // For now, simulate vouching by updating local state
      // In a real implementation, you'd call the reputation contract's vouching function
      const newVoucher: Voucher = {
        name: "You",
        amount: vouchedAmount,
        avatarUrl: "/placeholder.svg?height=40&width=40",
      }

      setUserLoanDetails((prev) => ({
        ...prev,
        amountActuallyFundedByVouchers: prev.amountActuallyFundedByVouchers + vouchedAmount,
        vouchers: [...prev.vouchers, newVoucher],
        loanStatus: prev.amountActuallyFundedByVouchers + vouchedAmount >= prev.originalLoanAmount ? "active" : prev.loanStatus,
      }))

      // Create a simulated transaction for vouching
      const simulatedTx: Transaction = {
        hash: `0x${Math.random().toString(16).substr(2, 64)}`,
        description: `Vouched ${vouchedAmount} ETH for ${vouchedForBorrowerName}`,
        status: "success",
        timestamp: Date.now(),
        explorerUrl: `${FLOW_EXPLORER_BASE}/tx/0x${Math.random().toString(16).substr(2, 64)}`,
        type: "vouch",
      }
      setTransactions(prev => [simulatedTx, ...prev])

      setCurrentScreen("VOUCHING_SUCCESS")
      toast.success("Vouching successful!")
    } catch (error) {
      console.error("Error vouching:", error)
      toast.error("Failed to vouch. Please try again.")
    }
  }

  // Handle WETH wrapping
  const handleWrapETH = async (amount: number) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return false
    }

    try {
      await writeContract({
        address: WETH_ADDRESS,
        abi: WETH_ABI,
        functionName: "deposit",
        value: parseEther(amount.toString()),
      })
      return true
    } catch (error) {
      console.error("Error wrapping ETH:", error)
      toast.error("Failed to wrap ETH")
      return false
    }
  }

  // Handle WETH approval for P2P contract
  const handleApproveWETH = async (amount: number) => {
    if (!isConnected || !connectedAddress) {
      toast.error("Please connect your wallet first!")
      return false
    }

    try {
      await writeContract({
        address: WETH_ADDRESS,
        abi: WETH_ABI,
        functionName: "approve",
        args: [P2P_LENDING_ADDRESS, parseEther(amount.toString())],
      })
      return true
    } catch (error) {
      console.error("Error approving WETH:", error)
      toast.error("Failed to approve WETH")
      return false
    }
  }

  // Network status component
  const NetworkStatus = () => {
    if (!chain) return null
    
    const isCorrectNetwork = chain.id === 545
    
    return (
      <div className={`fixed top-4 left-4 px-3 py-2 rounded-lg text-sm font-medium z-50 ${
        isCorrectNetwork 
          ? "bg-green-100 text-green-800" 
          : "bg-red-100 text-red-800"
      }`}>
        {isCorrectNetwork 
          ? `✓ Flow Testnet (${chain.name})`
          : `⚠ Wrong Network: ${chain.name}`
        }
      </div>
    )
  }

  // Mode selection screen
  if (!isConnected) {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-center p-6 text-center">
        <h1 className="text-3xl font-bold mb-4">Uncle Credit</h1>
        <p className="text-lg mb-8">Connect your wallet to start</p>
        <p className="text-sm text-gray-600 mb-4">
          Use the RainbowKit button in the top right corner
        </p>
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 max-w-md">
          <p className="text-sm text-blue-800">
            <strong>Make sure to connect to Flow EVM Testnet!</strong><br/>
            Chain ID: 545<br/>
            RPC: https://testnet.evm.nodes.onflow.org
          </p>
        </div>
      </div>
    )
  }

  if (currentScreen === "TRANSACTION_PENDING") {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-center p-6 text-center max-w-md mx-auto">
        <NetworkStatus />
        
        {/* Animated spinner */}
        <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-blue-600 mb-6"></div>
        
        <h1 className="text-2xl font-bold mb-4">Processing Transaction</h1>
        
        {pendingTransaction && (
          <div className="space-y-4">
            <p className="text-lg text-gray-700">{pendingTransaction.description}</p>
            
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <p className="text-sm text-blue-800">
                <strong>Your transaction is being processed on Flow EVM Testnet</strong>
              </p>
              <p className="text-xs text-blue-600 mt-2">
                This may take a few seconds to confirm...
              </p>
            </div>
            
            {currentTxHash && (
              <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
                <p className="text-sm text-gray-600 mb-2">Transaction Hash:</p>
                <div className="flex items-center space-x-2">
                  <code className="text-xs bg-white px-2 py-1 rounded border flex-1 truncate">
                    {currentTxHash}
                  </code>
                  <a
                    href={`${FLOW_EXPLORER_BASE}/tx/${currentTxHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 hover:text-blue-800 text-sm font-medium"
                  >
                    View →
                  </a>
                </div>
              </div>
            )}
          </div>
        )}
        
        <div className="flex items-center space-x-2 mt-8 text-gray-500">
          <div className="w-2 h-2 bg-blue-600 rounded-full animate-bounce"></div>
          <div className="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style={{animationDelay: '0.1s'}}></div>
          <div className="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style={{animationDelay: '0.2s'}}></div>
        </div>
      </div>
    )
  }

  // User registration screen
  if (isConnected && !isUserRegistered) {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-center p-6 text-center max-w-md mx-auto">
        <NetworkStatus />
        
        <h1 className="text-3xl font-bold mb-4">Uncle Credit</h1>
        <h2 className="text-xl font-semibold mb-6">Complete Registration</h2>
        
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
          <p className="text-sm text-yellow-800">
            <strong>Registration Required</strong><br/>
            You need to register with Uncle Credit before creating loans or offers.
          </p>
        </div>
        
        <div className="w-full space-y-4">
          <input
            type="text"
            placeholder="Enter your display name"
            value={userName}
            onChange={(e) => setUserName(e.target.value)}
            className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            maxLength={50}
            disabled={isRegistering}
          />
          
          <button
            onClick={() => handleUserRegistration(userName)}
            disabled={!userName.trim() || isRegistering}
            className="w-full bg-blue-600 text-white font-bold py-4 px-6 rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isRegistering ? "Registering..." : "Register"}
          </button>
        </div>
        
        <p className="text-sm text-gray-600 mt-6">
          Registration requires a blockchain transaction and costs a small gas fee.
        </p>
      </div>
    )
  }

  if (currentScreen === "MODE_SELECTION") {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-center p-6 text-center max-w-md mx-auto">
        <NetworkStatus />
        
        <h1 className="text-3xl font-bold mb-8">Uncle Credit</h1>
        <p className="text-lg mb-8">Choose your role:</p>
        
        <div className="space-y-4 w-full">
          <button
            onClick={() => {
              setUserMode("borrower")
              setCurrentScreen("LOAN_APPLICATION")
            }}
            className="w-full bg-blue-600 text-white font-bold py-4 px-6 rounded-lg hover:bg-blue-700 transition-colors"
          >
            I want to borrow money
          </button>
          
          <button
            onClick={() => {
              setUserMode("lender")
              setCurrentScreen("LENDER_DASHBOARD")
            }}
            className="w-full bg-green-600 text-white font-bold py-4 px-6 rounded-lg hover:bg-green-700 transition-colors"
          >
            I want to lend money
          </button>
        </div>

        {/* Recent Transactions */}
        {transactions.length > 0 && (
          <div className="mt-8 w-full">
            <h3 className="text-lg font-semibold mb-4">Recent Transactions</h3>
            <div className="space-y-2">
              {transactions.slice(0, 3).map((tx) => (
                <div key={tx.hash} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div className="flex items-center space-x-3">
                    <div className={`w-3 h-3 rounded-full ${
                      tx.status === "success" ? "bg-green-500" : 
                      tx.status === "failed" ? "bg-red-500" : "bg-yellow-500"
                    }`} />
                    <span className="text-sm">{tx.description}</span>
                  </div>
                  <a
                    href={tx.explorerUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 hover:text-blue-800 text-sm"
                  >
                    View
                  </a>
                </div>
              ))}
            </div>
          </div>
        )}

        <button
          onClick={() => {
            setUserMode(null)
            setCurrentScreen("MODE_SELECTION")
          }}
          className="mt-8 text-gray-600 text-sm"
        >
          Switch Mode
        </button>
      </div>
    )
  }

  if (currentScreen === "LENDER_DASHBOARD") {
    return (
      <div className="min-h-screen bg-white flex flex-col p-6 max-w-md mx-auto">
        <NetworkStatus />
        
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold">Lender Dashboard</h1>
          <button
            onClick={() => setCurrentScreen("MODE_SELECTION")}
            className="text-gray-600 text-sm"
          >
            Switch Mode
          </button>
        </div>

        <div className="mb-6">
          <p className="text-gray-600 mb-2">Your lending score:</p>
          <p className="text-4xl font-bold text-green-600">{Number(userScore || 0)}</p>
        </div>

        <div className="space-y-4">
          <div>
            <h3 className="text-lg font-semibold mb-3">Create Loan Offer</h3>
            <div className="space-y-3">
              <div className="flex space-x-2">
                <button
                  onClick={() => handleCreateLoanOffer(0.01, 5)} // 0.01 ETH for testing
                  className="flex-1 bg-green-600 text-white py-3 px-4 rounded-lg font-semibold disabled:opacity-50"
                  disabled={isWritePending}
                >
                  {isWritePending ? "Creating..." : "Offer 0.01 ETH (5% APR)"}
                </button>
                <button
                  onClick={() => handleCreateLoanOffer(0.025, 4)} // 0.025 ETH for testing
                  className="flex-1 bg-green-600 text-white py-3 px-4 rounded-lg font-semibold disabled:opacity-50"
                  disabled={isWritePending}
                >
                  {isWritePending ? "Creating..." : "Offer 0.025 ETH (4% APR)"}
                </button>
              </div>
              <button
                onClick={() => handleCreateLoanOffer(0.05, 3)} // 0.05 ETH for testing
                className="w-full bg-green-600 text-white py-3 px-4 rounded-lg font-semibold disabled:opacity-50"
                disabled={isWritePending}
              >
                {isWritePending ? "Creating..." : "Offer 0.05 ETH (3% APR)"}
              </button>
            </div>
          </div>

          {/* Active Offers */}
          <div>
            <h3 className="text-lg font-semibold mb-3">Your Active Offers</h3>
            {loanOffers && (loanOffers as any[]).length > 0 ? (
              <div className="space-y-2">
                {(loanOffers as any[]).map((offerId, index) => (
                  <div key={index} className="p-3 bg-gray-50 rounded-lg">
                    <p className="text-sm">Offer ID: {String(offerId).substring(0, 10)}...</p>
                    <p className="text-sm text-gray-600">Active</p>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-gray-600 text-sm">No active offers</p>
            )}
          </div>

          {/* Recent Transactions */}
          {transactions.length > 0 && (
            <div>
              <h3 className="text-lg font-semibold mb-3">Recent Transactions</h3>
              <div className="space-y-2">
                {transactions.slice(0, 5).map((tx) => (
                  <div key={tx.hash} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div className="flex items-center space-x-3">
                      <div className={`w-3 h-3 rounded-full ${
                        tx.status === "success" ? "bg-green-500" : 
                        tx.status === "failed" ? "bg-red-500" : "bg-yellow-500"
                      }`} />
                      <div>
                        <p className="text-sm font-medium">{tx.description}</p>
                        <p className="text-xs text-gray-500">
                          {new Date(tx.timestamp).toLocaleTimeString()}
                        </p>
                      </div>
                    </div>
                    <a
                      href={tx.explorerUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-blue-600 hover:text-blue-800 text-sm font-medium"
                    >
                      View →
                    </a>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    )
  }

  // Rest of the borrower flow screens...
  const borrowerScreens = () => {
    switch (currentScreen) {
      case "LOAN_APPLICATION":
        return (
          <div className="relative">
            <NetworkStatus />
            <LoanApplication onLoanSubmitted={handleLoanSubmitted} />
          </div>
        )

      case "LOAN_APPLICATION_SUCCESS":
        return (
          <div className="relative">
            <NetworkStatus />
            <LoanSuccessScreen
              loanAmount={userLoanDetails.originalLoanAmount}
              loanPurpose={userLoanDetails.purpose}
              onContinue={() => setCurrentScreen("LOAN_STATUS")}
            />
          </div>
        )

      case "LOAN_STATUS":
        return (
          <div className="relative">
            <NetworkStatus />
            <LoanStatusScreen
              loanAmount={userLoanDetails.originalLoanAmount}
              loanPurpose={userLoanDetails.purpose}
              amountFundedByVouchers={userLoanDetails.amountActuallyFundedByVouchers}
              userRepaymentAmount={userLoanDetails.totalPaidOnCurrentLoan}
              vouchers={userLoanDetails.vouchers}
              score={userLoanDetails.currentScore}
              onAskForNewLoan={() => setCurrentScreen("LOAN_APPLICATION")}
              onShare={() => setCurrentScreen("COMMUNITY_VOUCHING")}
              loanStatus={userLoanDetails.loanStatus}
              currencySymbol="ETH"
              repaymentDays={userLoanDetails.repaymentDays}
            />
          </div>
        )

      case "COMMUNITY_VOUCHING":
        return (
          <div className="relative">
            <NetworkStatus />
            <CommunityVouchingScreen
              currentUserScore={userLoanDetails.currentScore}
              borrowerName="Demo User"
              loanAmount={0.05} // Using smaller amounts for testing
              loanFundedAmount={0.025}
              loanPurpose="business equipment"
              existingVouchersCount={2}
              repaymentDays={7}
              onVouch={handleVouchAction}
              onAskForLoan={() => setCurrentScreen("LOAN_APPLICATION")}
              currentUserVouchingPower={0.5}
            />
          </div>
        )

      default:
        return (
          <div className="relative">
            <NetworkStatus />
            <LoanApplication onLoanSubmitted={handleLoanSubmitted} />
          </div>
        )
    }
  }

  return (
    <div className="relative">
      {userMode === "borrower" ? borrowerScreens() : null}
    </div>
  )
}

export default function UncleApp() {
  return <ClientOnlyUncleApp />
}