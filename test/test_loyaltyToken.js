const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LoyaltyToken", function () {
    let LoyaltyToken;
    let loyaltyToken;
    let owner, buyer1, buyer2, others;

    this.beforeEach(async function () {
        [owner, buyer1, buyer2, ...others] = await ethers.getSigners();

        // deploy LoyaltyToken
        LoyaltyToken = await ethers.getContractFactory("LoyaltyToken");
        loyaltyToken = await LoyaltyToken.deploy();
        await loyaltyToken.waitForDeployment();
    });

    // Test 1: Verify deploy
    it("Should deploy LoyaltyToken contract successfully", async function () {
        expect(await loyaltyToken.getAddress()).to.be.properAddress;
    });

    // Test 2: Mint LoyaltyTokens by different player
    it("Should mint LoyaltyTokens successfully", async function () {
        // Mint 10 LoyaltyTokens for buyer 0
        const tx1 = await loyaltyToken.connect(owner).mint(buyer1, 10);
        await tx1.wait();

        // Mint 10 LoyaltyTokens for buyer 1
        const tx2 = await loyaltyToken.connect(owner).mint(buyer2, 10);
        await tx2.wait();

        const buyer1_LT = await loyaltyToken.balanceOf(await buyer1.getAddress());
        expect(buyer1_LT).to.equal(10);
        const LT_count = await loyaltyToken.totalSupply();
        expect(LT_count).to.equal(20);
    });

    // Test 3: Only owner can mint
    it("Should throw error when non-owner attempts to mint", async function () {
        await expect(loyaltyToken.connect(buyer1).mint(buyer1, 10))
            .to.be.revertedWithCustomError(loyaltyToken, "OwnableUnauthorizedAccount");
    });

    // Test 4: Verify Approval for set amount of LoyaltyToken
    it("Should approve LoyaltyToken transfer successfully", async function () {
        // Mint 10 LoyaltyTokens for buyer 0
        const tx1 = await loyaltyToken.connect(owner).mint(buyer1, 10);
        await tx1.wait();

        await expect(loyaltyToken.connect(owner).transferFrom(await buyer1.getAddress(), await buyer2.getAddress(), 10))
            .to.be.revertedWithCustomError(loyaltyToken, "ERC20InsufficientAllowance");

        // Buyer 1 approves owner for ticket 0
        const tx2 = await loyaltyToken.connect(buyer1).approve(await owner.getAddress(), 10);
        await tx2.wait();
        
        // Verify approval of spender
        let initial_spending_limit = await loyaltyToken.allowance(await buyer1.getAddress(), await owner.getAddress());
        expect(initial_spending_limit).to.be.equal(10);

        // Spend 5 LoyaltyToken on behalf of buyer1
        const tx3 = await loyaltyToken.connect(owner).transferFrom(await buyer1.getAddress(), await buyer2.getAddress(), 5);
        await tx3.wait();

        // Verify accurate token settlement & spending limit after transfer
        let spending_limit = await loyaltyToken.allowance(await buyer1.getAddress(), await owner.getAddress());
        expect(spending_limit).to.be.equal(5);
        const buyer1_LT = await loyaltyToken.balanceOf(await buyer1.getAddress());
        expect(buyer1_LT).to.equal(5);
        const buyer2_LT = await loyaltyToken.balanceOf(await buyer2.getAddress());
        expect(buyer2_LT).to.equal(5);
    });

    // Test 5: Burn Loyalty tokens
    it("Should burn LoyaltyTokens successfully", async function () {
        // Mint ticket 0 for buyer 0
        const tx1 = await loyaltyToken.connect(owner).mint(owner, 10);
        await tx1.wait();

        const initial_owner_LT = await loyaltyToken.balanceOf(await owner.getAddress());
        expect(initial_owner_LT).to.equal(10);

        // Burn LoyaltyTokens
        const tx2 = await loyaltyToken.connect(owner).burn(10);
        await tx2.wait();

        const owner_LT = await loyaltyToken.balanceOf(await owner.getAddress());
        expect(owner_LT).to.equal(0);
    });
})