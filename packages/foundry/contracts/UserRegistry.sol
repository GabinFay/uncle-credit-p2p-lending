// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title UserRegistry
 * @dev Simple registry for tracking user profiles tied to Ethereum addresses.
 * MVP version without World ID - just basic address-based registration.
 */
contract UserRegistry {
    struct UserProfile {
        bool isRegistered;
        string name;
        uint256 registrationTime;
    }

    // Mapping from address to user profile
    mapping(address => UserProfile) public userProfiles;
    
    // Array to keep track of all registered users
    address[] public registeredUsers;
    
    // Total number of registered users
    uint256 public totalUsers;

    event UserRegistered(address indexed userAddress, string name, uint256 timestamp);
    event UserProfileUpdated(address indexed userAddress, string newName);

    /**
     * @dev Constructor - simple setup for MVP
     */
    constructor() {
        // No complex setup needed for MVP
    }

    /**
     * @dev Registers a new user with their address and basic info
     * @param _name The display name for the user
     */
    function registerUser(string memory _name) public {
        require(!userProfiles[msg.sender].isRegistered, "UserRegistry: Address already registered");
        require(bytes(_name).length > 0, "UserRegistry: Name cannot be empty");
        require(bytes(_name).length <= 50, "UserRegistry: Name too long");

        userProfiles[msg.sender] = UserProfile({
            isRegistered: true,
            name: _name,
            registrationTime: block.timestamp
        });
        
        registeredUsers.push(msg.sender);
        totalUsers++;

        emit UserRegistered(msg.sender, _name, block.timestamp);
    }

    /**
     * @dev Updates user's profile name
     * @param _newName The new display name
     */
    function updateProfile(string memory _newName) public {
        require(userProfiles[msg.sender].isRegistered, "UserRegistry: User not registered");
        require(bytes(_newName).length > 0, "UserRegistry: Name cannot be empty");
        require(bytes(_newName).length <= 50, "UserRegistry: Name too long");

        userProfiles[msg.sender].name = _newName;
        emit UserProfileUpdated(msg.sender, _newName);
    }

    /**
     * @dev Checks if a user is registered
     * @param _userAddress The address to check
     * @return True if registered, false otherwise
     */
    function isUserRegistered(address _userAddress) public view returns (bool) {
        return userProfiles[_userAddress].isRegistered;
    }

    /**
     * @dev Gets user profile information
     * @param _userAddress The address to query
     * @return isRegistered Whether the user is registered
     * @return name The user's display name
     * @return registrationTime When the user registered
     */
    function getUserProfile(address _userAddress) public view returns (bool isRegistered, string memory name, uint256 registrationTime) {
        UserProfile memory profile = userProfiles[_userAddress];
        return (profile.isRegistered, profile.name, profile.registrationTime);
    }

    /**
     * @dev Gets a registered user by index
     * @param _index The index in the registeredUsers array
     * @return The user's address
     */
    function getRegisteredUser(uint256 _index) public view returns (address) {
        require(_index < totalUsers, "UserRegistry: Index out of bounds");
        return registeredUsers[_index];
    }

    /**
     * @dev Gets the total number of registered users
     * @return The total count
     */
    function getTotalUsers() public view returns (uint256) {
        return totalUsers;
    }
} 