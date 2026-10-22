// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";
import {MADHandler} from "./helpers/MADHandler.sol";

contract MADTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    MADToken internal token;
    MADHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new MADToken();
        actors = [
            makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")
        ];
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        handler = new MADHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = MADHandler.transfer.selector;
        selectors[1] = MADHandler.approve.selector;
        selectors[2] = MADHandler.transferFrom.selector;
        selectors[3] = MADHandler.overdraw.selector;
        selectors[4] = MADHandler.transferFromToZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndBalancesConserveIt() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_BalancesMatchAuthorizedTransfers() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
        }
    }

    function invariant_AllowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j])
                );
            }
        }
    }
}
