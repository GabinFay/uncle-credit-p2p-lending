"use client"

import { CheckCircle, TrendingUp, ShieldCheck, ListChecks, ArrowRight, History, MessageSquare } from "lucide-react" // Added MessageSquare

interface VouchingSuccessScreenProps {
  borrowerName: string
  vouchAmount: number
  currencySymbol?: string
  loanFundedAmount: number
  loanTotalAmount: number
  userMessageToBorrower?: string
  // voucherOrdinal?: string; // Removed as per previous simplification
  scoreIncrease: number
  newVouchingScore: number
  remainingVouchingPower: number
  repaymentDays: number
  vouchProtectionDays?: number
  // onContinueHelping?: () => void; // Removed as per previous simplification
  onViewHistory?: () => void
  onDone?: () => void
}

export default function VouchingSuccessScreen({
  borrowerName,
  vouchAmount,
  currencySymbol = "$",
  loanFundedAmount,
  loanTotalAmount,
  userMessageToBorrower,
  scoreIncrease,
  newVouchingScore,
  remainingVouchingPower,
  repaymentDays,
  vouchProtectionDays = 30,
  onViewHistory,
  onDone,
}: VouchingSuccessScreenProps) {
  const fundingProgressPercent = Math.min((loanFundedAmount / loanTotalAmount) * 100, 100)
  const amountStillNeeded = Math.max(0, loanTotalAmount - loanFundedAmount)

  return (
    <div className="min-h-screen bg-slate-50 text-slate-800 p-4 sm:p-6 overflow-y-auto">
      <div className="max-w-lg mx-auto flex flex-col items-center text-center">
        {/* Good Deed Celebration */}
        <CheckCircle className="w-16 h-16 sm:w-20 sm:h-20 text-green-500 my-6" strokeWidth={1.5} />
        <h1 className="text-2xl sm:text-3xl font-bold text-slate-900 mb-2">
          You Helped {borrowerName} <br /> with a{" "}
          <span className="text-green-600">
            {currencySymbol}
            {vouchAmount.toFixed(2)}
          </span>{" "}
          vouch!
        </h1>

        {/* Impact Visualization */}
        <div className="bg-white p-4 sm:p-6 rounded-lg shadow-md w-full my-6">
          <h2 className="text-lg font-semibold text-slate-700 mb-1">Loan Progress</h2>
          <p className="text-2xl font-bold text-green-600 mb-2">
            {currencySymbol}
            {loanFundedAmount.toFixed(2)} / {currencySymbol}
            {loanTotalAmount.toFixed(2)} funded
          </p>
          <div className="w-full bg-slate-200 rounded-full h-4 mb-2">
            <div
              className="bg-green-500 h-4 rounded-full transition-all duration-500 ease-out"
              style={{ width: `${fundingProgressPercent}%` }}
            ></div>
          </div>
          {amountStillNeeded > 0 ? (
            <p className="text-sm text-slate-600">
              Only {currencySymbol}
              {amountStillNeeded.toFixed(2)} more needed.
            </p>
          ) : (
            <p className="text-sm text-green-600 font-semibold">Fully Funded! 🎉</p>
          )}
        </div>

        {/* Your Contribution */}
        <div className="bg-white p-4 sm:p-6 rounded-lg shadow-md w-full mb-6 text-left">
          <h3 className="text-md font-semibold text-slate-700 mb-2 flex items-center">
            <MessageSquare className="w-5 h-5 mr-2 text-green-500" /> Your Contribution
          </h3>
          <p className="text-slate-600">
            You vouched:{" "}
            <span className="font-bold text-green-600">
              {currencySymbol}
              {vouchAmount.toFixed(2)}
            </span>
          </p>
          {userMessageToBorrower && (
            <p className="text-slate-600 mt-1 text-sm italic">Your message: "{userMessageToBorrower}"</p>
          )}
        </div>

        {/* Community Impact Section was removed in previous step */}

        {/* Score Rewards */}
        <div className="bg-gradient-to-br from-green-500 to-emerald-600 text-white p-4 sm:p-6 rounded-lg shadow-lg w-full mb-6">
          <h3 className="text-lg font-semibold mb-2 flex items-center justify-center">
            <TrendingUp className="w-6 h-6 mr-2" /> Score Rewards
          </h3>
          <p className="text-xl font-bold">
            Vouching Score: +{scoreIncrease} points! (Now {newVouchingScore})
          </p>
          <p className="text-sm">
            Vouching Power:{" "}
            <span className="font-semibold">
              {currencySymbol}
              {remainingVouchingPower.toFixed(2)}
            </span>
          </p>
          <p className="text-xs italic mt-2 opacity-90">You're building community trust!</p>
        </div>

        {/* What Happens Next (Simplified) */}
        <div className="bg-white p-4 sm:p-5 rounded-lg shadow-md w-full mb-6 text-left text-sm">
          <h3 className="text-md font-semibold text-slate-700 mb-2 flex items-center">
            <ListChecks className="w-5 h-5 mr-2 text-green-500" /> What Happens Next
          </h3>
          <ul className="space-y-1 text-slate-600 list-disc list-inside pl-1">
            <li>
              {borrowerName} repays in {repaymentDays} days (post-funding).
            </li>
            <li>You're notified on payback & your vouch is returned.</li>
            <li>Timely repayment boosts your Vouching Score further!</li>
          </ul>
        </div>

        {/* Vouching Protection (Simplified) */}
        <div className="bg-white p-4 sm:p-5 rounded-lg shadow-md w-full mb-8 text-left text-sm">
          <h3 className="text-md font-semibold text-slate-700 mb-2 flex items-center">
            <ShieldCheck className="w-5 h-5 mr-2 text-green-500" /> Vouching Protection
          </h3>
          <ul className="space-y-1 text-slate-600 list-disc list-inside pl-1">
            <li>Your vouch is protected for {vouchProtectionDays} days.</li>
            <li>Mediation support available for repayment issues.</li>
          </ul>
        </div>

        {/* Action Buttons */}
        <div className="w-full grid grid-cols-1 sm:grid-cols-2 gap-3 mb-6">
          {onViewHistory && (
            <button
              onClick={onViewHistory}
              className="bg-slate-200 text-slate-700 font-semibold py-3 px-4 rounded-lg hover:bg-slate-300 transition-colors w-full text-md flex items-center justify-center"
            >
              <History className="w-5 h-5 mr-2" /> View History
            </button>
          )}
          {onDone && (
            <button
              onClick={onDone}
              className="bg-slate-700 text-white font-semibold py-3 px-4 rounded-lg hover:bg-slate-800 transition-colors w-full text-md flex items-center justify-center"
            >
              Done <ArrowRight className="w-5 h-5 ml-2" />
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
