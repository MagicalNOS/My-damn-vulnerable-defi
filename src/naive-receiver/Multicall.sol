// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

abstract contract Multicall is Context {

    // a solidity metric will cause the attack
    // when the bytes length is less than the actual length, abi decoder will splicit the array to
    // match the bytes length, this potentally will help the attacker to prevent the muticall throwing 
    // a error and revert all the transaction.

    // The right way: you should add the `request.from` to the end of data that the muticall will call.abi
    function multicall(bytes[] calldata data) external virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }
}
