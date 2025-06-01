// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal interface for Pyth Network Price Feeds
interface IPyth {
    struct Price {
        int64 price;    // Price
        uint64 conf;     // Confidence interval
        int32 expo;      // Exponent
        uint publishTime; // Publish time
    }

    function getPrice(bytes32 id) external view returns (Price memory price);

    function getEmaPrice(bytes32 id) external view returns (Price memory price);

    // Add other functions as needed, e.g., for price updates if using accumulator model
    // function updatePriceFeeds(bytes[] calldata updateData) external payable;
    // function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
} 