// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7755}      from "./interfaces/IERC7755.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7755KineticScore
 * @notice 🏆 On-Chain Kinetic Reputation Score Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On registerAgent():
 *           fee  = gross × 1 %  → OPACUS_TREASURY (instant)
 *           bond = gross × 99 % → held until removeAgent()
 *
 *         Score weights (must sum to 100):
 *           reputationBps        → 40 %
 *           escrowSuccessRateBps → 30 %
 *           taskCompletionBps    → 20 %
 *           teeUsageBps          →  5 %
 *           ogComputeBps         →  5 %
 *
 *         Score range: 0 – 10 000 (basis points, 10 000 = perfect 100 %)
 *         Oracle registry managed by owner.
 */
contract ERC7755KineticScore is IERC7755, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7755 = 0x4b534b53; // "KSKS"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;

    mapping(address => AgentScore) private _scores;
    mapping(address => uint256)    private _bondNet;  // 99% bond per agent
    mapping(address => bool)       private _oracles;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error NotOracle();
    error NotRegistered();
    error AlreadyRegistered();
    error ZeroAmount();
    error EthMismatch();
    error InvalidBreakdown();

    constructor() { owner = msg.sender; }

    modifier onlyOwner()  { if (msg.sender != owner)         revert NotOwner();  _; }
    modifier onlyOracle() { if (!_oracles[msg.sender])       revert NotOracle(); _; }

    // ─── IERC7755 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7755
    function registerAgent(
        string calldata did,
        address token,
        uint256 gross
    ) external payable override nonReentrant returns (string memory did_) {
        if (_scores[msg.sender].exists)  revert AlreadyRegistered();
        if (gross == 0)                  revert ZeroAmount();

        uint256 fee;
        uint256 bond;
        if (token == address(0)) {
            if (msg.value != gross) revert EthMismatch();
            bond = _collectETH(msg.sender, gross);
        } else {
            bond = _collectERC20(token, msg.sender, gross);
        }
        (fee,) = _splitFee(gross);

        bytes32 didHash = keccak256(bytes(did));

        ScoreBreakdown memory empty;

        _scores[msg.sender] = AgentScore({
            agent:           msg.sender,
            did:             didHash,
            weightedScore:   0,
            breakdown:       empty,
            latestProofHash: bytes32(0),
            registeredAt:    uint64(block.timestamp),
            updatedAt:       uint64(block.timestamp),
            token:           token,
            regFeeGross:     gross,
            regFeeAmount:    fee,
            exists:          true
        });
        _bondNet[msg.sender] = bond;

        emit AgentRegistered(msg.sender, didHash, fee);
        did_ = did;
    }

    /// @inheritdoc IERC7755
    function updateScore(
        address agent,
        ScoreBreakdown calldata breakdown,
        bytes32 proofHash
    ) external override onlyOracle {
        AgentScore storage s = _scores[agent];
        if (!s.exists) revert NotRegistered();

        // Verify weights sum to exactly 10 000 (100 %)
        uint256 sum = breakdown.reputationBps
                    + breakdown.escrowSuccessRateBps
                    + breakdown.taskCompletionBps
                    + breakdown.teeUsageBps
                    + breakdown.ogComputeBps;
        if (sum != 10_000) revert InvalidBreakdown();

        uint256 oldScore = s.weightedScore;
        uint256 weighted =
            (breakdown.reputationBps        * 40 +
             breakdown.escrowSuccessRateBps * 30 +
             breakdown.taskCompletionBps    * 20 +
             breakdown.teeUsageBps          *  5 +
             breakdown.ogComputeBps         *  5) / 100;

        s.breakdown       = breakdown;
        s.weightedScore   = weighted;
        s.latestProofHash = proofHash;
        s.updatedAt       = uint64(block.timestamp);

        emit ScoreUpdated(agent, s.did, oldScore, weighted, proofHash);
    }

    /// @inheritdoc IERC7755
    function verifyThreshold(address agent, uint256 minScore) external override returns (bool ok) {
        AgentScore storage s = _scores[agent];
        if (!s.exists) return false;
        ok = s.weightedScore >= minScore;
        emit ThresholdVerified(agent, s.did, minScore, ok);
    }

    /// @inheritdoc IERC7755
    function removeAgent(address agent) external override nonReentrant {
        // Allow only owner or the agent themselves
        if (msg.sender != owner && msg.sender != agent) revert NotOwner();
        AgentScore storage s = _scores[agent];
        if (!s.exists) revert NotRegistered();

        s.exists = false;
        uint256 bond = _bondNet[agent];
        _bondNet[agent] = 0;

        if (s.token == address(0)) {
            _sendETH(agent, bond);
        } else {
            _sendERC20(s.token, agent, bond);
        }

        emit AgentRemoved(agent);
    }

    /// @inheritdoc IERC7755
    function setOracle(address oracle, bool allowed) external override onlyOwner {
        _oracles[oracle] = allowed;
    }

    /// @inheritdoc IERC7755
    function getScore(address agent) external view override returns (AgentScore memory) {
        return _scores[agent];
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function SCORE_FEE_BPS()   external pure override returns (uint256) { return FEE_BPS; }
    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7755 || id == 0x01ffc9a7;
    }

    receive() external payable {}
}
