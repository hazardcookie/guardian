// SPDX-License-Identifier: UNLICENSED
/// @custom:security-contact bugs@ripple.com
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../src/RLUSDGuardian.sol";
import "forge-std/console.sol";
import {FalseReturnToken} from "./mocks/FalseReturnToken.sol";
import {NoReturnToken} from "./mocks/NoReturnToken.sol";
import {RLUSDGuardianV2} from "./mocks/RLUSDGuardianV2.sol";
import {MockToken} from "./mocks/MockToken.sol";

// Define error selectors
bytes4 constant OWNABLE_UNAUTHORIZED_ACCOUNT =
    bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
bytes4 constant ERC20_INSUFFICIENT_BALANCE =
    bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));

/// @notice Comprehensive test suite for the RLUSDGuardian contract.
/// @dev This contract contains all tests for the RLUSDGuardian, including setup, swap, whitelist, rescue, and upgradeability.
contract RLUSDGuardianTest is Test {
    // Contract instances and test addresses
    RLUSDGuardian public guardian; // The proxy instance of RLUSDGuardian under test
    RLUSDGuardianV2 public guardianV2Impl; // Used for upgradeability tests
    MockToken public rlusd; // RLUSD token instance (18 decimals)
    MockToken public usdc; // USDC token instance (6 decimals)
    address public owner; // Owner address (admin)
    address public marketMaker1; // First market maker address
    address public marketMaker2; // Second market maker address
    address public attacker; // Attacker address (not whitelisted)
    address public supplyManager1; // First supply manager address
    address public supplyManager2; // Second supply manager address

    // Events are already declared in RLUSDGuardian; re-declaring them here is unnecessary and
    // triggers compiler shadowing warnings. We simply reference the imported declarations.

    /// @notice Deploys the RLUSDGuardian behind a proxy and sets up initial test state.
    /// @dev This function is called before each test. It deploys tokens, mints balances, deploys the proxy, and funds the guardian.
    function setUp() public {
        console.log("setUp(): start");
        owner = address(1); // Assign owner address
        marketMaker1 = address(2); // Assign first market maker
        marketMaker2 = address(3); // Assign second market maker
        attacker = address(4); // Assign attacker address
        supplyManager1 = address(5);
        supplyManager2 = address(6);

        // Deploy test tokens (RLUSD with 18 decimals, USDC with 6 decimals)
        rlusd = new MockToken("RLUSD", "RLUSD", 18); // RLUSD token
        usdc = new MockToken("USDC", "USDC", 6); // USDC token

        // Mint initial supply to owner for both tokens
        rlusd.mint(owner, 1e12 * 10 ** 18); // Mint 1 trillion RLUSD to owner
        usdc.mint(owner, 1e12 * 10 ** 6); // Mint 1 trillion USDC to owner

        // Deploy RLUSDGuardian logic and proxy
        RLUSDGuardian logic = new RLUSDGuardian(); // Deploy logic contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(logic), ""); // Deploy proxy
        guardian = RLUSDGuardian(address(proxy)); // Assign proxy as guardian
        // Initialize the proxy (owner performs initialization)
        vm.prank(owner); // Set msg.sender to owner for next call
        guardian.initialize(address(rlusd), address(usdc), owner); // Initialize guardian with token addresses and owner

        // Fund the guardian contract with initial reserves of both tokens
        vm.startPrank(owner); // Start acting as owner
        rlusd.transfer(address(guardian), 50_000 * 10 ** 18); // Transfer 50,000 RLUSD to guardian
        usdc.transfer(address(guardian), 50_000 * 10 ** 6); // Transfer 50,000 USDC to guardian
        vm.stopPrank(); // Stop acting as owner

        // Log initial balances for debugging
        console.log("setUp(): guardian RLUSD balance", rlusd.balanceOf(address(guardian)));
        console.log("setUp(): guardian USDC balance", usdc.balanceOf(address(guardian)));
        console.log("setUp(): end");
        // No market makers are whitelisted at deployment (ensured by default state).
    }

    /// @notice Tests the supply manager role assignment and removal logic.
    /// @dev Verifies that only the owner can add or remove supply managers, that duplicate adds revert,
    ///      and that the correct events are emitted. Also checks that non-owners cannot assign the role.
    function testSupplyManagerRole() public {
        console.log("testSupplyManagerRole(): start");
        /* non-owner cannot designate (should revert with Ownable error) */
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED_ACCOUNT, attacker));
        guardian.addSupplyManager(supplyManager1);
        console.log("testSupplyManagerRole(): checked non-owner cannot designate");

        /* owner designates supplyManager1 (should emit event and succeed) */
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit SupplyManagerAdded(supplyManager1);
        guardian.addSupplyManager(supplyManager1);
        assertTrue(guardian.isSupplyManager(supplyManager1));
        console.log("testSupplyManagerRole(): owner designated supplyManager1");

        /* duplicate add should revert with AlreadySupplyManager error */
        vm.prank(owner);
        vm.expectRevert(AlreadySupplyManager.selector);
        guardian.addSupplyManager(supplyManager1);
        console.log("testSupplyManagerRole(): duplicate add reverted as expected");

        /* remove supplyManager1 (should emit event and succeed) */
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit SupplyManagerRemoved(supplyManager1);
        guardian.removeSupplyManager(supplyManager1);
        assertFalse(guardian.isSupplyManager(supplyManager1));
        console.log("testSupplyManagerRole(): removed supplyManager1");
        console.log("testSupplyManagerRole(): end");
    }

    /// @notice Tests the fundReserve and withdrawReserve functions for supply managers.
    /// @dev Verifies that a supply manager can fund the reserve with RLUSD, withdraw USDC,
    ///      and that invalid token withdrawals revert. Checks event emission and balance changes.
    function testSupplyManagerFundWithdraw() public {
        console.log("testSupplyManagerFundWithdraw(): start");
        // give role to supplyManager1 (must be owner)
        vm.prank(owner);
        guardian.addSupplyManager(supplyManager1);
        console.log("testSupplyManagerFundWithdraw(): supplyManager1 added");

        // fund RLUSD
        uint256 fundAmt = 1_000 * 1e18; // 1,000 RLUSD (18 decimals)
        rlusd.mint(supplyManager1, fundAmt); // Mint RLUSD to supplyManager1
        console.log("testSupplyManagerFundWithdraw(): minted RLUSD to supplyManager1");

        vm.startPrank(supplyManager1);
        rlusd.approve(address(guardian), fundAmt); // Approve guardian to spend RLUSD
        vm.expectEmit(true, true, true, true);
        emit ReserveFunded(supplyManager1, address(rlusd), fundAmt);
        guardian.fundReserve(address(rlusd), fundAmt); // Fund the reserve
        vm.stopPrank();
        console.log("testSupplyManagerFundWithdraw(): supplyManager1 funded RLUSD reserve");

        // Guardian's RLUSD balance should increase by fundAmt
        assertEq(rlusd.balanceOf(address(guardian)), 51_000 * 1e18);

        // withdraw USDC
        uint256 wdAmt = 500 * 1e6; // 500 USDC (6 decimals)

        vm.startPrank(supplyManager1);
        vm.expectEmit(true, true, true, true);
        emit ReserveWithdrawn(supplyManager1, address(usdc), wdAmt, supplyManager1);
        guardian.withdrawReserve(address(usdc), wdAmt, supplyManager1); // Withdraw USDC to self
        vm.stopPrank();
        console.log("testSupplyManagerFundWithdraw(): supplyManager1 withdrew USDC reserve");

        // supplyManager1 should now have wdAmt USDC, guardian's USDC should decrease
        assertEq(usdc.balanceOf(supplyManager1), wdAmt);
        assertEq(usdc.balanceOf(address(guardian)), 49_500 * 1e6);

        // invalid token: should revert with InvalidToken error
        vm.prank(supplyManager1);
        vm.expectRevert(InvalidToken.selector);
        guardian.withdrawReserve(address(0xdead), 1, supplyManager1);
        console.log("testSupplyManagerFundWithdraw(): invalid token withdraw reverted as expected");
        console.log("testSupplyManagerFundWithdraw(): end");
    }

    /// @notice Verifies that the contract owner is correctly set and tokens are initialized.
    function testInitialization() public view {
        console.log("testInitialization(): start");
        assertEq(guardian.owner(), owner, "Owner address mismatch after initialization");
        console.log("testInitialization(): end");
    }

    /// @notice Only the owner should be able to add or remove whitelisted market makers.
    function testWhitelistPermissions() public {
        console.log("testWhitelistPermissions(): start");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED_ACCOUNT, attacker));
        guardian.addWhitelist(marketMaker1);
        console.log("testWhitelistPermissions(): checked non-owner cannot whitelist");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(guardian));
        emit WhitelistAdded(marketMaker1);
        guardian.addWhitelist(marketMaker1);
        console.log("testWhitelistPermissions(): owner whitelisted marketMaker1");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(guardian));
        emit WhitelistRemoved(marketMaker1);
        guardian.removeWhitelist(marketMaker1);
        console.log("testWhitelistPermissions(): owner removed marketMaker1 from whitelist");

        vm.prank(marketMaker1);
        vm.expectRevert(NotAuthorised.selector);
        guardian.swapRLUSDForUSDC(100 * 10 ** 18);
        console.log("testWhitelistPermissions(): checked removed marketMaker1 cannot swap");
        console.log("testWhitelistPermissions(): end");
    }

    /// @notice Tests that adding a market maker to the whitelist twice reverts with AlreadyWhitelisted.
    /// @dev This test verifies that the contract prevents duplicate whitelist entries,
    ///      which could lead to redundant storage usage or confusion about market maker status.
    ///      The test attempts to add the same market maker twice and expects the second attempt to revert.
    function testWhitelistDuplicatePrevention() public {
        console.log("testWhitelistDuplicatePrevention(): start");
        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);
        console.log("testWhitelistDuplicatePrevention(): first whitelist succeeded");

        vm.prank(owner);
        vm.expectRevert(AlreadyWhitelisted.selector);
        guardian.addWhitelist(marketMaker1);
        console.log("testWhitelistDuplicatePrevention(): duplicate whitelist reverted as expected");
        console.log("testWhitelistDuplicatePrevention(): end");
    }

    /// @notice Tests that only whitelisted market makers can execute swaps.
    /// @dev This test verifies the access control mechanism for swap operations:
    ///      1. Non-whitelisted addresses cannot execute swaps
    ///      2. Whitelisted addresses can execute swaps after proper token approval
    ///      3. Token balances are correctly updated after successful swaps
    function testSwapAccessControl() public {
        console.log("testSwapAccessControl(): start");
        vm.prank(attacker);
        vm.expectRevert(NotAuthorised.selector);
        guardian.swapUSDCForRLUSD(100 * 10 ** 6);
        console.log("testSwapAccessControl(): checked non-whitelisted cannot swap");

        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);
        console.log("testSwapAccessControl(): whitelisted marketMaker1");
        vm.prank(owner);
        usdc.mint(marketMaker1, 100 * 10 ** 6);
        console.log("testSwapAccessControl(): minted 100 USDC to marketMaker1");
        vm.prank(marketMaker1);
        usdc.approve(address(guardian), 100 * 10 ** 6);
        console.log("testSwapAccessControl(): marketMaker1 approved guardian");
        vm.prank(marketMaker1);
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            marketMaker1, address(usdc), 100 * 10 ** 6, address(rlusd), 100 * 10 ** 18
        );
        guardian.swapUSDCForRLUSD(100 * 10 ** 6);
        console.log("testSwapAccessControl(): marketMaker1 swapped USDC for RLUSD");
        assertEq(usdc.balanceOf(marketMaker1), 0, "USDC balance did not decrease correctly");
        assertEq(
            rlusd.balanceOf(marketMaker1),
            100 * 10 ** 18,
            "RLUSD balance did not increase correctly"
        );
        console.log("testSwapAccessControl(): end");
    }

    /// @notice Tests the RLUSD -> USDC swap functionality with proper event emission.
    /// @dev This test verifies:
    ///      1. The swap function correctly transfers tokens
    ///      2. The correct event is emitted with accurate parameters
    ///      3. Token balances are updated correctly
    ///      4. The swap maintains the 1:1 USD value ratio between tokens
    function testSwapRLUSDForUSDC() public {
        console.log("testSwapRLUSDForUSDC(): start");
        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);
        console.log("testSwapRLUSDForUSDC(): whitelisted marketMaker1");
        vm.prank(owner);
        rlusd.mint(marketMaker1, 100 * 10 ** 18);
        console.log("testSwapRLUSDForUSDC(): minted 100 RLUSD to marketMaker1");
        vm.prank(marketMaker1);
        rlusd.approve(address(guardian), 100 * 10 ** 18);
        console.log("testSwapRLUSDForUSDC(): marketMaker1 approved guardian");
        vm.prank(marketMaker1);
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            marketMaker1, address(rlusd), 100 * 10 ** 18, address(usdc), 100 * 10 ** 6
        );
        guardian.swapRLUSDForUSDC(100 * 10 ** 18);
        console.log("testSwapRLUSDForUSDC(): marketMaker1 swapped RLUSD for USDC");
        assertEq(usdc.balanceOf(marketMaker1), 100 * 10 ** 6, "USDC balance mismatch after swap");
        assertEq(rlusd.balanceOf(marketMaker1), 0, "RLUSD balance mismatch after swap");
        console.log("testSwapRLUSDForUSDC(): end");
    }

    /// @notice Tests the USDC -> RLUSD swap functionality with proper event emission.
    /// @dev This test verifies:
    ///      1. The swap function correctly transfers tokens
    ///      2. The correct event is emitted with accurate parameters
    ///      3. Token balances are updated correctly
    ///      4. The swap maintains the 1:1 USD value ratio between tokens
    function testSwapUSDCForRLUSD() public {
        console.log("testSwapUSDCForRLUSD(): start");
        vm.prank(owner);
        guardian.addWhitelist(marketMaker2);
        console.log("testSwapUSDCForRLUSD(): whitelisted marketMaker2");
        vm.prank(owner);
        usdc.mint(marketMaker2, 100 * 10 ** 6);
        console.log("testSwapUSDCForRLUSD(): minted 100 USDC to marketMaker2");
        vm.prank(marketMaker2);
        usdc.approve(address(guardian), 100 * 10 ** 6);
        console.log("testSwapUSDCForRLUSD(): marketMaker2 approved guardian");
        vm.prank(marketMaker2);
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            marketMaker2, address(usdc), 100 * 10 ** 6, address(rlusd), 100 * 10 ** 18
        );
        guardian.swapUSDCForRLUSD(100 * 10 ** 6);
        console.log("testSwapUSDCForRLUSD(): marketMaker2 swapped USDC for RLUSD");
        assertEq(rlusd.balanceOf(marketMaker2), 100 * 10 ** 18, "RLUSD balance mismatch after swap");
        assertEq(usdc.balanceOf(marketMaker2), 0, "USDC balance mismatch after swap");
        console.log("testSwapUSDCForRLUSD(): end");
    }

    /// @notice Fuzz test for RLUSD -> USDC swaps to cover a wide range of amounts and edge cases.
    /// @dev This test uses fuzzing to verify swap functionality across various input amounts:
    ///      1. Tests amounts from 1 USDC worth up to the guardian's available liquidity
    ///      2. Verifies correct decimal handling between 18-decimal RLUSD and 6-decimal USDC
    ///      3. Ensures token balances are updated correctly after swaps
    ///      4. Maintains the 1:1 USD value ratio between tokens
    /// @param amount The base amount to test (will be scaled to appropriate decimals)
    function testFuzzSwapRLUSDForUSDC(uint256 amount) public {
        console.log(
            string.concat("testFuzzSwapRLUSDForUSDC(): start, amount=", vm.toString(amount))
        );

        // Limit the amount to prevent overflow
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint256).max / 10 ** 18); // Prevent overflow when scaling

        // Scale amount to RLUSD decimals (18 decimals)
        amount = amount * 10 ** 18;

        // Cap the amount to guardian's available USDC liquidity (in RLUSD terms)
        uint256 maxAmount = usdc.balanceOf(address(guardian)) * (10 ** 12); // convert USDC reserve (6 dec) to RLUSD base units (18 dec)
        vm.assume(amount <= maxAmount);

        // Ensure amount is large enough to convert to USDC (at least 1 USDC)
        vm.assume(amount >= 10 ** 12); // minimum 1 USDC worth of RLUSD

        // Whitelist and ensure marketMaker1 has exactly `amount` RLUSD
        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);

        // Mint the exact amount needed
        vm.prank(owner);
        rlusd.mint(marketMaker1, amount);

        // Approve and perform the swap
        vm.startPrank(marketMaker1);
        rlusd.approve(address(guardian), amount);
        guardian.swapRLUSDForUSDC(amount);
        vm.stopPrank();

        // After swap, marketMaker1's RLUSD decreased and USDC increased by the equivalent USD value
        uint256 expectedUSDC = amount / (10 ** 12); // convert 18-decimal RLUSD amount to 6-decimal USDC amount
        assertEq(
            usdc.balanceOf(marketMaker1), expectedUSDC, "USDC balance mismatch after fuzzed swap"
        );
        assertEq(
            rlusd.balanceOf(marketMaker1), 0, "RLUSD balance did not decrease by expected amount"
        );
        console.log(
            string.concat(
                "testFuzzSwapRLUSDForUSDC(): after swap, marketMaker1 USDC=",
                vm.toString(usdc.balanceOf(marketMaker1)),
                ", RLUSD=",
                vm.toString(rlusd.balanceOf(marketMaker1))
            )
        );
        console.log("testFuzzSwapRLUSDForUSDC(): end");
    }

    /// @notice Fuzz test for USDC -> RLUSD swaps to cover various input amounts and ensure stability.
    /// @dev This test uses fuzzing to verify swap functionality across various input amounts:
    ///      1. Tests amounts from 1 USDC up to the guardian's available RLUSD liquidity
    ///      2. Verifies correct decimal handling between 6-decimal USDC and 18-decimal RLUSD
    ///      3. Ensures token balances are updated correctly after swaps
    ///      4. Maintains the 1:1 USD value ratio between tokens
    /// @param amount The base amount to test (will be scaled to appropriate decimals)
    function testFuzzSwapUSDCForRLUSD(uint256 amount) public {
        console.log(
            string.concat("testFuzzSwapUSDCForRLUSD(): start, amount=", vm.toString(amount))
        );

        // Limit the amount to prevent overflow
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint256).max / 10 ** 6); // Prevent overflow when scaling

        // Scale amount to USDC decimals (6 decimals)
        amount = amount * 10 ** 6;

        // Limit to positive amounts within guardian's RLUSD liquidity
        uint256 maxUSDC = rlusd.balanceOf(address(guardian)) / (10 ** 12); // convert RLUSD reserve to USDC terms
        vm.assume(amount <= maxUSDC);

        // Mint the exact amount needed
        vm.prank(owner);
        usdc.mint(marketMaker2, amount);

        // Whitelist and execute swap
        vm.prank(owner);
        guardian.addWhitelist(marketMaker2);
        vm.startPrank(marketMaker2);
        usdc.approve(address(guardian), amount);
        guardian.swapUSDCForRLUSD(amount);
        vm.stopPrank();

        // After swap, marketMaker2's RLUSD increase should equal the USDC amount in USD value
        uint256 expectedRLUSD = amount * (10 ** 12); // convert 6-decimal USDC to 18-decimal RLUSD
        assertEq(
            rlusd.balanceOf(marketMaker2), expectedRLUSD, "RLUSD balance mismatch after fuzzed swap"
        );
        assertEq(usdc.balanceOf(marketMaker2), 0, "USDC balance should decrease by the swap amount");
        console.log(
            string.concat(
                "testFuzzSwapUSDCForRLUSD(): after swap, marketMaker2 RLUSD=",
                vm.toString(rlusd.balanceOf(marketMaker2)),
                ", USDC=",
                vm.toString(usdc.balanceOf(marketMaker2))
            )
        );
        console.log("testFuzzSwapUSDCForRLUSD(): end");
    }

    /// @notice Tests boundary conditions and error cases for swap functions.
    /// @dev This test verifies the contract's handling of edge cases:
    ///      1. Zero amount swaps should revert
    ///      2. Swaps exceeding user's balance should revert
    ///      3. Swaps exceeding guardian's liquidity should revert
    ///      4. Proper error messages are emitted for each failure case
    function testSwapBoundaryConditions() public {
        console.log("testSwapBoundaryConditions(): start");
        // Whitelist market maker for testing
        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);

        // Test 1: Zero amount swaps should revert
        vm.prank(marketMaker1);
        vm.expectRevert(AmountZero.selector);
        guardian.swapUSDCForRLUSD(0);

        vm.prank(marketMaker1);
        vm.expectRevert(AmountZero.selector);
        guardian.swapRLUSDForUSDC(0);

        // Test 2: Swap exceeding user's balance - marketMaker1 has no USDC
        vm.prank(marketMaker1);
        usdc.approve(address(guardian), 1_000_000 * 10 ** 6);
        vm.prank(marketMaker1);
        vm.expectRevert(InsufficientRLUSD.selector);
        guardian.swapUSDCForRLUSD(1_000_000 * 10 ** 6);

        // Test 3: Swap exceeding user's balance - marketMaker1 has no RLUSD
        vm.prank(marketMaker1);
        rlusd.approve(address(guardian), 1_000_000 * 10 ** 18);
        vm.prank(marketMaker1);
        vm.expectRevert(InsufficientUSDC.selector);
        guardian.swapRLUSDForUSDC(1_000_000 * 10 ** 18);

        // Test 4: Swap exceeding guardian's liquidity
        vm.prank(marketMaker1);
        vm.expectRevert(InsufficientUSDC.selector);
        guardian.swapRLUSDForUSDC(100_000 * 10 ** 18); // Try to swap more RLUSD than guardian has USDC for

        // Test 5: InsufficientRLUSD by draining guardian's RLUSD balance
        uint256 guardianRLUSDBalance = rlusd.balanceOf(address(guardian));
        vm.prank(owner);
        guardian.rescueTokens(address(rlusd), guardianRLUSDBalance, owner);

        // Verify guardian has no RLUSD
        assertEq(rlusd.balanceOf(address(guardian)), 0, "Guardian should have no RLUSD");

        // Mint and approve USDC for the test
        vm.prank(owner);
        usdc.mint(marketMaker1, 1_000 * 10 ** 6);
        vm.prank(marketMaker1);
        usdc.approve(address(guardian), 1_000 * 10 ** 6);

        // Now test InsufficientRLUSD
        vm.prank(marketMaker1);
        vm.expectRevert(InsufficientRLUSD.selector);
        guardian.swapUSDCForRLUSD(1_000 * 10 ** 6); // Try to swap more USDC than guardian has RLUSD for
        console.log("testSwapBoundaryConditions(): end");
    }

    /// @notice Tests the rescue function for recovering tokens, ensuring only owner can call and handling token quirks.
    /// @dev This test verifies:
    ///      1. Only the owner can call rescueTokens
    ///      2. Standard tokens can be rescued successfully
    ///      3. Non-standard tokens (returning false or no return value) are handled correctly
    ///      4. Token balances are updated correctly after rescue operations
    function testRescueTokens() public {
        console.log("testRescueTokens(): start");
        // Set up dummy tokens to rescue
        FalseReturnToken badToken = new FalseReturnToken("BadToken", "BAD", 18);
        NoReturnToken weirdToken = new NoReturnToken("WeirdToken", "WEIRD", 18);

        // Mint some tokens into the guardian contract (simulate accidental deposits)
        badToken.mint(address(guardian), 1_000 * 10 ** 18);
        weirdToken.mint(address(guardian), 500 * 10 ** 18);

        // Test 1: Only owner can call rescueTokens
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED_ACCOUNT, attacker));
        guardian.rescueTokens(address(badToken), 100 * 10 ** 18, attacker);

        // Test 2: Rescue a standard token (USDC) to owner
        uint256 ownerUSDCBefore = usdc.balanceOf(owner);
        vm.prank(owner);
        guardian.rescueTokens(address(usdc), 1_000 * 10 ** 6, owner);
        assertEq(
            usdc.balanceOf(owner),
            ownerUSDCBefore + 1_000 * 10 ** 6,
            "Owner did not receive rescued USDC"
        );
        assertEq(
            usdc.balanceOf(address(guardian)),
            49_000 * 10 ** 6,
            "Guardian USDC reserve not reduced after rescue"
        );
        console.log("testRescueTokens(): rescued USDC, owner balance=", usdc.balanceOf(owner));

        // Test 3: Rescue a token that returns false on transfer (should revert due to SafeERC20)
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("SafeERC20FailedOperation(address)")), address(badToken)
            )
        );
        guardian.rescueTokens(address(badToken), 100 * 10 ** 18, owner);

        // Test 4: Rescue a token that has no return value on transfer (SafeERC20 treats as success)
        uint256 ownerWeirdBefore = weirdToken.balanceOf(owner);
        vm.prank(owner);
        guardian.rescueTokens(address(weirdToken), 200 * 10 ** 18, owner);
        assertEq(
            weirdToken.balanceOf(owner),
            ownerWeirdBefore + 200 * 10 ** 18,
            "Owner did not receive rescued WeirdToken"
        );
        assertEq(
            weirdToken.balanceOf(address(guardian)),
            300 * 10 ** 18,
            "Guardian still holds some WeirdToken after rescue"
        );
        console.log(
            "testRescueTokens(): rescued WeirdToken, owner balance=", weirdToken.balanceOf(owner)
        );
        console.log("testRescueTokens(): end");
    }

    /// @notice Tests the upgradeability of the contract, ensuring only owner can upgrade and state is preserved.
    /// @dev This test verifies:
    ///      1. Only the owner can upgrade the contract
    ///      2. The new implementation's functionality works correctly
    ///      3. Existing state (whitelist) is preserved after upgrade
    ///      4. New functionality from the upgraded contract works as expected
    function testUpgradeability() public {
        console.log("testUpgradeability(): start");
        // Deploy a new implementation
        RLUSDGuardianV2 newImplementation = new RLUSDGuardianV2();

        // Whitelist market makers before upgrade
        vm.prank(owner);
        guardian.addWhitelist(marketMaker1);
        vm.prank(owner);
        guardian.addWhitelist(marketMaker2);

        // Test 1: Non-owner cannot upgrade
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED_ACCOUNT, attacker));
        guardian.upgradeToAndCall(address(newImplementation), "");

        // Test 2: Owner can upgrade
        vm.prank(owner);
        guardian.upgradeToAndCall(address(newImplementation), "");

        // Test 3: Verify new implementation functionality
        RLUSDGuardianV2 upgradedGuardian = RLUSDGuardianV2(address(guardian));
        assertEq(upgradedGuardian.getNewValue(), 42, "New implementation not working");

        // Test 4: Verify state preservation
        assertEq(
            upgradedGuardian.isWhitelisted(marketMaker1), true, "Whitelist state not preserved"
        );
        assertEq(
            upgradedGuardian.isWhitelisted(marketMaker2), true, "Whitelist state not preserved"
        );
        console.log(
            "testUpgradeability(): upgraded implementation, newValue=",
            upgradedGuardian.getNewValue()
        );
        console.log("testUpgradeability(): end");
    }
}
