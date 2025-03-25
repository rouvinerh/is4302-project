const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TicketNFT", function () {
    let TicketNFT;
    let ticketNFT;
    let owner, buyer1, buyer2, others;

    this.beforeEach(async function () {
        [owner, buyer1, buyer2, ...others] = await ethers.getSigners();

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
        // Mint ticket 0 for buyer 0
        const tx1 = await ticketNFT.connect(owner).createTicket(buyer1, "Event Name", 123213131, "A", "A1", 100);
        await tx1.wait();

        // Mint ticket 1 for buyer 1
        const tx2 = await ticketNFT.connect(owner).createTicket(buyer2, "Event Name", 123213131, "A", "A2", 100);
        await tx2.wait();

        let ownerOfTicket0 = await ticketNFT.ownerOf(0);
        let ownerOfTicket1 = await ticketNFT.ownerOf(1);

        expect(ownerOfTicket0).to.be.equal(await buyer1.getAddress());
        expect(ownerOfTicket1).to.be.equal(await buyer2.getAddress());
    });

    // Test 3: Only owner can mint
    it("Should throw error when non-owner attempts to mint", async function () {
        await expect(ticketNFT.connect(buyer1).createTicket(buyer1, "Event Name", 123213131, "A", "A1", 100))
            .to.be.revertedWithCustomError(ticketNFT, "OwnableUnauthorizedAccount");
    });

    // Test 4: Verify Approval for single NFT
    it("Should approve single NFT transfer successfully", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 = await ticketNFT.connect(owner).createTicket(buyer1, "Event Name", 123213131, "A", "A1", 100);
        await tx1.wait();

        await expect(ticketNFT.connect(owner).transferFrom(await buyer1.getAddress(), await buyer2.getAddress(), 0))
            .to.be.revertedWithCustomError(ticketNFT, "ERC721InsufficientApproval");

        // Buyer 1 approves owner for ticket 0
        const tx2 = await ticketNFT.connect(buyer1).approve(await owner.getAddress(), 0);
        await tx2.wait();
        
        // Verify approval of operator
        let operatorOfTicket0 = await ticketNFT.getApproved(0);
        expect(operatorOfTicket0).to.be.equal(await owner.getAddress());


        const tx3 = await ticketNFT.connect(owner).transferFrom(await buyer1.getAddress(), await buyer2.getAddress(), 0);
        await tx3.wait();

        let ownerOfTicket0 = await ticketNFT.ownerOf(0);

        // Verify transfer by operator
        expect(ownerOfTicket0).to.be.equal(await buyer2.getAddress());
    });

    // Test 5: Redeem Ticket
    it("Should redeem ticket successfully", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 = await ticketNFT.connect(owner).createTicket(buyer1, "Event Name", 123213131, "A", "A1", 100);
        await tx1.wait();

        // Check initial ticket state
        expect(await ticketNFT.getTicketState(0)).to.equal(0);

        // Redeem the ticket
        const tx2 = await ticketNFT.connect(owner).redeemTicket(0);
        await tx2.wait();

        // Check that the ticket is now redeemed
        expect(await ticketNFT.getTicketState(0)).to.equal(1);
    });

     // Test 6: Only owner can redeem Ticket
     it("Should throw error when non-owner attempts to redeem", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 = await ticketNFT.connect(owner).createTicket(buyer1, "Event Name", 123213131, "A", "A1", 100);
        await tx1.wait();

        await expect(ticketNFT.connect(buyer1).redeemTicket(0))
            .to.be.revertedWithCustomError(ticketNFT, "OwnableUnauthorizedAccount");
    });
})