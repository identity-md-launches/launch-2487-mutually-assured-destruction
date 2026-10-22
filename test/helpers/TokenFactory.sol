// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MADToken} from "../../src/MADToken.sol";

/// @dev Test fixture only. Simulates deployment and distribution by a launch factory.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }

    function distribute(MADToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "fixture transfer failed");
    }
}

/// @dev A token recipient whose fallback rejects all calls.
contract RejectingReceiver {
    fallback() external {
        revert("unexpected callback");
    }
}
