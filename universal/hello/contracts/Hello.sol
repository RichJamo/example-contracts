// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "@zetachain/toolkit/contracts/BytesHelperLib.sol";

contract Hello is UniversalContract {
    event HelloEvent(string, string);
    event ContextDataRevert(RevertContext);

    address constant _GATEWAY_ADDRESS =
        0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0;
    address constant _PROTOCOL_ADDRESS =
        0x735b14BB79463307AAcBED86DAf3322B1e6226aB;

    function onCrossChainCall(
        zContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override {
        string memory decodedMessage;
        if (message.length > 0) {
            decodedMessage = abi.decode(message, (string));
        }
        emit HelloEvent("Hello from a universal app", decodedMessage);
    }

    function investAssets(uint256 amount) external {
        address zrc20 = 0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c; // ZRC-20 USDC.ETH
        IZRC20(zrc20).approve(_GATEWAY_ADDRESS, type(uint256).max);
        uint256 gasLimit = 30000000; // 7000000

        address evmRecipient = 0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E;
        bytes memory recipient = abi.encodePacked(evmRecipient);

        bytes4 functionSelector = bytes4(keccak256(bytes("hello(string)"))); // is this right?
        string memory outgoingParam = "bob"; // 2 USDC
        bytes memory encodedArgs = abi.encode(outgoingParam); // is this right? should it be encodePacked?
        bytes memory outgoingMessage = abi.encodePacked(
            functionSelector,
            encodedArgs
        );

        RevertOptions memory revertOptions = RevertOptions(
            0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E, // revert address
            false, // callOnRevert
            address(this), // abortAddress
            bytes("revert message"),
            uint256(30000000) // onRevertGasLimit
        );

        IGatewayZEVM(_GATEWAY_ADDRESS).withdrawAndCall(
            recipient, // this contains the recipient smart contract address
            amount,
            zrc20, // this is used as an identifier of which chain to call
            outgoingMessage, // this is the function call for depositIntoVault(uint256 amount) in VaultManager
            gasLimit,
            revertOptions
        );
    }

    function onRevert(RevertContext calldata revertContext) external override {
        emit ContextDataRevert(revertContext);
    }
}
