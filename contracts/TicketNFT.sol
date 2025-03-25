// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TicketNFT is ERC721, Ownable {
    enum ticketState { owned, redeemed }
    
    struct ticket {
        address owner;
        string eventName;
        uint256 eventTime;
        string category;
        string seatNumber;
        uint256 price;
        ticketState state;
        
        // address prevOwner;
    }

    uint256 private _nextTokenId;
    mapping(uint256 => ticket) public tickets;

    // Modifier to ensure the ticket ID is valid
    modifier validTicketId(uint256 ticketId) {
        require(ticketId < _nextTokenId, "Invalid ticket ID");
        _;
    }

    constructor()
        ERC721("TicketNFT", "WJW")
        Ownable(msg.sender)
    {}

    function safeMint(address to, uint256 tokenId) internal returns (uint256) {
        _safeMint(to, tokenId);
        return tokenId;
    }

    function createTicket(
        address to,
        string memory eventName, 
        uint256 eventTime, //unix timestamp 
        string memory category, 
        string memory seatNumber, 
        uint256 price
    ) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;

        // Create a new ticket object
        ticket memory newTicket = ticket(
            to,
            eventName,
            eventTime,
            category,
            seatNumber,
            price,
            ticketState.owned
        );

        _safeMint(to, tokenId);
        tickets[tokenId] = newTicket;

        return tokenId;
    }
    
    function redeemTicket(uint256 ticketId) public validTicketId(ticketId) onlyOwner {
        require(tickets[ticketId].state != ticketState.redeemed, "Ticket has already been redeemed");

        tickets[ticketId].state = ticketState.redeemed;
    }

    function getTicketDetails(uint256 ticketId) public view validTicketId(ticketId) returns (ticket memory) {
        return tickets[ticketId];
    }

    function getTicketOwner(uint256 ticketId) public view validTicketId(ticketId) returns (address) {
        return tickets[ticketId].owner;
    }

    function getTicketState(uint256 ticketId) public view validTicketId(ticketId) returns (ticketState) {
        return tickets[ticketId].state;
    }
}