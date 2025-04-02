// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "./TicketNFT.sol";
import "./LoyaltyToken.sol";

contract TicketMarketplace {
    enum userRoleEnum {
        USER,
        EVENT_ORGANISER,
        ADMIN
    }

    struct Event {
        uint256 eventId;
        string eventName;
        uint256 eventTime;
        address organiser;
    }

    // struct Order {
    //     address seller;
    //     uint256 eventId;
    //     uint256 ticketId;
    //     uint256 price;
    // }

    TicketNFT public ticketNFT;
    uint256 private _nextEventId;
    uint256 public constant ETH_TO_SGD = 1000; // 1 ETH = 1000 SGD
    // uint256 public orderCounter;

    mapping(address => userRoleEnum) public userRoles;
    mapping(uint256 => Event) public events; //eventId to event struct
    mapping(address => uint256[]) public eventsOrganised; //event organiser address to [] of eventIds organised
    mapping(uint256 => uint256[]) public ticketsForSale; // "marketWallet" eventId --> [] of ticketId
    mapping(uint256 => uint256) public ticketToIndex; // ticketId → index in ticketsForSale array
    mapping(address => mapping(uint256 => uint256[])) public userWallet; //nested mapping from address --> event --> [] of ticketId
    mapping(address => uint256) public loyaltyPoints;

    // mapping(uint256 => Order) public orders;

    event EventCreated(uint256 eventId, string eventName);
    event TicketBought(uint256 ticketId, address buyer, uint256 price);
    event TicketListed(uint256 ticketId, address seller, uint256 price);
    event TicketUnlisted(uint256 ticketId);
    event TicketRedeemed(uint256 ticketId, address owner);

    modifier onlyAdmin() {
        require(userRoles[msg.sender] == userRoleEnum.ADMIN, "Not admin!");
        _;
    }

    modifier onlyEventOrganiser() {
        require(
            userRoles[msg.sender] == userRoleEnum.EVENT_ORGANISER,
            "Not organiser!"
        );
        _;
    }

    constructor(address _ticketNFT) {
        ticketNFT = TicketNFT(_ticketNFT);
    }

    /* Helper Functions */

    function sgdToWei(uint256 sgdAmount) public pure returns (uint256) {
        return (sgdAmount * 1e18) / ETH_TO_SGD;
    }

    // remove ticketId from ticketsForSale (pop-and-swap design to save gas)
    function removeFromTicketsForSale(
        uint256 eventId,
        uint256 ticketId
    ) internal {
        uint256 index = ticketToIndex[ticketId];
        uint256[] storage eventTicketSaleList = ticketsForSale[eventId];
        if (index != eventTicketSaleList.length - 1) {
            uint256 lastTicketId = eventTicketSaleList[
                eventTicketSaleList.length - 1
            ];
            eventTicketSaleList[index] = lastTicketId;
            ticketToIndex[lastTicketId] = index;
        }
        eventTicketSaleList.pop();
        delete ticketToIndex[ticketId];
    }

    // remove ticketId from prevOwner's wallet (similar pop-and-swap design as above)
    function removeTicketFromWallet(
        address seller,
        uint256 eventId,
        uint256 ticketId
    ) internal {
        uint256[] storage sellerTickets = userWallet[seller][eventId];
        for (uint256 i = 0; i < sellerTickets.length; i++) {
            if (sellerTickets[i] == ticketId) {
                sellerTickets[i] = sellerTickets[tickets.length - 1]; // swap with last
                sellerTickets.pop(); // remove last
                break;
            }
        }
    }

    /* Main Functions */

    // we should make this method payable and charge eventOrg for creating events
    function createEvent(
        string memory eventName,
        uint256 eventTime
    ) public onlyEventOrganiser {
        uint256 memory eventId = _nextEventId++;

        events[eventId].name = eventName;
        events[eventId].eventTime = eventTime;
        events[eventId].organiser = msg.sender;

        eventsOrganised[msg.sender].push(eventId);

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

            uint256 returnedTicketId = ticketNFT.createTicket(
                eventId,
                msg.sender, //event org address
                category,
                i, //seat number
                100 //price, CONSTANT for now but need to handle logic for diff price for diff category
            );

            //store new tickets to the mapping ticketsForSale;
            ticketsForSale[eventId].push(returnedTicketId);
            ticketToIndex[returnedTicketId] =
                ticketsForSale[eventId].length -
                1;
            // userWallet[msg.sender][eventId].push(returnedTicketId);  //maybe dont need this
        }

        emit EventCreated(eventId, eventName);
    }

    // transact in Wei/Eth
    function buyTicket(
        // uint256 eventId,
        uint256 ticketId,
        uint256 loyaltyPointsToRedeem //cat
    ) external payable {
        address memory buyer = msg.sender;
        ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);
        uint256 eventId = ticketDetails.eventId;
        address seller = ticketDetails.owner;
        address organiser = events[eventId].organiser;

        require(
            userWallet[buyer][eventId].length < 4,
            "Purchase limit exceeded. You can only own 4 tickets per event."
        );
        require(
            loyaltyPoints[buyer] >= loyaltyPointsToRedeem,
            "Not enough loyalty points"
        );

        uint256 ticketPriceSGD = ticketDetails.price;
        uint256 sgdRemaining = ticketPriceSGD - (loyaltyPointsToRedeem / 100);
        uint256 requiredEth = sgdToWei(sgdRemaining);
        require(msg.value == requiredEth, "Incorrect ETH sent");

        loyaltyPoints[buyer] -= loyaltyPointsToRedeem;

        // assume prevOnly transferred to TicketMarketplace
        // transfer ticket over to buyer logic @ price, make payable
        uint256 payout;
        if (seller == organiser) {
            payout = (requiredEth * 90) / 100;
        } else {
            payout = requiredEth;
        }
        ticketNFT.transferTicket(buyer, ticketId);
        payable(seller).transfer(payout); //TODO: need convert to weiToSGD & take 10% commission (done)
        userWallet[buyer][eventId].push(ticketId);
        //TODO: update prevOwners userWallet (done)
        removeTicketFromWallet(seller, eventId, ticketId);

        // helper function
        removeFromTicketsForSale(eventId, ticketId);

        // emit event
        emit TicketBought(ticketId, buyer, ticketPriceSGD);

        // require(marketWallet[eventId].length > 0, "Sold out"); shouldnt need this, FE should only display tickets from ticketsForSale mapping
        // uint256 ticketId = marketWallet[eventId][marketWallet[eventId].length - 1]; // get last ticket in the array so tht we can use pop() instead of delete() since we want to remove ticket from array
        // string memory eventName = eventNames[eventId];
    }

    function redeemTicket(uint256 ticketId) {
        ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);

        require(
            block.timestamp < events[ticketDetails.eventId].eventTime,
            "Event is expired"
        );

        address owner = msg.sender;
        ticketNFT.redeemTicket(ticketId);
        loyaltyPoints[owner] += ticketDetails.price;

        emit TicketRedeemed(ticketId, owner);
    }

    function listTicket(uint256 ticketId, uint256 listedPrice) external {
        ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);

        require(
            block.timestamp < events[ticketDetails.eventId].eventTime,
            "Event is expired"
        );

        require(listedPrice > 0, "Listed price must be greater than zero.");
        require(
            listedPrice <= ticketDetails.price,
            "Listed price cannot be more than original price."
        );
        // require(
        //     ticket.ownerOf(ticketId) == msg.sender,
        //     "You don't own this ticket."
        // );

        // assume owner manually transfer to TicketMarketplace
        // ticket.transferTicket(ticketId, address(this));

        //store listed tickets to the mapping ticketsForSale;
        ticketsForSale[ticketDetails.eventId].push(ticketId);
        ticketToIndex[ticketId] =
            ticketsForSale[ticketDetails.eventId].length -
            1;

        emit TicketListed(ticketId, msg.sender, listedPrice);

        // orderCounter += 1;
        // orders[orderCounter].seller = msg.sender;
        // orders[orderCounter].eventId = eventId;
        // orders[orderCounter].ticketId = ticketId; // idk how get
        // orders[orderCounter].price = listedPrice;
        // return orderCounter;
    }

    function unlistTicket(uint256 ticketId) external {
        ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);
        ticketNFT.transferTicket(address(this), msg.sender, ticketId);

        // helper function
        removeFromTicketsForSale(ticketDetails.eventId, ticketId);

        emit TicketUnlisted(ticketId);
    }

    function search(
        // string memory desiredEventName,
        uint256 eventId, // assume FE will display event id and name
        string memory desiredCategory,
        uint256 maxPrice
    ) external view returns (uint256 bestTicketId, uint256 bestPrice) {
        uint256 lowestPrice = type(uint256).max;
        uint256[] storage eventTicketSaleList = ticketsForSale[eventId];

        for (uint256 i = 0; i < eventTicketSaleList.length; i++) {
            uint256 ticketId = eventTicketSaleList[i];
            TicketNFT.ticket memory t = ticketNFT.getTicketDetails(ticketId);

            if (
                keccak256(bytes(t.category)) ==
                keccak256(bytes(desiredCategory)) &&
                t.price <= maxPrice &&
                t.price < lowestPrice
            ) {
                lowestPrice = t.price;
                bestTicketId = ticketId;
            }
        }

        if (lowestPrice == type(uint256).max) {
            revert("No matching offers");
        }

        /* for (uint256 i = 1; i <= orderCounter; i++) {
            Order storage order = orders[i];
            if (order.seller == address(0)) continue;

            uint256 ticketId = order.ticketId;
            TicketNFT.ticket memory t = ticketNFT.tickets(ticketId);

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
        } */

        bestPrice = lowestPrice;
    }

    // function payOrganiser{
    // //logic pay everything - 10%
    // }

    // function editOrder(uint256 orderId, uint256 newPrice) external {
    //     Order storage order = orders[orderId];
    //     require(order.seller != address(0), "Order does not exist");
    //     require(order.seller == msg.sender, "Not your order");

    //     require(
    //         newPrice <= ticket.getPrice(order.ticketId),
    //         "New price exceeds original ticket price"
    //     );

    //     order.price = newPrice;
    // }

    // function buyOrder(
    //     uint256 orderId,
    //     uint256 loyaltyPointsRedeemed
    // ) external payable {
    //     Order storage order = orders[orderId];
    //     require(order.seller != address(0), "Order does not exist");

    //     address buyer = msg.sender;
    //     uint256 eventId = order.eventId;
    //     uint256 ticketId = order.ticketId;
    //     uint256 price = order.price;

    //     require(
    //         block.timestamp < ticket.getEventTime(ticketId),
    //         "Cannot buy tickets for expired events."
    //     );
    //     require(
    //         userWallet[buyer][eventId].length < 4,
    //         "Purchase limit exceeded. You can only own 4 tickets per event."
    //     );
    //     require(
    //         loyaltyPoints[buyer] >= loyaltyPointsRedeemed,
    //         "Not enough loyalty points"
    //     );
    //     require(loyaltyPointsRedeemed <= price, "Too many points used");

    //     require(loyaltyPoints[buyer] >= loyaltyPointsRedeemed, "Not enough loyalty points");
    //     uint256 sgdRemaining = price - (loyaltyPointsRedeemed/100); //assume 100 loyalty point = 1 SGD
    //     uint256 requiredEth = sgdToWei(sgdRemaining);
    //     require(msg.value == requiredEth, "Incorrect ETH sent"); //implement eth to sgd conversion later

    //     // burn loyalty points
    //     loyaltyPoints[buyer] -= loyaltyPointsRedeemed;

    //     // contract pay seller full price
    //     payable(order.seller).transfer(price);

    //     ticket.transferFrom(address(this), buyer, ticketId);
    //     delete orders[orderId];

    //     emit TicketBought(orderId, buyer, ticketId, price);
    // }
}
