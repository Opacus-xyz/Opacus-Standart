// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7750 — Opacus Nitro Agent Execution Standard
 * @notice Interface for secure, fee-bearing agent task execution.
 *         1% of every task payment is forwarded to OPACUS_TREASURY.
 */
interface IERC7750 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    enum TaskStatus { Pending, Active, Completed, Cancelled, Disputed }

    struct Task {
        address submitter;
        address agent;
        address token;        // address(0) = native ETH
        uint256 grossAmount;
        uint256 feeAmount;    // 1% routed to treasury at submission
        uint256 netAmount;    // 99% held for agent
        bytes32 proofHash;
        TaskStatus status;
        uint64  createdAt;
        uint64  completedAt;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event TaskSubmitted(
        bytes32 indexed taskId,
        address indexed submitter,
        address indexed agent,
        address token,
        uint256 grossAmount,
        uint256 feeAmount
    );
    event TaskCompleted(bytes32 indexed taskId, bytes32 proofHash);
    event TaskCancelled(bytes32 indexed taskId, address refundTo);
    event TaskDisputed(bytes32 indexed taskId, address disputedBy);

    // ─── Core functions ───────────────────────────────────────────────────────

    /**
     * @notice Submit a task to an agent together with payment.
     *         1% fee is forwarded to OPACUS_TREASURY immediately.
     * @param agent   Executing agent address.
     * @param payload ABI-encoded task instructions.
     * @param token   ERC-20 token (address(0) for ETH).
     * @param gross   Total payment — fee is deducted from this.
     * @return taskId Unique task identifier (keccak256 hash).
     */
    function submitTask(
        address agent,
        bytes calldata payload,
        address token,
        uint256 gross
    ) external payable returns (bytes32 taskId);

    /**
     * @notice Agent marks the task complete and supplies an execution proof.
     *         Net payment (99%) is released to the agent.
     * @param taskId    Task to complete.
     * @param proofHash keccak256 of the execution proof artifact.
     * @param result    ABI-encoded execution result.
     */
    function completeTask(
        bytes32 taskId,
        bytes32 proofHash,
        bytes calldata result
    ) external;

    /**
     * @notice Cancel a Pending task; net amount is refunded to submitter.
     *         The 1% fee already sent to treasury is NOT refunded.
     * @param taskId Task to cancel.
     */
    function cancelTask(bytes32 taskId) external;

    /// @notice Raise a dispute on a completed task.
    function disputeTask(bytes32 taskId) external;

    /// @notice Return full task details.
    function getTask(bytes32 taskId) external view returns (Task memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function NITRO_FEE_BPS()    external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
