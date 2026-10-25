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
        amount = unlimited ? type(uint256).max : bound(amount, 0, SUPPLY);
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
}

contract MintGameInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MintGame internal token;
    MintGameHandler internal handler;

    function setUp() public {
        token = new MintGame();
        handler = new MintGameHandler(token, address(this));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = MintGameHandler.transfer.selector;
        selectors[1] = MintGameHandler.approve.selector;
        selectors[2] = MintGameHandler.transferFrom.selector;
        selectors[3] = MintGameHandler.revoke.selector;
        selectors[4] = MintGameHandler.attemptUnauthorizedTransfer.selector;
        selectors[5] = MintGameHandler.attemptOverdraw.selector;
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
            for (uint256 spender; spender < 4; ++spender) {
                assertEq(
                    token.allowance(handler.actors(owner), handler.actors(spender)),
                    handler.expectedAllowances(owner, spender)
                );
            }
        }
    }
}

