"use client"

import { Button } from "~~/components/ui/button"

import { useState } from "react"
import { VouchAmountModal } from "~~/components/uncle/vouch-amount-modal"

interface CommunityVouchingScreenProps {
  currentUserScore: number
  borrowerName: string
  loanAmount: number
  loanFundedAmount?: number
  loanPurpose: string
  existingVouchersCount: number
  repaymentDays: number
  onVouch?: (borrowerName: string, amount: number, message: string) => void
  onAskForLoan?: () => void
  currentUserVouchingPower?: number
  borrowerLoanOriginalAmount?: number
  borrowerLoanTotalPaid?: number // This is the borrower's score for their loan
}

export default function CommunityVouchingScreen({
  currentUserScore,
  borrowerName,
  loanAmount,
  loanFundedAmount = 0,
  loanPurpose,
  existingVouchersCount,
  repaymentDays,
  onVouch,
  onAskForLoan,
  currentUserVouchingPower,
  borrowerLoanOriginalAmount,
  borrowerLoanTotalPaid,
}: CommunityVouchingScreenProps) {
  const [isModalOpen, setIsModalOpen] = useState(false)

  const loanRemainingAmount = Math.max(0, loanAmount - loanFundedAmount)
  const maxUserCanVouchForThisLoan = Math.min(loanRemainingAmount, currentUserVouchingPower ?? Number.POSITIVE_INFINITY)

  const handleOpenVouchModal = () => {
    if (loanRemainingAmount <= 0) {
      alert("This loan is already fully funded!")
      return
    }
    if (maxUserCanVouchForThisLoan <= 0 && loanRemainingAmount > 0) {
      alert(
        "You don't have enough vouching power or the remaining amount is too small to vouch for with preset amounts.",
      )
      return
    }
    setIsModalOpen(true)
  }

  const handleVouchSubmit = (vouchAmount: number, message: string) => {
    if (onVouch) {
      onVouch(borrowerName, vouchAmount, message)
    }
    setIsModalOpen(false)
  }

  const handleAskForNewLoan = () => {
    if (onAskForLoan) {
      onAskForLoan()
    }
  }

  const loanDetailsString = `R$${loanAmount.toFixed(2)} for ${loanPurpose}` // Assuming R$
  const currencySymbol = "R$"

  return (
    <>
      <div className="min-h-screen bg-white flex flex-col items-center justify-between p-6 max-w-md mx-auto">
        <div className="w-full text-center mt-8">
          <p className="text-gray-500 text-sm">Your score</p>
          <div className="mt-2 w-16 h-16 bg-green-500 rounded-full flex items-center justify-center mx-auto">
            <span className="text-white text-2xl font-bold">{currentUserScore}</span>
          </div>
        </div>

        <div className="text-center my-10">
          <h1 className="text-2xl sm:text-3xl font-bold text-black">
            {borrowerName} is asking R$${loanAmount.toFixed(2)}
          </h1>
          <p className="text-lg sm:text-xl text-black mt-1">for {loanPurpose}</p>
          {borrowerLoanOriginalAmount !== undefined &&
            borrowerLoanTotalPaid !== undefined &&
            borrowerLoanOriginalAmount > 0 && (
              <div className="my-4 text-sm text-gray-700">
                <p>
                  {borrowerName} has paid back {currencySymbol}
                  {borrowerLoanTotalPaid.toFixed(2)} of {currencySymbol}
                  {borrowerLoanOriginalAmount.toFixed(2)} on their current/previous loans.
                </p>
                <p>
                  Repayment Score: <span className="font-bold text-green-600">{borrowerLoanTotalPaid}</span> /{" "}
                  {borrowerLoanOriginalAmount}
                </p>
                {/* Simple progress bar */}
                <div className="w-full bg-gray-200 rounded-full h-2.5 mt-1">
                  <div
                    className="bg-green-500 h-2.5 rounded-full"
                    style={{ width: `${(borrowerLoanTotalPaid / borrowerLoanOriginalAmount) * 100}%` }}
                  ></div>
                </div>
              </div>
            )}
        </div>

        {existingVouchersCount > 0 && (
          <div className="flex items-center justify-center space-x-2 my-6">
            <div className="flex -space-x-1">
              {Array.from({ length: Math.min(existingVouchersCount, 2) }).map((_, i) => (
                <div key={i} className="w-5 h-5 bg-gray-300 rounded-full border-2 border-white"></div>
              ))}
            </div>
            <p className="text-sm text-gray-600">
              {existingVouchersCount} other friend{existingVouchersCount > 1 ? "s" : ""} vouched
            </p>
          </div>
        )}
        {loanRemainingAmount <= 0 && <p className="text-green-600 font-semibold my-4">This loan is fully funded! 🎉</p>}

        <div className="w-full flex flex-col items-center mt-auto space-y-4">
          <Button
            onClick={handleOpenVouchModal}
            disabled={loanRemainingAmount <= 0 || maxUserCanVouchForThisLoan < 10} // Disable if smallest preset is too high
            className="bg-black text-white font-semibold py-3.5 px-8 rounded-lg hover:bg-gray-800 transition-colors w-full max-w-xs h-[50px]"
            aria-label={`Vouch for ${borrowerName}`}
          >
            Vouch for {borrowerName}
          </Button>

          <div className="text-center text-sm text-gray-700">
            <p>
              {borrowerName} will have <span className="font-bold">{repaymentDays} days</span>
            </p>
            <p>to pay you back</p>
          </div>

          <button
            onClick={handleAskForNewLoan}
            className="text-black mt-6 mb-4 text-sm underline"
            aria-label="Ask for a loan"
          >
            Ask for a loan
          </button>
        </div>
      </div>
      <VouchAmountModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onSubmit={handleVouchSubmit}
        borrowerName={borrowerName}
        loanDetails={loanDetailsString}
        maxVouchAmount={maxUserCanVouchForThisLoan}
        currencySymbol="R$"
        // presetAmounts={[10, 25, 50, 75, 100]} // Can be customized here if needed
      />
    </>
  )
}
