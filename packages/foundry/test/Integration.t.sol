// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UserRegistry} from "../contracts/UserRegistry.sol";
import {P2PLending} from "../contracts/P2PLending.sol";
import {Reputation} from "../contracts/Reputation.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract IntegrationTest is Test {
    UserRegistry userRegistry;
    P2PLending p2pLending;
    Reputation reputation;
    MockERC20 mockDai;

    address deployer;
    address user1; // Borrower
    address user2; // Lender
    address user3; // Another user

    uint256 constant ONE_DAY_SECONDS = 1 days;

    function setUp() public {
        deployer = vm.addr(1);
        user1 = vm.addr(2);
        user2 = vm.addr(3);
        user3 = vm.addr(4);

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        reputation = new Reputation(address(userRegistry));
        p2pLending = new P2PLending(address(userRegistry), address(reputation), payable(deployer), address(0));
        
        // Set P2PLending address in Reputation contract
        reputation.setP2PLendingContractAddress(address(p2pLending));
        
        mockDai = new MockERC20("MockDAI", "mDAI", 18);
        vm.stopPrank();

        // Register users with simplified registration
        vm.prank(user1);
        userRegistry.registerUser("Alice");
        vm.prank(user2);
        userRegistry.registerUser("Bob");
        vm.prank(user3);
        userRegistry.registerUser("Charlie");

        // Mint DAI for users
        vm.startPrank(deployer);
        mockDai.mint(user1, 1000e18);
        mockDai.mint(user2, 1000e18);
        vm.stopPrank();
    }

    function test_FullLoanCycle_OnTimeRepayment_NoCollateral() public {
        // 1. Lender (user2) creates a loan offer
        uint256 offerPrincipal = 100e18;
        uint16 offerInterestBPS = 500; // 5%
        uint256 offerDurationSeconds = 30 * ONE_DAY_SECONDS;
        address loanToken = address(mockDai);

        vm.startPrank(user2);
        mockDai.approve(address(p2pLending), offerPrincipal);

        bytes32 offerId = p2pLending.createLoanOffer(
            offerPrincipal,
            loanToken,
            offerInterestBPS,
            offerDurationSeconds,
            0,
            address(0)
        );
        vm.stopPrank();

        assertTrue(offerId != bytes32(0), "offerId should not be zero");

        P2PLending.LoanOffer memory createdOffer = p2pLending.getLoanOfferDetails(offerId);
        assertEq(createdOffer.lender, user2, "Offer lender mismatch");
        assertEq(createdOffer.amount, offerPrincipal, "Offer principal mismatch");

        // 2. Borrower (user1) accepts the loan offer
        vm.startPrank(user1);
        bytes32 agreementId = p2pLending.acceptLoanOffer(offerId, 0, address(0));
        vm.stopPrank();

        P2PLending.LoanAgreement memory agreement = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(agreement.borrower, user1, "Agreement borrower mismatch");
        assertEq(agreement.lender, user2, "Agreement lender mismatch");
        uint256 totalDue = agreement.principalAmount + (agreement.principalAmount * uint256(agreement.interestRateBPS) / 10000);

        // 3. Borrower (user1) repays the loan on time
        vm.warp(agreement.dueDate - 1 * ONE_DAY_SECONDS);

        vm.startPrank(user1);
        mockDai.approve(address(p2pLending), totalDue);
        p2pLending.repayLoan(agreementId, totalDue);
        vm.stopPrank();

        assertEq(uint(p2pLending.getLoanAgreementDetails(agreementId).status), uint(P2PLending.LoanStatus.Repaid), "Loan not repaid");
        
        // Check reputation scores
        Reputation.ReputationProfile memory borrowerProfile = reputation.getReputationProfile(user1);
        Reputation.ReputationProfile memory lenderProfile = reputation.getReputationProfile(user2);
        
        assertEq(borrowerProfile.currentReputationScore, reputation.REPUTATION_POINTS_REPAID_ON_TIME_ORIGINAL(), "Borrower reputation incorrect after on-time repayment");
        assertEq(lenderProfile.currentReputationScore, reputation.REPUTATION_POINTS_LENT_SUCCESSFULLY_ON_TIME_ORIGINAL(), "Lender reputation incorrect after on-time repayment");
    }

    function test_FullLoanCycle_Default_WithCollateral() public {
        // 1. Lender (user2) creates a loan offer with collateral
        uint256 offerPrincipal = 50e18;
        uint16 offerInterestBPS = 1000; // 10%
        uint256 offerDurationSeconds = 15 * ONE_DAY_SECONDS;
        address loanTokenDefault = address(mockDai);
        address offerCollateralToken = address(mockDai);
        uint256 offerCollateralAmount = 60e18;

        vm.startPrank(user2);
        mockDai.approve(address(p2pLending), offerPrincipal);

        bytes32 offerId = p2pLending.createLoanOffer(
            offerPrincipal, 
            loanTokenDefault, 
            offerInterestBPS, 
            offerDurationSeconds, 
            offerCollateralAmount, 
            offerCollateralToken
        );
        vm.stopPrank();

        // 2. Borrower (user1) accepts the loan offer
        vm.startPrank(user1);
        mockDai.approve(address(p2pLending), offerCollateralAmount);
        bytes32 agreementId = p2pLending.acceptLoanOffer(offerId, offerCollateralAmount, offerCollateralToken);
        vm.stopPrank();

        // Check balances after loan acceptance
        assertEq(mockDai.balanceOf(user1), 1000e18 - offerCollateralAmount + offerPrincipal, "Borrower DAI balance incorrect after loan with collateral");
        assertEq(mockDai.balanceOf(address(p2pLending)), offerCollateralAmount, "P2P contract should hold collateral");
        assertEq(mockDai.balanceOf(user2), 1000e18 - offerPrincipal, "Lender DAI balance incorrect after loan with collateral");

        P2PLending.LoanAgreement memory agreement = p2pLending.getLoanAgreementDetails(agreementId);
        
        // 3. Time passes, loan becomes overdue and defaults
        vm.warp(agreement.dueDate + 2 * ONE_DAY_SECONDS);

        // 4. Lender (user2) handles the default
        vm.startPrank(user2);
        p2pLending.handleP2PDefault(agreementId);
        vm.stopPrank();

        agreement = p2pLending.getLoanAgreementDetails(agreementId);
        assertEq(uint(agreement.status), uint(P2PLending.LoanStatus.Defaulted), "Loan status not Defaulted");

        // Check balances after default handling
        assertEq(mockDai.balanceOf(user1), 1000e18 - offerCollateralAmount + offerPrincipal, "Borrower DAI balance incorrect after default");
        assertEq(mockDai.balanceOf(address(p2pLending)), 0, "P2P contract DAI balance should be 0 after default");
        assertEq(mockDai.balanceOf(user2), 1000e18 - offerPrincipal + offerCollateralAmount, "Lender DAI balance incorrect after default (collateral transfer)");

        // Check reputation - borrower should lose reputation for defaulting
        Reputation.ReputationProfile memory borrowerProfile = reputation.getReputationProfile(user1);
        assertLt(borrowerProfile.currentReputationScore, 0, "Borrower reputation should be negative after default");
    }
} 