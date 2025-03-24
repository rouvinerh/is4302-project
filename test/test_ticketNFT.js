const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TicketNFT", function () {
    let TicketNFT;
    let ticketNFT;
    let owner, player1, player2, others;

    this.beforeEach(async function () {
        [owner, player1, player2, ...others] = await ethers.getSigners();

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

    });
})