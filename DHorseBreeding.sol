// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./DHorseBase.sol";

contract DHorseBreeding is DHorseBase{
     /// @dev The Pregnant event is fired when two DHorses successfully breed and the pregnancy
    ///  timer begins for the matron.
    event Pregnant(address owner, uint256 matronId, uint256 sireId, uint256 cooldownEndBlock);

    /// @notice The minimum payment required to use breed(). This fee goes towards
    ///  the gas cost paid by whatever calls giveBirth().
    uint256 public autoBirthFee = 2e15;

    // Keeps track of number of pregnant DHorses.
    uint256 public pregnantHorses;


    /// @dev Checks that a given DHorses is able to breed. Requires that the
    ///  current cooldown is finished (for sires) and also checks that there is
    ///  no pending pregnancy.
    function _isReadyToBreed(Horse memory _Horse) internal view returns (bool) {
        // In addition to checking the cooldownEndBlock, we also need to check to see if
        // the pethas a pending birth; there can be some period of time between the end
        // of the pregnacy timer and the birth event.
        return (_Horse.siringWithId == 0) && (_Horse.cooldownEndBlock <= uint64(block.number));
    }

    /// @dev Check if a sire has authorized breeding with this matron. True if both sire
    ///  and matron have the same owner, or if the sire has given siring permission to
    ///  the matron's owner (via approveSiring()).
    function _isSiringPermitted(uint256 _sireId, uint256 _matronId) internal view returns (bool) {
        address matronOwner = _owners[_matronId];
        address sireOwner = _owners[_sireId];

        // Siring is okay if they have same owner, or if the matron's owner was given
        // permission to breed with this sire.
        return (matronOwner == sireOwner || sireAllowedToAddress[_sireId] == matronOwner);
    }

    // @dev Set the cooldownEndTime for the given DHorse, based on its current cooldownIndex.
    //  Also increments the cooldownIndex (unless it has hit the cap).
    // @param _DHorses A reference to the DHorse in storage which needs its timer started.
    function _triggerCooldown(Horse storage _Horses) internal {
        // Compute an estimation of the cooldown time in blocks (based on current cooldownIndex).
        _Horses.cooldownEndBlock = uint64((cooldowns[_Horses.cooldownIndex]/secondsPerBlock) + block.number);

        // Increment the breeding count, clamping it at 13
        if (_Horses.cooldownIndex < 13) {
            _Horses.cooldownIndex += 1;
        }
    }

    /// @notice Grants approval to another user to sire with one of your DHorses.
    /// @param _addr The address that will be able to sire with your DHorse. Set to
    ///  address(0) to clear all siring approvals for this DHorse.
    /// @param _sireId A DHorse that you own that _addr will now be able to sire with.
    function approveSiring(address _addr, uint256 _sireId)
        external
        whenNotPaused
    {
        require(_owns(msg.sender, _sireId));
        sireAllowedToAddress[_sireId] = _addr;
    }

    /// @dev Updates the minimum payment required for calling giveBirthAuto(). 
    function setAutoBirthFee(uint256 val) external onlyOwner {
        autoBirthFee = val;
    }

    /// @dev Checks to see if a given DHorse is pregnant and (if so) if the gestation
    ///  period has passed.
    function _isReadyToGiveBirth(Horse memory _matron) private view returns (bool) {
        return (_matron.siringWithId != 0) && (_matron.cooldownEndBlock <= uint64(block.number));
    }

    // @notice Checks that a given DHorses is able to breed (i.e. it is not pregnant or
    //  in the middle of a siring cooldown).
    // @param _DHorseId reference the id of the DHorses, any user can inquire about it
    function isReadyToBreed(uint256 _HorseId)
        public
        view
        returns (bool)
    {
        require(_HorseId > 0);
        Horse storage _Horse = Horses[_HorseId];
        return _isReadyToBreed(_Horse);
    }

    // @dev Checks whether a DHorse is currently pregnant.
    // @param _DHorseId reference the id of the DHorses, any user can inquire about it
    function isPregnant(uint256 _HorseId)
        public
        view
        returns (bool)
    {
        require(_HorseId > 0);
        // A DHorse is pregnant if and only if this field is set
        return Horses[_HorseId].siringWithId != 0;
    }

    /// @dev Internal check to see if a given sire and matron are a valid mating pair.
    /// @param _matron A reference to the DHorse struct of the potential matron.
    /// @param _matronId The matron's ID.
    /// @param _sire A reference to the DHorse struct of the potential sire.
    /// @param _sireId The sire's ID
    function _isValidMatingPair(
        Horse storage _matron,
        uint256 _matronId,
        Horse storage _sire,
        uint256 _sireId
    )
        private
        view
        returns(bool)
    {
        // A DHorse can't breed with itself!
        if (_matronId == _sireId) {
            return false;
        }

        // DHorses can't breed with their parents.
        if (_matron.matronId == _sireId || _matron.sireId == _sireId) {
            return false;
        }
        if (_sire.matronId == _matronId || _sire.sireId == _matronId) {
            return false;
        }

        // We can short circuit the sibling check (below) if either DHorseis
        // gen zero (has a matron ID of zero).
        if (_sire.matronId == 0 || _matron.matronId == 0) {
            return true;
        }

        // DHorses can't breed with full or half siblings.
        if (_sire.matronId == _matron.matronId || _sire.matronId == _matron.sireId) {
            return false;
        }
        if (_sire.sireId == _matron.matronId || _sire.sireId == _matron.sireId) {
            return false;
        }

        return true;
    }

    /// @dev Internal check to see if a given sire and matron are a valid mating pair for
    ///  breeding via auction (i.e. skips ownership and siring approval checks).
    function _canBreedWithViaAuction(uint256 _matronId, uint256 _sireId)
        internal
        view
        returns (bool)
    {
        Horse storage matron = Horses[_matronId];
        Horse storage sire = Horses[_sireId];
        return _isValidMatingPair(matron, _matronId, sire, _sireId);
    }

    /// @notice Checks to see if two DHorses can breed together, including checks for
    ///  ownership and siring approvals. 
    /// @param _matronId The ID of the proposed matron.
    /// @param _sireId The ID of the proposed sire.
    function canBreedWith(uint256 _matronId, uint256 _sireId)
        external
        view
        returns(bool)
    {
        require(_matronId > 0);
        require(_sireId > 0);
        Horse storage matron = Horses[_matronId];
        Horse storage sire = Horses[_sireId];
        return _isValidMatingPair(matron, _matronId, sire, _sireId) &&
            _isSiringPermitted(_sireId, _matronId);
    }

    /// @dev Internal utility function to initiate breeding, assumes that all breeding
    ///  requirements have been checked.
    function _breedWith(uint256 _matronId, uint256 _sireId) internal {
        // Grab a reference to the DHorses from storage.
        Horse storage sire = Horses[_sireId];
        Horse storage matron = Horses[_matronId];

        // Mark the matron as pregnant, keeping track of who the sire is.
        matron.siringWithId = uint32(_sireId);

        // Trigger the cooldown for both parents.
        _triggerCooldown(sire);
        _triggerCooldown(matron);

        // Clear siring permission for both parents. This may not be strictly necessary
        delete sireAllowedToAddress[_matronId];
        delete sireAllowedToAddress[_sireId];

        // Every time a DHorse gets pregnant, counter is incremented.
        pregnantHorses++;

        // Emit the pregnancy event.
        emit Pregnant(_owners[_matronId], _matronId, _sireId, matron.cooldownEndBlock);
    }

    /// @notice Breed a DHorse you own (as matron) with a sire that you own, or for which you
    ///  have previously been given Siring approval. Will either make your DHorsepregnant, or will
    ///  fail entirely. Requires a pre-payment of the fee given out to the first caller of giveBirth()
    /// @param _matronId The ID of the DHorse acting as matron (will end up pregnant if successful)
    /// @param _sireId The ID of the DHorse acting as sire (will begin its siring cooldown if successful)
    function breed(uint256 _matronId, uint256 _sireId)
        external
        payable
        whenNotPaused
    {
        // Checks for payment.
        require(msg.value >= autoBirthFee);

        // Caller must own the matron.
        require(_owns(msg.sender, _matronId));
      
        // Check that matron and sire are both owned by caller, or that the sire
        // has given siring permission to caller (i.e. matron's owner).
        // Will fail for _sireId = 0
        require(_isSiringPermitted(_sireId, _matronId));

        // Grab a reference to the potential matron
        Horse storage matron = Horses[_matronId];

        // Make sure matron isn't pregnant, or in the middle of a siring cooldown
        require(_isReadyToBreed(matron));

        // Grab a reference to the potential sire
        Horse storage sire = Horses[_sireId];

        // Make sure sire isn't pregnant, or in the middle of a siring cooldown
        require(_isReadyToBreed(sire));

        // Test that these DHorses are a valid mating pair.
        require(_isValidMatingPair(
            matron,
            _matronId,
            sire,
            _sireId
        ));

        // All checks passed, DHorse gets pregnant!
        _breedWith(_matronId, _sireId);
    }

    /// @notice Have a pregnant DHorse give birth!
    /// @param _matronId A DHorse ready to give birth.
    /// @return The DHorse ID of the new DHorses.
    /// @dev Looks at a given DHorse and, if pregnant and if the gestation period has passed,
    ///  The new DHorse is assigned
    ///  to the current owner of the matron. Upon successful completion, both the matron and the
    ///  new DHorses will be ready to breed again. Note that anyone can call this function (if they
    ///  are willing to pay the gas!), but the new DHorses always goes to the mother's owner.
    function giveBirth(uint256 _matronId)
        external
        whenNotPaused
        returns(uint256)
    {
        // Grab a reference to the matron in storage.
        Horse storage matron = Horses[_matronId];

        // Check that the matron is a valid DHorse.
        require(matron.birthTime != 0);

        // Check that the matron is pregnant, and that its time has come!
        require(_isReadyToGiveBirth(matron));

        // Grab a reference to the sire in storage.
        uint256 sireId = matron.siringWithId;
        Horse storage sire = Horses[sireId];

        // Determine the higher generation number of the two parents
        uint16 parentGen = matron.generation;
        if (sire.generation > matron.generation) {
            parentGen = sire.generation;
        }

        // Make the new DHorses!
        address owner = _owners[_matronId];
        uint256 HorsesId = _createHorse(_matronId, matron.siringWithId, parentGen + 1,  owner);

        delete matron.siringWithId;

        // Every time a DHorse gives birth counter is decremented.
        pregnantHorses--;

        // Send the balance fee to the person who made birth happen.
        payable(msg.sender).transfer(autoBirthFee);

        // return the new DHorses's ID
        return HorsesId;
    }

    /// @dev Returns true if the claimant owns the token.
    /// @param _claimant - Address claiming to own the token.
    /// @param _tokenId - ID of token whose ownership to verify.
    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return (ownerOf(_tokenId) == _claimant);
    }

}
