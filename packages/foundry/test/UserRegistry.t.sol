// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UserRegistry} from "../contracts/UserRegistry.sol";

contract UserRegistryTest is Test {
    UserRegistry public userRegistry;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    function setUp() public {
        userRegistry = new UserRegistry();
    }
    
    function test_RegisterUser() public {
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        assertTrue(userRegistry.isUserRegistered(alice));
        
        (bool isRegistered, string memory name, uint256 registrationTime) = userRegistry.getUserProfile(alice);
        assertTrue(isRegistered);
        assertEq(name, "Alice");
        assertGt(registrationTime, 0);
        
        assertEq(userRegistry.getTotalUsers(), 1);
        assertEq(userRegistry.getRegisteredUser(0), alice);
    }
    
    function test_CannotRegisterTwice() public {
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        vm.prank(alice);
        vm.expectRevert("UserRegistry: Address already registered");
        userRegistry.registerUser("Alice Again");
    }
    
    function test_CannotRegisterEmptyName() public {
        vm.prank(alice);
        vm.expectRevert("UserRegistry: Name cannot be empty");
        userRegistry.registerUser("");
    }
    
    function test_CannotRegisterTooLongName() public {
        string memory longName = "This name is way too long and exceeds the 50 character limit set by the contract";
        
        vm.prank(alice);
        vm.expectRevert("UserRegistry: Name too long");
        userRegistry.registerUser(longName);
    }
    
    function test_UpdateProfile() public {
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        vm.prank(alice);
        userRegistry.updateProfile("Alice Updated");
        
        (, string memory name,) = userRegistry.getUserProfile(alice);
        assertEq(name, "Alice Updated");
    }
    
    function test_CannotUpdateUnregisteredProfile() public {
        vm.prank(alice);
        vm.expectRevert("UserRegistry: User not registered");
        userRegistry.updateProfile("Alice");
    }
    
    function test_MultipleUserRegistration() public {
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        vm.prank(bob);
        userRegistry.registerUser("Bob");
        
        vm.prank(charlie);
        userRegistry.registerUser("Charlie");
        
        assertEq(userRegistry.getTotalUsers(), 3);
        assertTrue(userRegistry.isUserRegistered(alice));
        assertTrue(userRegistry.isUserRegistered(bob));
        assertTrue(userRegistry.isUserRegistered(charlie));
        
        // Check order in array
        assertEq(userRegistry.getRegisteredUser(0), alice);
        assertEq(userRegistry.getRegisteredUser(1), bob);
        assertEq(userRegistry.getRegisteredUser(2), charlie);
    }
    
    function test_GetRegisteredUserOutOfBounds() public {
        vm.expectRevert("UserRegistry: Index out of bounds");
        userRegistry.getRegisteredUser(0);
        
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        vm.expectRevert("UserRegistry: Index out of bounds");
        userRegistry.getRegisteredUser(1);
    }
    
    function test_UnregisteredUserProfile() public {
        (bool isRegistered, string memory name, uint256 registrationTime) = userRegistry.getUserProfile(alice);
        assertFalse(isRegistered);
        assertEq(name, "");
        assertEq(registrationTime, 0);
    }
    
    function test_EventEmission() public {
        vm.expectEmit(true, false, false, true);
        emit UserRegistry.UserRegistered(alice, "Alice", block.timestamp);
        
        vm.prank(alice);
        userRegistry.registerUser("Alice");
        
        vm.expectEmit(true, false, false, true);
        emit UserRegistry.UserProfileUpdated(alice, "Alice Updated");
        
        vm.prank(alice);
        userRegistry.updateProfile("Alice Updated");
    }
} 