// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UserRegistry.sol";
import "./P2PLending.sol"; // Import P2PLending to use its enums
import "forge-std/console.sol"; // For debugging, remove in production

interface IP2PLending { // Define an interface for P2PLending if needed for specific calls from Reputation
    // Declare functions from P2PLending that Reputation might need to call, if any.
    // Or, if P2PLending calls Reputation, Reputation might not need to call P2PLending directly.
}

/**
 * @title Reputation Contract
 * @author CreditInclusion Team
 * @notice Manages user reputation scores, social vouching, and stake slashing.
 */
contract Reputation is Ownable, ReentrancyGuard {
    UserRegistry public userRegistry;
    address public p2pLendingContractAddress; // Address of the P2PLending contract

    struct ReputationProfile {
        address userAddress;
        uint256 loansTaken;
        uint256 loansGiven;
        uint256 loansRepaidOnTime; // Specifically on original or extended due date
        uint256 loansRepaidLateGrace; // Repaid late but before default, without formal extension
        uint256 loansDefaulted;
        uint256 totalValueBorrowed;
        uint256 totalValueLent;
        int256 currentReputationScore;
        uint256 vouchingStakeAmount; // Total amount user has actively staked for others
        uint256 timesVouchedForOthers;
        uint256 timesDefaultedAsVoucher; // Times a user they vouched for defaulted
        uint256 modificationsApprovedByLender; // Times this lender approved a modification
        uint256 modificationsRejectedByLender; // Times this lender rejected a modification
    }

    struct Vouch {
        address voucher;
        address borrower;
        address tokenAddress;
        uint256 stakedAmount;
        bool isActive;
    }

    mapping(address => ReputationProfile) public userReputations;
    mapping(address => mapping(address => Vouch)) public activeVouches; // voucher => borrower => Vouch
    mapping(address => Vouch[]) public userVouchesGiven; // voucher => list of all vouches they made (active and inactive)
    mapping(address => Vouch[]) public userVouchesReceived; // borrower => list of all vouches they received (active and inactive)

    // Borrower Reputation Points
    int256 public constant REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL = 10;
    int256 public constant REPUTATION_POINTS_REPAID_LATE_GRACE = 3; // Paid after original due date but before default, no formal extension
    int256 public constant REPUTATION_POINTS_REPAID_ON_TIME_AFTER_EXTENSION = 7;
    int256 public constant REPUTATION_POINTS_REPAID_LATE_AFTER_EXTENSION = 2;
    int256 public constant REPUTATION_POINTS_REPAID_WITH_PARTIAL_AGREEMENT_MET = 8; // Assumes this led to full repayment on agreed terms
    int256 public constant REPUTATION_POINTS_DEFAULTED = -50;

    // Lender Reputation Points
    int256 public constant REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL = 5;
    int256 public constant REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION = 3; // If repaid after modification
    int256 public constant REPUTATION_POINTS_LENDER_APPROVED_EXTENSION = 2;
    int256 public constant REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT = 1;
    int256 public constant REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION = 0; // Neutral for now

    // Voucher Reputation Points
    int256 public constant REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER = -20;

    /**
     * @notice Defines the outcome of a loan repayment for reputation calculation.
     *         This enum is specific to the Reputation contract's internal logic.
     */
    enum PaymentOutcomeType {
        None, // Default or not yet determined
        OnTimeOriginal,          // Paid by original due date, no modifications involved or modifications were not ultimately used for repayment timing.
        LateGraceOriginal,       // Paid after original due date but before default, no formal extension approved.
        OnTimeExtended,          // Paid by an approved new due date (extension).
        LateExtended,            // Paid after an approved new due date (extension) but before default.
        PartialAgreementMetAndRepaid, // A partial payment agreement was approved, terms met, and loan eventually fully repaid.
        Defaulted                // Loan defaulted.
    }

    event ReputationUpdated(address indexed user, int256 newScore, string reason);
    event LoanTermOutcomeRecorded(bytes32 indexed agreementId, address indexed user, int256 reputationChange, string reason, PaymentOutcomeType outcomeType);
    event VouchAdded(address indexed voucher, address indexed borrower, address token, uint256 amount);
    event VouchRemoved(address indexed voucher, address indexed borrower, uint256 returnedAmount);
    event VouchSlashed(address indexed voucher, address indexed defaultingBorrower, uint256 slashedAmount, address indexed slashedToLender);

    modifier onlyVerifiedUser(address user) {
        require(userRegistry.isUserRegistered(user), "Reputation: User not World ID verified");
        _;
    }

    modifier onlyP2PLendingContract() {
        require(msg.sender == p2pLendingContractAddress, "Reputation: Caller is not P2PLending contract");
        _;
    }

    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        userRegistry = UserRegistry(_userRegistryAddress);
    }

    function setP2PLendingContractAddress(address _p2pLendingAddress) external onlyOwner {
        require(_p2pLendingAddress != address(0), "Invalid P2PLending contract address");
        p2pLendingContractAddress = _p2pLendingAddress;
    }

    function _initializeReputationProfileIfNotExists(address user) internal {
        if (userReputations[user].userAddress == address(0) && userRegistry.isUserRegistered(user)) {
            userReputations[user] = ReputationProfile({
                userAddress: user,
                loansTaken: 0,
                loansGiven: 0,
                loansRepaidOnTime: 0,
                loansRepaidLateGrace: 0,
                loansDefaulted: 0,
                totalValueBorrowed: 0,
                totalValueLent: 0,
                currentReputationScore: 0,
                vouchingStakeAmount: 0,
                timesVouchedForOthers: 0,
                timesDefaultedAsVoucher: 0,
                modificationsApprovedByLender: 0,
                modificationsRejectedByLender: 0
            });
        }
    }

    /**
     * @notice Records the outcome of a loan payment/conclusion for reputation adjustments.
     * @dev Called by P2PLending contract upon loan repayment or other conclusions like meeting modified terms.
     * @param agreementId The ID of the loan agreement.
     * @param borrower The address of the borrower.
     * @param lender The address of the lender.
     * @param principalAmount The principal amount of the loan.
     * @param outcome The determined outcome type for reputation calculation.
     * @param modificationTypeUsed The type of payment modification that was active/approved (if any).
     * @param lenderApprovedRequest True if the lender had approved a modification request relevant to this outcome.
     */
    function recordLoanPaymentOutcome(
        bytes32 agreementId,
        address borrower,
        address lender,
        uint256 principalAmount,
        PaymentOutcomeType outcome,
        P2PLending.PaymentModificationType modificationTypeUsed, // Enum from P2PLending
        bool lenderApprovedRequest
    ) external onlyP2PLendingContract {
        _initializeReputationProfileIfNotExists(borrower);
        _initializeReputationProfileIfNotExists(lender);

        ReputationProfile storage borrowerProfile = userReputations[borrower];
        ReputationProfile storage lenderProfile = userReputations[lender];
        int256 borrowerRepChange = 0;
        string memory borrowerReason = "Loan outcome processed";
        int256 lenderRepChange = 0;
        string memory lenderReason = "Loan outcome processed for lender";

        borrowerProfile.loansTaken++;
        borrowerProfile.totalValueBorrowed += principalAmount;

        if (outcome == PaymentOutcomeType.OnTimeOriginal) {
            borrowerRepChange = REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL;
            borrowerProfile.loansRepaidOnTime++;
            borrowerReason = "Loan repaid on time (original terms)";
            lenderRepChange += REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL;
            lenderReason = "Loan lent and repaid on time (original terms)";
        } else if (outcome == PaymentOutcomeType.LateGraceOriginal) {
            borrowerRepChange = REPUTATION_POINTS_REPAID_LATE_GRACE;
            borrowerProfile.loansRepaidLateGrace++;
            borrowerReason = "Loan repaid late (grace, original terms)";
            lenderRepChange += REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION; // Still successful, but late
            lenderReason = "Loan lent and repaid (late grace)";
        } else if (outcome == PaymentOutcomeType.OnTimeExtended) {
            borrowerRepChange = REPUTATION_POINTS_REPAID_ON_TIME_AFTER_EXTENSION;
            borrowerProfile.loansRepaidOnTime++; // Counts as on-time for the modified terms
            borrowerReason = "Loan repaid on time (after extension)";
            lenderRepChange += REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION;
            lenderReason = "Loan lent and repaid (on time after extension)";
        } else if (outcome == PaymentOutcomeType.LateExtended) {
            borrowerRepChange = REPUTATION_POINTS_REPAID_LATE_AFTER_EXTENSION;
            borrowerProfile.loansRepaidLateGrace++; // Or a new category for late after extension?
            borrowerReason = "Loan repaid late (after extension)";
            lenderRepChange += REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION; // Still successful, but very late
            lenderReason = "Loan lent and repaid (late after extension)";
        } else if (outcome == PaymentOutcomeType.PartialAgreementMetAndRepaid) {
            borrowerRepChange = REPUTATION_POINTS_REPAID_WITH_PARTIAL_AGREEMENT_MET;
            borrowerProfile.loansRepaidOnTime++; // Assuming meeting partial agreement counts as on-time like behavior for this path
            borrowerReason = "Loan repaid after meeting partial payment agreement";
            lenderRepChange += REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION;
            lenderReason = "Loan lent and repaid (after partial payment agreement)";
        }
        // Default outcome is handled by updateReputationOnLoanDefault and not this function

        if (borrowerRepChange != 0) {
            borrowerProfile.currentReputationScore += borrowerRepChange;
            emit ReputationUpdated(borrower, borrowerProfile.currentReputationScore, borrowerReason);
            emit LoanTermOutcomeRecorded(agreementId, borrower, borrowerRepChange, borrowerReason, outcome);
        }

        // Lender reputation adjustments based on modification handling
        if (lenderApprovedRequest) {
            lenderProfile.modificationsApprovedByLender++;
            if (modificationTypeUsed == P2PLending.PaymentModificationType.DueDateExtension) {
                lenderRepChange += REPUTATION_POINTS_LENDER_APPROVED_EXTENSION;
            } else if (modificationTypeUsed == P2PLending.PaymentModificationType.PartialPaymentAgreement) {
                lenderRepChange += REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT;
            }
        } else if (modificationTypeUsed != P2PLending.PaymentModificationType.None) { // A modification was involved but not approved by lender
            lenderProfile.modificationsRejectedByLender++;
            lenderRepChange += REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION;
        }
        // If this function is called, it implies the loan was successfully concluded (not defaulted)
        lenderProfile.loansGiven++;
        lenderProfile.totalValueLent += principalAmount;
        // The REPUTATION_POINTS_LENT_SUCCESSFULLY... is already added above based on outcome.

        if (lenderRepChange != 0) {
            lenderProfile.currentReputationScore += lenderRepChange;
            
            // lenderReason is already set based on the core outcome (e.g., OnTimeOriginal, LateGraceOriginal)
            string memory finalLenderReason = lenderReason; 

            // Check if any modification-specific points were added that would alter the base lenderRepChange
            bool modificationSpecificPointsInvolved = false;
            if (lenderApprovedRequest) {
                if (modificationTypeUsed == P2PLending.PaymentModificationType.DueDateExtension && lenderRepChange != REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION + REPUTATION_POINTS_LENDER_APPROVED_EXTENSION && lenderRepChange != REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL + REPUTATION_POINTS_LENDER_APPROVED_EXTENSION) {
                    // This case implies only base points if true, so only override if combined
                } else if (modificationTypeUsed == P2PLending.PaymentModificationType.DueDateExtension && (REPUTATION_POINTS_LENDER_APPROVED_EXTENSION != 0) ) {
                     modificationSpecificPointsInvolved = true;
                }
                if (modificationTypeUsed == P2PLending.PaymentModificationType.PartialPaymentAgreement && lenderRepChange != REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION + REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT && lenderRepChange != REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL + REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT) {
                    // This case implies only base points if true, so only override if combined
                } else if (modificationTypeUsed == P2PLending.PaymentModificationType.PartialPaymentAgreement && (REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT != 0) ) {
                    modificationSpecificPointsInvolved = true;
                }

            } else if (modificationTypeUsed != P2PLending.PaymentModificationType.None) { 
                 // A modification was involved but not approved by lender (e.g. rejected)
                 // If points for rejection are non-zero and were added to lenderRepChange
                 if (REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION != 0 && (lenderRepChange == REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL + REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION || lenderRepChange == REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION + REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION ) ) {
                    modificationSpecificPointsInvolved = true;
                 }
            }

            if (modificationSpecificPointsInvolved) {
                finalLenderReason = "Loan outcome and modification handling for lender";
            }
            // If !modificationSpecificPointsInvolved, finalLenderReason remains the specific one (e.g. "Loan lent and repaid on time (original terms)")

            emit ReputationUpdated(lender, lenderProfile.currentReputationScore, finalLenderReason);
            emit LoanTermOutcomeRecorded(agreementId, lender, lenderRepChange, finalLenderReason, outcome);
        }
    }

    function updateReputationOnLoanDefault(
        address borrower,
        address /*lender*/, // lender param not directly used here for score update
        uint256 /*loanAmount*/, // loanAmount not directly used here for score update
        bytes32[] calldata /*vouchesForThisLoan*/ // Not used here, P2PLending iterates active vouches
    ) external onlyP2PLendingContract {
        _initializeReputationProfileIfNotExists(borrower);
        ReputationProfile storage borrowerProfile = userReputations[borrower];
        borrowerProfile.loansTaken++; // Should this be incremented if it wasn't already via repayment path?
        borrowerProfile.loansDefaulted++;
        borrowerProfile.currentReputationScore += REPUTATION_POINTS_DEFAULTED;
        emit ReputationUpdated(borrower, borrowerProfile.currentReputationScore, "Loan defaulted");
    }

    function addVouch(
        address borrowerToVouchFor,
        uint256 amountToStake,
        address tokenAddress
    ) external nonReentrant onlyVerifiedUser(msg.sender) {
        require(borrowerToVouchFor != msg.sender, "Cannot vouch for yourself");
        require(userRegistry.isUserRegistered(borrowerToVouchFor), "Borrower not World ID verified");
        require(amountToStake > 0, "Stake amount must be positive");
        require(tokenAddress != address(0), "Invalid token address");
        require(!activeVouches[msg.sender][borrowerToVouchFor].isActive, "Already actively vouching for this borrower");

        _initializeReputationProfileIfNotExists(msg.sender);
        _initializeReputationProfileIfNotExists(borrowerToVouchFor);

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amountToStake);

        Vouch memory newVouch = Vouch({
            voucher: msg.sender,
            borrower: borrowerToVouchFor,
            tokenAddress: tokenAddress,
            stakedAmount: amountToStake,
            isActive: true
        });
        activeVouches[msg.sender][borrowerToVouchFor] = newVouch;
        userVouchesGiven[msg.sender].push(newVouch);
        userVouchesReceived[borrowerToVouchFor].push(newVouch);

        ReputationProfile storage voucherProfile = userReputations[msg.sender];
        voucherProfile.vouchingStakeAmount += amountToStake;
        voucherProfile.timesVouchedForOthers++;
        emit VouchAdded(msg.sender, borrowerToVouchFor, tokenAddress, amountToStake);
    }

    function removeVouch(address borrowerVouchedFor) external nonReentrant onlyVerifiedUser(msg.sender) {
        Vouch storage vouch = activeVouches[msg.sender][borrowerVouchedFor];
        require(vouch.isActive, "No active vouch for this borrower");
        // Add check: ensure borrowerVouchedFor does not have active loans that depend on this vouch

        vouch.isActive = false;
        uint256 stakedAmountToReturn = vouch.stakedAmount;
        // vouch.stakedAmount = 0; // Not strictly necessary as isActive is false

        ReputationProfile storage voucherProfile = userReputations[msg.sender];
        voucherProfile.vouchingStakeAmount -= stakedAmountToReturn;

        IERC20(vouch.tokenAddress).transfer(msg.sender, stakedAmountToReturn);
        emit VouchRemoved(msg.sender, borrowerVouchedFor, stakedAmountToReturn);
    }

    function slashVouchAndReputation(
        address voucher,
        address defaultingBorrower, // Kept for event clarity, though could be derived
        uint256 amountToSlash,
        address lenderToCompensate
    ) external onlyP2PLendingContract {
        Vouch storage vouch = activeVouches[voucher][defaultingBorrower];
        require(vouch.isActive, "Vouch not active or does not exist");
        require(amountToSlash <= vouch.stakedAmount, "Slash amount exceeds staked amount");
        require(amountToSlash > 0, "Slash amount must be positive");

        _initializeReputationProfileIfNotExists(voucher); // Ensure profile exists

        vouch.stakedAmount -= amountToSlash;

        ReputationProfile storage voucherProfile = userReputations[voucher];
        voucherProfile.currentReputationScore += REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER;
        voucherProfile.vouchingStakeAmount -= amountToSlash; 
        voucherProfile.timesDefaultedAsVoucher++;

        IERC20(vouch.tokenAddress).transfer(lenderToCompensate, amountToSlash);

        emit VouchSlashed(voucher, defaultingBorrower, amountToSlash, lenderToCompensate);
        emit ReputationUpdated(voucher, voucherProfile.currentReputationScore, "Vouched loan defaulted, stake slashed");

        if (vouch.stakedAmount == 0) {
            vouch.isActive = false;
        }
    }

    function getReputationProfile(address _user) public view returns (ReputationProfile memory) {
        return userReputations[_user];
    }

    function getVouchDetails(address voucher, address borrower) external view returns (Vouch memory) {
        return activeVouches[voucher][borrower];
    }

    function getUserVouchesGiven(address voucher) external view returns (Vouch[] memory) {
        return userVouchesGiven[voucher];
    }

    function getUserVouchesReceived(address borrower) external view returns (Vouch[] memory) {
        return userVouchesReceived[borrower];
    }

    function getActiveVouchesForBorrower(address borrower) external view returns (Vouch[] memory activeReceivedVouches) {
        Vouch[] memory allReceived = userVouchesReceived[borrower];
        uint activeCount = 0;
        for (uint i = 0; i < allReceived.length; i++) {
            // Check against the definitive source of active status
            if (activeVouches[allReceived[i].voucher][allReceived[i].borrower].isActive) {
                activeCount++;
            }
        }

        activeReceivedVouches = new Vouch[](activeCount);
        uint currentIndex = 0;
        for (uint i = 0; i < allReceived.length; i++) {
            // Retrieve the potentially updated state from activeVouches map
            Vouch storage currentVouchState = activeVouches[allReceived[i].voucher][allReceived[i].borrower];
            if (currentVouchState.isActive) {
                activeReceivedVouches[currentIndex] = currentVouchState;
                currentIndex++;
            }
        }
    }
} 