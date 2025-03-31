// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "./TicketNFT.sol";
import "./LoyaltyToken.sol";

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

    /*
    Struct Event to do the two below
    mapping event org -> eventId
    */
    mapping(uint256 => string) public eventNames;

    TicketNFT public ticket;
    uint256 private _nextEventId = 0;

    uint256 public orderCounter;
    mapping(address => userRole) public userRoles;
    mapping(uint256 => Order) public orders;



    //nested mapping from address --> event --> [] of ticketId
    mapping(address => mapping(uint256 => uint256[])) public userWallet;

    // event --> [] of ticketId
    mapping(uint256 => uint256[]) public marketWallet;

    mapping(address => uint256) public loyaltyPoints;

    event EventCreated(uint256 eventId, string eventName);
    event TicketListed(
        uint256 orderId,
        address seller,
        uint256 ticketId,
        uint256 price
    );
    event TicketBought(
        uint256 orderId,
        address buyer,
        uint256 ticketId,
        uint256 price
    );
    event TicketUnlisted(uint256 orderId);
    event TicketRedeemed(uint256 ticketId, address owner);

    uint256 public constant ETH_TO_SGD = 1000; // 1 ETH = 1000 SGD

    function sgdToWei(uint256 sgdAmount) public pure returns (uint256) {
        return (sgdAmount * 1e18) / ETH_TO_SGD;
    }


    modifier onlyAdmin() {
        require(userRoles[msg.sender] == UserRole.ADMIN, "Not admin!");
        _;
    }

    modifier onlyEventOrganiser() {
        require(
            userRoles[msg.sender] == UserRole.EVENT_ORGANISER,
            "Not organiser!"
        );
        _;
    }

    constructor(address _ticketNFT) {
        ticketNFT = TicketNFT(_ticketNFT);
    }

    function createEvent(
        string memory eventName,
        uint256 eventTime
    ) public onlyEventOrganiser {
        uint256 eventId = _nextEventId++; // Assign current value, then increment
        eventNames[eventId] = eventName;

        emit EventCreated(eventId, eventName);

        // assume simple stuff cus 12000 is hella gas
        for (uint256 i = 0; i < 200; i++) {
            string memory category;
            if (i < 40) {
                category = "catA";
            } else if (i < 100) { 
                category = "catB";
            } else {
                category = "catC";
            }

            ticketNFT.createTicket(
                msg.sender,
                eventName,
                eventTime,
                category,
                "1",
                148
            );
            //EVENT -> TICKET
            //store new tickets to the mapping marketWallet;
        }
    }

    function payOrganiser{
    //logic pay everything - 10% 
    }

    // transact in Wei/Eth
    function buyTicket(
        uint256 eventId,
        uint256 loyaltyPointsToRedeem
        //cat 
    ) external payable {
        address buyer = msg.sender;
        require(loyaltyPoints[buyer] >= loyaltyPointsToRedeem, "Not enough loyalty points");

        string memory eventName = eventNames[eventId];
        uint256 ticketPriceSGD = ticket.getPrice;
        uint256 sgdRemaining = ticketPriceSGD - (loyaltyPointsToRedeem/100);
        uint256 requiredEth = sgdToWei(sgdRemaining);
        require(msg.value == requiredEth, "Incorrect ETH sent");

        loyaltyPoints[buyer] -= loyaltyPointsToRedeem;
        // transfer ticket over to buyer logic @ price, make payable
        // emit event
    }

    function redeemTicket(uint256 ticketId) {
        require(
            block.timestamp < ticket.getEventTime(ticketId),
            "Cannot redeem ticket for expired events."
        );

        address user = msg.sender;
        loyaltyPoints[user] += ticket.getPrice(); // need this joshua pookiebear
        ticket.redeemTicket();
        // idk how get ticket id joshua :(
        getTicketForEvent()
        // If eventId matches, put in array list.
        // produces array list of eventIds
        emit TicketRedeemed(ticketId, user);
    }

    function getTicketForEvent (
        uint256 eventId, 
        address user
    ) returns (TicketNFT[]) {
        // loop through mapping of userID -> ticketId for each ticket, check event Id.
        TicketNFT[] listOfTickets = userToTicket[user]; 
        TicketNFT[] result; 
        for (uint256 i = 1; i <= listOfTickets.length; i++) {
            //how get ticket id
            if(TicketNFT[i].getEvent(1231)) {
                result.pop(TicketNFT[i]);
            }
        }
    }

    function listOrder(
        uint256 eventId,
        uint256 listedPrice,
        uint256 qty
    ) returns (uint256) {
        require(
            block.timestamp < ticket.getEventTime(ticketId),
            "Cannot list tickets for expired events."
        );
        require(
            listedPrice > 0, 
            "Listed price must be greater than zero."
        );
        require(
            listedPrice <= ticket.getPrice(ticketId),
            "Listed price cannot be more than original price."
        );
        require(
            ticket.ownerOf(ticketId) == msg.sender,
            "You don't own this ticket."
        );

        orderCounter += 1;
        orders[orderCounter].seller = msg.sender;
        orders[orderCounter].ticketId = ticketId; // idk how get
        orders[orderCounter].price = listedPrice;

        ticket.transferFrom(msg.sender, address(this), ticketId);
        emit TicketListed(orderCounter, msg.sender, ticketId, listedPrice);

        return orderCounter;
    }

    function buyOrder(
        uint256 orderId,
        uint256 loyaltyPointsRedeemed
    ) external payable {
        Order storage order = orders[orderId];
        require(order.seller != address(0), "Order does not exist");

        address buyer = msg.sender;
        uint256 ticketId = order.ticketId;
        uint256 price = order.price;

        require(
            block.timestamp < ticket.getEventTime(ticketId),
            "Cannot list tickets for expired events."
        );

        require(
            loyaltyPoints[buyer] >= loyaltyPointsRedeemed,
            "Not enough loyalty points"
        );
        require(loyaltyPointsRedeemed <= price, "Too many points used");

        require(loyaltyPoints[buyer] >= loyaltyPointsRedeemed, "Not enough loyalty points");
        uint256 sgdRemaining = price - (loyaltyPointsRedeemed/100); //assume 100 loyalty point = 1 SGD
        uint256 requiredEth = sgdToWei(sgdRemaining);
        require(msg.value == requiredEth, "Incorrect ETH sent"); //implement eth to sgd conversion later

        // burn loyalty points
        loyaltyPoints[buyer] -= loyaltyPointsRedeemed;

        // contract pay seller full price
        payable(order.seller).transfer(price);

        ticket.transferFrom(address(this), buyer, ticketId);
        delete orders[orderId];

        emit TicketBought(orderId, buyer, ticketId, price);
    }

    function unlistOrder() {
        Order storage order = orders[orderId];
        require(order.seller != address(0), "Order does not exist");
        require(order.seller == msg.sender, "Not your order");

        ticket.transferFrom(address(this), msg.sender, order.ticketId);
        delete orders[orderId];

        emit TicketUnlisted(orderId);
    }

    function editOrder(uint256 orderId, uint256 newPrice) external {
        Order storage order = orders[orderId];
        require(order.seller != address(0), "Order does not exist");
        require(order.seller == msg.sender, "Not your order");

        require(
            newPrice <= ticket.getPrice(order.ticketId),
            "New price exceeds original ticket price"
        );

        order.price = newPrice;
    }

    function search(
        string memory desiredEventName,
        string memory desiredCategory,
        uint256 maxPrice
    ) external view returns (uint256 bestOrderId, uint256 bestPrice) {
        uint256 lowestPrice = type(uint256).max;

        for (uint256 i = 1; i <= orderCounter; i++) {
            Order storage order = orders[i];
            if (order.seller == address(0)) continue;

            uint256 ticketId = order.ticketId;
            TicketNFT.ticket memory t = ticket.tickets(ticketId);

            if (
                keccak256(bytes(t.eventName)) ==
                keccak256(bytes(desiredEventName)) &&
                keccak256(bytes(t.category)) ==
                keccak256(bytes(desiredCategory)) &&
                order.price <= maxPrice &&
                order.price < lowestPrice
            ) {
                lowestPrice = order.price;
                bestOrderId = i;
            }
        }

        if (bestOrderId == 0) {
            revert("No matching offers");
        }

        bestPrice = lowestPrice;
    }
}


/*
to do 

    - Ticket mapping to make primary buying easier
    -  Buy Ticket -> Ticekt mapping (Event -> ticketId) -> give them next avail tix with regards to cat and event

*/