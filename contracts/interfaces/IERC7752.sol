// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7752 — 0G Data Bridge Standard
 * @notice Interface for intent-based cross-chain data bridging backed by
 *         the 0G Compute Network. 1% of every bridge amount → OPACUS_TREASURY.
 */
interface IERC7752 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    enum IntentStatus  { Pending, Active, Fulfilled, Cancelled, Failed }
    enum IntentType    { Oracle, Data, Compute, Api, Storage }

    struct BridgeIntent {
        address   submitter;
        IntentType intentType;
        bytes     payload;          // encoded intent parameters
        uint64    sourceChainId;
        uint64    destChainId;
        address   token;
        uint256   grossAmount;
        uint256   feeAmount;        // 1% to treasury
        uint256   netAmount;        // 99% held for fulfiller
        bytes32   proofHash;
        IntentStatus status;
        uint64    createdAt;
        uint64    fulfilledAt;
        uint64    ttl;              // absolute Unix timestamp expiry
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event IntentSubmitted(
        bytes32 indexed intentId,
        address indexed submitter,
        IntentType      intentType,
        uint64          destChainId,
        uint256         grossAmount,
        uint256         feeAmount
    );
    event IntentFulfilled(bytes32 indexed intentId, bytes32 proofHash, bytes result);
    event IntentCancelled(bytes32 indexed intentId);
    event IntentFailed(bytes32 indexed intentId, string reason);

    // ─── Core functions ───────────────────────────────────────────────────────

    /**
     * @notice Submit a cross-chain bridge intent.
     *         1% fee → OPACUS_TREASURY immediately; 99% held for the fulfiller.
     * @param intentType    Category of 0G request.
     * @param payload       ABI-encoded request data.
     * @param destChainId   Destination chain ID (0 = 0G network).
     * @param ttlSeconds    Seconds until intent expires.
     * @param token         Payment token (address(0) = ETH).
     * @param gross         Total payment amount.
     * @return intentId     Unique identifier.
     */
    function submitIntent(
        IntentType intentType,
        bytes calldata payload,
        uint64 destChainId,
        uint64 ttlSeconds,
        address token,
        uint256 gross
    ) external payable returns (bytes32 intentId);

    /**
     * @notice Authorised fulfiller marks intent fulfilled and provides proof.
     * @param intentId  Intent to fulfil.
     * @param proofHash keccak256 of cross-chain execution proof.
     */
    function fulfillIntent(
        bytes32 intentId,
        bytes32 proofHash
    ) external;

    /**
     * @notice Cancel an expired or pending intent; net amount refunded.
     *         Already-paid fee is not refunded.
     */
    function cancelIntent(bytes32 intentId) external;

    /// @notice Register / update an authorised fulfiller address.
    function setFulfiller(address fulfiller, bool authorised) external;

    /// @notice Return full intent details.
    function getIntent(bytes32 intentId) external view returns (BridgeIntent memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function BRIDGE_FEE_BPS()   external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
