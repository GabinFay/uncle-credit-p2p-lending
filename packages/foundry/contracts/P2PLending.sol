// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol"; // No longer needed for Pyth
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./UserRegistry.sol";
// import "./SocialVouching.sol"; // Functionality to be in Reputation.sol
// import "./Treasury.sol"; // No longer used in P2P model
import "./interfaces/IReputationOApp.sol";
import "./Reputation.sol"; // IMPORT Reputation contract
// import "./interfaces/IP2PLending.sol";
// import "./interfaces/IReputation.sol";
import "forge-std/console.sol"; // Added for debugging

/**
 * @title P2PLending (Previously LoanContract)
 * @author CreditInclusion Team
 * @notice Manages the peer-to-peer lending lifecycle, including loan offers, requests, agreements, repayments, and defaults.
 * @dev Interacts with UserRegistry for World ID verification and Reputation contract for scoring and vouching.
 *      This contract holds escrowed funds for active loan offers and collateral for active loan agreements.
 */
contract P2PLending is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @notice Reference to the UserRegistry contract for verifying user identities.
     */
    UserRegistry public userRegistry;
    // SocialVouching public socialVouching; // REMOVED
    // address payable public treasuryAddress; // REMOVED - P2P model
    /**
     * @notice Reference to the Reputation contract for managing user scores and vouching.
     */
    Reputation public reputationContract; // CHANGED from reputationOApp and socialVouching concept
    /**
     * @notice Reference to the (optional) IReputationOApp interface for cross-chain reputation (placeholder).
     */
    IReputationOApp public reputationOApp; // To be reviewed if still needed alongside direct Reputation.sol calls
    address payable public platformWallet; // For potential platform fees

    /**
     * @notice Defines the types of payment modifications a borrower can request.
     */
    enum PaymentModificationType {
        None,                   // Default, no modification active/requested
        DueDateExtension,       // Request to extend the loan's due date
        PartialPaymentAgreement // Request to make an agreed-upon partial payment amount
    }

    /**
     * @notice Defines the possible states of a loan offer, request, or agreement.
     */
    enum LoanStatus {
        Active,             // Funds transferred, loan is ongoing
        Repaid,             // Loan fully repaid
        Defaulted,          // Loan not repaid by due date and past grace period
        Cancelled,          // Offer or request cancelled before agreement
        PendingModificationApproval, // Borrower requested a modification, awaiting lender response
        Active_PartialPaymentAgreed, // Lender approved a partial payment agreement, loan active
        Overdue             // Loan is past its due date but not yet defaulted (within grace period or awaiting resolution)
    }

    // This Loan struct is from the old model, will be replaced by P2P structs
    // struct Loan_OLD_MODEL { 
    //     bytes32 loanId;
    //     address borrower;
    //     uint256 principalAmount;
    //     address loanToken; 
    //     uint256 interestRate; 
    //     uint256 duration; 
    //     uint256 startTime;
    //     uint256 dueDate; 
    //     uint256 collateralAmount;
    //     address collateralToken;
    //     uint256 totalVouchedAmountAtApplication; 
    //     LoanVoucherDetail[] vouches; 
    //     uint256 amountPaid; 
    //     LoanStatus status;
    // }

    // mapping(bytes32 => Loan_OLD_MODEL) public loans; // Will be replaced
    // mapping(address => bytes32[]) public userLoans; // Will be replaced or adapted
    // uint256 public loanCounter; // For generating unique loan IDs - will need similar for P2P agreements

    // --- P2P Specific Structs ---
    /**
     * @notice Represents a loan offer created by a lender.
     * @param offerId Unique identifier for the loan offer.
     * @param lender Address of the user offering to lend funds.
     * @param offerAmount The principal amount offered.
     * @param loanToken The ERC20 token in which the loan is denominated.
     * @param interestRate The interest rate for the loan, in basis points (e.g., 500 for 5.00%).
     * @param duration The duration of the loan in seconds.
     * @param collateralRequiredAmount Amount of collateral required by the lender (0 if none).
     * @param collateralRequiredToken The ERC20 token for collateral (address(0) if none).
     * @param status Current status of the loan offer (e.g., OfferOpen, AgreementReached).
     */
    struct LoanOffer {
        bytes32 id;
        address lender;
        uint256 amount;
        address token;
        uint16 interestRateBPS;
        uint256 durationSeconds;
        uint256 requiredCollateralAmount;
        address collateralToken;
        bool isActive;
        bool isFulfilled;
    }

    /**
     * @notice Represents a loan request created by a borrower.
     * @param requestId Unique identifier for the loan request.
     * @param borrower Address of the user requesting to borrow funds.
     * @param requestAmount The principal amount requested.
     * @param loanToken The ERC20 token in which the loan is requested.
     * @param proposedInterestRate The maximum interest rate the borrower is willing to pay, in basis points.
     * @param proposedDuration The desired duration of the loan in seconds.
     * @param offeredCollateralAmount Amount of collateral the borrower is offering (0 if none).
     * @param offeredCollateralToken The ERC20 token for collateral offered (address(0) if none).
     * @param status Current status of the loan request (e.g., RequestOpen, AgreementReached).
     */
    struct LoanRequest {
        bytes32 id;
        address borrower;
        uint256 amount;
        address token;
        uint16 proposedInterestRateBPS;
        uint256 proposedDurationSeconds;
        uint256 offeredCollateralAmount;
        address collateralToken;
        bool isActive;
        bool isFulfilled;
    }

    /**
     * @notice Represents an active loan agreement formed between a lender and a borrower.
     * @param agreementId Unique identifier for the loan agreement.
     * @param originalOfferId ID of the LoanOffer this agreement originated from (if applicable).
     * @param originalRequestId ID of the LoanRequest this agreement originated from (if applicable).
     * @param lender Address of the lender.
     * @param borrower Address of the borrower.
     * @param principalAmount The principal amount of the loan.
     * @param loanToken The ERC20 token of the loan principal.
     * @param interestRate The agreed interest rate in basis points.
     * @param duration The agreed duration of the loan in seconds.
     * @param collateralAmount The amount of collateral locked for this loan (0 if none).
     * @param collateralToken The ERC20 token of the collateral (address(0) if none).
     * @param startTime Timestamp when the loan agreement became active.
     * @param dueDate Timestamp when the loan is due for full repayment.
     * @param amountPaid Total amount repaid by the borrower so far.
     * @param status Current status of the loan agreement (e.g., Active, Repaid, Defaulted).
     */
    struct LoanAgreement {
        bytes32 id;
        bytes32 originalOfferId;
        bytes32 originalRequestId;
        address lender;
        address borrower;
        uint256 principalAmount;
        address loanToken;
        uint16 interestRateBPS;
        uint256 durationSeconds;
        uint256 collateralAmount;
        address collateralToken;
        uint256 startTime;
        uint256 dueDate;
        uint256 amountPaid;
        LoanStatus status;
        PaymentModificationType requestedModificationType;
        uint256 requestedModificationValue;
        bool modificationApprovedByLender;
    }

    /**
     * @notice Maps loan offer IDs to LoanOffer structs.
     */
    mapping(bytes32 => LoanOffer) public loanOffers;
    /**
     * @notice Maps user addresses to an array of IDs of loan offers they created.
     */
    mapping(address => bytes32[]) public userLoanOfferIds; // lender => offer IDs
    /**
     * @notice Maps loan request IDs to LoanRequest structs.
     */
    mapping(bytes32 => LoanRequest) public loanRequests;
    /**
     * @notice Maps user addresses to an array of IDs of loan requests they created.
     */
    mapping(address => bytes32[]) public userLoanRequestIds; // borrower => request IDs
    /**
     * @notice Maps loan agreement IDs to LoanAgreement structs.
     */
    mapping(bytes32 => LoanAgreement) public loanAgreements;
    /**
     * @notice Maps user addresses to an array of IDs of loan agreements where they are the lender.
     */
    mapping(address => bytes32[]) public userLoanAgreementIdsAsLender;   // lender => agreement IDs
    /**
     * @notice Maps user addresses to an array of IDs of loan agreements where they are the borrower.
     */
    mapping(address => bytes32[]) public userLoanAgreementIdsAsBorrower; // borrower => agreement IDs

    /**
     * @notice Constant representing 100.00% for basis points calculations (10000 = 100%).
     */
    uint256 public constant BASIS_POINTS = 10000;

    // --- Events ---
    // Old events to be revised for P2P
    // event LoanApplied(bytes32 indexed loanId, address indexed borrower, uint256 amount, address token);
    // event LoanApproved(bytes32 indexed loanId);
    // event LoanDisbursed(bytes32 indexed loanId);
    // event LoanPaymentMade(bytes32 indexed loanId, uint256 paymentAmount, uint256 totalPaid);
    // event LoanFullyRepaid(bytes32 indexed loanId);
    // event LoanDefaulted(bytes32 indexed loanId);
    // event LoanLiquidated(bytes32 indexed loanId, uint256 collateralSeized);

    /**
     * @notice Emitted when a new loan offer is created.
     * @param offerId Unique ID of the offer.
     * @param lender Address of the lender creating the offer.
     * @param amount Principal amount offered.
     * @param token Token of the principal amount.
     * @param interestRateBPS Interest rate in basis points.
     * @param durationSeconds Duration of the loan in seconds.
     */
    event LoanOfferCreated(
        bytes32 indexed offerId,
        address indexed lender,
        uint256 amount,
        address token,
        uint16 interestRateBPS,
        uint256 durationSeconds
    );
    /**
     * @notice Emitted when a new loan request is created.
     * @param requestId Unique ID of the request.
     * @param borrower Address of the borrower creating the request.
     * @param amount Principal amount requested.
     * @param token Token of the principal amount.
     * @param proposedInterestRateBPS Proposed interest rate in basis points.
     * @param proposedDurationSeconds Proposed duration of the loan in seconds.
     */
    event LoanRequestCreated(
        bytes32 indexed requestId,
        address indexed borrower,
        uint256 amount,
        address token,
        uint16 proposedInterestRateBPS,
        uint256 proposedDurationSeconds
    );
    /**
     * @notice Emitted when a loan offer is accepted or a loan request is funded, forming an agreement.
     * @param agreementId Unique ID of the newly formed loan agreement.
     * @param lender Address of the lender in the agreement.
     * @param borrower Address of the borrower in the agreement.
     * @param principalAmount Principal amount of the loan.
     * @param token Token of the principal amount.
     * @param interestRateBPS Agreed interest rate for the loan.
     * @param durationSeconds Agreed duration of the loan.
     * @param startTime Timestamp when the loan became active.
     * @param dueDate Timestamp when the loan is due.
     * @param collateralAmount Amount of collateral locked for the agreement.
     * @param collateralToken Token of the collateral.
     */
    event LoanAgreementCreated(
        bytes32 indexed agreementId,
        address indexed lender,
        address indexed borrower,
        uint256 principalAmount,
        address token,
        uint16 interestRateBPS,
        uint256 durationSeconds,
        uint256 startTime,
        uint256 dueDate,
        uint256 collateralAmount,
        address collateralToken
    );
    /**
     * @notice Emitted when a repayment is made on a loan agreement.
     * @param agreementId The ID of the loan agreement.
     * @param payer The address of the user making the payment (borrower).
     * @param amountPaidThisTime The amount paid in the current transaction.
     * @param newTotalAmountPaid The new cumulative total amount paid towards the loan.
     * @param newRemainingBalance The outstanding balance after this payment.
     * @param newStatus The status of the loan agreement after this payment.
     */
    event LoanRepayment(
        bytes32 indexed agreementId,
        address indexed payer,
        uint256 amountPaidThisTime,
        uint256 newTotalAmountPaid,
        uint256 newRemainingBalance,
        LoanStatus newStatus
    );
    /**
     * @notice Emitted when a loan agreement is fully repaid.
     * @param agreementId ID of the fully repaid loan agreement.
     */
    event LoanAgreementRepaid(bytes32 indexed agreementId);
    /**
     * @notice Emitted when a loan agreement is marked as defaulted.
     * @param agreementId ID of the defaulted loan agreement.
     */
    event LoanAgreementDefaulted(bytes32 indexed agreementId);
    /**
     * @notice Emitted when a borrower requests a payment modification.
     * @param agreementId The ID of the loan agreement.
     * @param borrower The address of the borrower requesting the modification.
     * @param modificationType The type of modification requested (e.g., DueDateExtension).
     * @param value The value associated with the modification (e.g., new due date timestamp or proposed partial payment amount).
     */
    event PaymentModificationRequested(
        bytes32 indexed agreementId,
        address indexed borrower,
        PaymentModificationType modificationType,
        uint256 value
    );

    /**
     * @notice Emitted when a lender responds to a borrower's payment modification request.
     * @param agreementId The ID of the loan agreement.
     * @param lender The address of the lender responding.
     * @param approved True if the lender approved the request, false otherwise.
     * @param modificationType The type of modification that was requested.
     * @param originalRequestedValue The original value associated with the modification request.
     */
    event PaymentModificationResponded(
        bytes32 indexed agreementId,
        address indexed lender,
        bool approved,
        PaymentModificationType modificationType,
        uint256 originalRequestedValue
    );

    // --- Modifiers ---
    /**
     * @dev Modifier to ensure the calling user is verified in the UserRegistry.
     * @param user The address to check for World ID verification.
     */
    modifier onlyVerifiedUser(address user) {
        require(userRegistry.isUserRegistered(user), "P2PL: User not World ID verified");
        _;
    }

    // modifier onlyLoanExists(bytes32 loanId) { // Will be agreementExists, offerExists, requestExists
    //     require(loans[loanId].borrower != address(0), "LoanContract: Loan does not exist");
    //     _;
    // }

    /**
     * @notice Contract constructor.
     * @param _userRegistryAddress Address of the deployed UserRegistry contract.
     * @param _reputationContractAddress Address of the deployed Reputation contract.
     * @param _platformWallet Address of the platform wallet for potential fees.
     * @param _reputationOAppAddress Address of the (optional) Reputation OApp for cross-chain features. Can be address(0).
     */
    constructor(
        address _userRegistryAddress,
        address _reputationContractAddress,
        address payable _platformWallet,
        address _reputationOAppAddress 
    ) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "P2PL: Invalid UserRegistry address");
        require(_reputationContractAddress != address(0), "P2PL: Invalid Reputation contract address");
        require(_platformWallet != address(0), "P2PL: Invalid platform wallet");
        userRegistry = UserRegistry(_userRegistryAddress);
        reputationContract = Reputation(_reputationContractAddress);
        platformWallet = _platformWallet;
        if (_reputationOAppAddress != address(0)) {
            reputationOApp = IReputationOApp(_reputationOAppAddress);
        }
        // The socialVouchingAddress param will be repurposed for the Reputation.sol contract later
    }

    // --- Admin Functions (mostly for setters, Ownable ensures only owner) ---
    /**
     * @notice Sets the address of the main Reputation contract.
     * @dev Can only be called by the contract owner.
     *      Changing this address affects where reputation updates and vouch slashing calls are directed.
     * @param _newReputationContractAddress The address of the new Reputation contract.
     */
    function setReputationContractAddress(address _newReputationContractAddress) external onlyOwner {
        require(_newReputationContractAddress != address(0), "P2PL: Invalid Reputation contract address");
        reputationContract = Reputation(_newReputationContractAddress);
    }
    
    /**
     * @notice Sets the address of the LayerZero Reputation OApp contract.
     * @dev Can only be called by the contract owner.
     *      This is for the optional cross-chain reputation functionality.
     *      Set to address(0) to disable OApp interactions.
     * @param newReputationOAppAddress The address of the new IReputationOApp contract, or address(0).
     */
    function setReputationOAppAddress(address newReputationOAppAddress) external onlyOwner {
        if (newReputationOAppAddress == address(0)) {
            delete reputationOApp;
        } else {
            reputationOApp = IReputationOApp(newReputationOAppAddress);
        }
    }
    
    /**
     * @notice Placeholder function for setting a Pyth Network address (feature removed).
     * @dev This function will always revert as Pyth Network integration has been removed from this contract.
     */
    function setPythAddress(address /* newPythAddress */) external onlyOwner {
        revert("P2PL: Pyth integration removed"); 
    }

    // --- P2P Lending Core Functions ---

    /**
     * @notice Creates a new loan offer as a lender.
     * @dev The lender must have sufficient balance of `loanToken_` and must approve this contract
     *      to transfer `offerAmount_` if the offer is accepted. This approval should be done prior to calling.
     *      The offer becomes `OfferOpen`. Generates a unique offer ID.
     * @param amount_ The principal amount the lender is offering.
     * @param token_ The ERC20 token for the loan principal.
     * @param interestRateBPS_ The interest rate in basis points (e.g., 500 for 5.00%).
     * @param durationSeconds_ The duration of the loan in seconds.
     * @param requiredCollateralAmount_ The amount of collateral required from the borrower (0 if none).
     * @param collateralToken_ The ERC20 token for collateral (address(0) if none).
     * @return offerId The unique ID of the newly created loan offer.
     */
    function createLoanOffer(
        uint256 amount_,
        address token_,
        uint16 interestRateBPS_,
        uint256 durationSeconds_,
        uint256 requiredCollateralAmount_,
        address collateralToken_
    ) external nonReentrant onlyVerifiedUser(msg.sender) returns (bytes32 offerId) {
        require(amount_ > 0, "P2PL: Offer amount must be > 0");
        require(token_ != address(0), "P2PL: Invalid loan token");
        require(durationSeconds_ > 0, "P2PL: Duration must be > 0");
        // require(interestRate_ < MAX_INTEREST_RATE, "Interest rate too high"); // Consider platform limits

        if (requiredCollateralAmount_ > 0) {
            require(collateralToken_ != address(0), "P2PL: Invalid collateral token for non-zero amount");
        } else {
            require(collateralToken_ == address(0), "P2PL: Collateral token must be zero for zero amount");
        }

        // Lender must have sufficient balance of the loan token
        require(IERC20(token_).balanceOf(msg.sender) >= amount_, "P2PL: Insufficient balance for offer");
        // Lender must approve this contract to transfer offerAmount_ if offer is accepted
        // This approval should ideally happen before calling, or be part of the acceptOffer flow.
        // For now, we assume the lender will approve separately.

        offerId = keccak256(abi.encodePacked(msg.sender, amount_, token_, interestRateBPS_, durationSeconds_, block.timestamp, userLoanOfferIds[msg.sender].length));

        loanOffers[offerId] = LoanOffer({
            id: offerId,
            lender: msg.sender,
            amount: amount_,
            token: token_,
            interestRateBPS: interestRateBPS_,
            durationSeconds: durationSeconds_,
            requiredCollateralAmount: requiredCollateralAmount_,
            collateralToken: collateralToken_,
            isActive: true,
            isFulfilled: false
        });

        userLoanOfferIds[msg.sender].push(offerId);
        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_); // Lender sends funds to contract when creating offer
        // console.logBytes32(offerId); // Debugging
        emit LoanOfferCreated(offerId, msg.sender, amount_, token_, interestRateBPS_, durationSeconds_);
        return offerId;
    }

    /**
     * @notice Creates a new loan request as a borrower.
     * @dev If collateral is offered, the borrower must have sufficient balance of `offeredCollateralToken_`
     *      and must approve this contract to transfer `offeredCollateralAmount_` if the request is funded.
     *      This collateral approval should be done prior to calling.
     *      The request becomes `RequestOpen`. Generates a unique request ID.
     * @param amount_ The principal amount the borrower is requesting.
     * @param token_ The ERC20 token for the loan principal.
     * @param proposedInterestRateBPS_ The maximum interest rate the borrower is willing to pay, in basis points.
     * @param proposedDurationSeconds_ The desired duration of the loan in seconds.
     * @param offeredCollateralAmount_ The amount of collateral the borrower is offering (0 if none).
     * @param offeredCollateralToken_ The ERC20 token for collateral (address(0) if none).
     * @return requestId The unique ID of the newly created loan request.
     */
    function createLoanRequest(
        uint256 amount_,
        address token_,
        uint16 proposedInterestRateBPS_,
        uint256 proposedDurationSeconds_,
        uint256 offeredCollateralAmount_,
        address offeredCollateralToken_
    ) external nonReentrant onlyVerifiedUser(msg.sender) returns (bytes32 requestId) {
        require(amount_ > 0, "P2PL: Request amount must be > 0");
        require(token_ != address(0), "P2PL: Invalid loan token");
        require(proposedDurationSeconds_ > 0, "P2PL: Duration must be > 0");

        if (offeredCollateralAmount_ > 0) {
            require(offeredCollateralToken_ != address(0), "P2PL: Invalid collateral token for non-zero amount");
            // Borrower must have and approve offeredCollateralAmount_ if request is funded.
            // This is handled during the funding stage.
            require(IERC20(offeredCollateralToken_).balanceOf(msg.sender) >= offeredCollateralAmount_, "P2PL: Insufficient collateral balance for request");
        } else {
            require(offeredCollateralToken_ == address(0), "P2PL: Collateral token must be zero for zero amount");
        }

        requestId = keccak256(abi.encodePacked(msg.sender, amount_, token_, proposedInterestRateBPS_, proposedDurationSeconds_, block.timestamp, userLoanRequestIds[msg.sender].length));

        loanRequests[requestId] = LoanRequest({
            id: requestId,
            borrower: msg.sender,
            amount: amount_,
            token: token_,
            proposedInterestRateBPS: proposedInterestRateBPS_,
            proposedDurationSeconds: proposedDurationSeconds_,
            offeredCollateralAmount: offeredCollateralAmount_,
            collateralToken: offeredCollateralToken_,
            isActive: true,
            isFulfilled: false
        });

        userLoanRequestIds[msg.sender].push(requestId);
        emit LoanRequestCreated(requestId, msg.sender, amount_, token_, proposedInterestRateBPS_, proposedDurationSeconds_);
        return requestId;
    }

    /**
     * @notice Allows a borrower to accept an open loan offer, forming a loan agreement.
     * @dev Transfers loan principal from lender to borrower. If collateral is required by the offer,
     *      transfers collateral from borrower to this contract. Borrower must have approved collateral transfer.
     *      Lender must have approved principal transfer from their account by this contract.
     *      Marks the offer as `AgreementReached` and creates an `Active` loan agreement.
     * @param offerId_ The ID of the loan offer to accept.
     * @param borrowerCollateralAmount_ Amount of collateral provided by borrower (must match offer requirement).
     * @param borrowerCollateralToken_ Token of collateral provided by borrower (must match offer requirement).
     * @return agreementId The unique ID of the newly formed loan agreement.
     */
    function acceptLoanOffer(
        bytes32 offerId_,
        uint256 borrowerCollateralAmount_,
        address borrowerCollateralToken_
    ) external nonReentrant onlyVerifiedUser(msg.sender) returns (bytes32 agreementId) {
        require(loanOffers[offerId_].lender != address(0), "P2PL: Offer does not exist");
        LoanOffer storage offer = loanOffers[offerId_];
        require(offer.isActive, "P2PL: Offer not active");
        require(!offer.isFulfilled, "P2PL: Offer already fulfilled");
        require(offer.lender != msg.sender, "P2PL: Cannot accept own offer");

        // Check collateral requirements
        if (offer.requiredCollateralAmount > 0) {
            require(borrowerCollateralToken_ == offer.collateralToken, "P2PL: Collateral token mismatch");
            require(borrowerCollateralAmount_ == offer.requiredCollateralAmount, "P2PL: Collateral amount mismatch");
            require(IERC20(borrowerCollateralToken_).balanceOf(msg.sender) >= borrowerCollateralAmount_, "P2PL: Insufficient collateral balance");
            // Borrower approves this contract to take collateral
            IERC20(borrowerCollateralToken_).safeTransferFrom(msg.sender, address(this), borrowerCollateralAmount_);
        } else {
            require(borrowerCollateralAmount_ == 0, "P2PL: Collateral not required by offer");
            require(borrowerCollateralToken_ == address(0), "P2PL: Collateral not required by offer");
        }

        // Lender must have approved this contract to transfer the loan amount
        // This is a critical step. If not approved, transferFrom will fail.
        // Consider adding a check for allowance: require(IERC20(offer.loanToken).allowance(offer.lender, address(this)) >= offer.amount, "Lender has not approved transfer");
        IERC20(offer.token).safeTransfer(msg.sender, offer.amount);

        offer.isFulfilled = true;
        offer.isActive = false; // Offer is now consumed by this agreement

        uint256 startTime = block.timestamp;
        uint256 dueDate = startTime + offer.durationSeconds;
        agreementId = keccak256(abi.encodePacked(offer.id, msg.sender, startTime));

        loanAgreements[agreementId] = LoanAgreement({
            id: agreementId,
            originalOfferId: offerId_,
            originalRequestId: bytes32(0), // Not from a request
            lender: offer.lender,
            borrower: msg.sender,
            principalAmount: offer.amount,
            loanToken: offer.token,
            interestRateBPS: offer.interestRateBPS,
            durationSeconds: offer.durationSeconds,
            collateralAmount: borrowerCollateralAmount_, // Actual collateral locked
            collateralToken: borrowerCollateralToken_,
            startTime: startTime,
            dueDate: dueDate,
            amountPaid: 0,
            status: LoanStatus.Active,
            requestedModificationType: PaymentModificationType.DueDateExtension,
            requestedModificationValue: 0,
            modificationApprovedByLender: false
        });

        userLoanAgreementIdsAsLender[offer.lender].push(agreementId);
        userLoanAgreementIdsAsBorrower[msg.sender].push(agreementId);

        emit LoanAgreementCreated(agreementId, offer.lender, msg.sender, offer.amount, offer.token, offer.interestRateBPS, offer.durationSeconds, startTime, dueDate, borrowerCollateralAmount_, borrowerCollateralToken_);
        // Call Reputation.sol - details to be added if loan formation affects reputation immediately
        // For now, reputation is primarily affected by repayment/default events.

        return agreementId;
    }

    /**
     * @notice Allows a lender to fund an open loan request, forming a loan agreement.
     * @dev Transfers loan principal from lender to borrower. If collateral was offered in the request,
     *      transfers collateral from borrower to this contract. Borrower must have approved collateral transfer.
     *      Lender must have approved principal transfer from their account by this contract.
     *      Marks the request as `AgreementReached` and creates an `Active` loan agreement.
     * @param requestId_ The ID of the loan request to fund.
     * @return agreementId The unique ID of the newly formed loan agreement.
     */
    function fundLoanRequest(
        bytes32 requestId_
    ) external nonReentrant onlyVerifiedUser(msg.sender) returns (bytes32 agreementId) {
        require(loanRequests[requestId_].borrower != address(0), "P2PL: Request does not exist");
        LoanRequest storage request = loanRequests[requestId_];
        require(request.isActive, "P2PL: Request not active");
        require(!request.isFulfilled, "P2PL: Request already fulfilled");
        require(request.borrower != msg.sender, "P2PL: Cannot fund own request");

        require(IERC20(request.token).balanceOf(msg.sender) >= request.amount, "P2PL: Insufficient balance to fund");
        // Lender transfers funds directly to borrower
        IERC20(request.token).safeTransferFrom(msg.sender, request.borrower, request.amount);

        if (request.offeredCollateralAmount > 0) {
            // Borrower must have pre-approved this contract or the lender needs to be able to pull.
            // For simplicity, assuming borrower approved this contract during createLoanRequest if collateral was specified.
            // If createLoanRequest doesn't escrow collateral, this transfer must happen now.
            IERC20(request.collateralToken).safeTransferFrom(request.borrower, address(this), request.offeredCollateralAmount);
        }

        request.isActive = false;
        request.isFulfilled = true;

        uint256 startTime = block.timestamp;
        uint256 dueDate = startTime + request.proposedDurationSeconds;
        // Use request.id and msg.sender (lender) for agreementId uniqueness when funding a request
        agreementId = keccak256(abi.encodePacked(request.id, msg.sender, startTime)); 

        loanAgreements[agreementId] = LoanAgreement({
            id: agreementId,
            originalOfferId: bytes32(0), // Not from an offer
            originalRequestId: requestId_,
            lender: msg.sender,
            borrower: request.borrower,
            principalAmount: request.amount,
            loanToken: request.token,
            interestRateBPS: request.proposedInterestRateBPS,
            durationSeconds: request.proposedDurationSeconds,
            collateralAmount: request.offeredCollateralAmount,
            collateralToken: request.collateralToken,
            startTime: startTime,
            dueDate: dueDate,
            amountPaid: 0,
            status: LoanStatus.Active,
            requestedModificationType: PaymentModificationType.DueDateExtension,
            requestedModificationValue: 0,
            modificationApprovedByLender: false
        });

        userLoanAgreementIdsAsLender[msg.sender].push(agreementId);
        userLoanAgreementIdsAsBorrower[request.borrower].push(agreementId);

        emit LoanAgreementCreated(agreementId, msg.sender, request.borrower, request.amount, request.token, request.proposedInterestRateBPS, request.proposedDurationSeconds, startTime, dueDate, request.offeredCollateralAmount, request.collateralToken);
        // Call Reputation.sol - similar to acceptLoanOffer

        return agreementId;
    }

    // --- Getter Functions ---
    /**
     * @notice Retrieves the details of a specific loan offer.
     * @param offerId The ID of the loan offer.
     * @return The LoanOffer struct for the given ID. Reverts if the offer does not exist.
     */
    function getLoanOfferDetails(bytes32 offerId) external view returns (LoanOffer memory) {
        require(loanOffers[offerId].lender != address(0), "P2PL: Offer does not exist");
        return loanOffers[offerId];
    }

    /**
     * @notice Retrieves the details of a specific loan request.
     * @param requestId The ID of the loan request.
     * @return The LoanRequest struct for the given ID. Reverts if the request does not exist.
     */
    function getLoanRequestDetails(bytes32 requestId) external view returns (LoanRequest memory) {
        require(loanRequests[requestId].borrower != address(0), "P2PL: Request does not exist");
        return loanRequests[requestId];
    }

    /**
     * @notice Retrieves the details of a specific loan agreement.
     * @param agreementId The ID of the loan agreement.
     * @return The LoanAgreement struct for the given ID. Reverts if the agreement does not exist.
     */
    function getLoanAgreementDetails(bytes32 agreementId) external view returns (LoanAgreement memory) {
        require(loanAgreements[agreementId].borrower != address(0), "P2PL: Agreement does not exist");
        return loanAgreements[agreementId];
    }

    /**
     * @notice Retrieves an array of loan offer IDs created by a specific user.
     * @param user The address of the user (lender).
     * @return An array of bytes32 offer IDs.
     */
    function getUserLoanOfferIds(address user) external view returns (bytes32[] memory) {
        return userLoanOfferIds[user];
    }

    /**
     * @notice Retrieves an array of loan request IDs created by a specific user.
     * @param user The address of the user (borrower).
     * @return An array of bytes32 request IDs.
     */
    function getUserLoanRequestIds(address user) external view returns (bytes32[] memory) {
        return userLoanRequestIds[user];
    }

    /**
     * @notice Retrieves an array of loan agreement IDs where a specific user is the lender.
     * @param user The address of the user (lender).
     * @return An array of bytes32 agreement IDs.
     */
    function getUserLoanAgreementIdsAsLender(address user) external view returns (bytes32[] memory) {
        return userLoanAgreementIdsAsLender[user];
    }

    /**
     * @notice Retrieves an array of loan agreement IDs where a specific user is the borrower.
     * @param user The address of the user (borrower).
     * @return An array of bytes32 agreement IDs.
     */
    function getUserLoanAgreementIdsAsBorrower(address user) external view returns (bytes32[] memory) {
        return userLoanAgreementIdsAsBorrower[user];
    }

    // --- Internal Helper Functions & Loan Lifecycle Management ---
    /**
     * @dev Internal function to calculate simple interest for a loan.
     * @param principalAmount The principal amount of the loan.
     * @param interestRateBps The interest rate in basis points.
     * @return interest The calculated interest amount.
     */
    function _calculateInterest(
        uint256 principalAmount,
        uint16 interestRateBps
    ) internal pure returns (uint256 interest) {
        if (principalAmount == 0 || interestRateBps == 0) {
            return 0;
        }
        return (principalAmount * interestRateBps) / BASIS_POINTS;
    }

    /**
     * @dev Internal function to calculate the total amount due for a loan agreement (principal + interest).
     * @param agreement The LoanAgreement struct for which to calculate the total due.
     * @return totalDue The total amount due for the loan.
     */
    function _calculateTotalDue(LoanAgreement storage agreement) internal view returns (uint256 totalDue) {
        uint256 interest = _calculateInterest(
            agreement.principalAmount, 
            agreement.interestRateBPS
        );
        return agreement.principalAmount + interest;
    }

    // --- Repayment and Default Handling ---
    /**
     * @notice Allows a borrower to make a payment towards an active loan agreement.
     * @dev Transfers `paymentAmount` of `loanToken` from borrower to lender.
     *      Updates `amountPaid`. If fully repaid, marks agreement as `Repaid`, returns collateral (if any)
     *      to borrower, and calls `reputationContract.updateReputationOnLoanRepayment`.
     *      Prevents overpayment. Borrower must have approved `paymentAmount` transfer to this contract.
     * @param agreementId The ID of the loan agreement to repay.
     * @param paymentAmount The amount of `loanToken` to repay.
     */
    function repayLoan(bytes32 agreementId, uint256 paymentAmount) external nonReentrant {
        LoanAgreement storage agreement = loanAgreements[agreementId];
        require(agreement.borrower == msg.sender, "P2PL: Not borrower");
        require(
            agreement.status == LoanStatus.Active ||
            agreement.status == LoanStatus.Overdue ||
            agreement.status == LoanStatus.Active_PartialPaymentAgreed,
            "P2PL: Loan not in repayable state"
        );
        require(paymentAmount > 0, "P2PL: Payment amount must be > 0");

        uint256 totalDue = _calculateTotalDue(agreement);

        uint256 remainingDueBeforePayment = totalDue - agreement.amountPaid;

        require(paymentAmount <= remainingDueBeforePayment, "P2PL: Payment exceeds remaining due");

        PaymentModificationType originalModificationTypeBeforeRepay = agreement.requestedModificationType;
        bool wasModificationApprovedBeforeRepay = agreement.modificationApprovedByLender;
        uint256 agreedPartialPaymentValue = agreement.requestedModificationValue; // Store before potential reset

        IERC20(agreement.loanToken).safeTransferFrom(msg.sender, agreement.lender, paymentAmount);

        agreement.amountPaid += paymentAmount;
        LoanStatus newStatus = agreement.status; // Default to current status

        if (agreement.status == LoanStatus.Active_PartialPaymentAgreed) {
            if (paymentAmount == agreedPartialPaymentValue) { // Borrower paid the agreed partial amount
                agreement.modificationApprovedByLender = false;
                agreement.requestedModificationValue = 0;
                // Now determine the next actual status based on full repayment or due date
                if (agreement.amountPaid >= totalDue) {
                    newStatus = LoanStatus.Repaid;
                } else if (block.timestamp > agreement.dueDate) {
                    newStatus = LoanStatus.Overdue;
                } else {
                    newStatus = LoanStatus.Active;
                }
            } else {
                // Borrower paid something, but not the agreed partial amount.
                // Status remains Active_PartialPaymentAgreed. amountPaid is updated.
                // Modification flags are NOT reset yet.
                newStatus = LoanStatus.Active_PartialPaymentAgreed; 
            }
        } else {
            // For Active or Overdue status (not Active_PartialPaymentAgreed)
            if (agreement.amountPaid >= totalDue) { // Fully paid
                newStatus = LoanStatus.Repaid;
            } else if (block.timestamp > agreement.dueDate) { // Partially paid, and past due date
                newStatus = LoanStatus.Overdue;
            } else { // Partially paid, but still within due date
                newStatus = LoanStatus.Active;
            }
        }

        uint256 newRemainingBalance;
        if (agreement.amountPaid >= totalDue) {
            newRemainingBalance = 0;
        } else {
            newRemainingBalance = totalDue - agreement.amountPaid; // Safe subtraction
        }

        emit LoanRepayment(agreementId, msg.sender, paymentAmount, agreement.amountPaid, newRemainingBalance, newStatus);

        if (newStatus == LoanStatus.Repaid) {
            emit LoanAgreementRepaid(agreementId);

            Reputation.PaymentOutcomeType outcomeType = Reputation.PaymentOutcomeType.None;
            uint256 originalDueDate = agreement.dueDate; // Due date at the moment of this repayment

            // Adjust originalDueDate if an extension was approved and this repayment is meeting that extended due date
            if (wasModificationApprovedBeforeRepay && originalModificationTypeBeforeRepay == PaymentModificationType.DueDateExtension) {
                // If the repayment is happening *after* an extension was approved, the "original" due date for outcome evaluation is the extended one.
                // However, agreement.dueDate would have already been updated by respondToPaymentModification.
                // We need to compare block.timestamp against this potentially modified agreement.dueDate
            }

            if (block.timestamp <= originalDueDate) { // Paid on or before the (potentially extended) due date
                if (wasModificationApprovedBeforeRepay) {
                    if (originalModificationTypeBeforeRepay == PaymentModificationType.DueDateExtension) {
                        outcomeType = Reputation.PaymentOutcomeType.OnTimeExtended;
                    } else if (originalModificationTypeBeforeRepay == PaymentModificationType.PartialPaymentAgreement) {
                        // This implies the final payment completed the loan after a partial agreement was met.
                        outcomeType = Reputation.PaymentOutcomeType.PartialAgreementMetAndRepaid;
                    }
                } else {
                    outcomeType = Reputation.PaymentOutcomeType.OnTimeOriginal;
                }
            } else { // Paid after the (potentially extended) due date, but before default (since it's Repaid now)
                if (wasModificationApprovedBeforeRepay && originalModificationTypeBeforeRepay == PaymentModificationType.DueDateExtension) {
                    outcomeType = Reputation.PaymentOutcomeType.LateExtended;
                } else {
                    // No approved extension, or it was a partial agreement that didn't change due date and paid late
                    outcomeType = Reputation.PaymentOutcomeType.LateGraceOriginal;
                }
            }

            if (agreement.collateralAmount > 0 && agreement.collateralToken != address(0)) {
                IERC20(agreement.collateralToken).safeTransfer(agreement.borrower, agreement.collateralAmount);
            }

            if (address(reputationContract) != address(0)) { 
                reputationContract.recordLoanPaymentOutcome(
                    agreementId,
                    agreement.borrower,
                    agreement.lender,
                    agreement.principalAmount,
                    outcomeType,
                    originalModificationTypeBeforeRepay, // Pass the type that was active before this repayment processed it
                    wasModificationApprovedBeforeRepay // Pass the approval status before this repayment processed it
                );
            }
        }
        agreement.status = newStatus; // Set the final status
    }

    /**
     * @notice Handles the default of an active loan agreement.
     * @dev Can be called by anyone if the loan is overdue and not fully repaid.
     *      Marks the agreement as `Defaulted`. Transfers collateral (if any) from this contract to the lender.
     *      Calls `reputationContract.updateReputationOnLoanDefault` for the borrower.
     *      Then, iterates through active vouches for the borrower (obtained from Reputation contract)
     *      and calls `reputationContract.slashVouchAndReputation` for each active vouch to slash a percentage
     *      of their stake, compensating the lender of the defaulted loan.
     * @param agreementId The ID of the loan agreement to handle for default.
     */
    function handleP2PDefault(bytes32 agreementId) external nonReentrant {
        LoanAgreement storage agreement = loanAgreements[agreementId];
        require(agreement.lender != address(0), "P2PL: Agreement does not exist");
        require(agreement.status == LoanStatus.Active, "P2PL: Loan not active for default");
        require(block.timestamp > agreement.dueDate, "P2PL: Loan not yet overdue");

        uint256 totalDue = _calculateTotalDue(agreement);
        require(agreement.amountPaid < totalDue, "P2PL: Loan already fully paid, cannot default");

        agreement.status = LoanStatus.Defaulted;
        emit LoanAgreementDefaulted(agreementId);

        if (agreement.collateralAmount > 0 && agreement.collateralToken != address(0)) {
            IERC20(agreement.collateralToken).safeTransfer(agreement.lender, agreement.collateralAmount);
        }

        if (address(reputationContract) != address(0)) { 
            reputationContract.updateReputationOnLoanDefault(
                agreement.borrower, 
                agreement.lender, 
                agreement.principalAmount,
                new bytes32[](0) 
            );

            Reputation.Vouch[] memory activeVouches = reputationContract.getActiveVouchesForBorrower(agreement.borrower);
            uint256 tenPercentSlashBasis = 1000; // 10.00%

            for (uint i = 0; i < activeVouches.length; i++) {
                Reputation.Vouch memory currentVouch = activeVouches[i];
                if (currentVouch.isActive && currentVouch.stakedAmount > 0) { 
                    uint256 slashAmount = (currentVouch.stakedAmount * tenPercentSlashBasis) / BASIS_POINTS;
                    if (slashAmount == 0 && currentVouch.stakedAmount > 0) { 
                        slashAmount = 1; 
                    }
                    if (slashAmount > currentVouch.stakedAmount) { 
                        slashAmount = currentVouch.stakedAmount;
                    }

                    if (slashAmount > 0) {
                        reputationContract.slashVouchAndReputation(
                            currentVouch.voucher,
                            agreement.borrower,
                            slashAmount,
                            agreement.lender 
                        );
                    }
                }
            }
        }
    }

    // To be implemented based on PRD.md:
    // requestP2PLoanExtension(...)

    // --- Borrower/Lender Actions for Loan Modifications ---

    /**
     * @notice Allows a borrower to request a modification to their loan agreement terms.
     * @param _agreementId The ID of the loan agreement to modify.
     * @param _modificationType The type of modification being requested (e.g., DueDateExtension).
     * @param _value The value associated with the modification (e.g., new proposed due date timestamp, or proposed partial payment amount).
     * @dev Only the borrower of an Active or Overdue loan can request a modification.
     *      The loan status will be set to PendingModificationApproval.
     */
    function requestPaymentModification(
        bytes32 _agreementId,
        PaymentModificationType _modificationType,
        uint256 _value
    ) external nonReentrant {
        LoanAgreement storage agreement = loanAgreements[_agreementId];
        require(agreement.borrower == msg.sender, "P2PL: Not borrower");
        require(agreement.status == LoanStatus.Active || agreement.status == LoanStatus.Overdue, "P2PL: Loan not active/overdue");
        // Potentially add check: require(!agreement.modificationApprovedByLender, "P2PL: Prior request still active/unprocessed");
        // This would prevent spamming requests if a lender hasn't acted on a previous one.
        // Or, a new request implicitly cancels/overwrites a previous one.
        // For now, allowing overwrite.

        require(_value > 0, "P2PL: Modification value must be > 0"); // Basic validation for value
        if (_modificationType == PaymentModificationType.DueDateExtension) {
            require(_value > agreement.dueDate, "P2PL: New due date must be later");
        }
        // For PartialPaymentAgreement, _value is the proposed partial amount. Further validation might be needed (e.g., not > remaining balance).

        agreement.requestedModificationType = _modificationType;
        agreement.requestedModificationValue = _value;
        agreement.modificationApprovedByLender = false; // Reset approval status for new request
        agreement.status = LoanStatus.PendingModificationApproval;

        emit PaymentModificationRequested(_agreementId, msg.sender, _modificationType, _value);
    }

    /**
     * @notice Allows a lender to respond to a borrower's payment modification request.
     * @param _agreementId The ID of the loan agreement.
     * @param _approved True if the lender approves the modification, false otherwise.
     * @dev Only the lender of a loan with status PendingModificationApproval can call this.
     *      Updates loan terms or status based on approval.
     */
    function respondToPaymentModification(
        bytes32 _agreementId,
        bool _approved
    ) external nonReentrant {
        LoanAgreement storage agreement = loanAgreements[_agreementId];
        require(agreement.lender == msg.sender, "P2PL: Not lender");
        require(agreement.status == LoanStatus.PendingModificationApproval, "P2PL: No pending modification");

        PaymentModificationType originalType = agreement.requestedModificationType;
        uint256 originalValue = agreement.requestedModificationValue;

        if (_approved) {
            agreement.modificationApprovedByLender = true;
            if (originalType == PaymentModificationType.DueDateExtension) {
                agreement.dueDate = originalValue;
                // Status becomes Active if new dueDate is in future, or Overdue if original due date has passed but new one is also in past (edge case, but handled by isOverdue check)
                // For simplicity, just set to Active. Overdue check is dynamic in getters.
                // If block.timestamp > agreement.dueDate (original), but < originalValue (new dueDate), it should be Active.
                // If block.timestamp > originalValue (new dueDate), it will be Overdue.
                // So, if it was Overdue, it might become Active again if new due date is in the future.
                if (block.timestamp < agreement.dueDate) {
                    agreement.status = LoanStatus.Active;
                } else {
                    agreement.status = LoanStatus.Overdue; // Remains overdue or becomes overdue if new date is also past
                }
                 // TODO: Consider if reputation should be impacted here positively for lender being flexible?
            } else if (originalType == PaymentModificationType.PartialPaymentAgreement) {
                // The lender agrees to the borrower making a partial payment of `originalValue`.
                // The loan status reflects this agreement, but the actual payment is separate.
                agreement.status = LoanStatus.Active_PartialPaymentAgreed;
                // No change to dueDate or amountPaid here. The `originalValue` is the *agreed* partial payment amount.
            }
        } else {
            agreement.modificationApprovedByLender = false; // Explicitly set though it was already false
            // Log lender rejection for their stats if needed in Reputation contract
            // For now, REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION is 0, so direct call might not be needed unless stats are incremented.
            // If Reputation.sol handles this via recordLoanPaymentOutcome, ensure flags allow it.
             // Revert status to what it was before the request, or to Overdue if applicable
             // This requires knowing the previous status. For now, simply set to Active or Overdue.
            if (block.timestamp < agreement.dueDate) {
                agreement.status = LoanStatus.Active;
            } else {
                agreement.status = LoanStatus.Overdue;
            }
            // TODO: Consider if reputation should be impacted here negatively for borrower if lender rejects often?
        }

        // Clear the request fields after processing to prevent re-processing or confusion
        // agreement.requestedModificationType = default; // Solidity doesn't have a direct default for enums easily
        // agreement.requestedModificationValue = 0;
        // Let's keep them for history for now, modificationApprovedByLender is the main gate.

        emit PaymentModificationResponded(_agreementId, msg.sender, _approved, originalType, originalValue);
        // Potentially call reputationContract here based on approval/rejection and type
        // For lender-specific reputation on *responding* to modification (not final loan outcome), a separate call might be cleaner.
        // However, recordLoanPaymentOutcome in Reputation.sol now has `lenderApprovedRequest` and `modificationTypeUsed`
        // which can be used to adjust lender score when the loan finally settles (repaid/defaulted).
        // For now, no immediate reputation call here, it will be handled at final loan settlement.
    }

} 