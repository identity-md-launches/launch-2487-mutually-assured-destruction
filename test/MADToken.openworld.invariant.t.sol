// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";
import {MADOpenHandler} from "./helpers/MADOpenHandler.sol";

/// @dev Starts from the launch state (the whole supply in one place) and lets the fuzzer spread it
/// to addresses of its choosing, including the token itself, precompiles and the test contracts.
contract MADTokenOpenWorldInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    MADToken internal token;
    MADOpenHandler internal handler;

    function setUp() public {
        token = new MADToken();
        address genesis = makeAddr("launch factory");
        assertTrue(token.transfer(genesis, SUPPLY));
        handler = new MADOpenHandler(token, genesis, SUPPLY);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_SupplyNeverChangesAndHoldersOwnAllOfIt() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, SUPPLY, "supply is held outside the addresses that received it");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_EveryBalanceAndAllowanceMatchesTheModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.actorAt(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            for (uint256 j; j < n; ++j) {
                address spender = handler.actorAt(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_TokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0);
    }
}
