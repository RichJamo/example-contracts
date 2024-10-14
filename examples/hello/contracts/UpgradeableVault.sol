// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RevertContext, RevertOptions} from "@zetachain/protocol-contracts/contracts/Revert.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import "hardhat/console.sol";

import "./interfaces/IStrategy.sol";

contract UpgradeableVault is
    Initializable,
    ERC4626Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    UniversalContract
{
    using SafeERC20 for IERC20;

    error InvalidStrategyAddress();
    error InvalidTreasuryAddress();
    error FeeExceedsLimit();
    error ApprovalFailed();
    error NothingToWithdraw();
    error InvalidZRC20Address();
    error CantBeZeroAddress();
    error DepositExceedsLimit();
    error MintExceedsLimit();
    error WithdrawExceedsLimit();
    error RedeemExceedsLimit();

    IZRC20 private _asset;
    uint8 private _decimals;
    address public strategyAddress;
    address public treasuryAddress;
    uint16 public performanceFeeRate;
    uint256 private totalPrincipal;

    address constant _GATEWAY_ADDRESS =
        0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0;

    mapping(address => uint256) private userPrincipal;

    event StrategyUpdated(address indexed newStrategy);
    event PerformanceFeePaid(address indexed user, uint256 amount);
    event PerformanceFeeUpdated(uint256 newFeeRate);
    event VaultInitialized(uint8 decimals, uint256 performanceFeeRate);
    event ContextDataRevert(RevertContext);
    event HelloEvent(string, string);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer function to replace the constructor in upgradeable contracts.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        IZRC20 asset_,
        address strategyAddress_,
        address treasuryAddress_,
        uint16 performanceFeeRate_
    ) external initializer {
        if (treasuryAddress_ == address(0)) revert InvalidTreasuryAddress();
        __ERC20_init(name_, symbol_);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        _asset = asset_;
        strategyAddress = strategyAddress_;
        _decimals = IERC20Metadata(address(asset_)).decimals();
        treasuryAddress = treasuryAddress_;
        performanceFeeRate = performanceFeeRate_;

        emit VaultInitialized(_decimals, performanceFeeRate_);
    }

    /**
     * @dev UUPS upgrade authorization
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function onCrossChainCall(
        zContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override {
        if (amount == 0) {
            // this indicates that it's an initial call to withdraw - is this a tight enough condition?
            address gas_zrc20 = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe; // ZRC-20 ETH.ETH - TODO in future this will have to indicate target chain dynamically
            IZRC20(gas_zrc20).approve(_GATEWAY_ADDRESS, type(uint256).max);
            uint256 gasLimit = 30000000; // could potentially reduce to 7000000

            uint256 withdrawAmount;
            if (message.length > 0) {
                withdrawAmount = abi.decode(message, (uint256));
            }
            bytes memory recipient = abi.encodePacked(strategyAddress);

            bytes4 functionSelector = bytes4(
                keccak256(bytes("withdraw(uint256)"))
            );
            bytes memory encodedArgs = abi.encode(withdrawAmount);
            bytes memory outgoingMessage = abi.encodePacked(
                functionSelector,
                encodedArgs
            );

            RevertOptions memory revertOptions = RevertOptions(
                0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690, // revert address
                false, // callOnRevert
                address(this), // abortAddress
                bytes("revert message"),
                uint256(30000000) // onRevertGasLimit
            );

            IGatewayZEVM(_GATEWAY_ADDRESS).call(
                recipient,
                address(_asset),
                outgoingMessage,
                gasLimit,
                revertOptions
            );
            // we call withdraw here and send a call to the strategy contract to withdraw and send assets back here
        } else {
            address decodedAddress;
            if (message.length > 0) {
                decodedAddress = abi.decode(message, (address));
            }
            if (decodedAddress == strategyAddress) {
                // this indicates that the strategy is sending assets back to the vault
                // we then send the amount back to the owner on the EVM in USDC? (withdraw or withdrawAndCall?)
                // withdraw(amount, address(0), context.sender); - TODO - eventually this will be the call here - watch for re-entrancy issues
                IZRC20(_asset).approve(_GATEWAY_ADDRESS, amount);

                bytes memory recipient = abi.encodePacked(strategyAddress);

                RevertOptions memory revertOptions = RevertOptions(
                    0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690, // revert address
                    false, // callOnRevert
                    address(this), // abortAddress
                    bytes("revert message"),
                    uint256(30000000) // onRevertGasLimit
                );
                console.log("Calling withdraw on gateway");
                IGatewayZEVM(_GATEWAY_ADDRESS).withdraw(
                    recipient, // this has to be the address of the owner/user on the EVM
                    amount, // the amount that the strategy has sent back
                    address(_asset), // TODO - when I move beyond the localnet, may need to re - specify this? Maybe need origin_asset AND target_asset?
                    revertOptions // do these need to be different from the revertOptions in deposit?
                );
            } else {
                console.log("Executing Deposit");

                // amount > 0 and sender != strategyAddress indicates that it's a deposit - is this a tight enough condition?
                if (zrc20 != address(_asset)) revert InvalidZRC20Address();
                if (decodedAddress == address(0)) revert CantBeZeroAddress();
                deposit(amount, decodedAddress);
            }
        }
    }

    function onRevert(RevertContext calldata revertContext) external override {
        emit ContextDataRevert(revertContext);
    }

    function setStrategy(address _strategyAddress) external onlyOwner {
        if (_strategyAddress == address(0)) revert InvalidStrategyAddress();
        strategyAddress = _strategyAddress;
        emit StrategyUpdated(_strategyAddress);
    }

    function updateTreasuryAddress(
        address _treasuryAddress
    ) external onlyOwner {
        if (_treasuryAddress == address(0)) revert InvalidTreasuryAddress();
        treasuryAddress = _treasuryAddress;
    }

    function setPerformanceFee(uint16 newFeeRate) external onlyOwner {
        if (newFeeRate > 2000) revert FeeExceedsLimit();
        performanceFeeRate = newFeeRate;
        emit PerformanceFeeUpdated(newFeeRate);
    }

    function switchStrategy(address newStrategy) external onlyOwner {
        if (newStrategy == address(0)) revert InvalidStrategyAddress();
        if (newStrategy == strategyAddress) revert InvalidStrategyAddress();

        address oldStrategy = strategyAddress;
        strategyAddress = newStrategy;
        emit StrategyUpdated(newStrategy);

        uint256 strategyBalance = IStrategy(oldStrategy)
            .totalUnderlyingAssets();
        if (strategyBalance > 0) {
            IStrategy(oldStrategy).withdraw(strategyBalance);
        }

        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance > 0) {
            bool success = _asset.approve(strategyAddress, vaultBalance);
            if (!success) revert ApprovalFailed();
            IStrategy(strategyAddress).invest(vaultBalance);
        }
    }

    function emergencyWithdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) revert NothingToWithdraw();
        SafeERC20.safeTransfer(IERC20(_token), owner(), balance);
    }

    /**
     * @dev Decimals are read from the underlying asset in the constructor and cached. If this fails (e.g., the asset
     * has not been created yet), the cached value is set to a default obtained by `super.decimals()` (which depends on
     * inheritance but is most likely 18). Override this function in order to set a guaranteed hardcoded value.
     * See {IERC20Metadata-decimals}.
     */
    function decimals()
        public
        view
        virtual
        override(ERC4626Upgradeable)
        returns (uint8)
    {
        return _decimals;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        // Get the amount of USDC held directly by the vault
        uint256 usdcBalance = _asset.balanceOf(address(this));

        // Call the strategy to get the equivalent value of aArbUSDC in terms of USDC
        uint256 strategyUSDCValue = IStrategy(strategyAddress)
            .totalUnderlyingAssets();

        // Return the total assets: USDC held in the vault + USDC equivalent held in the strategy
        return usdcBalance + strategyUSDCValue;
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(
        uint256 assets
    ) public view virtual override returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(
        uint256 shares
    ) public view virtual override returns (uint256 assets) {
        uint256 userAssets = _convertToAssets(shares, Math.Rounding.Floor);
        return userAssets;
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override returns (uint256) {
        if (assets > maxDeposit(receiver)) revert DepositExceedsLimit();

        uint256 shares = previewDeposit(assets);

        userPrincipal[receiver] += assets;
        totalPrincipal += assets;

        _deposit(_msgSender(), receiver, assets, shares); //TODO understand what _msgSender is going to be here?

        investAssets(assets);

        return shares;
    }

    function investAssets(uint256 amount) internal {
        address gas_zrc20 = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe; // ZRC-20 ETH.ETH
        IZRC20(gas_zrc20).approve(_GATEWAY_ADDRESS, type(uint256).max);
        uint256 gasLimit = 30000000; // could potentially reduce to 7000000

        IZRC20(_asset).approve(_GATEWAY_ADDRESS, amount);

        bytes memory recipient = abi.encodePacked(strategyAddress);

        bytes4 functionSelector = bytes4(keccak256(bytes("invest(uint256)")));
        bytes memory encodedArgs = abi.encode(amount);
        bytes memory outgoingMessage = abi.encodePacked(
            functionSelector,
            encodedArgs
        );

        RevertOptions memory revertOptions = RevertOptions(
            0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690, // revert address
            false, // callOnRevert
            address(this), // abortAddress
            bytes("revert message"),
            uint256(30000000) // onRevertGasLimit
        );

        IGatewayZEVM(_GATEWAY_ADDRESS).withdrawAndCall(
            recipient, // this contains the recipient smart contract address
            amount, // amount of zrc20 to withdraw
            address(_asset), // the zrc20 that is being withdrawn, also indicates which chain to target
            outgoingMessage, // this is the function call for invest(uint256 amount) in Mock4626Strategy
            gasLimit,
            revertOptions
        );
    }

    /** @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
     * In this case, the shares will be minted without requiring any assets to be deposited.
     */
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override returns (uint256) {
        if (shares > maxMint(receiver)) revert MintExceedsLimit();

        uint256 assets = previewMint(shares);

        userPrincipal[receiver] += assets;
        totalPrincipal += assets;

        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4626-withdraw}. 
    user specifies amount in terms of the asset that they want to withdraw, e.g. 50 USDC 
    */
    function withdraw(
        uint256 assets,
        address receiver,
        address user
    ) public virtual override returns (uint256) {
        if (assets > maxWithdraw(user)) revert WithdrawExceedsLimit();

        uint256 shares = previewWithdraw(assets);

        uint256 feeWithdrawn = _calculateAndApplyFee(user, assets);

        IStrategy(strategyAddress).withdraw(assets + feeWithdrawn);
        if (feeWithdrawn > 0) {
            emit PerformanceFeePaid(user, feeWithdrawn);
            // SafeERC20.safeTransfer(_asset, treasuryAddress, feeWithdrawn);
        }

        _withdraw(_msgSender(), receiver, user, assets, shares);
        return shares;
    }

    /** @dev See {IERC4626-redeem}. 
    user specifies how many shares they want to withdraw, e.g. 10 shares
    */
    function redeem(
        uint256 shares,
        address receiver,
        address user
    ) public virtual override returns (uint256) {
        if (shares > maxRedeem(user)) revert RedeemExceedsLimit();

        uint256 assets = previewRedeem(shares);

        uint256 feeWithdrawn = _calculateAndApplyFee(user, assets);

        IStrategy(strategyAddress).withdraw(assets + feeWithdrawn);

        if (feeWithdrawn > 0) {
            emit PerformanceFeePaid(user, feeWithdrawn);
            // SafeERC20.safeTransfer(_asset, treasuryAddress, feeWithdrawn);
        }

        _withdraw(_msgSender(), receiver, user, assets, shares);

        return assets;
    }

    function _calculateAndApplyFee(
        address user,
        uint256 assets
    ) internal returns (uint256 feeWithdrawn) {
        uint256 principal = userPrincipal[user];
        uint256 totalUserAssets = convertToAssets(balanceOf(user));
        uint256 principalWithdrawn;
        uint256 profit;
        uint256 fee;

        if (totalUserAssets > principal) {
            profit = totalUserAssets - principal;

            fee = (profit * performanceFeeRate) / (10000 - performanceFeeRate);

            principalWithdrawn = (assets * principal) / totalUserAssets;
            uint256 profitWithdrawn = assets - principalWithdrawn;

            feeWithdrawn =
                (profit * performanceFeeRate * profitWithdrawn) /
                (profit * (10000 - performanceFeeRate));

            userPrincipal[user] -= principalWithdrawn;
        } else {
            principalWithdrawn = assets;
            feeWithdrawn = 0;
            userPrincipal[user] -= principalWithdrawn;
        }

        totalPrincipal -= principalWithdrawn;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        uint256 totalAssetsNetOfFee;
        totalAssets() > totalPrincipal
            ? totalAssetsNetOfFee =
                totalAssets() -
                ((totalAssets() - totalPrincipal) * performanceFeeRate) /
                10000
            : totalAssetsNetOfFee = totalAssets();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : Math.mulDiv(assets, supply, totalAssetsNetOfFee, rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function _initialConvertToShares(
        uint256 assets,
        Math.Rounding /*rounding*/
    ) internal view virtual returns (uint256 shares) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        uint256 totalAssetsNetOfFee;
        totalAssets() > totalPrincipal
            ? totalAssetsNetOfFee =
                totalAssets() -
                ((totalAssets() - totalPrincipal) * performanceFeeRate) /
                10000
            : totalAssetsNetOfFee = totalAssets();
        return
            (supply == 0)
                ? _initialConvertToAssets(shares, rounding)
                : Math.mulDiv(shares, totalAssetsNetOfFee, supply, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToShares} when overriding it.
     */
    function _initialConvertToAssets(
        uint256 shares,
        Math.Rounding /*rounding*/
    ) internal view virtual returns (uint256 assets) {
        return shares;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        // SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address user,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != user) {
            _spendAllowance(user, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(user, shares);
        // SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, user, assets, shares);
    }

    /**
     * @dev Checks if vault is "healthy" in the sense of having assets backing the circulating shares.
     */
    function _isVaultCollateralized() private view returns (bool) {
        return totalAssets() > 0 || totalSupply() == 0;
    }
}
