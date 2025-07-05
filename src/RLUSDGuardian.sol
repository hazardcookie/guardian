// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/*───────────────────────────────────────────────────────────────────────────*\
 |  RLUSD Guardian                                                           |
 |  ------------------------------------------------------------------------ |
 |  A minimal, proxy-upgradeable treasury contract that lets Ripple          |
 |  pre-fund RLUSD & USDC balances and grant a small set of institutional    |
 |  market-makers the right to swap the two stable-coins at par (1 : 1).     |
 |                                                                           |
 |  Key features                                                             |
 |  • UUPS upgradeable (Initializable + _authorizeUpgrade).                  |
 |  • Ownable (Fireblocks / multisig) access control.                        |
 |  • Mapping-based whitelist (<10 MM wallets expected).                     |
 |  • SafeERC20 transfers, ReentrancyGuard, strict CEI pattern.              |
 |  • Decimal-aware conversion (RLUSD 18 dec ↔︎ USDC 6 dec).                  |
 |                                                                           |
 |  Author: @hazardcookie (hazardcookie.eth)                                 |
 |  Security-contact bugs@ripple.com                                         |
\*───────────────────────────────────────────────────────────────────────────*/

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/* ------------------------------------------------------------------------- */
/*                               Custom errors                               */
/* ------------------------------------------------------------------------- */
error ZeroTokenAddress();
error ZeroAddress();
error AlreadyWhitelisted();
error NotWhitelisted();
error NotAuthorised();
error AmountZero();
error AmountTooSmall();
error NonIntegralConversion(); //  amount must be an exact multiple
error InsufficientUSDC();
error InsufficientRLUSD();
error InsufficientReserve();
error ZeroRecipient();
error AlreadySupplyManager();
error NotSupplyManager();
error InvalidToken();
error InvalidDecimals();

/* ------------------------------------------------------------------------- */
/*                                   Events                                  */
/* ------------------------------------------------------------------------- */
/// @notice Emitted when an account is added to the whitelist.
event WhitelistAdded(address indexed account);

/// @notice Emitted when an account is removed from the whitelist.
event WhitelistRemoved(address indexed account);

/// @notice Emitted when a swap between RLUSD and USDC is executed.
event SwapExecuted(
    address indexed account,
    address indexed tokenIn,
    uint256 amountIn,
    address indexed tokenOut,
    uint256 amountOut
);

/// @notice Emitted when tokens are rescued by the owner.
event TokensRescued(address indexed token, uint256 amount, address indexed to);

/// @notice Emitted when an account is added as a supply manager.
event SupplyManagerAdded(address indexed account);

/// @notice Emitted when an account is removed as a supply manager.
event SupplyManagerRemoved(address indexed account);

/// @notice Emitted when the reserve is funded with RLUSD or USDC.
event ReserveFunded(address indexed from, address indexed token, uint256 amount);

/// @notice Emitted when tokens are withdrawn from the reserve.
event ReserveWithdrawn(
    address indexed by, address indexed token, uint256 amount, address indexed to
);

