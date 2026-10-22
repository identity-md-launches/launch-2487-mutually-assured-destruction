// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";
import {TokenFactory, RejectingReceiver} from "./helpers/TokenFactory.sol";

contract MADTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    MADToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal outsider;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        outsider = makeAddr("outsider");
        token = new MADToken();
    }

    function test_MetadataAndWholeSupply() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new MADToken();
    }

    function test_FactoryDeploymentMintsOnlyToFactory() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("MAD factory deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            salt,
                            keccak256(type(MADToken).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(alice);
        MADToken launched = factory.deploy(salt);

        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(address(launched)), 0);
        assertLe(address(launched).code.length, 24_576);
    }

    function test_LaunchDistributionClaimAndPoolTransfersAreExact() public {
        TokenFactory factory = new TokenFactory();
        MADToken launched = factory.deploy(keccak256("MAD distribution"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager fixture");
        address remainderRecipient = makeAddr("remainder recipient fixture");

        factory.distribute(launched, distributor, SUPPLY / 10);
        factory.distribute(launched, poolManager, SUPPLY * 8 / 10);
        factory.distribute(launched, remainderRecipient, SUPPLY / 10);

        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(remainderRecipient), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 100e18));
        assertEq(launched.balanceOf(bob), 100e18);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 100e18));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 17e18);
        assertTrue(token.transfer(alice, 17e18));
        assertEq(token.balanceOf(address(this)), SUPPLY - 17e18);
        assertEq(token.balanceOf(alice), 17e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_WholeSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractRecipientNeedsNoCallback() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1e18));
        assertEq(token.balanceOf(address(receiver)), 1e18);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        token.transfer(alice, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11)
        );
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferAmountIsMaxUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 12e18);
        assertTrue(token.approve(spender, 12e18));
        assertEq(token.allowance(address(this), spender), 12e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, 12e18));
        assertTrue(token.approve(spender, 3e18));
        assertEq(token.allowance(address(this), spender), 3e18);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_EmptyAccountCanApproveButSpenderCannotSpend() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenApprovingZeroSpender() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
    }

    function test_TransferFromSpendsExactAllowanceAndEmitsTransfer() public {
        token.approve(spender, 9e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4e18));
        assertEq(token.allowance(address(this), spender), 5e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4e18);
        assertEq(token.balanceOf(alice), 4e18);
        assertEq(token.balanceOf(spender), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 5e18));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 5e18);
    }

    function test_UnlimitedAllowanceRemainsUnchanged() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1e18));
        assertTrue(token.transferFrom(address(this), bob, 2e18));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3e18);
        assertEq(token.balanceOf(alice), 1e18);
        assertEq(token.balanceOf(bob), 2e18);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 5e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 5e18));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromExceedsAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenDifferentSpenderUsesApproval() public {
        token.approve(spender, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1)
        );
        vm.prank(outsider);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenDeployerSpendsHolderBalanceWithoutApproval() public {
        token.transfer(alice, 10);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_RevertWhenHolderUsesTransferFromWithoutSelfApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenTransferFromExceedsBalanceRestoresAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 20);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 20);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromToZeroRestoresAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenZeroTransferFromHasInvalidEndpoint() public {
        // Allowance validation rejects a zero owner before the balance transfer is reached.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transferFrom(alice, address(0), 0);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(alice, 100e18);
        bytes[] memory attempts = new bytes[](14);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", outsider, 1);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", 1);
        attempts[2] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        attempts[4] = abi.encodeWithSignature("pause()");
        attempts[5] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[6] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[7] = abi.encodeWithSignature("seize(address)", alice);
        attempts[8] = abi.encodeWithSignature("transferOwnership(address)", outsider);
        attempts[9] = abi.encodeWithSignature("owner()");
        attempts[10] = abi.encodeWithSignature("initialize(address)", outsider);
        attempts[11] = abi.encodeWithSignature("upgradeTo(address)", outsider);
        attempts[12] = abi.encodeWithSignature("setMinter(address)", outsider);
        attempts[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(deployerSucceeded, "deployer reached privileged selector");
            vm.prank(outsider);
            (bool outsiderSucceeded,) = address(token).call(attempts[i]);
            assertFalse(outsiderSucceeded, "outsider reached privileged selector");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100e18);
            assertEq(token.balanceOf(outsider), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100e18));
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_RejectsNativeCurrencyAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool acceptedEther,) = address(token).call{value: 1 ether}("");
        assertFalse(acceptedEther);
        (bool acceptedUnknown,) = address(token).call(hex"ffffffff");
        assertFalse(acceptedUnknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferConservesBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromRespectsAllowance(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(
            token.allowance(address(this), spender),
            approval == type(uint256).max ? approval : approval - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutChangingState(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess
            )
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverAllowanceRevertsWithoutChangingState(uint256 approval, uint256 excess)
        public
    {
        approval = bound(approval, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approval);
        uint256 amount = approval + excess;
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
