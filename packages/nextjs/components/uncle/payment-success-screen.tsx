"use client"
import { Button } from "~~/components/ui/button"

interface PaymentSuccessScreenProps {
  paidAmount: number
  currencySymbol?: string
  newRecoveryScore: number // This is the new total score (totalPaid)
  onContinue: () => void // This will now trigger "Ask for a new loan"
  originalLoanAmount?: number // Optional: to show progress like "Score X out of Y"
}

export default function PaymentSuccessScreen({
  paidAmount,
  currencySymbol = "R$",
  newRecoveryScore,
  onContinue,
  originalLoanAmount,
}: PaymentSuccessScreenProps) {
  return (
    <div className="min-h-screen bg-green-500 text-white flex flex-col items-center p-6 overflow-y-auto">
      <div className="max-w-md w-full flex flex-col items-center flex-1">
        {/* Score Section - Top */}
        <div className="w-full text-center pt-8 sm:pt-12">
          <p className="text-green-100 text-sm">Your new score</p>
          <p className="text-6xl sm:text-7xl font-bold text-white my-2 relative inline-block">
            {newRecoveryScore}
            <span className="absolute bottom-[-10px] left-0 right-0 h-1.5 bg-white opacity-75"></span>
          </p>
        </div>

        {/* Paid Amount & Description - Centered Middle Section */}
        <div className="flex-grow flex flex-col justify-center items-center text-center w-full">
          <div className="my-6">
            {" "}
            {/* Added margin for spacing */}
            <h1 className="text-4xl sm:text-5xl font-bold">
              {currencySymbol}
              {paidAmount.toFixed(2)}
            </h1>
            <p className="text-lg sm:text-xl mt-2">
              Your payment was successful!
              {originalLoanAmount &&
                newRecoveryScore < originalLoanAmount &&
                ` Pay ${currencySymbol}${(originalLoanAmount - newRecoveryScore).toFixed(2)} more to reach score ${originalLoanAmount}.`}
              {originalLoanAmount &&
                newRecoveryScore >= originalLoanAmount &&
                ` You've reached a perfect score of ${originalLoanAmount} by fully repaying your loan!`}
            </p>
          </div>
        </div>

        {/* Continue Button - Bottom */}
        <div className="w-full pt-4 pb-8 sm:pb-12">
          <Button
            onClick={onContinue}
            className="w-full max-w-xs mx-auto bg-white text-green-600 font-bold py-3 px-6 rounded-lg text-lg hover:bg-gray-100 transition-colors"
            aria-label="Ask for a new loan"
          >
            Ask for a new loan
          </Button>
        </div>
      </div>
    </div>
  )
}
