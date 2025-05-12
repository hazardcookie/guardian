// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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
 |  Authors: @hazardcookie                                                   |
\*───────────────────────────────────────────────────────────────────────────*/

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
error NonIntegralConversion();      //  amount must be an exact multiple
error InsufficientUSDC();
error InsufficientRLUSD();
error ZeroRecipient();

/* ------------------------------------------------------------------------- */
/*                                   Events                                  */
/* ------------------------------------------------------------------------- */
event WhitelistAdded(address indexed account);
event WhitelistRemoved(address indexed account);
event SwapExecuted(
    address indexed account,
    address indexed tokenIn,
    uint256 amountIn,
    address indexed tokenOut,
    uint256 amountOut
);
// emitted every time rescueTokens succeeds
event TokensRescued(               
    address indexed token,
    uint256 amount,
    address indexed to
);

/// @title RLUSDGuardian
/// @notice Holds hot-wallet liquidity in RLUSD & USDC and lets *whitelisted*
///         market-makers atomically swap between them at a 1 : 1 USD value.
/// @dev    Designed for proxy deployment using the UUPS pattern.
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

    /// @dev Decimals cached for conversion math.
    uint8 private rlusdDecimals;
    uint8 private usdcDecimals;

    /// @dev 10**(abs(rlusdDecimals − usdcDecimals)). For RLUSD18 ↔︎ USDC6 this is 1e12.
    uint256 private conversionFactor;

    /// @dev wallet ⇒ isWhitelisted
    mapping(address => bool) private _whitelist;

    /* --------------------------------------------------------------------- */
    /*                            Initialisation                             */
    /* --------------------------------------------------------------------- */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Proxy initializer (replaces constructor).
    /// @param rlusdAddress Address of the RLUSD ERC-20 contract.
    /// @param usdcAddress  Address of the USDC  ERC-20 contract.
    /// @param initialOwner The initial owner of the contract.
    function initialize(
        address rlusdAddress,
        address usdcAddress,
        address initialOwner
    ) external initializer {
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
        usdcToken  = IERC20(usdcAddress);

        rlusdDecimals = IERC20Metadata(rlusdAddress).decimals();
        usdcDecimals  = IERC20Metadata(usdcAddress).decimals();

        conversionFactor = rlusdDecimals >= usdcDecimals
            ? 10 ** (rlusdDecimals - usdcDecimals)
            : 10 ** (usdcDecimals - rlusdDecimals);
    }

    /// @dev UUPS upgrade authorisation -- only the contract owner can upgrade.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /* --------------------------------------------------------------------- */
    /*                        Whitelist administration                       */
    /* --------------------------------------------------------------------- */

    function addWhitelist(address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        if (_whitelist[account])    revert AlreadyWhitelisted();
        _whitelist[account] = true;
        emit WhitelistAdded(account);
    }

    function removeWhitelist(address account) external onlyOwner {
        if (!_whitelist[account]) revert NotWhitelisted();
        _whitelist[account] = false;
        emit WhitelistRemoved(account);
    }

    function isWhitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    /* --------------------------------------------------------------------- */
    /*                              Swap logic                               */
    /* --------------------------------------------------------------------- */

    /// @notice Swap RLUSD (18 dec) for USDC (6 dec) at 1 : 1 USD value.
    function swapRLUSDForUSDC(uint256 rlusdAmount) external nonReentrant {
        if (!_whitelist[msg.sender])          revert NotAuthorised();
        if (rlusdAmount == 0)                 revert AmountZero();
        if (rlusdAmount % conversionFactor != 0)
            revert NonIntegralConversion(); // prevent dust

        uint256 usdcAmount = rlusdAmount / conversionFactor;
        if (usdcAmount == 0)                  revert AmountTooSmall();
        if (usdcToken.balanceOf(address(this)) < usdcAmount)
            revert InsufficientUSDC();

        /* CEI pattern */
        rlusdToken.safeTransferFrom(msg.sender, address(this), rlusdAmount);
        usdcToken.safeTransfer(msg.sender, usdcAmount);

        emit SwapExecuted(
            msg.sender,
            address(rlusdToken),
            rlusdAmount,
            address(usdcToken),
            usdcAmount
        );
    }

    /// @notice Swap USDC (6 dec) for RLUSD (18 dec) at 1 : 1 USD value.
    function swapUSDCForRLUSD(uint256 usdcAmount) external nonReentrant {
        if (!_whitelist[msg.sender])          revert NotAuthorised();
        if (usdcAmount == 0)                  revert AmountZero();

        uint256 rlusdAmount = usdcAmount * conversionFactor;
        if (rlusdAmount == 0)                 revert AmountTooSmall();
        if (rlusdToken.balanceOf(address(this)) < rlusdAmount)
            revert InsufficientRLUSD();

        usdcToken.safeTransferFrom(msg.sender, address(this), usdcAmount);
        rlusdToken.safeTransfer(msg.sender, rlusdAmount);

        emit SwapExecuted(
            msg.sender,
            address(usdcToken),
            usdcAmount,
            address(rlusdToken),
            rlusdAmount
        );
    }

    /* --------------------------------------------------------------------- */
    /*                         Emergency / owner-tools                       */
    /* --------------------------------------------------------------------- */

    /// @notice Owner can withdraw any ERC-20 token (including RLUSD/USDC).
    function rescueTokens(
        address tokenAddress,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (tokenAddress == address(0)) revert ZeroTokenAddress();
        if (to == address(0))           revert ZeroRecipient();

        IERC20(tokenAddress).safeTransfer(to, amount);
        emit TokensRescued(tokenAddress, amount, to);
    }

    /* --------------------------------------------------------------------- */
    /*                       Storage gap for future upgrades                 */
    /* --------------------------------------------------------------------- */
    uint256[49] private __gap; // reduced by 1 to account for new event var (none stored)
}
