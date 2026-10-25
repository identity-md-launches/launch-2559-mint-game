// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MintGame} from "src/MintGame.sol";

/// @notice Algebraic properties and explicit arithmetic edges complement the stateful ledger tests.
/// forge-config: default.fuzz.runs = 1024
contract MintGamePropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MintGame internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new MintGame();
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
    }

    function test_OneSmallestUnitCanBeTransferredAndReturned() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsSpentUnlikeInfiniteAllowance() public {
        uint256 finite = type(uint256).max - 1;
        token.approve(spender, finite);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), finite - 1);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        token.approve(spender, finite);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), finite - 1);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAmountFailsEvenWithInfiniteApproval() public {
        token.approve(spender, type(uint256).max);
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(alice, type(uint256).max);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceDoesNotReturnWhenTokensAreReturned() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromToZeroStillRevertsWithInfiniteApproval() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndPreservesApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, approval);
        vm.prank(alice);
        token.approve(bob, approval);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.allowance(alice, bob), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplittingATransferHasTheSameResult(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        MintGame split = new MintGame();
        assertTrue(token.transfer(alice, total));
        assertTrue(split.transfer(alice, first));
        assertTrue(split.transfer(alice, total - first));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(split.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovedOverdrawRollsBackFiniteAllowance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - 1 - balance);
        uint256 requested = balance + excess;
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, requested);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), requested);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevokingOneSpenderDoesNotRevokeAnother(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        token.approve(spender, type(uint256).max);
        token.approve(bob, amount);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), bob), amount);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
