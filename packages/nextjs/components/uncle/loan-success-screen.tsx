"use client"

import { CheckCircle } from "lucide-react" // Using a check icon for celebration

interface LoanSuccessScreenProps {
  loanAmount: number
  loanPurpose: string
  onContinue: () => void
}

export default function LoanSuccessScreen({ loanAmount, loanPurpose, onContinue }: LoanSuccessScreenProps) {
  const nextSteps = [
    "Community members will see your request",
    "Friends can vouch for you to fund the loan",
    "You'll be notified when fully funded",
    "Money will be available right after",
  ]

  return (
    <div className="min-h-screen bg-green-500 flex flex-col items-center justify-center p-6 text-white text-center">
      <div className="max-w-md w-full">
        <CheckCircle className="mx-auto mb-6 h-16 w-16 text-white" strokeWidth={1.5} />
        <h1 className="text-3xl sm:text-4xl font-bold mb-3">Done!</h1>
        <p className="text-xl sm:text-2xl font-semibold mb-10">
          You’ve successfully asked <br /> ${loanAmount.toFixed(2)} for {loanPurpose}.
        </p>

        <div className="bg-white/10 p-6 rounded-lg mb-10 text-left">
          <h2 className="text-lg font-semibold mb-4 text-center">What happens next?</h2>
          <ul className="space-y-3">
            {nextSteps.map((step, index) => (
              <li key={index} className="flex items-start">
                <span className="text-green-300 mr-3 text-xl font-bold">{index + 1}.</span>
                <span className="text-sm">{step}</span>
              </li>
            ))}
          </ul>
        </div>

        <button
          onClick={onContinue}
          className="w-full max-w-xs mx-auto bg-white text-green-600 font-bold py-3 px-6 rounded-lg text-lg hover:bg-gray-100 transition-colors"
          aria-label="Continue to loan status"
        >
          Continue
        </button>
      </div>
    </div>
  )
}
