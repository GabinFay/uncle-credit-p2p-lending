"use client"

import { Button } from "~~/components/ui/button"

interface LoanDashboardScreenProps {
  score: number // This is totalPaidOnCurrentLoan
  currentLoanAmount: number // Remaining balance
  originalLoanAmount: number // Initial loan amount
  amountPaid: number // Total paid so far
  loanPurpose: string
  vouchersCount: number // Keep or remove based on relevance for this screen's focus
  onPayNow: () => void
  onNotReadyToPay?: () => void
  onAskForNewLoan: () => void
  currencySymbol?: string
  isOverdue?: boolean
}

export default function LoanDashboardScreen({
  score,
  currentLoanAmount,
  originalLoanAmount,
  amountPaid = 0,
  loanPurpose,
  vouchersCount,
  onPayNow,
  onNotReadyToPay,
  onAskForNewLoan,
  currencySymbol = "$",
  isOverdue = false,
}: LoanDashboardScreenProps) {
  const hasRemainingBalance = currentLoanAmount > 0

  return (
    <div className="min-h-screen bg-white flex flex-col items-center justify-between p-6 max-w-md mx-auto">
      {/* Score Section */}
      <div className="w-full text-center mt-8">
        <p className="text-gray-500 text-sm">Your score</p>
        <p className="text-6xl font-bold text-[#26cb4d] my-2 relative inline-block">
          {score}
          <span className="absolute bottom-[-8px] left-0 right-0 h-1 bg-[#26cb4d]"></span>
        </p>
      </div>

      {/* Loan Details Section */}
      <div className="text-center my-10">
        <p className="text-3xl font-bold text-black">
          {currencySymbol}
          {originalLoanAmount.toFixed(2)} for
        </p>
        <p className="text-xl text-black mt-1">{loanPurpose}</p>
        {amountPaid > 0 && (
          <p className="text-gray-500 mt-2 text-md">
            You've paid {currencySymbol}
            {amountPaid.toFixed(2)}
          </p>
        )}
      </div>

      {/* Vouchers Information - Conditionally render if relevant, or remove if screen is focused on payment */}
      {vouchersCount > 0 &&
        amountPaid === 0 &&
        !isOverdue && ( // Example condition: show only on initial dashboard
          <div className="flex items-center justify-center space-x-2 mb-8">
            <div className="flex -space-x-1.5">
              {Array.from({ length: Math.min(vouchersCount, 3) }).map((_, index) => (
                <div
                  key={index}
                  className="w-6 h-6 bg-gray-300 rounded-full border-2 border-white"
                  aria-label={`Voucher ${index + 1}`}
                ></div>
              ))}
            </div>
            <p className="text-sm text-gray-600">
              {vouchersCount} friend{vouchersCount !== 1 ? "s" : ""} vouched for you
            </p>
          </div>
        )}

      {/* Action Buttons and Links */}
      <div className="w-full flex flex-col items-center mt-auto space-y-4">
        {hasRemainingBalance && (
          <Button
            onClick={onPayNow}
            className="bg-black text-white font-semibold py-3.5 px-12 rounded-lg hover:bg-gray-800 transition-colors w-full max-w-xs h-[50px]"
            aria-label="Pay now"
          >
            Pay now
          </Button>
        )}

        {hasRemainingBalance &&
          onNotReadyToPay && ( // If onNotReadyToPay is provided, show this path
            <div className="text-center text-sm mt-3">
              <p className="text-gray-800">
                Your payment is due <span className="font-bold">today</span>.
              </p>
              <button
                onClick={onNotReadyToPay}
                className="text-red-600 hover:text-red-700 underline font-medium"
                aria-label="Not ready to pay?"
              >
                Not ready to pay?
              </button>
            </div>
          )}

        {hasRemainingBalance &&
          !onNotReadyToPay &&
          isOverdue && ( // Only show harsh overdue if onNotReadyToPay is NOT an option
            <div className="text-center text-sm mt-3">
              <p className="text-[#ff0000] font-medium">
                You still have {currencySymbol}
                {currentLoanAmount.toFixed(2)} overdue,
              </p>
              <p className="text-[#ff0000] font-medium">don't risk losing your score.</p>
            </div>
          )}

        {!hasRemainingBalance && amountPaid > 0 && (
          <p className="text-green-600 font-semibold mt-4">Congratulations! Your loan is fully paid!</p>
        )}

        <button
          onClick={onAskForNewLoan}
          className="text-black mt-8 mb-4 text-sm underline"
          aria-label="Ask for a new loan"
        >
          Ask for a new loan
        </button>
      </div>
    </div>
  )
}
