// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  IERC7756 — Opacus QUIC Transport Registry
 * @notice Interface for the ERC-7756 on-chain QUIC endpoint registry.
 *
 * PURPOSE
 * -------
 * Agents that want to communicate via HTTP/3 + QUIC (or eBPF kernel-bypass
 * QUIC) advertise their transport endpoints on-chain.  Any other agent or
 * smart contract can discover the fastest reachable endpoint for a given
 * wallet address without trusting a centralised directory.
 *
 * KEY CONCEPTS
 * ------------
 * • quicEndpoint  — full QUIC URI, e.g. "quic://agent.example.com:4433"
 * • grpcEndpoint  — gRPC-over-HTTP3 URI for structured RPC
 * • kernelBypass  — flag: true = agent supports eBPF/XDP zero-copy path
 * • 0-RTT capable — flag: true = agent accepts QUIC 0-RTT early data
 * • latencyBudget — agent-declared SLA in microseconds (0 = no guarantee)
 *
 * FEE MODEL
 * ---------
 * registerEndpoint() collects a one-time 1%-fee registration bond.
 * updateEndpoint()   is free (no value movement).
 */
interface IERC7756 {

    // ─── Structs ─────────────────────────────────────────────────────────────

    enum TransportMode {
        Standard,       // Regular QUIC / HTTP3
        KernelBypass,   // eBPF + XDP zero-copy (sub-20 µs)
        Datagram        // WebTransport datagram mode (browser-compatible)
    }

    struct Endpoint {
        address     agent;
        string      quicEndpoint;   // e.g. "quic://agent.xyz:4433"
        string      grpcEndpoint;   // e.g. "https://agent.xyz:443" (gRPC-H3)
        TransportMode mode;
        bool        zeroRTT;        // supports QUIC 0-RTT early data
        bool        kernelBypass;   // supports eBPF/XDP path
        uint32      latencyBudgetUs;// declared SLA µs (0 = best-effort)
        uint64      registeredAt;
        uint64      updatedAt;
    }

    // ─── Events ──────────────────────────────────────────────────────────────

    event EndpointRegistered(
        address indexed agent,
        string  quicEndpoint,
        TransportMode mode,
        bool    kernelBypass
    );

    event EndpointUpdated(
        address indexed agent,
        string  quicEndpoint,
        TransportMode mode
    );

    event EndpointDeregistered(address indexed agent);

    // ─── Write ───────────────────────────────────────────────────────────────

    /**
     * @notice Register a QUIC transport endpoint.
     * @param quicEndpoint   QUIC URI string.
     * @param grpcEndpoint   gRPC-over-H3 URI (empty string if not supported).
     * @param mode           TransportMode enum value.
     * @param zeroRTT        Whether the agent accepts 0-RTT data.
     * @param kernelBypass   Whether the agent runs eBPF kernel-bypass.
     * @param latencyBudgetUs  Declared latency SLA in microseconds.
     * @param token          ERC-20 for registration bond; address(0) = ETH.
     * @param grossAmount    Gross bond amount (1% fee → treasury, 99% locked).
     */
    function registerEndpoint(
        string  calldata quicEndpoint,
        string  calldata grpcEndpoint,
        TransportMode    mode,
        bool             zeroRTT,
        bool             kernelBypass,
        uint32           latencyBudgetUs,
        address          token,
        uint256          grossAmount
    ) external payable;

    /**
     * @notice Update transport details. Free — no fee.
     */
    function updateEndpoint(
        string  calldata quicEndpoint,
        string  calldata grpcEndpoint,
        TransportMode    mode,
        bool             zeroRTT,
        bool             kernelBypass,
        uint32           latencyBudgetUs
    ) external;

    /**
     * @notice Remove endpoint and reclaim 99% of bond.
     */
    function deregisterEndpoint() external;

    // ─── Read ────────────────────────────────────────────────────────────────

    /**
     * @notice Get the endpoint record for an agent wallet.
     */
    function getEndpoint(address agent) external view returns (Endpoint memory);

    /**
     * @notice Discover all agents that support kernel-bypass mode.
     * @param offset  Pagination start index.
     * @param limit   Maximum results to return.
     */
    function getKernelBypassAgents(uint256 offset, uint256 limit)
        external view returns (Endpoint[] memory);

    /**
     * @notice Discover all agents with a latency SLA ≤ maxLatencyUs.
     */
    function getAgentsByLatency(uint32 maxLatencyUs, uint256 offset, uint256 limit)
        external view returns (Endpoint[] memory);

    /**
     * @notice ERC-165 support.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
