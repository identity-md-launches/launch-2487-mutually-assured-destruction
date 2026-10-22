// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../../src/MADToken.sol";

/// @dev Test-only model for transfers and approvals among four independent holders.
contract MADHandler is Test {
    MADToken internal immutable token;
    address[4] internal actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(MADToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 250_000_000 * 1e18;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 limit = _min(expectedBalance[owner], allowance);
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] = allowance - amount;
        }
    }

    function overdraw(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1
            )
        );
        vm.prank(from);
        token.transfer(_actor(toSeed), balance + 1);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = _min(expectedBalance[owner], expectedAllowance[owner][spender]);
        uint256 amount = bound(rawAmount, 0, limit);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _min(uint256 left, uint256 right) internal pure returns (uint256) {
        return left < right ? left : right;
    }
}
