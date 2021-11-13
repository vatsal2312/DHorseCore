// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./ERC721Base.sol";
import "./SaleClockAuction.sol";

contract DHorseBase is ERC721Base("DHorse", "HORSE") {

    /// @dev The Birth event is fired whenever a new DHorse comes into existence. This obviously
    ///  includes any time a DHorse is created through the giveBirth method, but it is also called
    ///  when a new gen0 DHorse is created.
    event Birth(address owner, uint256 HorseId, uint256 matronId, uint256 sireId);

     /*** DATA TYPES ***/

    /// @dev The main DHorse struct. Every DHorse is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    struct Horse {

        // The timestamp from the block when this DHorsecame into existence.
        uint64 birthTime;

        // The minimum timestamp after which this DHorsecan engage in breeding
        // activities again. This same timestamp is used for the pregnancy
        // timer (for matrons) as well as the siring cooldown.
        uint64 cooldownEndBlock;

        // The ID of the parents of this DHorse, set to 0 for gen0 DHorses.
        uint32 matronId;
        uint32 sireId;

        // Set to the ID of the sire DHorsefor matrons that are pregnant,
        // zero otherwise. A non-zero value here is how we kblock.timestamp a DHorse
        // is pregnant. Used to retrieve the genetic material for the new
        // DHorse when the birth transpires.
        uint32 siringWithId;

        // Set to the index in the cooldown array (see below) that represents
        // the current cooldown duration for this DHorse. This starts at zero
        // for gen0 DHorses, and is initialized to floor(generation/2) for others.
        // Incremented by one for each successful breeding action, regardless
        // of whether this DHorseis acting as matron or sire.
        uint16 cooldownIndex;

        // The "generation number" of this DHorse.
        // for sale are called "gen0" and have a generation number of 0. The
        // generation number of all other DHorses is the larger of the two generation
        // numbers of their parents, plus one.
        // (i.e. max(matron.generation, sire.generation) + 1)
        uint16 generation;
    }

    /*** CONSTANTS ***/

    /// @dev A lookup table indipeting the cooldown duration after any successful
    ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    ///  for sires. Designed such that the cooldown roughly doubles each time a DHorse
    ///  is bred, encouraging owners not to just keep breeding the same DHorseover
    ///  and over again. Caps out at one week (a DHorsecan breed an unbounded number
    ///  of times, and the maximum cooldown is always seven days).
    uint32[14] public cooldowns = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;

    /*** STORAGE ***/

    /// @dev An array containing the DHorse struct for all DHorses in existence. The ID
    ///  of each DHorseis actually an index into this array. Note that ID 0 is a negaDHorse,
    ///  the unDHorse, the mythical beast that is the parent of all gen0 DHorses. A bizarre
    ///  creature that is both matron and sire... to itself! Has an invalid genetic code.
    ///  In other words, DHorseID 0 is invalid... ;-)
    Horse[] Horses;

    /// @dev A mapping from DHorseIDs to an address that has been approved to use
    ///  this DHorse for siring via breedWith(). Each DHorse can only have one approved
    ///  address for siring at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public sireAllowedToAddress;

    /// @dev The address of the ClockAuction contract that handles sales of DHorses. This
    ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    ///  initiated every 15 minutes.
    SaleClockAuction public saleAuction;

    constructor(){

    }

     function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._transfer(from, to, tokenId);
        // once the DHorse is transferred also clear sire allowances
        delete sireAllowedToAddress[tokenId];
    }

    /// @dev An internal method that creates a new DHorse and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is block.timestampn to be valid. Will generate both a Birth event
    ///  and a Transfer event.
    /// @param _matronId The DHorse ID of the matron of this DHorse(zero for gen0)
    /// @param _sireId The DHorse ID of the sire of this DHorse(zero for gen0)
    /// @param _generation The generation number of this DHorse, must be computed by caller.
    /// @param _owner The inital owner of this DHorse, must be non-zero (except for the unDHorse, ID 0)
    function _createHorse(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _generation,
        address _owner
    )
        internal
        returns (uint)
    {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createDHorse() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        require(_matronId == uint256(uint32(_matronId)));
        require(_sireId == uint256(uint32(_sireId)));
        require(_generation == uint256(uint16(_generation)));

        // New DHorse starts with the same cooldown as parent gen/2
        uint16 cooldownIndex = uint16(_generation / 2);
        if (cooldownIndex > 13) {
            cooldownIndex = 13;
        }

        Horse memory _Horse = Horse({
            birthTime: uint64(block.timestamp),
            cooldownEndBlock: 0,
            matronId: uint32(_matronId),
            sireId: uint32(_sireId),
            siringWithId: 0,
            cooldownIndex: cooldownIndex,
            generation: uint16(_generation)
        });
        Horses.push(_Horse);
        uint256 newHorseId =  Horses.length - 1;

      
        require(newHorseId == uint256(uint32(newHorseId)));

        // emit the birth event
        emit Birth( _owner, newHorseId, uint256(_Horse.matronId), uint256(_Horse.sireId));

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _mint(_owner, newHorseId);

        return newHorseId;
    }

    // Fix how many seconds per blocks are currently observed.
    function setSecondsPerBlock(uint256 secs) external onlyOwner {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }

    /// @notice Returns the total number of DHorses currently in existence.
    /// @dev Required for ERC-721 compliance.
    function totalSupply() public view returns (uint) {
        return Horses.length - 1;
    }

    /// @notice Returns a list of all DHorse IDs assigned to an address.
    /// @param _owner The owner whose DHorses we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire DHorse array looking for DHorses belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(address _owner) external view returns(uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalHorses = totalSupply();
            uint256 resultIndex = 0;

            // We count on the fact that all DHorses have IDs starting at 1 and increasing
            // sequentially up to the totalDHorsecount.
            uint256 HorseId;

            for (HorseId = 1; HorseId <= totalHorses; HorseId++) {
                if (_owners[HorseId] == _owner) {
                    result[resultIndex] = HorseId;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    

}
