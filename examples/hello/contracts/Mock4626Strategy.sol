// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMoonwellVault.sol";

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
            msg.sender,
            address(this)
        );
        require(shares > 0, "Withdraw failed");
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
