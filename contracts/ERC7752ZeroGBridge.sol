// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7752}      from "./interfaces/IERC7752.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7752ZeroGBridge
 * @notice 💾 0G Cross-Chain Bridge Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On submitIntent():
 *           fee = gross × 1 %  → OPACUS_TREASURY (instant)
 *           net = gross × 99 % → held until fulfillIntent() or cancelIntent()
 *
 *         Fulfiller registry: trusted relayers set by owner.
 *         Off-chain relayers watch IntentSubmitted, execute cross-chain
 *         transfer, then call fulfillIntent() with proof.
 */
contract ERC7752ZeroGBridge is IERC7752, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7752 = 0x30474252; // "0GBR"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;
    uint256 private _nonce;

    mapping(bytes32 => BridgeIntent)   private _intents;
    mapping(address  => bool)          private _fulfillers;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error IntentNotFound();
    error NotFulfiller();
    error NotSubmitter();
    error WrongStatus(IntentStatus current);
    error ZeroAmount();
    error EthMismatch();
    error Expired();

    constructor() { owner = msg.sender; }

    modifier onlyOwner()     { if (msg.sender != owner)            revert NotOwner();    _; }
    modifier onlyFulfiller() { if (!_fulfillers[msg.sender])       revert NotFulfiller(); _; }

    // ─── IERC7752 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7752
    function submitIntent(
        IntentType intentType,
        bytes calldata payload,
        uint64 destChainId,
        uint64 ttlSeconds,
        address token,
        uint256 gross
    ) external payable override nonReentrant returns (bytes32 intentId) {
        if (gross == 0)              revert ZeroAmount();

        uint256 net;
        uint256 fee;
        if (token == address(0)) {
            if (msg.value != gross) revert EthMismatch();
            net = _collectETH(msg.sender, gross);
        } else {
            net = _collectERC20(token, msg.sender, gross);
        }
        (fee,) = _splitFee(gross);

        intentId = keccak256(abi.encodePacked(msg.sender, block.timestamp, ++_nonce));

        _intents[intentId] = BridgeIntent({
            submitter:   msg.sender,
            intentType:  intentType,
            payload:     payload,
            sourceChainId: uint64(block.chainid),
            destChainId: destChainId,
            token:       token,
            grossAmount: gross,
            feeAmount:   fee,
            netAmount:   net,
            proofHash:   bytes32(0),
            status:      IntentStatus.Pending,
            createdAt:   uint64(block.timestamp),
            fulfilledAt: 0,
            ttl:         uint64(block.timestamp + ttlSeconds)
        });

        emit IntentSubmitted(intentId, msg.sender, intentType, destChainId, gross, fee);
    }

    /// @notice Fulfil an intent; release net to fulfiller.
    function fulfillIntent(bytes32 intentId, bytes32 proofHash) external override nonReentrant onlyFulfiller {
        BridgeIntent storage intent = _intents[intentId];
        if (intent.submitter == address(0))          revert IntentNotFound();
        if (intent.status != IntentStatus.Pending)   revert WrongStatus(intent.status);
        if (block.timestamp > intent.ttl)      revert Expired();

        intent.status      = IntentStatus.Fulfilled;
        intent.proofHash   = proofHash;
        intent.fulfilledAt = uint64(block.timestamp);

        if (intent.token == address(0)) {
            _sendETH(msg.sender, intent.netAmount);
        } else {
            _sendERC20(intent.token, msg.sender, intent.netAmount);
        }

        emit IntentFulfilled(intentId, proofHash, "");
    }

    /// @inheritdoc IERC7752
    function cancelIntent(bytes32 intentId) external override nonReentrant {
        BridgeIntent storage intent = _intents[intentId];
        if (intent.submitter == address(0))           revert IntentNotFound();
        if (intent.submitter != msg.sender)           revert NotSubmitter();
        if (intent.status != IntentStatus.Pending)    revert WrongStatus(intent.status);

        intent.status = IntentStatus.Cancelled;

        if (intent.token == address(0)) {
            _sendETH(intent.submitter, intent.netAmount);
        } else {
            _sendERC20(intent.token, intent.submitter, intent.netAmount);
        }

        emit IntentCancelled(intentId);
    }

    /// @inheritdoc IERC7752
    function setFulfiller(address fulfiller, bool allowed) external override onlyOwner {
        _fulfillers[fulfiller] = allowed;
    }

    /// @inheritdoc IERC7752
    function getIntent(bytes32 intentId) external view override returns (BridgeIntent memory) {
        return _intents[intentId];
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function BRIDGE_FEE_BPS()  external pure override returns (uint256) { return FEE_BPS; }
    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7752 || id == 0x01ffc9a7;
    }

    receive() external payable {}
}
