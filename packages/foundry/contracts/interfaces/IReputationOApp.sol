// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title IReputationOApp
 * @dev Placeholder interface for a LayerZero Omnichain Application (OApp) for reputation.
 * This contract would handle sending and receiving reputation updates across chains.
 */
interface IReputationOApp is IERC165 {

    /**
     * @notice Sends a user's reputation update to a destination chain via LayerZero.
     * This function would be called on the source chain.
     * @param _destinationChainId The LayerZero chain ID of the destination.
     * @param _userAddress The address of the user whose reputation is being sent.
     * @param _newReputationScore The user's new total reputation score.
     * @param _adapterParams LayerZero adapter parameters for customizing message execution (e.g., gas).
     */
    function sendReputationToChain(
        uint32 _destinationChainId,
        address _userAddress, 
        int256 _newReputationScore,
        bytes calldata _adapterParams
    ) external payable; // Payable to cover LayerZero messaging fees

    /**
     * @notice Called by the LayerZero endpoint on the destination chain to deliver a reputation update.
     * This function is part of the OApp's receiving logic.
     * @param _sourceChainId The LayerZero chain ID from which this update originated.
     * @param _userAddress The address of the user whose reputation is to be updated.
     * @param _newReputationScore The user's new total reputation score from the source chain.
     */
    function receiveReputationUpdate(
        uint32 _sourceChainId,
        address _userAddress, 
        int256 _newReputationScore
    ) external; // May also need Ownable/access control to ensure only LZ endpoint calls it

    /**
     * @notice Gets a user's current locally stored (potentially aggregated) reputation score.
     * @param user The address of the user.
     * @return The current reputation score on this chain.
     */
    function getLocalReputation(address user) external view returns (int256);

    // Other LayerZero utilities like quoteFees would also be part of a full OApp implementation.
    // function estimateFees(uint32 _dstChainId, bytes calldata _toAddress, bytes calldata _payload, bool _useZro, bytes calldata _adapterParams) external view returns (uint nativeFee, uint zroFee);
} 