/// @title RLUSDGuardian
/// @notice Holds hot-wallet liquidity in RLUSD & USDC and lets *whitelisted* market-makers atomically swap between them at a 1 : 1 USD value.
/// @custom:security-contact bugs@ripple.com
/// @dev Designed for proxy deployment using the UUPS pattern.
contract RLUSDGuardian is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* --------------------------------------------------------------------- */
    /*                             State variables                           */
    /* --------------------------------------------------------------------- */

    /// @notice RLUSD ERC-20 token contract (18 decimals).
    IERC20 public rlusdToken;

    /// @notice USDC ERC-20 token contract (6 decimals).
    IERC20 public usdcToken;

    /// @dev conversionFactor = 10 ** (rlusdDec - usdcDec); for RLUSD18 ↔︎ USDC6 this is 1e12.
    uint256 private conversionFactor;

    /// @dev Mapping of wallet address to whitelist status.
    mapping(address account => bool isWhitelisted) private _whitelist;

    /// @dev Mapping of wallet address to supply manager status.
    mapping(address account => bool isSupplyManager) private _supplyManagers;

    /* --------------------------------------------------------------------- */
    /*                               Modifiers                               */
    /* --------------------------------------------------------------------- */

    /// @dev Restricts caller to owner or authorised supply manager.
    modifier onlyOwnerOrSupplyManager() {
        if (!_supplyManagers[msg.sender] && msg.sender != owner()) revert NotAuthorised();
        _;
    }

    /* --------------------------------------------------------------------- */
    /*                            Initialisation                             */
    /* --------------------------------------------------------------------- */

    /// @notice Disables initializers for the implementation contract.
    /// @dev OpenZeppelin UUPS pattern: disables initializers on the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Proxy initializer (replaces constructor).
    /// @param rlusdAddress Address of the RLUSD ERC-20 contract.
    /// @param usdcAddress  Address of the USDC  ERC-20 contract.
    /// @param initialOwner The initial owner of the contract.
    /// @dev Sets up the contract for proxy deployment. Only callable once.
    function initialize(address rlusdAddress, address usdcAddress, address initialOwner)
        external
        initializer
    {
        if (rlusdAddress == address(0) || usdcAddress == address(0)) {
            revert ZeroTokenAddress();
        }
        if (initialOwner == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        rlusdToken = IERC20(rlusdAddress);
        usdcToken = IERC20(usdcAddress);

        uint8 rlusdDec = IERC20Metadata(rlusdAddress).decimals();
        uint8 usdcDec = IERC20Metadata(usdcAddress).decimals();

        // Ensure RLUSD has at least as many decimals as USDC to prevent value distortion in swaps
        if (rlusdDec <= usdcDec) revert InvalidDecimals();

        // conversionFactor = 10 ** (rlusdDec - usdcDec)
        conversionFactor = 10 ** (rlusdDec - usdcDec);
    }

    /// @notice UUPS upgrade authorisation -- only the contract owner can upgrade.
    /// @param newImplementation The address of the new implementation contract.
    /// @dev Required by UUPSUpgradeable. Only callable by the owner.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* --------------------------------------------------------------------- */
    /*                        Whitelist administration                       */
    /* --------------------------------------------------------------------- */

    /// @notice Adds an account to the whitelist.
    /// @param account The address to whitelist.
    /// @dev Only callable by the owner. Reverts if already whitelisted or zero address.
    function addWhitelist(address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        if (_whitelist[account]) revert AlreadyWhitelisted();
        _whitelist[account] = true;
        emit WhitelistAdded(account);
    }

    /// @notice Removes an account from the whitelist.
    /// @param account The address to remove from the whitelist.
    /// @dev Only callable by the owner. Reverts if not whitelisted.
    function removeWhitelist(address account) external onlyOwner {
        if (!_whitelist[account]) revert NotWhitelisted();
        _whitelist[account] = false;
        emit WhitelistRemoved(account);
    }

    /// @notice Checks if an account is whitelisted.
    /// @param account The address to check.
    /// @return True if the account is whitelisted, false otherwise.
    function isWhitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    /* --------------------------------------------------------------------- */
    /*                      Supply-manager administration                    */
    /* --------------------------------------------------------------------- */

    /// @notice Adds an account as a supply manager.
    /// @param account The address to add as a supply manager.
    /// @dev Only callable by the owner. Reverts if already a supply manager or zero address.
    function addSupplyManager(address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        if (_supplyManagers[account]) revert AlreadySupplyManager();
        _supplyManagers[account] = true;
        emit SupplyManagerAdded(account);
    }

    /// @notice Removes an account from supply managers.
    /// @param account The address to remove as a supply manager.
    /// @dev Only callable by the owner. Reverts if not a supply manager.
    function removeSupplyManager(address account) external onlyOwner {
        if (!_supplyManagers[account]) revert NotSupplyManager();
        _supplyManagers[account] = false;
        emit SupplyManagerRemoved(account);
    }

    /// @notice Checks if an account is a supply manager.
    /// @param account The address to check.
    /// @return True if the account is a supply manager, false otherwise.
    function isSupplyManager(address account) external view returns (bool) {
        return _supplyManagers[account];
    }

    /* --------------------------------------------------------------------- */
    /*                      Reserve fund / withdraw logic                    */
    /* --------------------------------------------------------------------- */

    /// @notice Fund the contract's reserve with RLUSD or USDC.
    /// @param tokenAddress The address of the token to fund (must be RLUSD or USDC).
    /// @param amount The amount to fund.
    /// @dev Only callable by supply managers or the owner. Reverts for invalid token or zero amount.
    function fundReserve(address tokenAddress, uint256 amount)
        external
        nonReentrant
        onlyOwnerOrSupplyManager
    {
        if (tokenAddress != address(rlusdToken) && tokenAddress != address(usdcToken)) {
            revert InvalidToken();
        }
        if (amount == 0) revert AmountZero();

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        emit ReserveFunded(msg.sender, tokenAddress, amount);
    }

    /// @notice Withdraw tokens from the contract's reserve.
    /// @param tokenAddress The address of the token to withdraw (must be RLUSD or USDC).
    /// @param amount The amount to withdraw.
    /// @param to The recipient address.
    /// @dev Only callable by supply managers or the owner. Reverts for invalid token or zero recipient.
    function withdrawReserve(address tokenAddress, uint256 amount, address to)
        external
        nonReentrant
        onlyOwnerOrSupplyManager
    {
        if (tokenAddress != address(rlusdToken) && tokenAddress != address(usdcToken)) {
            revert InvalidToken();
        }
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert ZeroRecipient();
        if (IERC20(tokenAddress).balanceOf(address(this)) < amount) {
            revert InsufficientReserve();
        }

        IERC20(tokenAddress).safeTransfer(to, amount);
        emit ReserveWithdrawn(msg.sender, tokenAddress, amount, to);
    }

    /* --------------------------------------------------------------------- */
    /*                              Swap logic                               */
    /* --------------------------------------------------------------------- */

    /// @notice Swap RLUSD (18 dec) for USDC (6 dec) at 1 : 1 USD value.
    /// @param rlusdAmount The amount of RLUSD to swap (must be a multiple of conversionFactor).
    /// @dev Only callable by whitelisted accounts. Reverts for zero amount, non-integral conversion, or insufficient liquidity.
    function swapRLUSDForUSDC(uint256 rlusdAmount) external nonReentrant {
        if (!_whitelist[msg.sender]) revert NotAuthorised();
        if (rlusdAmount == 0) revert AmountZero();

        // Cache variables for gas efficiency
        uint256 _factor = conversionFactor;
        IERC20 _usdc = usdcToken;
        IERC20 _rlusd = rlusdToken;

        // Prevent dust
        if (rlusdAmount % _factor != 0) revert NonIntegralConversion();

        uint256 usdcAmount = rlusdAmount / _factor;
        if (usdcAmount == 0) revert AmountTooSmall();
        if (_usdc.balanceOf(address(this)) < usdcAmount) revert InsufficientUSDC();

        // CEI pattern
        _rlusd.safeTransferFrom(msg.sender, address(this), rlusdAmount);
        _usdc.safeTransfer(msg.sender, usdcAmount);

        emit SwapExecuted(msg.sender, address(_rlusd), rlusdAmount, address(_usdc), usdcAmount);
    }

    /// @notice Swap USDC (6 dec) for RLUSD (18 dec) at 1 : 1 USD value.
    /// @param usdcAmount The amount of USDC to swap.
    /// @dev Only callable by whitelisted accounts. Reverts for zero amount or insufficient liquidity.
    function swapUSDCForRLUSD(uint256 usdcAmount) external nonReentrant {
        if (!_whitelist[msg.sender]) revert NotAuthorised();
        if (usdcAmount == 0) revert AmountZero();

        // Cache variables for gas efficiency
        uint256 _factor = conversionFactor;
        IERC20 _usdc = usdcToken;
        IERC20 _rlusd = rlusdToken;

        uint256 rlusdAmount = usdcAmount * _factor;
        if (rlusdAmount == 0) revert AmountTooSmall();
        if (_rlusd.balanceOf(address(this)) < rlusdAmount) revert InsufficientRLUSD();

        _usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        _rlusd.safeTransfer(msg.sender, rlusdAmount);

        emit SwapExecuted(msg.sender, address(_usdc), usdcAmount, address(_rlusd), rlusdAmount);
    }

    /* --------------------------------------------------------------------- */
    /*                         Emergency / owner-tools                       */
    /* --------------------------------------------------------------------- */

    /// @notice Owner can withdraw any ERC-20 token (including RLUSD/USDC).
    /// @param tokenAddress The address of the token to rescue.
    /// @param amount The amount to rescue.
    /// @param to The recipient address.
    /// @dev Only callable by the owner. Reverts for zero token address or zero recipient.
    function rescueTokens(address tokenAddress, uint256 amount, address to) external onlyOwner {
        if (tokenAddress == address(0)) revert ZeroTokenAddress();
        if (to == address(0)) revert ZeroRecipient();

        IERC20(tokenAddress).safeTransfer(to, amount);
        emit TokensRescued(tokenAddress, amount, to);
    }

    /* --------------------------------------------------------------------- */
    /*                       Storage gap for future upgrades                 */
    /* --------------------------------------------------------------------- */
    /// @dev Storage gap for future upgrades.
    uint256[50] private __gap;
}
