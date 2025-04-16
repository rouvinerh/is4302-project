// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TicketNFT is ERC721, Ownable {
    enum ticketState { OWNED, LISTED, REDEEMED }
    
    struct ticket {
        uint256 ticketId;
        uint256 eventId;
        address owner;
        address prevOwner;
        string category;
        string seatNumber;
        uint256 price;
        ticketState state;
    }

    uint256 private _nextTokenId;
    mapping(uint256 => ticket) public tickets;

    // Modifier to ensure the ticket ID is valid
    modifier validTicketId(uint256 ticketId) {
        require(ticketId < _nextTokenId, "Invalid ticket ID");
        _;
    }

    // custom modifier
    modifier ownerOnly(uint256 ticketId) {
        require(tickets[ticketId].owner == msg.sender, "Caller is not the owner");
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
        uint256 eventId,
        address eventOrgAddress,
        string memory category, 
        string memory seatNumber, 
        uint256 price // CONSTANT, different from order price
    ) public onlyOwner returns (uint256) {      //ownerOnly: only owner of this contract can call i.e admin address (might need to use dummy account to deploy TicketNFT then tranf ownership to TicketMarketplace)
        uint256 tokenId = _nextTokenId++;

        // Create a new ticket object
        ticket memory newTicket = ticket(
            tokenId,
            eventId,
            eventOrgAddress,
            address(0),
            category,
            seatNumber,
            price,
            ticketState.LISTED
        );

        _safeMint(eventOrgAddress, tokenId);
        tickets[tokenId] = newTicket;

        return tokenId;
    }
    
    function transferTicket(uint256 ticketId, address newOwner) public validTicketId(ticketId) ownerOnly(ticketId) {
        _transfer(tickets[ticketId].owner, newOwner, ticketId);
        tickets[ticketId].prevOwner = tickets[ticketId].owner;
        tickets[ticketId].owner = newOwner;
        tickets[ticketId].state = ticketState.OWNED;
    }

    function listTicket(uint256 ticketId) public validTicketId(ticketId) ownerOnly(ticketId) {
        tickets[ticketId].state = ticketState.LISTED;
    }

    function unlistTicket(uint256 ticketId) public validTicketId(ticketId) ownerOnly(ticketId) {
        tickets[ticketId].state = ticketState.OWNED;
    }

    function redeemTicket(uint256 ticketId) external validTicketId(ticketId) {
        require(tickets[ticketId].state != ticketState.REDEEMED, "Ticket has already been redeemed");
        require(
            tickets[ticketId].owner == msg.sender || getApproved(ticketId) == msg.sender,
            "Caller is not the owner or approved"
        );
        tickets[ticketId].state = ticketState.REDEEMED;
    }

    function setTicketPrice(uint256 ticketId, uint256 newPrice) public validTicketId(ticketId) ownerOnly(ticketId) {
        tickets[ticketId].price = newPrice;
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

    function getPrice(uint256 ticketId) public view validTicketId(ticketId) returns (uint256) {
        return tickets[ticketId].price;
    }
}