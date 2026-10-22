// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MADToken} from "../../src/MADToken.sol";

/// @dev Open-world model: holders are any address the fuzzer picks, spenders may be strangers,
/// and every call that ought to fail is made and must fail with the exact OpenZeppelin error and
/// no state change.
contract MADOpenHandler is Test {
    uint256 internal constant MAX_ACTORS = 24;

    MADToken internal immutable token;
    address[] internal actors;
    mapping(address => bool) public isActor;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public succeeded;
    uint256 public rejected;

    constructor(MADToken token_, address genesis, uint256 supply) {
        token = token_;
        _add(genesis);
        expectedBalance[genesis] = supply;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    /// @dev Sends to an arbitrary address, which becomes a holder; the zero address must be refused.
    function transferTo(uint256 fromSeed, address to, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        if (to == address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
            vm.prank(from);
            token.transfer(to, amount);
            ++rejected;
            return;
        }
        if (!_trackable(to)) to = _actor(uint256(uint160(to)));
        _add(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ++succeeded;
    }

    /// @dev Any amount above the balance, up to uint256 max, must revert and move nothing.
    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
        ++rejected;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++succeeded;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(rawAmount, 0, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] = allowance - amount;
        ++succeeded;
    }

    /// @dev A spender asking for more than it was allowed is refused before the balance is read.
    function overspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawExcess)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        if (allowance == type(uint256).max) return;
        uint256 amount = allowance + bound(rawExcess, 1, type(uint256).max - allowance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
        ++rejected;
    }

    /// @dev An allowance that covers the amount does not cover a balance that does not.
    function spendBeyondBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 rawExcess)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(rawExcess, 1, 1e30);
        vm.prank(owner);
        token.approve(spender, amount);
        expectedAllowance[owner][spender] = amount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, owner, amount);
        ++rejected;
    }

    /// @dev Any selector that is not part of ERC-20, from any holder, must do nothing at all.
    function unknownCall(uint256 callerSeed, bytes4 selector, bytes calldata args) external {
        if (_isErc20(selector)) return;
        vm.prank(_actor(callerSeed));
        (bool ok,) = address(token).call(abi.encodePacked(selector, args));
        assertFalse(ok, "token answered a selector outside ERC-20");
        ++rejected;
    }

    function _isErc20(bytes4 s) internal pure returns (bool) {
        return s == IERC20.transfer.selector || s == IERC20.transferFrom.selector
            || s == IERC20.approve.selector || s == IERC20.allowance.selector
            || s == IERC20.balanceOf.selector || s == IERC20.totalSupply.selector
            || s == IERC20Metadata.name.selector || s == IERC20Metadata.symbol.selector
            || s == IERC20Metadata.decimals.selector || s == bytes4(keccak256("INITIAL_SUPPLY()"));
    }

    function _trackable(address a) internal view returns (bool) {
        return isActor[a] || actors.length < MAX_ACTORS;
    }

    function _add(address a) internal {
        if (isActor[a]) return;
        isActor[a] = true;
        actors.push(a);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
}
