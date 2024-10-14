// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMoonwellVault.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/IGatewayEVM.sol";
import "hardhat/console.sol";

// LOCALNET_USDC_ADDRESS = 0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82;
// MOCK_4626_VAULT_ADDRESS - get this on deployment to localnet

contract Mock4626Strategy is Ownable {
    string public name;
    // address public immutable amanaVault;
    IERC20 public immutable inputToken;
    IMoonwellVault public immutable receiptToken;
    address constant _GATEWAY_ADDRESS =
        0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    constructor(
        string memory _name,
        // address _amanaVault,
        address _inputTokenAddress,
        address _receiptTokenAddress
    ) Ownable(msg.sender) {
        // require(_amanaVault != address(0), "Invalid amanaVault address");
        name = _name;
        // amanaVault = _amanaVault;
        inputToken = IERC20(_inputTokenAddress); // could get this from amanaVault
        receiptToken = IMoonwellVault(_receiptTokenAddress);
    }

    modifier onlyGateway() {
        require(
            msg.sender == _GATEWAY_ADDRESS,
            "Only Gateway contract can call"
        );
        _;
    }

    function invest(uint256 amount) external onlyGateway {
        bool success = inputToken.transferFrom(
            _GATEWAY_ADDRESS,
            address(this),
            amount
        );
        require(success, "Transfer failed");
        success = inputToken.approve(address(receiptToken), amount);
        require(success, "Approval failed");
        uint256 shares = receiptToken.deposit(amount, address(this));
        require(shares > 0, "Deposit failed");
    }

    function withdraw(uint256 _amount) external onlyGateway {
        uint256 shares = receiptToken.withdraw(
            _amount,
            address(this), // receiver
            address(this) // owner
        );
        console.log("shares: %s", shares);
        require(shares > 0, "Withdraw failed");
        uint256 strategyBalance = inputToken.balanceOf(address(this));
        console.log("strategyBalance: %s", strategyBalance);
        // send USDC back to vault on ZEVM
        bytes memory outgoingMessage = abi.encode(address(this)); // what does this message need to contain?

        RevertOptions memory revertOptions = RevertOptions(
            0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690, // revert address
            false, // callOnRevert
            address(this), // abortAddress
            bytes("revert message"),
            uint256(30000000) // onRevertGasLimit
        );

        address amana_vault_address = 0x9E545E3C0baAB3E08CdfD552C960A1050f373042; // TODO get this dynamically? Or as a constant?
        inputToken.approve(_GATEWAY_ADDRESS, _amount); // is this necessary?
        console.log(address(inputToken));

        IGatewayEVM(_GATEWAY_ADDRESS).depositAndCall(
            amana_vault_address, // the amana vault contract address - make this a constant? (just an address, not bytes)
            _amount, // the amount of USDC to send back
            address(inputToken), // ERC20 of the underlying asset token
            outgoingMessage, //the message to send
            revertOptions
        );
    }

    function totalUnderlyingAssets() external view returns (uint256) {
        uint256 shares = receiptToken.balanceOf(address(this));
        return receiptToken.convertToAssets(shares);
    }

    function emergencyWithdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        SafeERC20.safeTransfer(IERC20(_token), owner(), balance);
    }

    function emergencyWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(owner()).transfer(balance);
    }

    receive() external payable {}
}
