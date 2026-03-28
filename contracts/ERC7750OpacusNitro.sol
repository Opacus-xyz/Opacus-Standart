// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7750}      from "./interfaces/IERC7750.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7750OpacusNitro
 * @notice ⚡ Opacus Nitro Agent Execution Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On submitTask():
 *           fee     = gross × 1 %  → forwarded to OPACUS_TREASURY immediately
 *           net     = gross × 99 % → locked in this contract for the agent
 *
 *         On completeTask():
 *           net is released to the agent.
 *
 *         On cancelTask():
 *           net is refunded to the submitter (fee is NOT recoverable).
 */
contract ERC7750OpacusNitro is IERC7750, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7750 = 0x4e697472; // "Nitr"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;
    mapping(bytes32 => Task) private _tasks;
    uint256 private _nonce;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error TaskNotFound();
    error NotSubmitter();
    error NotAgent();
    error WrongStatus(TaskStatus current);
    error ZeroAmount();
    error EthMismatch();

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ─── IERC7750 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7750
    function submitTask(
        address agent,
        bytes calldata payload,
        address token,
        uint256 gross
    ) external payable override nonReentrant returns (bytes32 taskId) {
        if (gross == 0) revert ZeroAmount();

        uint256 net;
        if (token == address(0)) {
            // ETH path
            if (msg.value != gross) revert EthMismatch();
            net = _collectETH(msg.sender, gross);
        } else {
            // ERC-20 path
            net = _collectERC20(token, msg.sender, gross);
        }

        (uint256 fee,) = _splitFee(gross);
        taskId = keccak256(abi.encodePacked(msg.sender, agent, block.timestamp, _nonce++));

        _tasks[taskId] = Task({
            submitter:   msg.sender,
            agent:       agent,
            token:       token,
            grossAmount: gross,
            feeAmount:   fee,
            netAmount:   net,
            proofHash:   bytes32(0),
            status:      TaskStatus.Pending,
            createdAt:   uint64(block.timestamp),
            completedAt: 0
        });

        emit TaskSubmitted(taskId, msg.sender, agent, token, gross, fee);
    }

    /// @inheritdoc IERC7750
    function completeTask(
        bytes32 taskId,
        bytes32 proofHash,
        bytes calldata /*result*/
    ) external override nonReentrant {
        Task storage t = _tasks[taskId];
        if (t.submitter == address(0)) revert TaskNotFound();
        if (msg.sender != t.agent)     revert NotAgent();
        if (t.status != TaskStatus.Pending && t.status != TaskStatus.Active)
            revert WrongStatus(t.status);

        t.proofHash   = proofHash;
        t.status      = TaskStatus.Completed;
        t.completedAt = uint64(block.timestamp);

        // Release net to agent
        if (t.token == address(0)) {
            _sendETH(t.agent, t.netAmount);
        } else {
            _sendERC20(t.token, t.agent, t.netAmount);
        }

        emit TaskCompleted(taskId, proofHash);
    }

    /// @inheritdoc IERC7750
    function cancelTask(bytes32 taskId) external override nonReentrant {
        Task storage t = _tasks[taskId];
        if (t.submitter == address(0)) revert TaskNotFound();
        if (msg.sender != t.submitter) revert NotSubmitter();
        if (t.status != TaskStatus.Pending) revert WrongStatus(t.status);

        t.status = TaskStatus.Cancelled;

        // Refund net to submitter — fee already gone to treasury
        if (t.token == address(0)) {
            _sendETH(t.submitter, t.netAmount);
        } else {
            _sendERC20(t.token, t.submitter, t.netAmount);
        }

        emit TaskCancelled(taskId, t.submitter);
    }

    /// @inheritdoc IERC7750
    function disputeTask(bytes32 taskId) external override {
        Task storage t = _tasks[taskId];
        if (t.submitter == address(0)) revert TaskNotFound();
        if (msg.sender != t.submitter && msg.sender != t.agent)
            revert NotSubmitter();
        if (t.status == TaskStatus.Completed ||
            t.status == TaskStatus.Pending   ||
            t.status == TaskStatus.Active) {
            t.status = TaskStatus.Disputed;
            emit TaskDisputed(taskId, msg.sender);
        } else {
            revert WrongStatus(t.status);
        }
    }

    /// @inheritdoc IERC7750
    function getTask(bytes32 taskId) external view override returns (Task memory) {
        return _tasks[taskId];
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function NITRO_FEE_BPS()   external pure override returns (uint256) { return FEE_BPS; }

    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7750 ||
               id == 0x01ffc9a7; // ERC-165
    }

    receive() external payable {}
}
