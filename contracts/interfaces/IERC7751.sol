// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7751 — H3 Geospatial Agent Routing Standard
 * @notice Interface for registering agents in a geospatial H3-indexed
 *         directory with QUIC endpoint binding and capability discovery.
 *         1% of every registration fee is forwarded to OPACUS_TREASURY.
 */
interface IERC7751 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    struct AgentRecord {
        address wallet;
        bytes32 h3Index;         // Uber H3 cell (resolution 8, FNV-1a of wallet)
        string  quicEndpoint;    // quic://region.0g.compute:4433
        bytes32[] capabilities;  // keccak256 of capability strings
        uint256 kineticScore;
        address token;
        uint256 regFeeGross;
        uint64  registeredAt;
        uint64  expiresAt;
        bool    active;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event AgentRegistered(
        address indexed wallet,
        bytes32 indexed h3Index,
        string  quicEndpoint,
        uint256 feeAmount
    );
    event AgentUpdated(address indexed wallet, bytes32 indexed h3Index);
    event AgentDeregistered(address indexed wallet);

    // ─── Core functions ───────────────────────────────────────────────────────

    /**
     * @notice Register an agent in the H3 routing table.
     *         1% of `gross` → OPACUS_TREASURY; 99% held as activation bond.
     * @param h3Index       Derived H3 cell for the agent's location.
     * @param quicEndpoint  QUIC/HTTP3 endpoint string.
     * @param capabilities  Array of keccak256-hashed capability strings.
     * @param token         ERC-20 token for payment (address(0) = ETH).
     * @param gross         Total registration fee.
     * @return did          Deterministic DID = hash(h3Index, wallet).
     */
    function registerAgent(
        bytes32 h3Index,
        string calldata quicEndpoint,
        bytes32[] calldata capabilities,
        address token,
        uint256 gross
    ) external payable returns (bytes32 did);

    /// @notice Update QUIC endpoint and capabilities (no extra fee).
    function updateAgent(
        bytes32 h3Index,
        string calldata quicEndpoint,
        bytes32[] calldata capabilities
    ) external;

    /// @notice Deregister and withdraw the 99% bond.
    function deregisterAgent() external;

    /**
     * @notice Discover agents matching a capability in an H3 region.
     * @param capability  keccak256 of capability string (e.g. keccak256("bridge")).
     * @param h3Near      Center H3 cell; pass bytes32(0) to search globally.
     * @param minScore    Minimum kineticScore (0–10 000 basis).
     * @param limit       Max results.
     * @return agents     Matching agent records.
     */
    function discoverAgents(
        bytes32 capability,
        bytes32 h3Near,
        uint256 minScore,
        uint256 limit
    ) external view returns (AgentRecord[] memory agents);

    /// @notice Return the full record for `wallet`.
    function getAgent(address wallet) external view returns (AgentRecord memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function H3_FEE_BPS()       external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
