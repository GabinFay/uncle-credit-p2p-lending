// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/UserRegistry.sol";
import "../contracts/P2PLending.sol";
import "../contracts/Reputation.sol";
import "./mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

// import "./mocks/MockReputationOApp.sol"; // Removed: File does not exist

contract P2PLendingTest is Test {
    UserRegistry public userRegistry;
    P2PLending public p2pLending;
    Reputation public reputation;
    MockERC20 public mockDai;
    MockERC20 public mockUsdc;
    address owner;
    address borrower = vm.addr(1);
    address lender = vm.addr(4);
    address platformWallet = vm.addr(2);
    address voucher1 = vm.addr(3);
    address reputationOAppMockAddress = address(0);

    uint256 constant ONE_DAY_SECONDS = 1 days;
    uint16 constant DEFAULT_INTEREST_RATE_P2P = 1000; // 10%
    uint16 constant BASIS_POINTS_TEST = 10000;
    uint256 constant DEFAULT_OFFER_AMOUNT_P2P = 100e18;

    // P2PLending Events
    event LoanOfferCreated(bytes32 indexed offerId, address indexed lender, uint256 amount, address token, uint16 interestRateBPS, uint256 durationSeconds);
    event LoanRequestCreated(bytes32 indexed requestId, address indexed borrower, uint256 amount, address token, uint16 proposedInterestRateBPS, uint256 proposedDurationSeconds);
    event LoanAgreementCreated(bytes32 indexed agreementId, address indexed lender, address indexed borrower, uint256 principalAmount, address token, uint16 interestRateBPS, uint256 durationSeconds, uint256 startTime, uint256 dueDate, uint256 collateralAmount, address collateralToken);
    event LoanRepayment(bytes32 indexed agreementId, address indexed payer, uint256 amountPaidThisTime, uint256 newTotalAmountPaid, uint256 newRemainingBalance, P2PLending.LoanStatus newStatus);
    event LoanAgreementRepaid(bytes32 indexed agreementId);
    event LoanAgreementDefaulted(bytes32 indexed agreementId);
    event CollateralSeized(bytes32 indexed agreementId, address indexed token, uint256 amount, address indexed seizedBy);
    event VouchSlashed(address indexed voucher, address indexed borrower, uint256 amount, address indexed lender);
    event PaymentModificationRequested(bytes32 indexed agreementId, address indexed borrower, P2PLending.PaymentModificationType modificationType, uint256 value);
    event PaymentModificationResponded(bytes32 indexed agreementId, address indexed lender, bool approved, P2PLending.PaymentModificationType modificationType, uint256 originalRequestedValue);

    // Events from Reputation contract for emit checks
    event ReputationUpdated(address indexed user, int256 newScore, string reason); // User is indexed
    event LoanTermOutcomeRecorded(bytes32 indexed agreementId, address indexed user, int256 reputationChange, string reason, Reputation.PaymentOutcomeType outcomeType);

    function setUp() public {
        owner = address(this);

        userRegistry = new UserRegistry();
        reputation = new Reputation(address(userRegistry));
        
        p2pLending = new P2PLending(address(userRegistry), address(reputation), payable(platformWallet), reputationOAppMockAddress);
        
        vm.prank(reputation.owner());
        reputation.setP2PLendingContractAddress(address(p2pLending));
        vm.stopPrank();

        vm.prank(borrower); userRegistry.registerUser("Borrower");
        vm.prank(lender); userRegistry.registerUser("Lender");
        vm.prank(voucher1); userRegistry.registerUser("Voucher");

        mockDai = new MockERC20("Mock DAI", "mDAI", 18);
        mockDai.mint(lender, 10000 * 1e18);
        mockDai.mint(borrower, 1000 * 1e18);
        mockDai.mint(voucher1, 500 * 1e18);

        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        mockUsdc.mint(borrower, 2000 * 1e6);
    }

    // Helper to create and accept an offer without collateral, returns only agreementId
    function _createAndAcceptOfferNoCollateral_IdOnly() internal returns (bytes32 agreementId) {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), DEFAULT_OFFER_AMOUNT_P2P);
        bytes32 offerId = p2pLending.createLoanOffer(DEFAULT_OFFER_AMOUNT_P2P, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();

        vm.startPrank(borrower);
        agreementId = p2pLending.acceptLoanOffer(offerId, 0, address(0));
        vm.stopPrank();
    }

    // Helper to create and accept an offer without collateral, returns agreementId and details
    function _createAndAcceptOfferNoCollateral_WithDetails() internal returns (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), DEFAULT_OFFER_AMOUNT_P2P);
        bytes32 offerId = p2pLending.createLoanOffer(DEFAULT_OFFER_AMOUNT_P2P, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();

        vm.startPrank(borrower);
        agreementId = p2pLending.acceptLoanOffer(offerId, 0, address(0));
        vm.stopPrank();
        agreement = p2pLending.getLoanAgreementDetails(agreementId);
    }

    // Helper to create and accept an offer with collateral
    function _createAndAcceptOfferWithCollateral() internal returns (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), DEFAULT_OFFER_AMOUNT_P2P);
        bytes32 offerId = p2pLending.createLoanOffer(DEFAULT_OFFER_AMOUNT_P2P, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 50e6, address(mockUsdc));
        vm.stopPrank();

        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), 50e6);
        agreementId = p2pLending.acceptLoanOffer(offerId, 50e6, address(mockUsdc));
        vm.stopPrank();
        agreement = p2pLending.getLoanAgreementDetails(agreementId);
    }

    // --- Loan Offer Tests ---
    function test_CreateLoanOffer_Success() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 100e18);
        vm.expectEmit(true, true, false, false, address(p2pLending)); // offerId, lender indexed
        emit LoanOfferCreated(bytes32(0), lender, 100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS);
        p2pLending.createLoanOffer(100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();
    }

    function test_RevertIf_CreateLoanOffer_InsufficientBalance() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 20000e18);
        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        p2pLending.createLoanOffer(20000e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();
    }

    // --- Loan Request Tests ---
    function test_CreateLoanRequest_Success() public {
        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), 100e6); // Collateral
        vm.expectEmit(true, true, false, false, address(p2pLending)); // requestId, borrower indexed
        emit LoanRequestCreated(bytes32(0), borrower, 50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS);
        p2pLending.createLoanRequest(50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS, 100e6, address(mockUsdc));
        vm.stopPrank();
    }

    function test_RevertIf_CreateLoanRequest_InsufficientCollateralBalance() public {
        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), 3000e6);
        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        p2pLending.createLoanRequest(50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS, 3000e6, address(mockUsdc));
        vm.stopPrank();
    }

    // --- Loan Acceptance/Funding Tests ---
    function test_AcceptLoanOffer_Success_NoCollateral() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 100e18);
        bytes32 offerId = p2pLending.createLoanOffer(100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();

        uint256 expectedStartTime = block.timestamp; 
        uint256 expectedDurationSeconds = 7 * ONE_DAY_SECONDS;
        uint256 expectedDueDate = expectedStartTime + expectedDurationSeconds;
        vm.startPrank(borrower);
        vm.expectEmit(true, true, true, false, address(p2pLending)); 
        emit LoanAgreementCreated(bytes32(0), lender, borrower, 100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, expectedDurationSeconds, expectedStartTime, expectedDueDate, 0, address(0));
        p2pLending.acceptLoanOffer(offerId, 0, address(0));
        vm.stopPrank();
    }

    function test_AcceptLoanOffer_Success_WithCollateral() public {
        uint256 collateralAmount = 50e6; // USDC
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 100e18);
        bytes32 offerId = p2pLending.createLoanOffer(100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, collateralAmount, address(mockUsdc));
        vm.stopPrank();

        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), collateralAmount);
        p2pLending.acceptLoanOffer(offerId, collateralAmount, address(mockUsdc));
        vm.stopPrank();
    }

    function test_FundLoanRequest_Success_NoCollateral() public {
        vm.startPrank(borrower);
        bytes32 requestId = p2pLending.createLoanRequest(50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS, 0, address(0));
        vm.stopPrank();

        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 50e18);
        p2pLending.fundLoanRequest(requestId);
        vm.stopPrank();
    }

    function test_FundLoanRequest_Success_WithCollateral() public {
        uint256 collateralAmount = 100e6;
        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), collateralAmount);
        bytes32 requestId = p2pLending.createLoanRequest(50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS, collateralAmount, address(mockUsdc));
        vm.stopPrank();

        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 50e18);
        p2pLending.fundLoanRequest(requestId);
        vm.stopPrank();
    }

    function test_RevertIf_AcceptOwnOffer() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 100e18);
        bytes32 offerId = p2pLending.createLoanOffer(100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 0, address(0));
        vm.expectRevert(bytes("Cannot accept your own offer"));
        p2pLending.acceptLoanOffer(offerId, 0, address(0));
        vm.stopPrank();
    }

    function test_RevertIf_FundOwnRequest() public {
        vm.startPrank(borrower);
        bytes32 requestId = p2pLending.createLoanRequest(50e18, address(mockDai), 1200, 14 * ONE_DAY_SECONDS, 0, address(0));
        mockDai.approve(address(p2pLending), 50e18);
        vm.expectRevert(bytes("Cannot fund your own request"));
        p2pLending.fundLoanRequest(requestId);
        vm.stopPrank();
    }

    // --- Repayment Tests ---
    function test_RepayLoan_Full_Success_NoCollateral() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;

        vm.warp(agreement.dueDate - 10 seconds); // Ensure payment is on time
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), totalDue);

        vm.expectEmit(true, true, false, true, address(p2pLending));
        emit LoanRepayment(agreementId, borrower, totalDue, totalDue, 0, P2PLending.LoanStatus.Repaid);
        vm.expectEmit(false, false, false, true, address(p2pLending));
        emit LoanAgreementRepaid(agreementId);
        
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower (agreementId, user indexed)
        emit LoanTermOutcomeRecorded(agreementId, borrower, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL(), "Loan repaid on time (original terms)", Reputation.PaymentOutcomeType.OnTimeOriginal);
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower (borrower is topic1)
        emit ReputationUpdated(borrower, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL(), "Loan repaid on time (original terms)");
        
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender (agreementId, user indexed)
        emit LoanTermOutcomeRecorded(agreementId, lender, reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL(), "Loan lent and repaid on time (original terms)", Reputation.PaymentOutcomeType.OnTimeOriginal);
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender (lender is topic1)
        emit ReputationUpdated(lender, reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL(), "Loan lent and repaid on time (original terms)");

        p2pLending.repayLoan(agreementId, totalDue);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Repaid));
        assertEq(agreementAfter.amountPaid, totalDue);

        Reputation.ReputationProfile memory borrowerProfile = reputation.getReputationProfile(borrower);
        assertEq(borrowerProfile.currentReputationScore, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL());
    }

    function test_RepayLoan_Partial_Then_Full_Success_WithCollateral() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 200e18);
        bytes32 offerId = p2pLending.createLoanOffer(200e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 14 * ONE_DAY_SECONDS, 100e6, address(mockUsdc));
        vm.stopPrank();

        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), 100e6);
        bytes32 agreementId = p2pLending.acceptLoanOffer(offerId, 100e6, address(mockUsdc));
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreement = p2pLending.getLoanAgreementDetails(agreementId);
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        uint256 partialPayment = totalDue / 2;
        uint256 remainingPayment = totalDue - partialPayment;

        vm.warp(agreement.dueDate - 2 days); // Ensure payment is on time

        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), partialPayment);
        p2pLending.repayLoan(agreementId, partialPayment);
        vm.stopPrank();

        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), remainingPayment);

        vm.expectEmit(true, true, false, true, address(p2pLending));
        emit LoanRepayment(agreementId, borrower, remainingPayment, totalDue, 0, P2PLending.LoanStatus.Repaid);
        vm.expectEmit(false, false, false, true, address(p2pLending));
        emit LoanAgreementRepaid(agreementId);

        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for borrower (agreementId, user indexed)
        emit LoanTermOutcomeRecorded(agreementId, borrower, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL(), "Loan repaid on time (original terms)", Reputation.PaymentOutcomeType.OnTimeOriginal);
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for borrower (borrower is topic1)
        emit ReputationUpdated(borrower, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL(), "Loan repaid on time (original terms)");
        
        vm.expectEmit(true, true, false, false, address(reputation)); // LTOR for lender (agreementId, user indexed)
        emit LoanTermOutcomeRecorded(agreementId, lender, reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL(), "Loan lent and repaid on time (original terms)", Reputation.PaymentOutcomeType.OnTimeOriginal);
        vm.expectEmit(true, false, false, true, address(reputation)); // RU for lender (lender is topic1)
        emit ReputationUpdated(lender, reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL(), "Loan lent and repaid on time (original terms)");

        p2pLending.repayLoan(agreementId, remainingPayment);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Repaid));
    }
    
    function test_RepayLoan_MultiplePartials_ThenFullRepayment() public {
        bytes32 agreementId = _createAndAcceptOfferNoCollateral_IdOnly();

        // Calculate totalDue based on constants as the agreement struct is not fetched here
        uint256 totalDueInTest = (DEFAULT_OFFER_AMOUNT_P2P * (BASIS_POINTS_TEST + DEFAULT_INTEREST_RATE_P2P)) / BASIS_POINTS_TEST;
        uint256 payment1 = totalDueInTest / 4;
        uint256 payment2 = totalDueInTest / 4;
        uint256 payment3 = totalDueInTest / 2; // This should be totalDueInTest - payment1 - payment2 for exactness
        // Correcting payment3 for exact repayment:
        payment3 = totalDueInTest - payment1 - payment2;

        vm.warp(block.timestamp + 1 days); // Warp to a point well before typical 7-day due date

        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), totalDueInTest); // Approve total once
        p2pLending.repayLoan(agreementId, payment1);
        p2pLending.repayLoan(agreementId, payment2);
        p2pLending.repayLoan(agreementId, payment3);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Repaid));
        assertEq(agreementAfter.amountPaid, totalDueInTest);
    }

    function test_RepayLoan_Partial_StatusRemainsActive() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        uint256 partialPayment = totalDue / 2;

        vm.warp(agreement.dueDate - 1 days); // Before due date
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), partialPayment);
        p2pLending.repayLoan(agreementId, partialPayment);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Active));
    }

    function test_RepayLoan_Partial_StatusBecomesOverdue() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        uint256 partialPayment = totalDue / 2;

        vm.warp(agreement.dueDate + 1 days); // After due date
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), partialPayment);
        p2pLending.repayLoan(agreementId, partialPayment);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Overdue));
    }

    function test_RevertIf_RepayLoan_NotBorrower() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(lender); // Not borrower
        mockDai.approve(address(p2pLending), 10e18);
        vm.expectRevert(bytes("P2PL: Not borrower"));
        p2pLending.repayLoan(agreementId, 10e18);
        vm.stopPrank();
    }

    function test_RevertIf_RepayLoan_Overpayment() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), totalDue + 1e18);
        vm.expectRevert(bytes("Payment exceeds remaining due"));
        p2pLending.repayLoan(agreementId, totalDue + 1e18);
        vm.stopPrank();
    }

    // --- Default Tests ---
    function test_HandleP2PDefault_Success_NoCollateral() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();

        // Add a vouch for the borrower from voucher1
        uint256 vouchStakeAmount = 50e18;
        vm.startPrank(voucher1);
        mockDai.approve(address(reputation), vouchStakeAmount);
        reputation.addVouch(borrower, vouchStakeAmount, address(mockDai));
        vm.stopPrank();
        Reputation.ReputationProfile memory voucherProfileBefore = reputation.getReputationProfile(voucher1);
        uint256 lenderDaiBalanceBeforeSlash = mockDai.balanceOf(lender);

        vm.warp(agreement.dueDate + 1 days); // Advance time past due date
        
        vm.startPrank(lender); // Lender calls default
        vm.expectEmit(false, false, false, true, address(p2pLending));
        emit LoanAgreementDefaulted(agreementId);

        vm.expectEmit(true, false, false, true, address(reputation)); // ReputationUpdated for borrower (borrower is topic1)
        emit ReputationUpdated(borrower, reputation.REPUTATION_POINTS_DEFAULTED(), "Loan defaulted");
         
        uint256 expectedSlashAmount = (vouchStakeAmount * 1000) / BASIS_POINTS_TEST; // 10%
        vm.expectEmit(true, true, true, true, address(reputation)); 
        emit VouchSlashed(voucher1, borrower, expectedSlashAmount, lender);
        vm.expectEmit(true, false, false, true, address(reputation)); // (voucher1 is topic1)
        emit ReputationUpdated(voucher1, voucherProfileBefore.currentReputationScore + reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER(), "Vouched loan defaulted, stake slashed");

        p2pLending.handleP2PDefault(agreementId);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Defaulted));
        Reputation.ReputationProfile memory borrowerProfile = reputation.getReputationProfile(borrower);
        assertEq(borrowerProfile.currentReputationScore, reputation.REPUTATION_POINTS_DEFAULTED());

        // Check voucher state
        Reputation.ReputationProfile memory voucherProfileAfter = reputation.getReputationProfile(voucher1);
        assertEq(voucherProfileAfter.currentReputationScore, voucherProfileBefore.currentReputationScore + reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER(), "Voucher reputation incorrect no collateral");
        Reputation.Vouch memory vouchAfter = reputation.getVouchDetails(voucher1, borrower);
        assertEq(vouchAfter.stakedAmount, vouchStakeAmount - expectedSlashAmount, "Voucher stake incorrect no collateral");
        assertEq(mockDai.balanceOf(lender), lenderDaiBalanceBeforeSlash + expectedSlashAmount, "Lender DAI incorrect after slash no collateral");
    }

    function test_HandleP2PDefault_Success_WithCollateral() public {
        vm.startPrank(lender);
        mockDai.approve(address(p2pLending), 100e18);
        bytes32 offerId = p2pLending.createLoanOffer(100e18, address(mockDai), DEFAULT_INTEREST_RATE_P2P, 7 * ONE_DAY_SECONDS, 50e6, address(mockUsdc));
        vm.stopPrank();

        vm.startPrank(borrower);
        mockUsdc.approve(address(p2pLending), 50e6);
        bytes32 agreementId = p2pLending.acceptLoanOffer(offerId, 50e6, address(mockUsdc));
        vm.stopPrank();
        P2PLending.LoanAgreement memory agreement = p2pLending.getLoanAgreementDetails(agreementId);

        // Add a vouch
        uint256 vouchStakeAmount = 30e18;
        vm.startPrank(voucher1);
        mockDai.approve(address(reputation), vouchStakeAmount);
        reputation.addVouch(borrower, vouchStakeAmount, address(mockDai));
        vm.stopPrank();
        Reputation.ReputationProfile memory voucherProfileBefore = reputation.getReputationProfile(voucher1);
        uint256 lenderDaiBalanceBeforeSlash = mockDai.balanceOf(lender);

        vm.warp(agreement.dueDate + 1 days); // Advance time past due date
        uint256 lenderUsdcBefore = mockUsdc.balanceOf(lender);

        vm.startPrank(lender);
        vm.expectEmit(true, true, false, true, address(p2pLending));
        emit CollateralSeized(agreementId, address(mockUsdc), 50e6, lender);
        vm.expectEmit(true, false, false, true, address(reputation)); // (borrower is topic1)
        emit ReputationUpdated(borrower, reputation.REPUTATION_POINTS_DEFAULTED(), "Loan defaulted");
        
        uint256 expectedSlashAmount = (vouchStakeAmount * 1000) / BASIS_POINTS_TEST; // 10%
        vm.expectEmit(true, true, true, true, address(reputation)); 
        emit VouchSlashed(voucher1, borrower, expectedSlashAmount, lender);
        vm.expectEmit(true, false, false, true, address(reputation)); // (voucher1 is topic1)
        emit ReputationUpdated(voucher1, voucherProfileBefore.currentReputationScore + reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER(), "Vouched loan defaulted, stake slashed");

        p2pLending.handleP2PDefault(agreementId);
        vm.stopPrank();

        assertEq(mockUsdc.balanceOf(lender), lenderUsdcBefore + 50e6);
        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Defaulted));
        Reputation.ReputationProfile memory borrowerProfile = reputation.getReputationProfile(borrower);
        assertEq(borrowerProfile.currentReputationScore, reputation.REPUTATION_POINTS_DEFAULTED());

        // Check voucher state
        Reputation.ReputationProfile memory voucherProfileAfter = reputation.getReputationProfile(voucher1);
        assertEq(voucherProfileAfter.currentReputationScore, voucherProfileBefore.currentReputationScore + reputation.REPUTATION_POINTS_VOUCH_DEFAULTED_VOUCHER(), "Voucher reputation incorrect");
        Reputation.Vouch memory vouchAfter = reputation.getVouchDetails(voucher1, borrower);
        assertEq(vouchAfter.stakedAmount, vouchStakeAmount - expectedSlashAmount, "Voucher stake incorrect");
        assertEq(mockDai.balanceOf(lender), lenderDaiBalanceBeforeSlash + expectedSlashAmount, "Lender DAI incorrect after slash");
    }

    function test_RevertIf_HandleP2PDefault_NotOverdue() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(lender);
        vm.expectRevert(bytes("Loan not yet overdue"));
        p2pLending.handleP2PDefault(agreementId);
        vm.stopPrank();
    }

    function test_RevertIf_HandleP2PDefault_AlreadyRepaid() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), totalDue);
        p2pLending.repayLoan(agreementId, totalDue);
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectRevert(bytes("P2PL: Loan not in defaultable state (Active/Overdue)"));
        p2pLending.handleP2PDefault(agreementId);
        vm.stopPrank();
    }

    // --- Payment Modification Tests ---
    function test_RequestAndApproveDueDateExtension() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 newDueDate = agreement.dueDate + 5 days;

        vm.startPrank(borrower);
        vm.expectEmit(true, true, false, true, address(p2pLending));
        emit PaymentModificationRequested(agreementId, borrower, P2PLending.PaymentModificationType.DueDateExtension, newDueDate);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, newDueDate);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfterReq = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfterReq.status), uint(P2PLending.LoanStatus.PendingModificationApproval));

        vm.startPrank(lender);
        vm.expectEmit(true, true, false, true, address(p2pLending));
        emit PaymentModificationResponded(agreementId, lender, true, P2PLending.PaymentModificationType.DueDateExtension, newDueDate);
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfterApproval = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(agreementAfterApproval.dueDate, newDueDate);
        assertEq(uint(agreementAfterApproval.status), uint(P2PLending.LoanStatus.Active));
        assertTrue(agreementAfterApproval.modificationApprovedByLender);
    }

    function test_RequestAndApprovePartialPaymentAgreement() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 partialAmount = 50e18;

        vm.startPrank(borrower);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.PartialPaymentAgreement, partialAmount);
        vm.stopPrank();

        vm.startPrank(lender);
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Active_PartialPaymentAgreed));
        assertEq(agreementAfter.requestedModificationValue, partialAmount); 
    }
    
    function test_RepayLoan_AgreedPartialPayment_Success() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 partialAmount = 30e18;

        vm.startPrank(borrower);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.PartialPaymentAgreement, partialAmount);
        vm.stopPrank();
        vm.startPrank(lender);
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();

        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), partialAmount);
        p2pLending.repayLoan(agreementId, partialAmount);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(agreementAfter.amountPaid, partialAmount);
        // Status should revert from Active_PartialPaymentAgreed to Active (or Overdue if due date passed)
        // This test assumes it remains Active for simplicity here.
        assertTrue(uint(agreementAfter.status) == uint(P2PLending.LoanStatus.Active) || uint(agreementAfter.status) == uint(P2PLending.LoanStatus.Overdue) ); 
    }

    function test_RepayLoan_AgreedPartialPayment_IncorrectAmount() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 agreedPartialAmount = 30e18;
        uint256 incorrectPayment = 20e18;

        vm.startPrank(borrower);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.PartialPaymentAgreement, agreedPartialAmount);
        vm.stopPrank();
        vm.startPrank(lender);
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();

        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), incorrectPayment);
        p2pLending.repayLoan(agreementId, incorrectPayment);
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfter = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(agreementAfter.amountPaid, incorrectPayment);
        // Status should remain Active_PartialPaymentAgreed because the agreed amount was not met.
        assertEq(uint(agreementAfter.status), uint(P2PLending.LoanStatus.Active_PartialPaymentAgreed));
    }

    function test_RequestAndRejectModification() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 originalDueDate = agreement.dueDate;
        uint256 newDueDate = agreement.dueDate + 5 days;

        vm.startPrank(borrower);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, newDueDate);
        vm.stopPrank();

        vm.startPrank(lender);
        p2pLending.respondToPaymentModification(agreementId, false); // Reject
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreementAfterReject = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(agreementAfterReject.dueDate, originalDueDate); // Due date should not change
        assertEq(uint(agreementAfterReject.status), uint(P2PLending.LoanStatus.Active)); // Or Overdue if time passed
        assertFalse(agreementAfterReject.modificationApprovedByLender);
    }

    function test_RevertIf_RequestModification_NotBorrower() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(lender); // Not borrower
        vm.expectRevert(bytes("P2PL: Not borrower"));
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, block.timestamp + 10 days);
        vm.stopPrank();
    }
    
    function test_RevertIf_RequestModification_LoanNotActiveOrOverdue_InvalidId() public {
        bytes32 nonExistentAgreementId = keccak256(abi.encodePacked("non-existent-agreement"));

        vm.startPrank(borrower);
        // Test with a non-existent ID
        vm.expectRevert(bytes("P2PL: Not borrower")); // Because agreement.borrower will be address(0)
        p2pLending.requestPaymentModification(nonExistentAgreementId, P2PLending.PaymentModificationType.DueDateExtension, block.timestamp + 10 days);
        vm.stopPrank();
    }

    function test_RevertIf_RequestModification_OnRepaidLoan() public {
        (bytes32 agreementId, P2PLending.LoanAgreement memory agreement) = _createAndAcceptOfferNoCollateral_WithDetails();
        uint256 totalDue = (agreement.principalAmount * (BASIS_POINTS_TEST + agreement.interestRateBPS)) / BASIS_POINTS_TEST;
        vm.startPrank(borrower);
        mockDai.approve(address(p2pLending), totalDue);
        p2pLending.repayLoan(agreementId, totalDue);
        
        vm.expectRevert(bytes("P2PL: Loan not active/overdue"));
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, block.timestamp + 10 days);
        vm.stopPrank();
    }

    function test_RevertIf_RequestModification_InvalidValue() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(borrower);
        vm.expectRevert(bytes("P2PL: Modification value must be > 0"));
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, 0); // Invalid new due date
        vm.stopPrank();
    }

    function test_RevertIf_RespondModification_NotLender() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(borrower);
        p2pLending.requestPaymentModification(agreementId, P2PLending.PaymentModificationType.DueDateExtension, block.timestamp + 10 days);
        vm.stopPrank();

        vm.startPrank(borrower); // Not lender
        vm.expectRevert(bytes("P2PL: Not lender"));
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();
    }

    function test_RevertIf_RespondModification_NoPendingModification() public {
        (bytes32 agreementId, ) = _createAndAcceptOfferNoCollateral_WithDetails();
        vm.startPrank(lender);
        vm.expectRevert(bytes("P2PL: No pending modification"));
        p2pLending.respondToPaymentModification(agreementId, true);
        vm.stopPrank();
    }
} 