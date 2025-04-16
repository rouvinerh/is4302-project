// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "./TicketNFT.sol";
import "./LoyaltyToken.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TicketMarketplace is ReentrancyGuard {
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

    TicketNFT public ticketNFT;
    LoyaltyToken public loyaltyToken;
    uint256 private _nextEventId;
    uint256 public constant ETH_TO_SGD = 1000; // 1 ETH = 1000 SGD
    uint256 private commissionStorage;

    mapping(address => userRoleEnum) public userRoles;
    mapping(uint256 => Event) public events; //eventId to event struct
    mapping(address => uint256[]) public eventsOrganised; //event organiser address to [] of eventIds organised
    mapping(uint256 => uint256[]) public ticketsForSale; // "marketWallet" eventId --> [] of ticketId
    mapping(uint256 => uint256) public ticketToIndex; // ticketId → index in ticketsForSale array
    mapping(address => mapping(uint256 => uint256[])) public userWallet; //nested mapping from address --> event --> [] of ticketId

    event EventCreated(uint256 eventId, string eventName);
    event TicketBought(uint256 ticketId, address buyer, uint256 price);
    event TicketListed(uint256 ticketId, address seller, uint256 price);
    event TicketUnlisted(uint256 ticketId);
    event TicketRedeemed(uint256 ticketId, address owner);
    event FundsWithdrawn(address admin, uint256 withdrawableAmount);
    event FundsDeposited(address admin, uint256 depositedAmount);

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

    constructor(address _ticketNFT, address _loyaltyToken) {
        ticketNFT = TicketNFT(_ticketNFT);
        loyaltyToken = LoyaltyToken(_loyaltyToken);
        userRoles[msg.sender] = userRoleEnum.ADMIN; // Set deployer as admin
    }

    function setUserRole(address user, userRoleEnum role) external onlyAdmin {
        userRoles[user] = role;
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
                sellerTickets[i] = sellerTickets[sellerTickets.length - 1]; // swap with last
                sellerTickets.pop(); // remove last
                break;
            }
        }
    }

    /* Main Functions */

    function createEvent(
        string memory eventName,
        uint256 eventTime,
        uint256[3] memory categoryPrices // [catA, catB, catC]
    ) public payable onlyEventOrganiser {
        // charge event onboarding fee of $1000 SGD
        require(msg.value >= sgdToWei(1000), "Insufficient onboarding fee.");

        uint256 eventId = _nextEventId++;

        events[eventId].eventName = eventName;
        events[eventId].eventTime = eventTime;
        events[eventId].organiser = msg.sender;

        eventsOrganised[msg.sender].push(eventId);

        // assume simple stuff cus 12000 is hella gas
        for (uint256 i = 0; i < 200; i++) {
            string memory category;
            uint256 price;

            if (i < 40) {
                category = "catA";
                price = categoryPrices[0];
            } else if (i < 100) {
                category = "catB";
                price = categoryPrices[1];
            } else {
                category = "catC";
                price = categoryPrices[2];
            }
            string memory seatNumber = Strings.toString(i);
            uint256 returnedTicketId = ticketNFT.createTicket(
                eventId,
                msg.sender, //event org address
                category,
                seatNumber, //seat number
                price
            );

            //store new tickets to the mapping ticketsForSale;
            ticketsForSale[eventId].push(returnedTicketId);
            ticketToIndex[returnedTicketId] =
                ticketsForSale[eventId].length -
                1;
        }

        emit EventCreated(eventId, eventName);
    }

    // transact in Wei/Eth
    function buyTicket(
        uint256 ticketId,
        uint256 loyaltyPointsToRedeem
    ) external payable {
        address buyer = msg.sender;
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(
            ticketId
        );
        uint256 eventId = ticketDetails.eventId;
        address seller = ticketDetails.owner;
        address organiser = events[eventId].organiser;

        require(
            block.timestamp < events[eventId].eventTime,
            "Event is expired"
        );

        require(
            userWallet[buyer][eventId].length < 4,
            "Purchase limit exceeded"
        );
        require(
            loyaltyToken.balanceOf(buyer) >= loyaltyPointsToRedeem,
            "Not enough loyalty points"
        );

        uint256 ticketPriceSGD = ticketDetails.price;
        uint256 sgdRemaining = ticketPriceSGD - (loyaltyPointsToRedeem / 100);
        uint256 requiredEth = sgdToWei(sgdRemaining);
        require(msg.value == requiredEth, "Incorrect ETH sent");

        loyaltyToken.burn(buyer, loyaltyPointsToRedeem);

        uint256 payout;
        if (seller == organiser) {
            payout = (requiredEth * 90) / 100;
            commissionStorage += (requiredEth - payout);
        } else {
            payout = requiredEth;
        }

        ticketNFT.transferTicket(ticketId, buyer);
        payable(seller).transfer(payout);
        userWallet[buyer][eventId].push(ticketId);
        removeTicketFromWallet(seller, eventId, ticketId);
        removeFromTicketsForSale(eventId, ticketId);
        emit TicketBought(ticketId, buyer, ticketPriceSGD);
    }

    function redeemTicket(uint256 ticketId) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(
            ticketId
        );

        require(
            block.timestamp < events[ticketDetails.eventId].eventTime,
            "Event is expired"
        );

        address owner = msg.sender;
        ticketNFT.redeemTicket(ticketId);
        loyaltyToken.mint(owner, ticketDetails.price);

        emit TicketRedeemed(ticketId, owner);
    }

    function listTicket(uint256 ticketId, uint256 listedPrice) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(
            ticketId
        );

        require(
            block.timestamp < events[ticketDetails.eventId].eventTime,
            "Event is expired"
        );

        require(listedPrice > 0, "Listed price must be more than zero");
        require(
            listedPrice <= ticketDetails.price,
            "Listed price cannot exceed original price"
        );

        // List the ticket using TicketNFT's listTicket function
        ticketNFT.listTicket(ticketId);

        // Update the ticket's price to the listed price
        ticketNFT.setTicketPrice(ticketId, listedPrice);

        //store listed tickets to the mapping ticketsForSale;
        ticketsForSale[ticketDetails.eventId].push(ticketId);
        ticketToIndex[ticketId] =
            ticketsForSale[ticketDetails.eventId].length -
            1;

        emit TicketListed(ticketId, msg.sender, listedPrice);
    }

    function unlistTicket(uint256 ticketId) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(
            ticketId
        );
        ticketNFT.transferTicket(ticketId, msg.sender);

        // helper function
        removeFromTicketsForSale(ticketDetails.eventId, ticketId);

        emit TicketUnlisted(ticketId);
    }

    function search(
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

        bestPrice = lowestPrice;
    }

    /* Admin Functions */

    function withdrawFunds() external nonReentrant onlyAdmin {
        // withdrawal capped to ensure sufficient liquidity pool for token redemption
        uint256 min_liquidity_pool_required = sgdToWei(loyaltyToken.totalSupply() / 100);
        uint256 liquidity_pool = address(this).balance;
        require(
            liquidity_pool > min_liquidity_pool_required,
            "No excess profit available for withdrawal, minimum liquidity pool to be retained."
        );

        uint256 withdrawableAmount = liquidity_pool - min_liquidity_pool_required;

        // Transfer the amount to the admin
        (bool success, ) = msg.sender.call{value: withdrawableAmount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(msg.sender, withdrawableAmount);
    }

    function depositFunds() external payable onlyAdmin {
        emit FundsDeposited(msg.sender, msg.value);
    }

    receive() external payable {}
}
