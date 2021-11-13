// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./DHorseAuction.sol";

/// @title all functions related to creating DHorses
contract DHorseMinting is DHorseAuction {

    // Limits the number of DHorses the contract owner can ever create.
    uint256 public constant PROMO_CREATION_LIMIT = 5000;
    uint256 public constant GEN0_CREATION_LIMIT = 45000;

    // Constants for gen0 auctions.
    uint256 public constant GEN0_STARTING_PRICE = 10e15;
    uint256 public constant GEN0_AUCTION_DURATION = 1 days;

    // Counts the number of DHorses the contract owner has created.
    uint256 public promoCreatedCount;
    uint256 public gen0CreatedCount;

    /// @dev we can create promo DHorses, up to a limit. Only callable by owner
    /// @param _owner the future owner of the created DHorses. Default to contract owner
    function createPromoDHorse(address _owner) external onlyOwner {
        address DHorseOwner = _owner;
        if (DHorseOwner == address(0)) {
             DHorseOwner = owner();
        }
        require(promoCreatedCount < PROMO_CREATION_LIMIT);

        promoCreatedCount++;
        _createHorse(0, 0, 0,  DHorseOwner);
    }

    /// @dev Creates a new gen0 DHorse with the given  and
    ///  creates an auction for it.
    function createGen0Auction() external onlyOwner {
        require(gen0CreatedCount < GEN0_CREATION_LIMIT);

        uint256 DHorseId = _createHorse(0, 0, 0, address(this));
        _approve(address(saleAuction), DHorseId);

        saleAuction.createAuction(
            DHorseId,
            _computeNextGen0Price(),
            0,
            GEN0_AUCTION_DURATION,
            address(this)
        );

        gen0CreatedCount++;
    }

    /// @dev Computes the next gen0 auction starting price, given
    ///  the average of the past 5 prices + 50%.
    function _computeNextGen0Price() internal view returns (uint256) {
        uint256 avePrice = saleAuction.averageGen0SalePrice();

        // Sanity check to ensure we don't overflow arithmetic
        require(avePrice == uint256(uint128(avePrice)));

        uint256 nextPrice = avePrice + (avePrice / 2);

        // We never auction for less than starting price
        if (nextPrice < GEN0_STARTING_PRICE) {
            nextPrice = GEN0_STARTING_PRICE;
        }

        return nextPrice;
    }

         
 

}
