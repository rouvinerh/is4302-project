// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "./TicketNFT.sol";

contract TicketMarketplace {
    enum userRole { 
        USER,
        EVENT_ORGANISER,
        ADMIN
    }

    struct Order {
        address seller;
        uint256 ticketId;
        uint256 price;
    }

    TicketNFT public ticket;
    uint256 private _nextEventId = 0;
    
    uint256 public orderCounter; 
    // 1 ETH = 100 SGD
    mapping(address => userRole) public userRoles;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => string) public eventNames;
    mapping(address => uint256) public userToTicket; 
    mapping(address => uint256) public loyaltyPoints;

    event EventCreated(uint256 eventId, string eventName);
    event TicketListed(uint256 orderId, address seller, uint256 ticketId, uint256 price);
    event TicketBought(uint256 orderId, address buyer, uint256 ticketId, uint256 price);
    event TicketUnlisted(uint256 orderId);
    event TicketRedeemed(uint256 ticketId, address owner);

    modifier onlyAdmin() {
        require(userRoles[msg.sender] == UserRole.ADMIN, "Not admin!");
        _;
    }

    modifier onlyEventOrganiser() {
        require(userRoles[msg.sender] == UserRole.EVENT_ORGANISER, "Not organiser!");
        _;
    }

    constructor(address _ticketNFT) {
        ticketNFT = TicketNFT(_ticketNFT);
    }

    function createEvent(string memory eventName, uint256 eventTime) public onlyEventOrganiser {
        uint256 eventId = _nextEventId++; // Assign current value, then increment
        eventNames[eventId] = eventName;

        emit EventCreated(eventId, eventName);

        // assume simple stuff cus 12000 is hella gas
        for (uint256 i = 0; i < 200; i++) {
            // first 2k is cat A, etc.
            ticketNFT.createTicket(msg.sender, eventName, eventTime, "catA", "1", 148);
        }
    }
    // transact in Wei/Eth
    function buyTicket(uint256 eventId, uint256 loyaltyPointsToRedeem) payable external {
        address buyer = msg.sender;
        loyaltyPoints[buyer] -= loyaltyPointsToRedeem;
        // transfer ticket over to buyer logic @ price, make payable
        // emit event
    }

    function redeemTicket(uint256 eventId) {
        address user = msg.sender;
        loyaltyPoints[user] += ticket.getPrice(); // need this joshua pookiebear
        ticket.redeemTicket();
        // idk how get ticket id joshua :(
        // loop through mapping of userID -> ticketId for each ticket, check event Id.
        // If eventId matches, put in array list.
        // produces array list of eventIds
    }

    function listOrder(uint256 eventId, uint256 listedPrice, uint256 qty) returns (uint256) {
        require(listedPrice < ticket.getPrice(ticketId), "listed price cannot be more than original price.");

        orderCounter += 1;
        orders[orderCounter].seller = msg.sender;
        orders[orderCounter].ticketId = ticketId; // idk how get
        orders[orderCounter].price = listedPrice;

        // transfer ticket to marketplace
        return orderCounter; 
    }

    function buyOrder(uint256 orderId, uint256 loyaltyPointsRedeemed) payable external {
        address seller = orders[orderCounter].seller;
        uint256 ticketId = orders[orderCounter].ticketId;
        uint256 price = orders[orderCounter].price;
        loyaltyPoints[buyer] -= loyaltyPointsToRedeem;
        price -= loyaltyPointsRedeemed;
    }

    function unlistOrder(){
        // midterm
    }

    function search() {
        // midterm
    }
}