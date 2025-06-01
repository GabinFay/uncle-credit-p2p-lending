// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UserRegistry} from "../contracts/UserRegistry.sol";
import {Reputation} from "../contracts/Reputation.sol";
import {P2PLending} from "../contracts/P2PLending.sol"; // Import P2PLending for its enums
import {MockERC20} from "./mocks/MockERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ReputationTest is Test {
    UserRegistry userRegistry;
    Reputation reputation;
    MockERC20 mockDai;

    address owner = address(this);
    address user1 = vm.addr(1); // Generic user / borrower
    address user2 = vm.addr(2); // Generic user / lender
    address voucher1 = vm.addr(3);
    address p2pLendingContract; // Will be set in setUp

    event ReputationUpdated(address indexed user, int256 newScore, string reason);
    event LoanTermOutcomeRecorded(bytes32 indexed agreementId, address indexed user, int256 reputationChange, string reason, Reputation.PaymentOutcomeType outcomeType);
    event VouchAdded(address indexed voucher, address indexed borrower, address token, uint256 amount);
    event VouchRemoved(address indexed voucher, address indexed borrower, uint256 returnedAmount);
    event VouchSlashed(address indexed voucher, address indexed defaultingBorrower, uint256 slashedAmount, address indexed slashedToLender);

    function setUp() public {
        userRegistry = new UserRegistry();
        reputation = new Reputation(address(userRegistry));

        p2pLendingContract = vm.addr(4);

        vm.prank(owner);
        reputation.setP2PLendingContractAddress(p2pLendingContract);

        vm.prank(user1); userRegistry.registerUser("User1");
        vm.prank(user2); userRegistry.registerUser("User2");
        vm.prank(voucher1); userRegistry.registerUser("Voucher1");

        mockDai = new MockERC20("Mock DAI", "mDAI", 18);
        mockDai.mint(voucher1, 1000e18);
    }

    function test_RevertIf_SetP2PLendingContractAddress_NotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        reputation.setP2PLendingContractAddress(p2pLendingContract);
        vm.stopPrank();
    }

    function test_RevertIf_SetP2PLendingContractAddress_ZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("Invalid P2PLending contract address"));
        reputation.setP2PLendingContractAddress(address(0));
        vm.stopPrank();
    }

    function test_SetP2PLendingContractAddress_Success() public {
        address newP2PAddress = vm.addr(5);
        vm.prank(owner);
        reputation.setP2PLendingContractAddress(newP2PAddress);
        assertEq(reputation.p2pLendingContractAddress(), newP2PAddress);
    }

    // Test for recordLoanPaymentOutcome - OnTimeOriginal
    function test_RecordLoanPaymentOutcome_OnTimeOriginal() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement1"));
        uint256 principalAmount = 100e18;
        
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansTaken = initialBorrowerProfile.loansTaken;
        uint256 initialBorrowerLoansRepaidOnTime = initialBorrowerProfile.loansRepaidOnTime;
        uint256 initialBorrowerTotalValueBorrowed = initialBorrowerProfile.totalValueBorrowed;

        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;
        uint256 initialLenderLoansGiven = initialLenderProfile.loansGiven;
        uint256 initialLenderTotalValueLent = initialLenderProfile.totalValueLent;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL();
        string memory borrowerReason = "Loan repaid on time (original terms)";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;

        int256 lenderRepChange = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL();
        string memory expectedLenderReasonContract = "Loan lent and repaid on time (original terms)";
        int256 expectedLenderNewScore = initialLenderRep + lenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower (user1 indexed, newScore, reason)
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower (agreementId, user1 indexed, change, reason, outcome)
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.OnTimeOriginal);
        
        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender (user2 indexed, newScore, reason)
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender (agreementId, user2 indexed, change, reason, outcome)
        emit LoanTermOutcomeRecorded(agreementId, user2, lenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.OnTimeOriginal);

        reputation.recordLoanPaymentOutcome(
            agreementId,
            user1,
            user2,
            principalAmount,
            Reputation.PaymentOutcomeType.OnTimeOriginal,
            P2PLending.PaymentModificationType.None,
            false
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore, "Borrower rep score mismatch");
        assertEq(finalBorrowerProfile.loansTaken, initialBorrowerLoansTaken + 1, "Borrower loans taken mismatch");
        assertEq(finalBorrowerProfile.loansRepaidOnTime, initialBorrowerLoansRepaidOnTime + 1, "Borrower loans repaid on time mismatch");
        assertEq(finalBorrowerProfile.totalValueBorrowed, initialBorrowerTotalValueBorrowed + principalAmount, "Borrower total value borrowed mismatch");

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore, "Lender rep score mismatch");
        assertEq(finalLenderProfile.loansGiven, initialLenderLoansGiven + 1, "Lender loans given mismatch");
        assertEq(finalLenderProfile.totalValueLent, initialLenderTotalValueLent + principalAmount, "Lender total value lent mismatch");
    }

    // Test for recordLoanPaymentOutcome - LateGraceOriginal
    function test_RecordLoanPaymentOutcome_LateGraceOriginal() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_late_grace"));
        uint256 principalAmount = 50e18;
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansRepaidLateGrace = initialBorrowerProfile.loansRepaidLateGrace;
        
        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_LATE_GRACE();
        string memory borrowerReason = "Loan repaid late (grace, original terms)";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;

        int256 lenderRepChange = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION(); 
        string memory expectedLenderReasonContract = "Loan lent and repaid (late grace)";
        int256 expectedLenderNewScore = initialLenderRep + lenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.LateGraceOriginal);
        
        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender
        emit LoanTermOutcomeRecorded(agreementId, user2, lenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.LateGraceOriginal);

        reputation.recordLoanPaymentOutcome(
            agreementId, user1, user2, principalAmount,
            Reputation.PaymentOutcomeType.LateGraceOriginal,
            P2PLending.PaymentModificationType.None,
            false 
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansRepaidLateGrace, initialBorrowerLoansRepaidLateGrace + 1);

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore);
    }

    // Test for recordLoanPaymentOutcome - OnTimeExtended
    function test_RecordLoanPaymentOutcome_OnTimeExtended_LenderApproved() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_ext_ontime"));
        uint256 principalAmount = 70e18;
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansRepaidOnTime = initialBorrowerProfile.loansRepaidOnTime;

        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;
        uint256 initialLenderModificationsApproved = initialLenderProfile.modificationsApprovedByLender;
        
        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_ON_TIME_AFTER_EXTENSION();
        string memory borrowerReason = "Loan repaid on time (after extension)";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;

        int256 lenderRepDeltaForLoan = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION();
        int256 lenderRepDeltaForApproval = reputation.REPUTATION_POINTS_LENDER_APPROVED_EXTENSION();
        int256 totalLenderRepChange = lenderRepDeltaForLoan + lenderRepDeltaForApproval;
        string memory expectedLenderReasonContract = "Loan outcome and modification handling for lender";
        int256 expectedLenderNewScore = initialLenderRep + totalLenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.OnTimeExtended);
        
        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender
        emit LoanTermOutcomeRecorded(agreementId, user2, totalLenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.OnTimeExtended);

        reputation.recordLoanPaymentOutcome(
            agreementId, user1, user2, principalAmount,
            Reputation.PaymentOutcomeType.OnTimeExtended,
            P2PLending.PaymentModificationType.DueDateExtension,
            true 
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansRepaidOnTime, initialBorrowerLoansRepaidOnTime + 1);

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore, "Lender rep score after approved extension mismatch");
        assertEq(finalLenderProfile.modificationsApprovedByLender, initialLenderModificationsApproved + 1);
    }

    // Test for recordLoanPaymentOutcome - LateExtended
    function test_RecordLoanPaymentOutcome_LateExtended_LenderApproved() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_ext_late"));
        uint256 principalAmount = 80e18;
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansRepaidLateGrace = initialBorrowerProfile.loansRepaidLateGrace;

        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;
        uint256 initialLenderModificationsApproved = initialLenderProfile.modificationsApprovedByLender;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_LATE_AFTER_EXTENSION();
        string memory borrowerReason = "Loan repaid late (after extension)";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;
        
        int256 lenderRepDeltaForLoan = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION();
        int256 lenderRepDeltaForApproval = reputation.REPUTATION_POINTS_LENDER_APPROVED_EXTENSION(); 
        int256 totalLenderRepChange = lenderRepDeltaForLoan + lenderRepDeltaForApproval;
        string memory expectedLenderReasonContract = "Loan outcome and modification handling for lender";
        int256 expectedLenderNewScore = initialLenderRep + totalLenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.LateExtended);

        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender
        emit LoanTermOutcomeRecorded(agreementId, user2, totalLenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.LateExtended);

        reputation.recordLoanPaymentOutcome(
            agreementId, user1, user2, principalAmount,
            Reputation.PaymentOutcomeType.LateExtended,
            P2PLending.PaymentModificationType.DueDateExtension,
            true 
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansRepaidLateGrace, initialBorrowerLoansRepaidLateGrace + 1); 

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore);
        assertEq(finalLenderProfile.modificationsApprovedByLender, initialLenderModificationsApproved + 1);
    }

    // Test for recordLoanPaymentOutcome - PartialAgreementMetAndRepaid
    function test_RecordLoanPaymentOutcome_PartialAgreementMet_LenderApproved() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_partial_met"));
        uint256 principalAmount = 90e18; 
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansRepaidOnTime = initialBorrowerProfile.loansRepaidOnTime;

        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;
        uint256 initialLenderModificationsApproved = initialLenderProfile.modificationsApprovedByLender;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_WITH_PARTIAL_AGREEMENT_MET();
        string memory borrowerReason = "Loan repaid after meeting partial payment agreement";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;

        int256 lenderRepDeltaForLoan = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_AFTER_MODIFICATION();
        int256 lenderRepDeltaForApproval = reputation.REPUTATION_POINTS_LENDER_APPROVED_PARTIAL_AGREEMENT();
        int256 totalLenderRepChange = lenderRepDeltaForLoan + lenderRepDeltaForApproval;
        string memory expectedLenderReasonContract = "Loan outcome and modification handling for lender";
        int256 expectedLenderNewScore = initialLenderRep + totalLenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.PartialAgreementMetAndRepaid);

        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender
        emit LoanTermOutcomeRecorded(agreementId, user2, totalLenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.PartialAgreementMetAndRepaid);

        reputation.recordLoanPaymentOutcome(
            agreementId, user1, user2, principalAmount,
            Reputation.PaymentOutcomeType.PartialAgreementMetAndRepaid,
            P2PLending.PaymentModificationType.PartialPaymentAgreement,
            true 
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansRepaidOnTime, initialBorrowerLoansRepaidOnTime + 1);

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore);
        assertEq(finalLenderProfile.modificationsApprovedByLender, initialLenderModificationsApproved + 1);
    }


    function test_RecordLoanPaymentOutcome_LenderRejectedModification_BorrowerStillRepaidOnTimeOriginal() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_reject_ontime_orig"));
        uint256 principalAmount = 110e18;
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansRepaidOnTime = initialBorrowerProfile.loansRepaidOnTime;
        
        Reputation.ReputationProfile memory initialLenderProfile = reputation.getReputationProfile(user2);
        int256 initialLenderRep = initialLenderProfile.currentReputationScore;
        uint256 initialLenderModificationsRejected = initialLenderProfile.modificationsRejectedByLender;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL();
        string memory borrowerReason = "Loan repaid on time (original terms)";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;

        int256 lenderRepDeltaForLoan = reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL();
        int256 lenderRepDeltaForRejection = reputation.REPUTATION_POINTS_LENDER_REJECTED_MODIFICATION(); 
        int256 totalLenderRepChange = lenderRepDeltaForLoan + lenderRepDeltaForRejection;
        string memory expectedLenderReasonContract = "Loan lent and repaid on time (original terms)";
        int256 expectedLenderNewScore = initialLenderRep + totalLenderRepChange;

        vm.startPrank(p2pLendingContract);
        // Borrower events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower
        emit LoanTermOutcomeRecorded(agreementId, user1, borrowerRepChange, borrowerReason, Reputation.PaymentOutcomeType.OnTimeOriginal);

        // Lender events - Order: RU then LTOR
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender
        emit ReputationUpdated(user2, expectedLenderNewScore, expectedLenderReasonContract);
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender
        emit LoanTermOutcomeRecorded(agreementId, user2, totalLenderRepChange, expectedLenderReasonContract, Reputation.PaymentOutcomeType.OnTimeOriginal);

        reputation.recordLoanPaymentOutcome(
            agreementId,
            user1, 
            user2, 
            principalAmount,
            Reputation.PaymentOutcomeType.OnTimeOriginal, 
            P2PLending.PaymentModificationType.DueDateExtension,
            false
        );
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansRepaidOnTime, initialBorrowerLoansRepaidOnTime + 1);

        Reputation.ReputationProfile memory finalLenderProfile = reputation.getReputationProfile(user2);
        assertEq(finalLenderProfile.currentReputationScore, expectedLenderNewScore);
        assertEq(finalLenderProfile.modificationsRejectedByLender, initialLenderModificationsRejected + 1);
    }


    // Test updateReputationOnLoanDefault
    function test_UpdateReputationOnLoanDefault_Success() public {
        bytes32 agreementId = keccak256(abi.encodePacked("agreement_default"));
        uint256 principalAmount = 200e18;
        Reputation.ReputationProfile memory initialBorrowerProfile = reputation.getReputationProfile(user1);
        int256 initialBorrowerRep = initialBorrowerProfile.currentReputationScore;
        uint256 initialBorrowerLoansDefaulted = initialBorrowerProfile.loansDefaulted;
        uint256 initialBorrowerLoansTaken = initialBorrowerProfile.loansTaken;

        int256 borrowerRepChange = reputation.REPUTATION_POINTS_DEFAULTED();
        string memory borrowerReason = "Loan defaulted";
        int256 expectedBorrowerNewScore = initialBorrowerRep + borrowerRepChange;
        
        vm.startPrank(p2pLendingContract);
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower (user1 indexed)
        emit ReputationUpdated(user1, expectedBorrowerNewScore, borrowerReason);

        reputation.updateReputationOnLoanDefault(user1, user2, principalAmount, new bytes32[](0));
        vm.stopPrank();

        Reputation.ReputationProfile memory finalBorrowerProfile = reputation.getReputationProfile(user1);
        assertEq(finalBorrowerProfile.currentReputationScore, expectedBorrowerNewScore);
        assertEq(finalBorrowerProfile.loansDefaulted, initialBorrowerLoansDefaulted + 1);
        assertEq(finalBorrowerProfile.loansTaken, initialBorrowerLoansTaken + 1);
    }

    // Test for adding a vouch
    function test_AddVouch_Success() public {
        uint256 vouchAmount = 100e18;
        vm.prank(voucher1);
        mockDai.approve(address(reputation), vouchAmount);

        vm.expectEmit(true, true, false, true, address(reputation)); 
        emit VouchAdded(voucher1, user1, address(mockDai), vouchAmount);
        
        vm.prank(voucher1);
        reputation.addVouch(user1, vouchAmount, address(mockDai));

        Reputation.Vouch memory vouch = reputation.getVouchDetails(voucher1, user1);
        assertEq(vouch.voucher, voucher1);
        assertEq(vouch.borrower, user1);
        assertEq(vouch.tokenAddress, address(mockDai));
        assertEq(vouch.stakedAmount, vouchAmount);
        assertTrue(vouch.isActive);

        assertEq(mockDai.balanceOf(address(reputation)), vouchAmount);
        assertEq(mockDai.balanceOf(voucher1), 1000e18 - vouchAmount); 

        Reputation.ReputationProfile memory voucherProfile = reputation.getReputationProfile(voucher1);
        assertEq(voucherProfile.vouchingStakeAmount, vouchAmount);
        assertEq(voucherProfile.timesVouchedForOthers, 1);
    }

    function test_RemoveVouch_Success() public {
        uint256 vouchAmount = 100e18;
        vm.prank(voucher1);
        mockDai.approve(address(reputation), vouchAmount);
        vm.prank(voucher1);
        reputation.addVouch(user1, vouchAmount, address(mockDai));

        uint256 initialReputationBalance = mockDai.balanceOf(address(reputation));
        uint256 initialVoucherBalance = mockDai.balanceOf(voucher1);

        vm.expectEmit(true, true, false, true, address(reputation)); 
        emit VouchRemoved(voucher1, user1, vouchAmount);

        vm.prank(voucher1);
        reputation.removeVouch(user1);

        Reputation.Vouch memory vouch = reputation.getVouchDetails(voucher1, user1);
        assertFalse(vouch.isActive, "Vouch should be inactive"); 

        assertEq(mockDai.balanceOf(address(reputation)), initialReputationBalance - vouchAmount, "Reputation contract balance incorrect");
        assertEq(mockDai.balanceOf(voucher1), initialVoucherBalance + vouchAmount, "Voucher balance incorrect");

        Reputation.ReputationProfile memory finalVoucherProfile = reputation.getReputationProfile(voucher1);
        assertEq(finalVoucherProfile.vouchingStakeAmount, 0, "Voucher stake amount not zeroed");
    }

    function test_SlashVouch_Success() public {
        uint256 vouchAmount = 100e18;
        vm.prank(voucher1);
        mockDai.approve(address(reputation), vouchAmount);
        vm.prank(voucher1);
        reputation.addVouch(user1, vouchAmount, address(mockDai)); 

        uint256 slashPrincipal = vouchAmount / 2; 

        Reputation.ReputationProfile memory initialVoucherProfile = reputation.getReputationProfile(voucher1);
        int256 initialVoucherRep = initialVoucherProfile.currentReputationScore;
        uint256 initialVoucherTimesDefaulted = initialVoucherProfile.timesDefaultedAsVoucher;
        uint256 initialLenderDaiBalance = mockDai.balanceOf(user2); 

        int256 voucherRepChange = reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER();
        int256 expectedVoucherNewScore = initialVoucherRep + voucherRepChange;
        string memory repUpdateReason = "Vouched loan defaulted, stake slashed";


        vm.startPrank(p2pLendingContract); 

        vm.expectEmit(true, true, false, true, address(reputation)); 
        emit VouchSlashed(voucher1, user1, slashPrincipal, user2);

        vm.expectEmit(true, false, false, true, address(reputation)); 
        emit ReputationUpdated(voucher1, expectedVoucherNewScore, repUpdateReason);

        reputation.slashVouchAndReputation(voucher1, user1, slashPrincipal, user2);
        vm.stopPrank();

        Reputation.Vouch memory vouch = reputation.getVouchDetails(voucher1, user1);
        assertEq(vouch.stakedAmount, vouchAmount - slashPrincipal, "Vouch stake amount not reduced correctly");
        assertTrue(vouch.isActive, "Vouch should remain active if partially slashed"); 

        assertEq(mockDai.balanceOf(address(reputation)), vouchAmount - slashPrincipal, "Reputation contract balance after slash incorrect");
        assertEq(mockDai.balanceOf(user2), initialLenderDaiBalance + slashPrincipal, "Lender balance after slash incorrect");

        Reputation.ReputationProfile memory finalVoucherProfileAfterSlash = reputation.getReputationProfile(voucher1);
        assertEq(finalVoucherProfileAfterSlash.currentReputationScore, expectedVoucherNewScore, "Voucher reputation score not updated correctly");
        assertEq(finalVoucherProfileAfterSlash.vouchingStakeAmount, vouchAmount - slashPrincipal, "Voucher stake amount in profile incorrect");
        assertEq(finalVoucherProfileAfterSlash.timesDefaultedAsVoucher, initialVoucherTimesDefaulted + 1, "Times defaulted as voucher not incremented");
    }

    function test_SlashVouch_FullAmount_Success() public {
        uint256 vouchAmount = 100e18;
        vm.prank(voucher1);
        mockDai.approve(address(reputation), vouchAmount);
        vm.prank(voucher1);
        reputation.addVouch(user1, vouchAmount, address(mockDai));

        uint256 slashPrincipal = vouchAmount; 

        Reputation.ReputationProfile memory initialVoucherProfile = reputation.getReputationProfile(voucher1);
        int256 initialVoucherRep = initialVoucherProfile.currentReputationScore;
        uint256 initialVoucherTimesDefaulted = initialVoucherProfile.timesDefaultedAsVoucher;
        uint256 initialLenderDaiBalance = mockDai.balanceOf(user2);

        int256 voucherRepChange = reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER();
        int256 expectedVoucherNewScore = initialVoucherRep + voucherRepChange;
        string memory repUpdateReason = "Vouched loan defaulted, stake slashed";

        vm.startPrank(p2pLendingContract);
        vm.expectEmit(true, true, false, true, address(reputation));
        emit VouchSlashed(voucher1, user1, slashPrincipal, user2);
        vm.expectEmit(true, false, false, true, address(reputation));
        emit ReputationUpdated(voucher1, expectedVoucherNewScore, repUpdateReason);

        reputation.slashVouchAndReputation(voucher1, user1, slashPrincipal, user2);
        vm.stopPrank();

        Reputation.Vouch memory vouch = reputation.getVouchDetails(voucher1, user1);
        assertEq(vouch.stakedAmount, 0, "Vouch stake amount not zeroed after full slash");
        assertFalse(vouch.isActive, "Vouch should be inactive after full slash");

        assertEq(mockDai.balanceOf(address(reputation)), 0, "Reputation contract balance should be zero after full slash");
        assertEq(mockDai.balanceOf(user2), initialLenderDaiBalance + slashPrincipal, "Lender balance after full slash incorrect");
        
        Reputation.ReputationProfile memory finalVoucherProfileFullSlash = reputation.getReputationProfile(voucher1);
        assertEq(finalVoucherProfileFullSlash.currentReputationScore, expectedVoucherNewScore);
        assertEq(finalVoucherProfileFullSlash.vouchingStakeAmount, 0); 
        assertEq(finalVoucherProfileFullSlash.timesDefaultedAsVoucher, initialVoucherTimesDefaulted + 1);
    }
} 