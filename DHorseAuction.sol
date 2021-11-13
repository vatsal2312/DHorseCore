// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./DHorseBreeding.sol"; 
import "./SaleClockAuction.sol";


contract DHorseAuction is DHorseBreeding {

  
    /// @dev Sets the reference to the sale auction.
    /// @param _address - Address of sale contract.
    function setSaleAuctionAddress(address _address) external onlyOwner {
        SaleClockAuction candidateContract = SaleClockAuction(_address);

        require(candidateContract.isSaleClockAuction());

        // Set the new contract address
        saleAuction = candidateContract;
    }

   
    /// @dev Put a DHorse up for auction.
    ///  Does some ownership trickery to create auctions in one tx.
    function createSaleAuction(
        uint256 _HorseId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        whenNotPaused
    {
        // Auction contract checks input sizes
        // If DHorse is already on any auction, this will throw
        // because it will be owned by the auction contract.
        require(_owns(msg.sender, _HorseId));
        // Ensure the DHorse is not pregnant to prevent the auction
        // contract accidentally receiving ownership of the child.
        // NOTE: the DHorse IS allowed to be in a cooldown.
        require(!isPregnant(_HorseId));
        _approve(address(saleAuction),_HorseId);
        // Sale auction throws if inputs are invalid and clears
        // transfer and sire approval after escrowing the DHorse.
        saleAuction.createAuction(
            _HorseId,
            _startingPrice,
            _endingPrice,
            _duration,
            msg.sender
        );
    }

    
    /// @dev Transfers the balance of the sale auction contract
    /// to the DHorseCore contract. We use two-step withdrawal to
    /// prevent two transfer calls in the auction bid function.
    function withdrawAuctionBalances() external onlyOwner {
        saleAuction.withdrawBalance();
    }
}
