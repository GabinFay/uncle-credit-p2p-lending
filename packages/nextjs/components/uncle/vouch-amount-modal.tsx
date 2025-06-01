"use client"

import { useState, type FormEvent } from "react"
import { Button } from "~~/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
  // DialogClose, // We'll use a custom Cancel button for positioning
} from "~~/components/ui/dialog"
import { Textarea } from "~~/components/ui/textarea"

interface VouchAmountModalProps {
  isOpen: boolean
  onClose: () => void
  onSubmit: (amount: number, message: string) => void
  borrowerName: string
  loanDetails: string // e.g., "$100 for work equipment"
  maxVouchAmount?: number
  currencySymbol?: string
  presetAmounts?: number[]
}

const DEFAULT_PRESET_AMOUNTS = [10, 25, 50, 75, 100]

export function VouchAmountModal({
  isOpen,
  onClose,
  onSubmit,
  borrowerName,
  loanDetails,
  maxVouchAmount,
  currencySymbol = "$",
  presetAmounts = DEFAULT_PRESET_AMOUNTS,
}: VouchAmountModalProps) {
  const [selectedAmount, setSelectedAmount] = useState<number | null>(null)
  const [message, setMessage] = useState<string>("")
  const [error, setError] = useState<string>("")

  const handleAmountButtonClick = (presetAmount: number) => {
    setSelectedAmount(presetAmount)
    setError("")
  }

  const effectiveMaxAmount = maxVouchAmount ?? Number.POSITIVE_INFINITY

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault()
    if (selectedAmount === null || selectedAmount <= 0) {
      setError("Please select a vouch amount.")
      return
    }
    // The check for selectedAmount > effectiveMaxAmount is implicitly handled
    // by disabling buttons for amounts greater than effectiveMaxAmount.
    // However, a direct check is good practice if the state could be set otherwise.
    if (selectedAmount > effectiveMaxAmount) {
      setError(`Amount cannot exceed ${currencySymbol}${effectiveMaxAmount.toFixed(2)}.`)
      return
    }

    onSubmit(selectedAmount, message)
    setSelectedAmount(null)
    setMessage("")
    setError("")
    // onClose(); // onSubmit should handle closing if successful, or the parent does
  }

  if (!isOpen) return null

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-md p-0 bg-white text-black">
        {/* Custom Header to match Figma */}
        <div className="flex items-center justify-between p-6 border-b border-gray-200">
          <button type="button" onClick={onClose} className="text-sm font-medium text-gray-700 hover:text-gray-900">
            Cancel
          </button>
          <div className="flex-1 text-center">
            <DialogTitle className="text-xl font-bold">Vouch for {borrowerName}</DialogTitle>
            <DialogDescription className="text-sm text-gray-500 mt-1">{loanDetails}</DialogDescription>
          </div>
          <div className="w-14"></div> {/* Spacer for centering title */}
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          <div className="space-y-3">
            <p className="text-sm font-medium text-gray-900">How much do want to vouch?</p>
            <div className="flex flex-wrap gap-2">
              {presetAmounts.map((val) => (
                <Button
                  key={val}
                  type="button"
                  variant={selectedAmount === val ? "default" : "outline"}
                  onClick={() => handleAmountButtonClick(val)}
                  disabled={val > effectiveMaxAmount}
                  className={`flex-1 min-w-[60px] py-2 px-1 border rounded-md text-center ${
                    selectedAmount === val
                      ? "bg-gray-900 text-white border-gray-900" // Darker selected state
                      : "border-gray-300 text-gray-900 hover:bg-gray-100"
                  }`}
                >
                  {currencySymbol}
                  {val}
                </Button>
              ))}
            </div>
            {error && <p className="text-xs text-red-500 pt-1">{error}</p>}
          </div>

          <div className="space-y-2">
            <p className="text-sm font-medium text-gray-900">Why are you vouching?</p>
            <Textarea
              id="message"
              placeholder="You deserve it"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={3}
              className="w-full p-3 border border-gray-300 rounded-md text-sm placeholder-gray-400"
            />
          </div>

          {/* Custom Footer to match Figma */}
          <div className="pt-2">
            <Button
              type="submit"
              disabled={selectedAmount === null || selectedAmount <= 0}
              className="w-full bg-black text-white font-bold py-3 px-4 rounded-md text-base hover:bg-gray-800 h-12"
            >
              Send
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
