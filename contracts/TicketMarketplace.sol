// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "./TicketNFT.sol";
import "./LoyaltyToken.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TicketMarketplace is ReentrancyGuard {

    // Enum for user roles
    enum userRoleEnum {
        USER,
        EVENT_ORGANISER,
        ADMIN
    }

    // Struct for event data
    struct Event {
        uint256 eventId;
        string eventName;
        uint256 eventTime;
        address organiser;
    }

    TicketNFT public ticketNFT;
    LoyaltyToken public loyaltyToken;
    uint256 private _nextEventId;

    // Static conversion rate (1 ETH = 1000 SGD for simplicity)
    uint256 public constant ETH_TO_SGD = 1000;  

    // Stores commission for admin withdrawals
    uint256 private commissionStorage;          

    // Mappings for role management, events, ticket listings, and ownership
    mapping(address => userRoleEnum) public userRoles;
    mapping(uint256 => Event) public events;
    mapping(address => uint256[]) public eventsOrganised;
    mapping(uint256 => uint256[]) public ticketsForSale;
    mapping(uint256 => uint256) public ticketToIndex;
    mapping(address => mapping(uint256 => uint256[])) public userWallet;

    // Event logs
    event EventCreated(uint256 eventId, string eventName);
    event TicketBought(uint256 ticketId, address buyer, uint256 price);
    event TicketListed(uint256 ticketId, address seller, uint256 price);
    event TicketUnlisted(uint256 ticketId);
    event TicketRedeemed(uint256 ticketId, address owner);
    event FundsWithdrawn(address admin, uint256 withdrawableAmount);
    event FundsDeposited(address admin, uint256 depositedAmount);

    // Access control modifiers
    modifier onlyAdmin() {
        require(userRoles[msg.sender] == userRoleEnum.ADMIN, "Not admin!");
        _;
    }

    modifier onlyEventOrganiser() {
        require(userRoles[msg.sender] == userRoleEnum.EVENT_ORGANISER, "Not organiser!");
        _;
    }

    constructor(address _ticketNFT, address _loyaltyToken) {
        ticketNFT = TicketNFT(_ticketNFT);
        loyaltyToken = LoyaltyToken(_loyaltyToken);
        userRoles[msg.sender] = userRoleEnum.ADMIN;  // Deployer is assigned admin role
    }

    function setUserRole(address user, userRoleEnum role) external onlyAdmin {
        userRoles[user] = role;
    }

    /* --------------------------- Helper Functions --------------------------- */

    // Converts SGD price to Wei
    function sgdToWei(uint256 sgdAmount) public pure returns (uint256) {
        return (sgdAmount * 1e18) / ETH_TO_SGD;
    }

    // Removes a ticket from the ticketsForSale mapping (pop-and-swap for gas efficiency)
    function removeFromTicketsForSale(uint256 eventId, uint256 ticketId) internal {
        uint256 index = ticketToIndex[ticketId];
        uint256[] storage eventTicketSaleList = ticketsForSale[eventId];

        if (index != eventTicketSaleList.length - 1) {
            uint256 lastTicketId = eventTicketSaleList[eventTicketSaleList.length - 1];
            eventTicketSaleList[index] = lastTicketId;
            ticketToIndex[lastTicketId] = index;
        }

        eventTicketSaleList.pop();
        delete ticketToIndex[ticketId];
    }

    // Removes a ticket from the seller's wallet (pop-and-swap for gas efficiency)
    function removeTicketFromWallet(address seller, uint256 eventId, uint256 ticketId) internal {
        uint256[] storage sellerTickets = userWallet[seller][eventId];
        for (uint256 i = 0; i < sellerTickets.length; i++) {
            if (sellerTickets[i] == ticketId) {
                sellerTickets[i] = sellerTickets[sellerTickets.length - 1];
                sellerTickets.pop();
                break;
            }
        }
    }

    /* ---------------------------- Main Functions ---------------------------- */

    // Create a new event and mint tickets
    function createEvent(
        string memory eventName,
        uint256 eventTime,
        uint256[3] memory categoryPrices
    ) public payable onlyEventOrganiser {
        require(msg.value >= sgdToWei(1000), "Insufficient onboarding fee.");

        uint256 eventId = _nextEventId++;

        events[eventId] = Event(eventId, eventName, eventTime, msg.sender);
        eventsOrganised[msg.sender].push(eventId);

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

            uint256 returnedTicketId = ticketNFT.createTicket(
                eventId, msg.sender, category, Strings.toString(i), price
            );

            ticketsForSale[eventId].push(returnedTicketId);
            ticketToIndex[returnedTicketId] = ticketsForSale[eventId].length - 1;
        }

        emit EventCreated(eventId, eventName);
    }

    // Purchase ticket using ETH and optionally redeem loyalty points
    function buyTicket(uint256 ticketId, uint256 loyaltyPointsToRedeem) external payable {
        address buyer = msg.sender;
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);
        uint256 eventId = ticketDetails.eventId;
        address seller = ticketDetails.owner;
        address organiser = events[eventId].organiser;

        require(block.timestamp < events[eventId].eventTime, "Event is expired");
        require(userWallet[buyer][eventId].length < 4, "Purchase limit exceeded");
        require(loyaltyToken.balanceOf(buyer) >= loyaltyPointsToRedeem, "Not enough loyalty points");

        uint256 ticketPriceSGD = ticketDetails.price;
        uint256 sgdRemaining = ticketPriceSGD - (loyaltyPointsToRedeem / 100);
        uint256 requiredEth = sgdToWei(sgdRemaining);
        require(msg.value == requiredEth, "Incorrect ETH sent");

        loyaltyToken.burn(buyer, loyaltyPointsToRedeem);

        uint256 payout = seller == organiser
            ? (requiredEth * 90) / 100
            : requiredEth;

        if (seller == organiser) {
            commissionStorage += (requiredEth - payout);
        }

        ticketNFT.setTicketPurchasePrice(ticketId, sgdRemaining);
        ticketNFT.transferTicket(ticketId, buyer);
        payable(seller).transfer(payout);
        userWallet[buyer][eventId].push(ticketId);

        removeTicketFromWallet(seller, eventId, ticketId);
        removeFromTicketsForSale(eventId, ticketId);

        emit TicketBought(ticketId, buyer, ticketPriceSGD);
    }

    // Redeem a ticket and gain loyalty points
    function redeemTicket(uint256 ticketId) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);
        require(block.timestamp < events[ticketDetails.eventId].eventTime, "Event is expired");

        address owner = msg.sender;
        ticketNFT.redeemTicket(ticketId);
        loyaltyToken.mint(owner, ticketDetails.price);

        emit TicketRedeemed(ticketId, owner);
    }

    // List a ticket for resale on the marketplace
    function listTicket(uint256 ticketId, uint256 listedPrice) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);

        require(block.timestamp < events[ticketDetails.eventId].eventTime, "Event is expired");
        require(listedPrice > 0, "Listed price must be more than zero");
        require(listedPrice <= ticketDetails.purchasePrice, "Listed price cannot exceed  price it was bought at");

        ticketNFT.listTicket(ticketId);
        ticketNFT.setTicketPrice(ticketId, listedPrice);

        ticketsForSale[ticketDetails.eventId].push(ticketId);
        ticketToIndex[ticketId] = ticketsForSale[ticketDetails.eventId].length - 1;

        emit TicketListed(ticketId, msg.sender, listedPrice);
    }

    // Unlist a ticket from resale
    function unlistTicket(uint256 ticketId) external {
        TicketNFT.ticket memory ticketDetails = ticketNFT.getTicketDetails(ticketId);

        ticketNFT.transferTicket(ticketId, msg.sender);
        ticketNFT.unlistTicket(ticketId);

        removeFromTicketsForSale(ticketDetails.eventId, ticketId);

        emit TicketUnlisted(ticketId);
    }

    // Search for the cheapest matching ticket
    function search(uint256 eventId, string memory desiredCategory, uint256 maxPrice)
        external view returns (uint256 bestTicketId, uint256 bestPrice) {

        uint256 lowestPrice = type(uint256).max;
        uint256[] storage eventTicketSaleList = ticketsForSale[eventId];

        for (uint256 i = 0; i < eventTicketSaleList.length; i++) {
            uint256 ticketId = eventTicketSaleList[i];
            TicketNFT.ticket memory t = ticketNFT.getTicketDetails(ticketId);

            if (
                keccak256(bytes(t.category)) == keccak256(bytes(desiredCategory)) &&
                t.price <= maxPrice &&
                t.price < lowestPrice
            ) {
                lowestPrice = t.price;
                bestTicketId = ticketId;
            }
        }

        require(lowestPrice != type(uint256).max, "No matching offers");
        bestPrice = lowestPrice;
    }

    /* --------------------------- Admin Functions --------------------------- */

    // Withdraw profits while maintaining liquidity pool for loyalty token redemption
    function withdrawFunds() external nonReentrant onlyAdmin {
        uint256 minLiquidityRequired = sgdToWei(loyaltyToken.totalSupply() / 100);
        uint256 liquidityPool = address(this).balance;

        require(liquidityPool > minLiquidityRequired, "No excess profit available for withdrawal.");

        uint256 withdrawableAmount = liquidityPool - minLiquidityRequired;

        (bool success, ) = msg.sender.call{value: withdrawableAmount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(msg.sender, withdrawableAmount);
    }

    // Admin deposits additional funds into the contract
    function depositFunds() external payable onlyAdmin {
        emit FundsDeposited(msg.sender, msg.value);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
