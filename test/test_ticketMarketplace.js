const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TicketMarketplace", function () {
    let ticketNFT;
    let ticketMarketplace;
    let owner;
    let eventOrganiser;
    let buyer1;
    let buyer2;
    let buyer3;
    let eventId;
    let ticketId;

    beforeEach(async function () {
        [owner, eventOrganiser, buyer1, buyer2, buyer3] = await ethers.getSigners();

        // Deploy TicketNFT
        const TicketNFT = await ethers.getContractFactory("TicketNFT");
        ticketNFT = await TicketNFT.deploy();
        await ticketNFT.waitForDeployment();

        // Deploy LoyaltyToken
        const LoyaltyToken = await ethers.getContractFactory("LoyaltyToken");
        loyaltyToken = await LoyaltyToken.deploy();
        await loyaltyToken.waitForDeployment();

        // Deploy TicketMarketplace
        const TicketMarketplace = await ethers.getContractFactory("TicketMarketplace");
        ticketMarketplace = await TicketMarketplace.deploy(await ticketNFT.getAddress(), await loyaltyToken.getAddress());
        await ticketMarketplace.waitForDeployment();

        // Set up roles
        await ticketMarketplace.setUserRole(owner.address, 2); // ADMIN role
        await ticketMarketplace.setUserRole(eventOrganiser.address, 1); // EVENT_ORGANISER role
        await ticketMarketplace.setUserRole(buyer1.address, 0); // USER role
        await ticketMarketplace.setUserRole(buyer2.address, 0); // USER role
        await ticketMarketplace.setUserRole(buyer3.address, 0); // USER role

        // Transfer ownership of TicketNFT to TicketMarketplace
        await ticketNFT.transferOwnership(await ticketMarketplace.getAddress());
    });

    describe("Event Creation", function () {
        it("Should allow event organiser to create an event", async function () {
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400; // 1 day from now
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await expect(ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices))
                .to.emit(ticketMarketplace, "EventCreated")
                .withArgs(0, eventName);

            const event = await ticketMarketplace.events(0);
            expect(event.eventName).to.equal(eventName);
            expect(event.eventTime).to.equal(eventTime);
            expect(event.organiser).to.equal(eventOrganiser.address);
        });

        it("Should not allow non-event organisers to create events", async function () {
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await expect(ticketMarketplace.connect(buyer1).createEvent(eventName, eventTime, catPrices))
                .to.be.revertedWith("Not organiser!");
        });
    });

    describe("Primary Market Purchase", function () {
        beforeEach(async function () {
            // Create an event
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices);
            eventId = 0;
            ticketId = 0; // First ticket in the event

            // Transfer ticket to marketplace first
            await ticketNFT.connect(eventOrganiser).transferTicket(ticketId, await ticketMarketplace.getAddress());
        });

        it("Should allow user to buy ticket from event organiser", async function () {
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            await expect(ticketMarketplace.connect(buyer1).buyTicket(ticketId, 0, { value: priceInWei }))
                .to.emit(ticketMarketplace, "TicketBought")
                .withArgs(ticketId, buyer1.address, ticketDetails.price);

            // Verify ticket ownership
            const newOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(newOwner).to.equal(buyer1.address);

            // Verify ticket is in buyer's wallet by checking the ticket state
            const ticketState = await ticketNFT.getTicketState(ticketId);
            expect(ticketState).to.equal(0); // OWNED state
        });

        it("Should not allow purchase of expired event tickets", async function () {
            // Create an expired event
            const eventName = "Expired Concert";
            const eventTime = Math.floor(Date.now() / 1000) - 86400; // 1 day ago
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices);
            
            const expiredTicketId = 200; // First ticket of the new event
            const ticketDetails = await ticketNFT.getTicketDetails(expiredTicketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);

            // Transfer expired ticket to marketplace
            await ticketNFT.connect(eventOrganiser).transferTicket(expiredTicketId, await ticketMarketplace.getAddress());

            // Try to buy the expired ticket
            await expect(ticketMarketplace.connect(buyer1).buyTicket(expiredTicketId, 0, { value: priceInWei }))
                .to.be.revertedWith("Event is expired");
        });

        it("Should not allow purchase with incorrect ETH amount", async function () {
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            const incorrectPriceInWei = priceInWei - BigInt(1);

            await expect(ticketMarketplace.connect(buyer1).buyTicket(ticketId, 0, { value: incorrectPriceInWei }))
                .to.be.revertedWith("Incorrect ETH sent");
        });

        it("Should not allow purchase of more than 4 tickets per event", async function () {
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);

            // Buy first ticket (already transferred to marketplace in beforeEach)
            await ticketMarketplace.connect(buyer1).buyTicket(ticketId, 0, { value: priceInWei });
            
            // Verify first ticket is owned by buyer1
            const firstTicketOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(firstTicketOwner).to.equal(buyer1.address);

            // Buy 3 more tickets
            for (let i = 1; i < 4; i++) {
                const currentTicketId = ticketId + i;
                
                // Verify ticket exists and is owned by event organizer
                const ticketOwner = await ticketNFT.getTicketOwner(currentTicketId);
                expect(ticketOwner).to.equal(eventOrganiser.address);
                
                // Transfer ticket to marketplace
                await ticketNFT.connect(eventOrganiser).transferTicket(currentTicketId, await ticketMarketplace.getAddress());
                
                // Buy the ticket
                await ticketMarketplace.connect(buyer1).buyTicket(currentTicketId, 0, { value: priceInWei });
                
                // Verify ticket is now owned by buyer1
                const newOwner = await ticketNFT.getTicketOwner(currentTicketId);
                expect(newOwner).to.equal(buyer1.address);
            }

            // Try to buy 5th ticket
            const fifthTicketId = ticketId + 4;
            
            // Verify ticket exists and is owned by event organizer
            const fifthTicketOwner = await ticketNFT.getTicketOwner(fifthTicketId);
            expect(fifthTicketOwner).to.equal(eventOrganiser.address);
            
            // Transfer ticket to marketplace
            await ticketNFT.connect(eventOrganiser).transferTicket(fifthTicketId, await ticketMarketplace.getAddress());
            
            // Try to buy the 5th ticket
            await expect(ticketMarketplace.connect(buyer1).buyTicket(fifthTicketId, 0, { value: priceInWei }))
                .to.be.revertedWith("Purchase limit exceeded");
        });
    });

    describe("Secondary Market Purchase", function () {
        beforeEach(async function () {
            // Create an event and buy a ticket
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices);
            eventId = 0;
            ticketId = 0;

            // Transfer ticket to marketplace first
            await ticketNFT.connect(eventOrganiser).transferTicket(ticketId, await ticketMarketplace.getAddress());

            // Buy ticket from event organiser
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            await ticketMarketplace.connect(buyer1).buyTicket(ticketId, 0, { value: priceInWei });
        });

        it("Should allow listing ticket for resale", async function () {
            const listedPrice = 80; // SGD
            
            // First transfer ticket to marketplace
            await ticketNFT.connect(buyer1).transferTicket(ticketId, await ticketMarketplace.getAddress());
            
            // Then list the ticket
            await expect(ticketMarketplace.connect(buyer1).listTicket(ticketId, listedPrice))
                .to.emit(ticketMarketplace, "TicketListed")
                .withArgs(ticketId, buyer1.address, listedPrice);

            // Verify ticket is listed by checking its state
            const ticketState = await ticketNFT.getTicketState(ticketId);
            expect(ticketState).to.equal(1); // LISTED state
        });

        it("Should allow secondary purchase from initial buyer", async function () {
            const listedPrice = 80; // SGD
            
            // First transfer ticket to marketplace
            await ticketNFT.connect(buyer1).transferTicket(ticketId, await ticketMarketplace.getAddress());
            
            // Then list the ticket
            await ticketMarketplace.connect(buyer1).listTicket(ticketId, listedPrice);

            // Buy from initial buyer using listed price
            const listedPriceInWei = await ticketMarketplace.sgdToWei(listedPrice);
            await expect(ticketMarketplace.connect(buyer2).buyTicket(ticketId, 0, { value: listedPriceInWei }))
                .to.emit(ticketMarketplace, "TicketBought")
                .withArgs(ticketId, buyer2.address, listedPrice);

            // Verify ticket ownership
            const newOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(newOwner).to.equal(buyer2.address);

            // Verify ticket state
            const ticketState = await ticketNFT.getTicketState(ticketId);
            expect(ticketState).to.equal(0); // OWNED state
        });

        it("Should allow multiple secondary market transactions", async function () {
            // First resale
            const firstListedPrice = 80; // SGD
            
            // First transfer ticket to marketplace
            await ticketNFT.connect(buyer1).transferTicket(ticketId, await ticketMarketplace.getAddress());
            
            // Then list the ticket
            await ticketMarketplace.connect(buyer1).listTicket(ticketId, firstListedPrice);
            
            const firstPriceInWei = await ticketMarketplace.sgdToWei(firstListedPrice);
            await ticketMarketplace.connect(buyer2).buyTicket(ticketId, 0, { value: firstPriceInWei });

            // Second resale
            const secondListedPrice = 70; // SGD
            
            // First transfer ticket to marketplace
            await ticketNFT.connect(buyer2).transferTicket(ticketId, await ticketMarketplace.getAddress());
            
            // Then list the ticket
            await ticketMarketplace.connect(buyer2).listTicket(ticketId, secondListedPrice);
            
            const secondPriceInWei = await ticketMarketplace.sgdToWei(secondListedPrice);
            await ticketMarketplace.connect(buyer3).buyTicket(ticketId, 0, { value: secondPriceInWei });

            // Verify final ownership
            const finalOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(finalOwner).to.equal(buyer3.address);

            // Verify ticket state
            const ticketState = await ticketNFT.getTicketState(ticketId);
            expect(ticketState).to.equal(0); // OWNED state
        });
    });

    describe("Loyalty Points", function () {
        beforeEach(async function () {
            // Create an event
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices);
            eventId = 0;
            ticketId = 0;

            // Transfer ticket to marketplace first
            await ticketNFT.connect(eventOrganiser).transferTicket(ticketId, await ticketMarketplace.getAddress());
        });

        it("Should allow purchase with loyalty points", async function () {
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            
            // Set loyalty points for buyer (100 points = 1 SGD)
            const loyaltyPointsToUse = BigInt(1000); // 10 SGD worth of points
            await ticketMarketplace.connect(owner).setLoyaltyPoints(buyer1.address, loyaltyPointsToUse);

            // Calculate remaining ETH needed after loyalty points
            const sgdRemaining = BigInt(ticketDetails.price) - (loyaltyPointsToUse / BigInt(100));
            const requiredEth = await ticketMarketplace.sgdToWei(Number(sgdRemaining));

            await expect(ticketMarketplace.connect(buyer1).buyTicket(ticketId, loyaltyPointsToUse, { value: requiredEth }))
                .to.emit(ticketMarketplace, "TicketBought")
                .withArgs(ticketId, buyer1.address, ticketDetails.price);

            // Verify loyalty points were deducted
            const remainingPoints = await ticketMarketplace.loyaltyPoints(buyer1.address);
            expect(remainingPoints).to.equal(0);
        });

        it("Should not allow purchase with insufficient loyalty points", async function () {
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            
            // Set insufficient loyalty points for buyer
            const loyaltyPointsToUse = BigInt(1000); // 10 SGD worth of points
            await ticketMarketplace.connect(owner).setLoyaltyPoints(buyer1.address, BigInt(500)); // Only 5 SGD worth of points

            // Calculate remaining ETH needed after loyalty points
            const sgdRemaining = BigInt(ticketDetails.price) - (loyaltyPointsToUse / BigInt(100));
            const requiredEth = await ticketMarketplace.sgdToWei(Number(sgdRemaining));

            await expect(ticketMarketplace.connect(buyer1).buyTicket(ticketId, loyaltyPointsToUse, { value: requiredEth }))
                .to.be.revertedWith("Not enough loyalty points");
        });
    });

    describe("Ticket Redemption", function () {
        beforeEach(async function () {
            // Create an event and buy a ticket
            const eventName = "Test Concert";
            const eventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(eventName, eventTime, catPrices);
            eventId = 0;
            ticketId = 0;

            // Transfer ticket to marketplace first
            await ticketNFT.connect(eventOrganiser).transferTicket(ticketId, await ticketMarketplace.getAddress());

            // Buy ticket from event organiser
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);
            await ticketMarketplace.connect(buyer1).buyTicket(ticketId, 0, { value: priceInWei });

            // Verify ticket is owned by buyer1
            const ticketOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(ticketOwner).to.equal(buyer1.address);
        });

        it("Should allow ticket redemption before event time", async function () {
            // Verify ticket is owned by buyer1 before redemption
            const ticketOwner = await ticketNFT.getTicketOwner(ticketId);
            expect(ticketOwner).to.equal(buyer1.address);

            // Approve marketplace to redeem the ticket
            await ticketNFT.connect(buyer1).approve(await ticketMarketplace.getAddress(), ticketId);

            await expect(ticketMarketplace.connect(buyer1).redeemTicket(ticketId))
                .to.emit(ticketMarketplace, "TicketRedeemed")
                .withArgs(ticketId, buyer1.address);

            // Verify loyalty points were awarded
            const ticketDetails = await ticketNFT.getTicketDetails(ticketId);
            const loyaltyPoints = await ticketMarketplace.loyaltyPoints(buyer1.address);
            expect(loyaltyPoints).to.equal(ticketDetails.price);

            // Verify ticket state is REDEEMED
            const ticketState = await ticketNFT.getTicketState(ticketId);
            expect(ticketState).to.equal(2); // REDEEMED state
        });

        it("Should not allow ticket redemption after event time", async function () {
            // Create an event that's not expired (for buying the ticket)
            const validEventName = "Valid Concert";
            const validEventTime = Math.floor(Date.now() / 1000) + 86400;
            const catPrices = [300, 200, 100]; // prices for catA, catB and catC
            await ticketMarketplace.connect(eventOrganiser).createEvent(validEventName, validEventTime, catPrices);
            
            const validTicketId = 200; // First ticket of the new event
            const ticketDetails = await ticketNFT.getTicketDetails(validTicketId);
            const priceInWei = await ticketMarketplace.sgdToWei(ticketDetails.price);

            // Transfer ticket to marketplace
            await ticketNFT.connect(eventOrganiser).transferTicket(validTicketId, await ticketMarketplace.getAddress());

            // Buy the ticket
            await ticketMarketplace.connect(buyer1).buyTicket(validTicketId, 0, { value: priceInWei });

            // Verify ticket is owned by buyer1
            const ticketOwner = await ticketNFT.getTicketOwner(validTicketId);
            expect(ticketOwner).to.equal(buyer1.address);

            // Approve marketplace to redeem the ticket
            await ticketNFT.connect(buyer1).approve(await ticketMarketplace.getAddress(), validTicketId);

            // Create an expired event instead
            const expiredEventName = "Expired Concert";
            const expiredEventTime = Math.floor(Date.now() / 1000) - 86400; // 1 day ago
            await ticketMarketplace.connect(eventOrganiser).createEvent(expiredEventName, expiredEventTime, catPrices);
            const expiredTicketId = 400; // First ticket of expired event

            await expect(ticketMarketplace.connect(buyer1).redeemTicket(expiredTicketId))
                .to.be.revertedWith("Event is expired");
        });
    });

    describe("Admin Fund Deposit & Withdrawal", function () {
        const depositAmount = ethers.parseEther("1.0");

        beforeEach(async function () {
            // Mint LoyaltyToken to simulate ongoing TicketMarketplace ecosystem
            await loyaltyToken.connect(owner).mint(buyer1.address, 100)
            expect(await loyaltyToken.totalSupply()).to.equal(100); 
        });

        it("Should deposit funds into TicketMarketplace", async function () {
            // Test deposit by admin
            await expect(ticketMarketplace.connect(owner).depositFunds({ value: depositAmount }))
                .to.emit(ticketMarketplace, "FundsDeposited")
                .withArgs(owner.address, depositAmount);
            
            // Verify contract balance increased
            expect(await ethers.provider.getBalance(await ticketMarketplace.getAddress()))
                .to.equal(depositAmount);
        });

        it("Should not allow non-admin to deposit funds", async function () {
            await expect(ticketMarketplace.connect(buyer1).depositFunds({ value: depositAmount }))
                .to.be.revertedWith("Not admin!");
        });

        it("Should allow admin to withdraw funds from TicketMarketplace", async function () {
            // Seed marketplace with ETH first
            await ticketMarketplace.connect(owner).depositFunds({ value: depositAmount });

            // Calculate expected withdrawable amount (total liquidity - min liquidity required)
            const min_liquidity_pool_required = await ticketMarketplace.sgdToWei(await loyaltyToken.totalSupply() / 100n);
            const expected_withdrawal = depositAmount - min_liquidity_pool_required;

            const tx = await ticketMarketplace.connect(owner).withdrawFunds();
            await expect(tx)
                .to.emit(ticketMarketplace, "FundsWithdrawn")
                .withArgs(owner.address, expected_withdrawal);
                
            await expect(tx) 
                .to.changeEtherBalances(
                    [ticketMarketplace, owner],
                    [-expected_withdrawal, expected_withdrawal]
                );
        });

        it("Should prevent withdrawal when liquidity is at minimum", async function () {
            // Seed marketplace with ETH first
            await ticketMarketplace.connect(owner).depositFunds({ value: depositAmount });

            // First withdraw available funds
            await ticketMarketplace.connect(owner).withdrawFunds();
            
            // Attempt another withdrawal (should fail)
            await expect(ticketMarketplace.connect(owner).withdrawFunds())
                .to.be.revertedWith("No excess profit available for withdrawal, minimum liquidity pool to be retained.");
        });

        it("Should not allow non-admin to withdraw funds from TicketMarketplace", async function () {
            await expect(ticketMarketplace.connect(buyer1).withdrawFunds())
                .to.be.revertedWith("Not admin!");
        });
    });
});
