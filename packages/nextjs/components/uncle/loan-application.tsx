"use client"

import { useState } from "react"
import { Button } from "~~/components/ui/button"
import { Input } from "~~/components/ui/input"

type LoanAmount = 10 | 25 | 50 | 75 | 100

interface LoanApplicationProps {
  onLoanSubmitted?: (amount: LoanAmount, purpose: string) => void
  onCancel?: () => void // This prop determines if the Cancel button is shown
}

const PRESET_AMOUNTS: LoanAmount[] = [10, 25, 50, 75, 100]

export default function LoanApplication({ onLoanSubmitted, onCancel }: LoanApplicationProps) {
  const [selectedAmount, setSelectedAmount] = useState<LoanAmount | null>(null)
  const [loanPurpose, setLoanPurpose] = useState("")

  const handleAmountSelect = (amount: LoanAmount) => {
    setSelectedAmount(amount)
  }

  const handlePurposeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setLoanPurpose(e.target.value)
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (selectedAmount && loanPurpose.trim() && onLoanSubmitted) {
      onLoanSubmitted(selectedAmount, loanPurpose.trim())
    }
  }

  return (
    <div className="min-h-screen bg-white flex flex-col p-4 sm:p-6 max-w-md mx-auto">
      {/* Header */}
      <header className="flex items-center justify-between mb-4 w-full">
        {onCancel && (
          <button onClick={onCancel} className="text-sm text-black font-medium" aria-label="Cancel">
            Cancel
          </button>
        )}
        <div className="flex-1 text-center">
          <h1 className="text-xl sm:text-2xl font-bold">New loan</h1>
        </div>
        <div className="w-14"></div> {/* Spacer for centering title when cancel exists */}
      </header>

      {/* Form */}
      <form onSubmit={handleSubmit} className="flex-grow flex flex-col justify-between">
        <div className="space-y-6 sm:space-y-8">
          {/* Amount Selection */}
          <div>
            <h2 className="text-lg sm:text-xl font-semibold text-black mb-4">How much do you need?</h2>
            <div className="grid grid-cols-3 gap-2 sm:gap-3">
              {PRESET_AMOUNTS.map((amount) => (
                <button
                  key={amount}
                  type="button"
                  onClick={() => handleAmountSelect(amount)}
                  className={`
                    py-3 px-4 text-lg font-semibold rounded-lg border-2 transition-colors
                    ${
                      selectedAmount === amount
                        ? "bg-black text-white border-black"
                        : "bg-gray-100 text-black border-gray-300 hover:border-gray-400"
                    }
                  `}
                  aria-label={`Select $${amount}`}
                >
                  R${amount}
                </button>
              ))}
            </div>
          </div>

          {/* Purpose Input */}
          <div>
            <h2 className="text-lg sm:text-xl font-semibold text-black mb-4">What will you use it for?</h2>
            <Input
              type="text"
              value={loanPurpose}
              onChange={handlePurposeChange}
              placeholder="Enter the purpose of your loan"
              className="w-full p-4 text-lg border-2 border-gray-300 rounded-lg focus:border-black focus:outline-none"
              aria-label="Loan purpose"
            />
          </div>
        </div>

        {/* Submit Button */}
        <div className="mt-auto">
          <Button
            type="submit"
            disabled={!selectedAmount || !loanPurpose.trim()}
            className="w-full bg-black text-white font-semibold py-4 text-lg rounded-lg hover:bg-gray-800 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed h-14"
            aria-label="Submit loan application"
          >
            Apply for loan
          </Button>
        </div>
      </form>
    </div>
  )
} 