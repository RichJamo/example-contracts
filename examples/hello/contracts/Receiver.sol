// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Receiver {
    event HelloEvent(string);

    constructor() {}

    function hello(string memory message) external {
        emit HelloEvent(message);
    }

    receive() external payable {}

    fallback() external payable {}
}
