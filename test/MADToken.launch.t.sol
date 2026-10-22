// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Deploys the token and performs the launch transfers in one call, as the factory does in one
/// transaction, recording what each recipient received.
contract OneCallLauncher {
    function launch(bytes32 salt, address distributor, address pool, address remainder)
        external
        returns (MADToken token, uint256 heldAfterDeploy, uint256[3] memory received)
    {
        token = new MADToken{salt: salt}();
        heldAfterDeploy = token.balanceOf(address(this));
        uint256 supply = token.totalSupply();
        uint256 swarm = supply / 10;
        uint256 seed = supply * 6 / 10;
        require(token.transfer(distributor, swarm), "swarm");
        require(token.transfer(pool, seed), "seed");
        require(token.transfer(remainder, token.balanceOf(address(this))), "remainder");
        received = [token.balanceOf(distributor), token.balanceOf(pool), token.balanceOf(remainder)];
    }

    function call(address target, bytes calldata data) external returns (bool ok) {
        (ok,) = target.call(data);
    }
}

contract MADTokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    MADToken internal token;
    address internal holder = makeAddr("holder");
    address internal spender = makeAddr("spender");
    address internal other = makeAddr("other");

    function setUp() public {
        token = new MADToken();
    }

    function test_OneTransactionLaunchFlowsAreExact() public {
        OneCallLauncher launcher = new OneCallLauncher();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address remainder = makeAddr("remainder");
        (MADToken launched, uint256 held, uint256[3] memory received) =
            launcher.launch(bytes32(uint256(7)), distributor, pool, remainder);
        assertEq(held, SUPPLY);
        assertEq(received[0], SUPPLY / 10);
        assertEq(received[1], SUPPLY * 6 / 10);
        assertEq(received[2], SUPPLY * 3 / 10);
        assertEq(launched.balanceOf(address(launcher)), 0);
        assertEq(launched.totalSupply(), SUPPLY);

        // The distributor pays a claimant whole, in parts and in full.
        vm.startPrank(distributor);
        assertTrue(launched.transfer(holder, 1));
        assertTrue(launched.transfer(holder, SUPPLY / 10 - 1));
        vm.stopPrank();
        assertEq(launched.balanceOf(holder), SUPPLY / 10);
        assertEq(launched.balanceOf(distributor), 0);
    }

    function test_SameSaltCannotRedeploy() public {
        OneCallLauncher launcher = new OneCallLauncher();
        launcher.launch(bytes32(uint256(1)), holder, spender, other);
        vm.expectRevert();
        launcher.launch(bytes32(uint256(1)), holder, spender, other);
    }

    /// @dev Reachable code only, as the launch floor reads it.
    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE) {
                reachable = false;
            }
        }
    }

    /// @dev The deployer (the factory on chain) gets no privilege over holders, with the argument
    /// shapes the launch floor uses.
    function test_DeployerCannotMoveFreezeOrMint() public {
        OneCallLauncher launcher = new OneCallLauncher();
        (MADToken launched,,) = launcher.launch(bytes32(uint256(2)), holder, spender, other);
        uint256 held = launched.balanceOf(holder);
        string[17] memory sigs = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            bytes memory data = abi.encodeWithSignature(sigs[i], holder, type(uint128).max);
            assertFalse(launcher.call(address(launched), data), sigs[i]);
        }
        assertFalse(
            launcher.call(
                address(launched),
                abi.encodeWithSelector(token.transferFrom.selector, holder, address(launcher), 1)
            )
        );
        assertEq(launched.balanceOf(holder), held);
        assertEq(launched.totalSupply(), SUPPLY);
        vm.prank(holder);
        assertTrue(launched.transfer(other, held));
        assertEq(launched.balanceOf(holder), 0);
    }

    /// @dev OpenZeppelin 5 dropped these; a spender must not find a way around `approve`.
    function test_NoPermitOrAllowanceShortcuts() public {
        bytes[] memory attempts = new bytes[](5);
        attempts[0] = abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 1);
        attempts[1] = abi.encodeWithSignature("decreaseAllowance(address,uint256)", spender, 1);
        attempts[2] = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            address(this),
            spender,
            type(uint256).max,
            type(uint256).max,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
        attempts[3] = abi.encodeWithSignature("nonces(address)", address(this));
        attempts[4] = abi.encodeWithSignature("DOMAIN_SEPARATOR()");
        for (uint256 i; i < attempts.length; ++i) {
            vm.prank(spender);
            (bool ok,) = address(token).call(attempts[i]);
            assertFalse(ok);
        }
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_AllowanceOneBelowMaxIsFiniteAndDecrements() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_SpendingExactBalanceThenOneMoreWeiFails() public {
        token.transfer(holder, 5);
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, other, 5));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, other, 1);
        assertEq(token.balanceOf(other), 5);
    }

    function test_ApprovalSurvivesAndIsIndependentPerSpender() public {
        token.approve(spender, 3);
        token.approve(other, 4);
        vm.prank(spender);
        token.transferFrom(address(this), holder, 3);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), other), 4);
        assertEq(token.allowance(spender, address(this)), 0);
    }

    function test_TokenAddressCanHoldTokensButCannotSpendThem() public {
        token.transfer(address(token), 1e18);
        assertEq(token.balanceOf(address(token)), 1e18);
        // No sweep or rescue path: the tokens are only movable by a call from the token itself.
        (bool ok,) =
            address(token).call(abi.encodeWithSignature("rescue(address,uint256)", holder, 1));
        assertFalse(ok);
        assertEq(token.balanceOf(address(token)), 1e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApproveOverwritesRegardlessOfHistory(
        uint256 first,
        uint256 second,
        uint256 used
    ) public {
        first = bound(first, 0, SUPPLY);
        used = bound(used, 0, first);
        token.approve(spender, first);
        vm.prank(spender);
        token.transferFrom(address(this), holder, used);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
    }

    function testFuzz_ThirdPartyCannotSpendWithoutApproval(address caller, uint256 amount) public {
        vm.assume(caller != address(this) && caller != spender);
        amount = bound(amount, 1, SUPPLY);
        token.approve(spender, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, amount
            )
        );
        vm.prank(caller);
        token.transferFrom(address(this), caller, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_TransferChainConserves(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        token.transfer(holder, a);
        b = bound(b, 0, a);
        vm.prank(holder);
        token.transfer(spender, b);
        c = bound(c, 0, b);
        vm.prank(spender);
        token.transfer(other, c);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(holder) + token.balanceOf(spender)
                + token.balanceOf(other),
            SUPPLY
        );
        assertEq(token.balanceOf(other), c);
        assertEq(token.balanceOf(spender), b - c);
        assertEq(token.balanceOf(holder), a - b);
    }
}
