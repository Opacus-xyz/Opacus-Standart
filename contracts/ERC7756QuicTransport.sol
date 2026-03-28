// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7756}      from "./interfaces/IERC7756.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7756QuicTransport
 * @notice ⚡ Opacus QUIC Transport Registry — ERC-7756 reference implementation.
 *
 * PURPOSE
 * -------
 * On-chain directory of agent QUIC/HTTP3 transport endpoints.
 * Enables any smart contract or off-chain agent to discover the fastest
 * reachable endpoint for a peer — including eBPF/XDP kernel-bypass capable
 * peers that offer sub-20 µs latency for MEV bots and arbitrage agents.
 *
 * TRANSPORT MODES
 * ---------------
 *  0 Standard      — Regular QUIC/HTTP3 (Quinn, msquic, etc.)
 *  1 KernelBypass  — eBPF+XDP zero-copy, 8–20 µs end-to-end latency
 *  2 Datagram      — WebTransport datagrams (browser / edge workers)
 *
 * FEE MODEL
 * ---------
 * registerEndpoint(): 1% of grossAmount → OPACUS_TREASURY, 99% locked as bond.
 * deregisterEndpoint(): 99% bond returned to agent; fee is non-refundable.
 * updateEndpoint(): free, no value movement.
 */
contract ERC7756QuicTransport is IERC7756, OpacusFeeBase {

    // ─── ERC-165 ─────────────────────────────────────────────────────────────

    bytes4 private constant _INTERFACE_ID_ERC7756 = 0x51554943; // "QUIC"

    // ─── Storage ─────────────────────────────────────────────────────────────

    address public owner;

    /// agent wallet → endpoint record
    mapping(address => Endpoint) private _endpoints;
    /// agent wallet → bond token (address(0) = ETH)
    mapping(address => address)  private _bondToken;
    /// agent wallet → locked net bond amount
    mapping(address => uint256)  private _bond;

    /// flat list for pagination queries
    address[] private _agentList;
    /// lookup: is address in agentList?
    mapping(address => bool) private _inList;

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── Register ────────────────────────────────────────────────────────────

    /**
     * @inheritdoc IERC7756
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
    ) external payable override nonReentrant {
        require(bytes(quicEndpoint).length > 0, "ERC7756: empty quicEndpoint");
        require(!_inList[msg.sender] || _bond[msg.sender] == 0, "ERC7756: already registered");

        uint256 net;
        if (token == address(0)) {
            require(msg.value == grossAmount, "ERC7756: ETH mismatch");
            net = _collectETH(msg.sender, grossAmount);
        } else {
            require(msg.value == 0, "ERC7756: unexpected ETH");
            net = _collectERC20(token, msg.sender, grossAmount);
        }

        _endpoints[msg.sender] = Endpoint({
            agent:           msg.sender,
            quicEndpoint:    quicEndpoint,
            grpcEndpoint:    grpcEndpoint,
            mode:            mode,
            zeroRTT:         zeroRTT,
            kernelBypass:    kernelBypass,
            latencyBudgetUs: latencyBudgetUs,
            registeredAt:    uint64(block.timestamp),
            updatedAt:       uint64(block.timestamp)
        });

        _bondToken[msg.sender] = token;
        _bond[msg.sender]      = net;

        if (!_inList[msg.sender]) {
            _agentList.push(msg.sender);
            _inList[msg.sender] = true;
        }

        emit EndpointRegistered(msg.sender, quicEndpoint, mode, kernelBypass);
    }

    // ─── Update ──────────────────────────────────────────────────────────────

    /**
     * @inheritdoc IERC7756
     */
    function updateEndpoint(
        string  calldata quicEndpoint,
        string  calldata grpcEndpoint,
        TransportMode    mode,
        bool             zeroRTT,
        bool             kernelBypass,
        uint32           latencyBudgetUs
    ) external override {
        require(_inList[msg.sender], "ERC7756: not registered");
        require(bytes(quicEndpoint).length > 0, "ERC7756: empty quicEndpoint");

        Endpoint storage ep = _endpoints[msg.sender];
        ep.quicEndpoint    = quicEndpoint;
        ep.grpcEndpoint    = grpcEndpoint;
        ep.mode            = mode;
        ep.zeroRTT         = zeroRTT;
        ep.kernelBypass    = kernelBypass;
        ep.latencyBudgetUs = latencyBudgetUs;
        ep.updatedAt       = uint64(block.timestamp);

        emit EndpointUpdated(msg.sender, quicEndpoint, mode);
    }

    // ─── Deregister ──────────────────────────────────────────────────────────

    /**
     * @inheritdoc IERC7756
     */
    function deregisterEndpoint() external override nonReentrant {
        require(_inList[msg.sender], "ERC7756: not registered");

        uint256 bondAmt = _bond[msg.sender];
        address bondTok = _bondToken[msg.sender];

        _bond[msg.sender]      = 0;
        _bondToken[msg.sender] = address(0);
        delete _endpoints[msg.sender];

        if (bondAmt > 0) {
            if (bondTok == address(0)) {
                _sendETH(msg.sender, bondAmt);
            } else {
                _sendERC20(bondTok, msg.sender, bondAmt);
            }
        }

        emit EndpointDeregistered(msg.sender);
    }

    // ─── Read ────────────────────────────────────────────────────────────────

    /**
     * @inheritdoc IERC7756
     */
    function getEndpoint(address agent)
        external view override returns (Endpoint memory)
    {
        return _endpoints[agent];
    }

    /**
     * @inheritdoc IERC7756
     */
    function getKernelBypassAgents(uint256 offset, uint256 limit)
        external view override returns (Endpoint[] memory results)
    {
        uint256 count;
        uint256 total = _agentList.length;
        // count matching
        for (uint256 i = 0; i < total; i++) {
            if (_endpoints[_agentList[i]].kernelBypass) count++;
        }
        if (offset >= count) return new Endpoint[](0);
        uint256 resultLen = count - offset < limit ? count - offset : limit;
        results = new Endpoint[](resultLen);
        uint256 found; uint256 idx;
        for (uint256 i = 0; i < total && idx < resultLen; i++) {
            if (_endpoints[_agentList[i]].kernelBypass) {
                if (found >= offset) { results[idx++] = _endpoints[_agentList[i]]; }
                found++;
            }
        }
    }

    /**
     * @inheritdoc IERC7756
     */
    function getAgentsByLatency(uint32 maxLatencyUs, uint256 offset, uint256 limit)
        external view override returns (Endpoint[] memory results)
    {
        uint256 count;
        uint256 total = _agentList.length;
        for (uint256 i = 0; i < total; i++) {
            uint32 lat = _endpoints[_agentList[i]].latencyBudgetUs;
            if (lat > 0 && lat <= maxLatencyUs) count++;
        }
        if (offset >= count) return new Endpoint[](0);
        uint256 resultLen = count - offset < limit ? count - offset : limit;
        results = new Endpoint[](resultLen);
        uint256 found; uint256 idx;
        for (uint256 i = 0; i < total && idx < resultLen; i++) {
            uint32 lat = _endpoints[_agentList[i]].latencyBudgetUs;
            if (lat > 0 && lat <= maxLatencyUs) {
                if (found >= offset) { results[idx++] = _endpoints[_agentList[i]]; }
                found++;
            }
        }
    }

    /**
     * @inheritdoc IERC7756
     */
    function supportsInterface(bytes4 interfaceId)
        external pure override returns (bool)
    {
        return interfaceId == _INTERFACE_ID_ERC7756
            || interfaceId == 0x01ffc9a7; // ERC-165
    }

    // ─── Agent count ─────────────────────────────────────────────────────────

    function totalAgents() external view returns (uint256) {
        return _agentList.length;
    }

    function QUIC_FEE_BPS() external pure returns (uint256) {
        return FEE_BPS;
    }
}
