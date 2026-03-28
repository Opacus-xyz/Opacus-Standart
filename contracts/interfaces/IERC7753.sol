// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7753 — Escrow V2 Proof-Based Escrow Standard
 * @notice Interface for conditional payment escrow where release requires
 *         on-chain proof submission. 1% of every lock → OPACUS_TREASURY.
 */
interface IERC7753 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    enum EscrowStatus { Locked, Released, Refunded, Disputed, Resolved }

    struct Escrow {
        address  creator;
        address  counterparty;
        address  token;
        uint256  grossAmount;
        uint256  feeAmount;        // 1% to treasury at lock time
        uint256  netAmount;        // 99% held
        bytes32  conditionHash;    // keccak256(conditionDescription)
        bytes32  proofHash;        // submitted at release
        EscrowStatus status;
        uint64   lockedAt;
        uint64   settledAt;
        uint64   expiresAt;        // auto-refund if passed without release
        string   description;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event EscrowCreated(
        bytes32 indexed escrowId,
        address indexed creator,
        address indexed counterparty,
        address token,
        uint256 grossAmount,
        uint256 feeAmount
    );
    event EscrowReleased(bytes32 indexed escrowId, bytes32 proofHash, address releasedTo);
    event EscrowRefunded(bytes32 indexed escrowId, address refundedTo);
    event EscrowDisputed(bytes32 indexed escrowId, address disputedBy);
    event EscrowResolved(bytes32 indexed escrowId, bool releasedToCounterparty);

    // ─── Core functions ───────────────────────────────────────────────────────

    /**
     * @notice Lock funds in escrow for `counterparty`.
     *         1% fee → OPACUS_TREASURY immediately; 99% locked.
     * @param counterparty  Recipient if condition is proven.
     * @param description   Human-readable delivery condition.
     * @param token         ERC-20 token (address(0) = ETH).
     * @param gross         Total amount; creator must have approved `gross`.
     * @param ttlSeconds    Seconds until escrow auto-expires.
     * @return escrowId     Unique escrow identifier.
     */
    function createEscrow(
        address counterparty,
        string calldata description,
        address token,
        uint256 gross,
        uint64 ttlSeconds
    ) external payable returns (bytes32 escrowId);

    /**
     * @notice Release locked net to counterparty with a delivery proof.
     *         Only the escrow creator may call this.
     * @param escrowId  Escrow to release.
     * @param proofHash keccak256 of the delivery artifact / output hash.
     */
    function releaseEscrow(bytes32 escrowId, bytes32 proofHash) external;

    /**
     * @notice Refund locked net to creator (deadline passed or creator-initiated).
     *         Callable by creator after expiry, or by counterparty at any time.
     */
    function refundEscrow(bytes32 escrowId) external;

    /// @notice Raise a dispute; locks the escrow for manual arbitration.
    function disputeEscrow(bytes32 escrowId) external;

    /**
     * @notice Arbitrator resolves a dispute.
     * @param toCounterparty  true = pay counterparty, false = refund creator.
     */
    function resolveDispute(bytes32 escrowId, bool toCounterparty) external;

    /// @notice Set arbitrator address (owner only).
    function setArbitrator(address arbitrator) external;

    /// @notice Return full escrow details.
    function getEscrow(bytes32 escrowId) external view returns (Escrow memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function ESCROW_FEE_BPS()   external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
