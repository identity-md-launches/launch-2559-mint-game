// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MintGame} from "../src/MintGame.sol";

/// @dev A closed set of holders and an independent ledger for randomized action sequences.
contract MintGameHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MintGame public immutable token;
    address[4] public actors;
    uint256[4] public expectedBalances;
    uint256[4][4] public expectedAllowances;
    address internal immutable outsider;

    constructor(MintGame token_, address initialHolder) {
        token = token_;
        actors[0] = initialHolder;
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        outsider = makeAddr("invariant outsider");
        expectedBalances[0] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        amount = bound(amount, 0, expectedBalances[from]);
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) public {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        // Finite approvals may exceed supply; max alone has unlimited semantics.
        amount = unlimited ? type(uint256).max : amount;
        expectedAllowances[owner][spender] = amount;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) public {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 approval = expectedAllowances[from][spender];
        uint256 maximum = expectedBalances[from] < approval ? expectedBalances[from] : approval;
        amount = bound(amount, 0, maximum);
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
        if (approval != type(uint256).max) expectedAllowances[from][spender] -= amount;
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) public {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        expectedAllowances[owner][spender] = 0;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], 0));
    }

    function attemptUnauthorizedTransfer(uint256 fromSeed, uint256 toSeed) public {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(actors[from], actors[to], 1);
    }

    function attemptOverdraw(uint256 fromSeed, uint256 toSeed) public {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalances[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, balance + 1)
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], balance + 1);
    }

    function attemptAllowanceOverdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 approval = bound(amount, 0, SUPPLY);
        approve(owner, spender, approval, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], approval, approval + 1
            )
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[(owner + 1) % actors.length], approval + 1);
        // The ledger keeps the approval and every balance from before the rejected call.
    }

    function attemptApprovedOverdraw(uint256 ownerSeed, uint256 spenderSeed, bool unlimited) public {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 balance = expectedBalances[owner];
        approve(owner, spender, balance + 1, unlimited);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balance, balance + 1)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[(owner + 1) % actors.length], balance + 1);
        // In particular, an allowance debit before the balance check must roll back.
    }

    function attemptInvalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) public {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 maximum = expectedBalances[owner];
        if (delegated && expectedAllowances[owner][spender] < maximum) {
            maximum = expectedAllowances[owner][spender];
        }
        amount = bound(amount, 0, maximum);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? actors[spender] : actors[owner]);
        if (delegated) token.transferFrom(actors[owner], address(0), amount);
        else token.transfer(address(0), amount);
    }

    function attemptInvalidApproval(uint256 ownerSeed, uint256 amount) public {
        uint256 owner = ownerSeed % actors.length;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[owner]);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract MintGameInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MintGame internal token;
    MintGameHandler internal handler;

    function setUp() public {
        token = new MintGame();
        handler = new MintGameHandler(token, address(this));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = MintGameHandler.transfer.selector;
        selectors[1] = MintGameHandler.approve.selector;
        selectors[2] = MintGameHandler.transferFrom.selector;
        selectors[3] = MintGameHandler.revoke.selector;
        selectors[4] = MintGameHandler.attemptUnauthorizedTransfer.selector;
        selectors[5] = MintGameHandler.attemptOverdraw.selector;
        selectors[6] = MintGameHandler.attemptAllowanceOverdraw.selector;
        selectors[7] = MintGameHandler.attemptApprovedOverdraw.selector;
        selectors[8] = MintGameHandler.attemptInvalidRecipient.selector;
        selectors[9] = MintGameHandler.attemptInvalidApproval.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndBalancesMatchIndependentLedger() public view {
        uint256 balanceSum;
        for (uint256 i; i < 4; ++i) {
            uint256 actual = token.balanceOf(handler.actors(i));
            assertEq(actual, handler.expectedBalances(i));
            balanceSum += actual;
        }
        assertEq(balanceSum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchIndependentLedger() public view {
        for (uint256 owner; owner < 4; ++owner) {
            assertEq(token.allowance(handler.actors(owner), address(0)), 0);
            for (uint256 spender; spender < 4; ++spender) {
                assertEq(
                    token.allowance(handler.actors(owner), handler.actors(spender)),
                    handler.expectedAllowances(owner, spender)
                );
            }
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "MINT GAME");
        assertEq(token.symbol(), "MINT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev Pin a nonzero delegated spend and both rollback paths independently of random selection.
    function test_HandlerSequenceExercisesRecoveryAfterFailures() public {
        handler.transfer(0, 1, 100);
        handler.approve(1, 2, type(uint256).max - 1, false);
        handler.transferFrom(1, 3, 2, 40);
        invariant_SupplyAndBalancesMatchIndependentLedger();
        invariant_AllowancesMatchIndependentLedger();
        handler.attemptInvalidRecipient(1, 2, 60, true);
        invariant_AllowancesMatchIndependentLedger();
        handler.attemptApprovedOverdraw(1, 2, false);
        invariant_AllowancesMatchIndependentLedger();
        handler.attemptApprovedOverdraw(1, 2, true);
        invariant_AllowancesMatchIndependentLedger();
        handler.attemptAllowanceOverdraw(1, 2, 59);
        invariant_AllowancesMatchIndependentLedger();
        handler.attemptInvalidApproval(1, type(uint256).max);
        handler.attemptInvalidRecipient(1, 2, 60, false);
        handler.approve(1, 2, 60, false);
        handler.transferFrom(1, 3, 2, 60);
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(3)), 100);
        invariant_SupplyAndBalancesMatchIndependentLedger();
        invariant_AllowancesMatchIndependentLedger();
        invariant_MetadataNeverChanges();
    }
}

