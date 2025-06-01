"use client"
import { useState } from "react"
import Image from "next/image"
import { Button } from "~~/components/ui/button"

interface Voucher {
  name: string
  avatarUrl?: string
  amount: number
}

interface LoanStatusScreenProps {
  loanAmount: number
  loanPurpose: string
  amountFundedByVouchers: number
  userRepaymentAmount: number
  vouchers: Voucher[]
  score: number
  onAskForNewLoan?: () => void
  onShare?: () => void
  onPayNow?: () => void
  onNotReadyToPay?: () => void
  loanStatus: "pending_approval" | "awaiting_vouchers" | "active" | "completed" | "overdue" | "defaulted"
  currencySymbol?: string
  repaymentDays?: number
}

export default function LoanStatusScreen({
  loanAmount,
  loanPurpose,
  amountFundedByVouchers,
  userRepaymentAmount,
  vouchers = [],
  score = 0,
  onAskForNewLoan,
  onShare,
  onPayNow,
  onNotReadyToPay,
  loanStatus,
  currencySymbol = "$",
  repaymentDays = 3,
}: LoanStatusScreenProps) {
  const [isSharing, setIsSharing] = useState(false)

  const isFullyVoucherFunded = amountFundedByVouchers >= loanAmount && loanAmount > 0
  const effectiveLoanPrincipal = Math.min(loanAmount, amountFundedByVouchers)
  const remainingForUserToPay = Math.max(0, effectiveLoanPrincipal - userRepaymentAmount)
  const amountStillNeededFromVouchers = Math.max(0, loanAmount - amountFundedByVouchers)

  const handleShareInternal = async () => {
    if (!onShare) return
    setIsSharing(true)
    onShare()
    setIsSharing(false)
  }

  // Figma design state: Fully voucher funded, user score is 0 (hasn't paid yet)
  if (isFullyVoucherFunded && userRepaymentAmount === 0 && loanStatus === "active") {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-between p-6 max-w-md mx-auto text-center">
        <div className="w-full mt-12">
          <p className="text-gray-500 text-sm">Your score</p>
          <p className="text-7xl font-bold text-[#26cb4d] my-2 relative inline-block">
            {score}
            <span className="absolute bottom-[-10px] left-0 right-0 h-1.5 bg-[#26cb4d]"></span>
          </p>
        </div>

        <div className="my-10">
          <p className="text-4xl font-bold text-black">
            {currencySymbol}
            {loanAmount.toFixed(2)} for
          </p>
          <p className="text-2xl text-black mt-1">{loanPurpose}</p>
        </div>

        {vouchers.length > 0 && (
          <div className="flex items-center justify-center space-x-2 mb-10">
            <div className="flex -space-x-1.5">
              {vouchers.slice(0, 3).map((voucher, index) => (
                <div
                  key={index}
                  className="w-8 h-8 bg-gray-300 rounded-full border-2 border-white"
                  title={voucher.name}
                >
                  {voucher.avatarUrl && (
                    <Image
                      src={voucher.avatarUrl || "/placeholder.svg?height=32&width=32&query=avatar"}
                      alt={voucher.name}
                      width={32}
                      height={32}
                      className="rounded-full"
                    />
                  )}
                </div>
              ))}
            </div>
            <p className="text-sm text-gray-600">
              {vouchers.length} friend{vouchers.length !== 1 ? "s" : ""} vouched for you
            </p>
          </div>
        )}

        <div className="w-full flex flex-col items-center mt-auto space-y-4 pb-6">
          {onPayNow && (
            <Button
              onClick={onPayNow}
              className="bg-black text-white font-bold py-3.5 px-12 rounded-lg hover:bg-gray-800 transition-colors w-full max-w-xs h-[50px] text-lg"
            >
              Pay now
            </Button>
          )}
          <div className="text-center text-sm mt-3">
            <p className="text-gray-500">
              Your payment is due <span className="font-bold text-black">today</span>.
            </p>
            {onNotReadyToPay && (
              <button
                onClick={onNotReadyToPay}
                className="text-red-600 hover:text-red-700 underline font-medium mt-1"
                aria-label="Not ready to pay?"
              >
                Not ready to pay?
              </button>
            )}
          </div>
          {onAskForNewLoan && (
            <button
              onClick={onAskForNewLoan}
              className="text-black mt-10 text-sm font-medium"
              aria-label="Ask for a new loan"
            >
              Ask for a new loan
            </button>
          )}
        </div>
      </div>
    )
  }

  // Awaiting Vouchers State - UPDATED
  if (loanStatus === "awaiting_vouchers" && !isFullyVoucherFunded && loanAmount > 0) {
    return (
      <div className="min-h-screen bg-white flex flex-col items-center justify-between p-6 max-w-md mx-auto text-center">
        <div className="w-full mt-12">
          <p className="text-gray-500 text-sm">Your score</p>
          <p className="text-7xl font-bold text-green-500 my-2 relative inline-block">
            {score}
            <span className="absolute bottom-[-10px] left-0 right-0 h-1.5 bg-green-500"></span>
          </p>
        </div>

        <div className="my-10">
          <p className="text-4xl font-bold text-black">
            {currencySymbol}
            {loanAmount.toFixed(2)} for
          </p>
          <p className="text-2xl text-black mt-1">{loanPurpose}</p>
        </div>

        {/* Vouching Progress Display */}
        <div className="my-8 w-full">
          {vouchers.length > 0 ? (
            <>
              <div className="flex items-center justify-center space-x-2 mb-2">
                <div className="flex -space-x-1.5">
                  {vouchers.slice(0, 3).map((voucher, index) => (
                    <div
                      key={index}
                      className="w-8 h-8 bg-gray-300 rounded-full border-2 border-white"
                      title={`${voucher.name} vouched ${currencySymbol}${voucher.amount.toFixed(2)}`}
                    >
                      {voucher.avatarUrl && (
                        <Image
                          src={voucher.avatarUrl || "/placeholder.svg?height=32&width=32&query=avatar"}
                          alt={voucher.name}
                          width={32}
                          height={32}
                          className="rounded-full"
                        />
                      )}
                    </div>
                  ))}
                </div>
                <p className="text-sm text-gray-600">
                  {vouchers.length} friend{vouchers.length !== 1 ? "s" : ""} vouched
                </p>
              </div>
              <p className="text-gray-700 text-lg">
                <span className="font-bold text-green-600">
                  {currencySymbol}
                  {amountFundedByVouchers.toFixed(2)}
                </span>{" "}
                of {currencySymbol}
                {loanAmount.toFixed(2)} funded
              </p>
              <p className="text-gray-500 text-sm mt-1">
                Still need{" "}
                <span className="font-semibold text-black">
                  {currencySymbol}
                  {amountStillNeededFromVouchers.toFixed(2)}
                </span>
              </p>
            </>
          ) : (
            <p className="text-gray-600">Waiting for vouches...</p>
          )}
        </div>

        <div className="w-full flex flex-col items-center mt-auto space-y-4 pb-6">
          {onShare && (
            <Button
              onClick={handleShareInternal}
              disabled={isSharing}
              className="bg-black text-white font-bold py-3.5 px-12 rounded-lg hover:bg-gray-800 transition-colors disabled:opacity-50 w-full max-w-xs h-[50px] text-lg"
            >
              {isSharing ? "Sharing..." : "Share"}
            </Button>
          )}
          {onAskForNewLoan && (
            <button
              onClick={onAskForNewLoan}
              className="text-black mt-10 text-sm font-medium"
              aria-label="Ask for a new loan"
            >
              Ask for a new loan
            </button>
          )}
        </div>
      </div>
    )
  }

  // Default/Other states (e.g., loan completed, partially paid, overdue but not yet matching Figma)
  return (
    <div className="min-h-screen bg-white flex flex-col items-center justify-between p-6 max-w-md mx-auto">
      <div className="w-full text-center mt-8">
        <p className="text-gray-500 text-sm">Your score</p>
        <p className="text-6xl font-bold text-green-500 my-2 relative inline-block">
          {score}
          <span className="absolute bottom-[-8px] left-0 right-0 h-1 bg-green-500"></span>
        </p>
      </div>

      <div className="text-center my-10">
        <p className="text-3xl font-bold text-black">
          {currencySymbol}
          {loanAmount.toFixed(2)} for
        </p>
        <p className="text-xl text-black mt-1">{loanPurpose}</p>
      </div>

      {/* Vouchers Display for other states if needed */}
      {vouchers.length > 0 && userRepaymentAmount < effectiveLoanPrincipal && !isFullyVoucherFunded && (
        <div className="my-6 w-full">
          <p className="text-center text-sm text-gray-700 mb-2">
            {`${currencySymbol}${amountFundedByVouchers.toFixed(2)} of ${currencySymbol}${loanAmount.toFixed(
              2,
            )} vouched by ${vouchers.length} friend${vouchers.length !== 1 ? "s" : ""}.`}
          </p>
        </div>
      )}

      <div className="w-full flex flex-col items-center mt-auto pb-6">
        {loanStatus === "completed" && (
          <p className="text-center text-green-600 font-semibold mt-4">
            Congratulations! Your loan is fully repaid! Score: {score}
          </p>
        )}

        {/* Pay Now / Not Ready for other overdue/active states if applicable */}
        {(loanStatus === "active" || loanStatus === "overdue") &&
          userRepaymentAmount < effectiveLoanPrincipal &&
          !isFullyVoucherFunded && ( // This condition might need review for partially paid but not fully voucher funded
            <>
              {onPayNow && (
                <Button
                  onClick={onPayNow}
                  className="bg-black text-white font-semibold py-3 px-12 rounded-lg hover:bg-gray-800 transition-colors w-full max-w-xs h-[50px] mt-4"
                >
                  Pay remaining ({currencySymbol}
                  {remainingForUserToPay.toFixed(2)})
                </Button>
              )}
              {onNotReadyToPay && (
                <div className="text-center text-sm mt-4">
                  <p className="text-gray-800">Payment due.</p>
                  <button onClick={onNotReadyToPay} className="text-red-600 hover:text-red-700 underline font-medium">
                    Not ready to pay?
                  </button>
                </div>
              )}
            </>
          )}

        {onAskForNewLoan && (
          <button
            onClick={onAskForNewLoan}
            className="text-black mt-8 text-sm underline"
            aria-label="Ask for a new loan"
          >
            Ask for a new loan
          </button>
        )}
      </div>
    </div>
  )
}
