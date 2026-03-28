// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal ERC-20 interface for fee transfers
interface IERC20Min {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title OpacusFeeBase
 * @notice Shared 1% protocol fee logic for all Opacus ERC-75xx standards.
 * @dev Every call that moves value MUST route 1% to OPACUS_TREASURY before
 *      holding the net amount in the implementing contract.
 *      FEE_BPS = 100  ÷  10 000  =  1.00%
 */
abstract contract OpacusFeeBase {
    // ─── Constants ────────────────────────────────────────────────────────────
    uint256 public constant FEE_BPS         = 100;          // 1 %
    uint256 private constant _BPS_DENOM     = 10_000;
    address public constant  OPACUS_TREASURY =
        0xA943F46eE5f977067f07565CF1d31A10B68D7718;

    // ─── Reentrancy guard ─────────────────────────────────────────────────────
    uint256 private _reentrancyStatus = 1; // 1 = unlocked, 2 = locked

    modifier nonReentrant() {
        require(_reentrancyStatus == 1, "ReentrancyGuard: reentrant call");
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    /// @notice Emitted each time the 1% protocol fee is collected
    event ProtocolFeePaid(
        address indexed payer,
        address indexed token,   // address(0) = native ETH
        uint256          feeAmount,
        address          treasury
    );

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /**
     * @notice Split a gross amount into fee (1%) and net (99%).
     * @param gross  Total value supplied by the user.
     * @return fee   1% sent to treasury.
     * @return net   99% held by the contract.
     */
    function _splitFee(uint256 gross)
        internal
        pure
        returns (uint256 fee, uint256 net)
    {
        fee = (gross * FEE_BPS) / _BPS_DENOM;
        net = gross - fee;
    }

    /**
     * @notice Pull ERC-20 from payer, forward fee to treasury, keep net.
     * @param token  ERC-20 contract address.
     * @param payer  Wallet that approved this contract.
     * @param gross  Total approved amount.
     * @return net   Amount retained by this contract.
     */
    function _collectERC20(address token, address payer, uint256 gross)
        internal
        returns (uint256 net)
    {
        (uint256 fee, uint256 n) = _splitFee(gross);
        // Single pull into contract; then forward fee in one transfer
        require(
            IERC20Min(token).transferFrom(payer, address(this), gross),
            "Token pull failed"
        );
        require(
            IERC20Min(token).transfer(OPACUS_TREASURY, fee),
            "Fee forward failed"
        );
        emit ProtocolFeePaid(payer, token, fee, OPACUS_TREASURY);
        net = n;
    }

    /**
     * @notice Route ETH fee to treasury, return net (held in contract via msg.value).
     * @param payer  Msg sender for event attribution.
     * @param gross  msg.value supplied with the call.
     * @return net   Gross minus fee — stays in this contract.
     */
    function _collectETH(address payer, uint256 gross)
        internal
        returns (uint256 net)
    {
        (uint256 fee, uint256 n) = _splitFee(gross);
        (bool ok,) = OPACUS_TREASURY.call{value: fee}("");
        require(ok, "ETH fee forward failed");
        emit ProtocolFeePaid(payer, address(0), fee, OPACUS_TREASURY);
        net = n;
    }

    /// @notice Send ERC-20 from this contract to `to`.
    function _sendERC20(address token, address to, uint256 amount) internal {
        require(IERC20Min(token).transfer(to, amount), "Token release failed");
    }

    /// @notice Send ETH from this contract to `to`.
    function _sendETH(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH release failed");
    }
}
