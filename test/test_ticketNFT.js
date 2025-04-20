const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TicketNFT", function () {
    let TicketNFT;
    let ticketNFT;
    let owner, buyer1, buyer2, others;

    this.beforeEach(async function () {
        // add some other users
        [owner, eventOrganiser1, eventOrganiser2, admin, buyer1, buyer2, ...others] = await ethers.getSigners();

        // deploy TicketNFT
        TicketNFT = await ethers.getContractFactory("TicketNFT");
        ticketNFT = await TicketNFT.deploy();
        await ticketNFT.waitForDeployment();
    });

    // Test 1: Verify deploy
    it("Should deploy TicketNFT contract successfully", async function () {
        expect(await ticketNFT.getAddress()).to.be.properAddress;
    });

    // Test 2: Mint ticket NFTs by different player
    it("Should mint ticket NFTs successfully", async function () {
        // Mint ticket 0 for event org 1
        const tx1 = await ticketNFT.connect(owner).createTicket(
            1,               // Event ID
            eventOrganiser1.address,       // event Org address
            "A",                 // Category
            "A1",                // Seat Number
            100                  // Price
        );
        await tx1.wait();

        // Mint ticket 1 for event org 2
        const tx2 = await ticketNFT.connect(owner).createTicket(
            2,               
            eventOrganiser2.address,       // event Org address
            "A",                 // Category
            "A1",                // Seat Number
            100                  // Price
        );
        await tx2.wait();

        let ownerOfTicket0 = await ticketNFT.ownerOf(0);
        let ownerOfTicket1 = await ticketNFT.ownerOf(1);
            
        // create event for 2 tickets, send to owner
        expect(ownerOfTicket0).to.be.equal(await eventOrganiser1.getAddress());
        expect(ownerOfTicket1).to.be.equal(await eventOrganiser2.getAddress());
    });


    // Test 3: Only owner can mint
    it("Should throw error when non-owner attempts to mint", async function () {
        await expect(ticketNFT.connect(buyer1).createTicket(
            2,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        )).to.be.reverted;    // 
    });

    // Test 4: Transfer ticket from owner to buyer
    it("Should transfer ticket successfully", async function () {
        // Mint ticket 0
        await ticketNFT.connect(owner).createTicket(
            1,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        );
    
        // Transfer the ticket from owner to buyer1
        await ticketNFT.connect(owner).transferTicket(0, buyer1.address);
    
        ownerOfTicket = await ticketNFT.ownerOf(0);
        expect(ownerOfTicket).to.be.equal(await buyer1.getAddress());
        
        // Mint ticket 1
        await ticketNFT.connect(owner).createTicket(
            1,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        );

        await ticketNFT.connect(owner).transferTicket(1, buyer2.address);
        ownerOfTicket = await ticketNFT.ownerOf(1);
        expect(ownerOfTicket).to.be.equal(await buyer2.getAddress());

    });

    // Test 5: Redeem Ticket
    it("Should redeem ticket successfully", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 =  await ticketNFT.connect(owner).createTicket(
            1,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        );
        await tx1.wait();

        // Check initial ticket state
        expect(await ticketNFT.getTicketState(0)).to.equal(1);

        // Redeem the ticket
        const tx2 = await ticketNFT.connect(owner).redeemTicket(0);
        await tx2.wait();

        // Check that the ticket is now redeemed
        expect(await ticketNFT.getTicketState(0)).to.equal(2);
    });

     // Test 6: Only owner can redeem Ticket
     it("Should throw error when non-owner or approved attempts to redeem", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 =  await ticketNFT.connect(owner).createTicket(
            1,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        );
        await tx1.wait();

        await expect(ticketNFT.connect(buyer1).redeemTicket(0))
            .to.be.revertedWith("Caller is not the owner or approved");
    });

    // Test 7: Cannot redeem already redeemed ticket
    it("Should throw error when attempting to redeem a redeemed ticket", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 =  await ticketNFT.connect(owner).createTicket(
            1,                // Event ID
            owner.address,    // Event Org address
            "A",              // Category
            "A1",             // Seat Number
            100               // Price
        );
        await tx1.wait();

        // Redeem the ticket
        const tx2 = await ticketNFT.connect(owner).redeemTicket(0);
        await tx2.wait();

        // Attempt to redeem the same ticket again
        await expect(ticketNFT.connect(owner).redeemTicket(0)).to.be.revertedWith("Ticket has already been redeemed");
    });
})