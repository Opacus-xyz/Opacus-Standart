// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7755 — Kinetic Score On-Chain Reputation Standard
 * @notice Interface for an on-chain reputation registry where agents earn
 *         a 0–10 000 basis-point score from completed tasks, escrows, and
 *         ZK proofs. 1% of every registration fee → OPACUS_TREASURY.
 */
interface IERC7755 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    struct ScoreBreakdown {
        uint256 reputationBps;         // weight 40 %
        uint256 escrowSuccessRateBps;  // weight 30 %
        uint256 taskCompletionBps;     // weight 20 %
        uint256 teeUsageBps;           // weight  5 %
        uint256 ogComputeBps;          // weight  5 %
    }

    struct AgentScore {
        address  agent;
        bytes32  did;              // did:opacus:h3:… or hash(agent)
        uint256  weightedScore;    // 0–10 000 bps (100 bps = 1 %)
        ScoreBreakdown breakdown;
        bytes32  latestProofHash;  // ZK proof of threshold claim
        uint64   updatedAt;
        uint64   registeredAt;
        address  token;
        uint256  regFeeGross;
        uint256  regFeeAmount;     // 1% captured in constructor
        bool     exists;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event AgentRegistered(
        address indexed agent,
        bytes32 indexed did,
        uint256 feeAmount
    );
    event ScoreUpdated(
        address indexed agent,
        bytes32 indexed did,
        uint256 oldScore,
        uint256 newScore,
        bytes32 proofHash
    );
    event ThresholdVerified(
        address indexed agent,
        bytes32 indexed did,
        uint256 minScore,
        bool    passed
    );
    event AgentRemoved(address indexed agent);

    // ─── Core functions ───────────────────────────────────────────────────────

    /**
     * @notice Register an agent for Kinetic reputation tracking.
     *         1% fee → OPACUS_TREASURY; 99% held as participation bond.
     * @param did    Agent DID (bytes32 representation).
     * @param token  ERC-20 payment token (address(0) = ETH).
     * @param gross  Total registration fee.
     * @return did_  The stored DID.
     */
    function registerAgent(
        string calldata did,
        address token,
        uint256 gross
    ) external payable returns (string memory did_);

    /**
     * @notice Authorised oracle updates an agent's score breakdown.
     * @param agent      Agent wallet address.
     * @param breakdown  New ScoreBreakdown values (each in bps).
     * @param proofHash  keccak256 of the ZK proof bundle.
     */
    function updateScore(
        address agent,
        ScoreBreakdown calldata breakdown,
        bytes32 proofHash
    ) external;

    /**
     * @notice Check whether agent's score meets `minScore` (in bps).
     * @param agent     Agent to check.
     * @param minScore  Minimum weighted score required.
     * @return passed   True if agent.weightedScore >= minScore.
     */
    function verifyThreshold(address agent, uint256 minScore)
        external returns (bool passed);

    /**
     * @notice Remove agent and return the 99% bond.
     *         Only callable by the agent itself.
     */
    function removeAgent(address agent) external;

    /// @notice Register an authorised score oracle.
    function setOracle(address oracle, bool authorised) external;

    /// @notice Return full score record for `agent`.
    function getScore(address agent) external view returns (AgentScore memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function SCORE_FEE_BPS()    external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
