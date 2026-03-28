// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7751}      from "./interfaces/IERC7751.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7751H3Routing
 * @notice 📍 H3 Geospatial Agent Routing Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On registerAgent():
 *           fee  = gross × 1 %  → OPACUS_TREASURY
 *           bond = gross × 99 % → held; returned on deregisterAgent()
 */
contract ERC7751H3Routing is IERC7751, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7751 = 0x48335230; // "H3R0"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;
    mapping(address => AgentRecord) private _agents;
    address[] private _agentList;      // for enumeration in discoverAgents

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error AlreadyRegistered();
    error NotRegistered();
    error ZeroAmount();
    error EthMismatch();

    constructor() { owner = msg.sender; }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ─── IERC7751 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7751
    function registerAgent(
        bytes32 h3Index,
        string calldata quicEndpoint,
        bytes32[] calldata capabilities,
        address token,
        uint256 gross
    ) external payable override nonReentrant returns (bytes32 did) {
        if (_agents[msg.sender].active) revert AlreadyRegistered();
        if (gross == 0) revert ZeroAmount();

        uint256 bond;
        uint256 fee;
        if (token == address(0)) {
            if (msg.value != gross) revert EthMismatch();
            bond = _collectETH(msg.sender, gross);
        } else {
            bond = _collectERC20(token, msg.sender, gross);
        }
        (fee,) = _splitFee(gross);

        did = keccak256(abi.encodePacked(h3Index, msg.sender));

        _agents[msg.sender] = AgentRecord({
            wallet:        msg.sender,
            h3Index:       h3Index,
            quicEndpoint:  quicEndpoint,
            capabilities:  capabilities,
            kineticScore:  0,
            token:         token,
            regFeeGross:   gross,
            registeredAt:  uint64(block.timestamp),
            expiresAt:     uint64(block.timestamp + 365 days),
            active:        true
        });
        _agentList.push(msg.sender);

        emit AgentRegistered(msg.sender, h3Index, quicEndpoint, fee);
    }

    /// @inheritdoc IERC7751
    function updateAgent(
        bytes32 h3Index,
        string calldata quicEndpoint,
        bytes32[] calldata capabilities
    ) external override {
        if (!_agents[msg.sender].active) revert NotRegistered();
        AgentRecord storage rec = _agents[msg.sender];
        rec.h3Index      = h3Index;
        rec.quicEndpoint = quicEndpoint;
        rec.capabilities = capabilities;
        emit AgentUpdated(msg.sender, h3Index);
    }

    /// @inheritdoc IERC7751
    function deregisterAgent() external override nonReentrant {
        AgentRecord storage rec = _agents[msg.sender];
        if (!rec.active) revert NotRegistered();

        rec.active = false;
        (, uint256 bond) = _splitFee(rec.regFeeGross);

        if (rec.token == address(0)) {
            _sendETH(msg.sender, bond);
        } else {
            _sendERC20(rec.token, msg.sender, bond);
        }

        emit AgentDeregistered(msg.sender);
    }

    /// @inheritdoc IERC7751
    function discoverAgents(
        bytes32 capability,
        bytes32 /*h3Near*/,   // proximity filtering is off-chain in V1
        uint256 minScore,
        uint256 limit
    ) external view override returns (AgentRecord[] memory agents) {
        uint256 count;
        address[] memory tmp = new address[](_agentList.length);

        for (uint256 i; i < _agentList.length; i++) {
            AgentRecord storage rec = _agents[_agentList[i]];
            if (!rec.active) continue;
            if (rec.kineticScore < minScore) continue;
            bool hasCap;
            for (uint256 j; j < rec.capabilities.length; j++) {
                if (rec.capabilities[j] == capability) { hasCap = true; break; }
            }
            if (!hasCap) continue;
            tmp[count++] = _agentList[i];
            if (count == limit) break;
        }

        agents = new AgentRecord[](count);
        for (uint256 i; i < count; i++) agents[i] = _agents[tmp[i]];
    }

    /// @inheritdoc IERC7751
    function getAgent(address wallet) external view override returns (AgentRecord memory) {
        return _agents[wallet];
    }

    // ─── Admin: update kinetic score (called by ERC-7755 oracle) ──────────────
    function setKineticScore(address agent, uint256 score) external onlyOwner {
        _agents[agent].kineticScore = score;
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function H3_FEE_BPS()      external pure override returns (uint256) { return FEE_BPS; }
    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7751 || id == 0x01ffc9a7;
    }

    receive() external payable {}
}
