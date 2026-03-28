// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7753}      from "./interfaces/IERC7753.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7753EscrowV2
 * @notice 🔒 Proof-Based Escrow V2 Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On createEscrow():
 *           fee = gross × 1 %  → OPACUS_TREASURY (instant)
 *           net = gross × 99 % → locked until release, refund, or arbitration
 *
 *         Arbitration: owner sets arbitrator address.
 *         The arbitrator can resolveDispute(id, releaseToCounterparty: bool).
 */
contract ERC7753EscrowV2 is IERC7753, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7753 = 0x45737632; // "Esv2"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;
    address public arbitrator;
    uint256 private _nonce;

    mapping(bytes32 => Escrow) private _escrows;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error EscrowNotFound();
    error NotCreator();
    error NotCounterparty();
    error NotArbitrator();
    error WrongStatus(EscrowStatus current);
    error ZeroAmount();
    error EthMismatch();
    error NotExpiredYet();

    constructor() { owner = msg.sender; }

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

    // ─── IERC7753 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7753
    function createEscrow(
        address counterparty,
        string calldata description,
        address token,
        uint256 gross,
        uint64 ttlSeconds
    ) external payable override nonReentrant returns (bytes32 escrowId) {
        if (gross == 0) revert ZeroAmount();

        uint256 net;
        uint256 fee;
        if (token == address(0)) {
            if (msg.value != gross) revert EthMismatch();
            net = _collectETH(msg.sender, gross);
        } else {
            net = _collectERC20(token, msg.sender, gross);
        }
        (fee,) = _splitFee(gross);

        escrowId = keccak256(abi.encodePacked(msg.sender, counterparty, block.timestamp, ++_nonce));

        _escrows[escrowId] = Escrow({
            creator:       msg.sender,
            counterparty:  counterparty,
            token:         token,
            grossAmount:   gross,
            feeAmount:     fee,
            netAmount:     net,
            conditionHash: keccak256(bytes(description)),
            proofHash:     bytes32(0),
            status:        EscrowStatus.Locked,
            lockedAt:      uint64(block.timestamp),
            settledAt:     0,
            expiresAt:     uint64(block.timestamp + ttlSeconds),
            description:   description
        });

        emit EscrowCreated(escrowId, msg.sender, counterparty, token, gross, fee);
    }

    /// @inheritdoc IERC7753
    function releaseEscrow(bytes32 escrowId, bytes32 proofHash) external override nonReentrant {
        Escrow storage esc = _escrows[escrowId];
        if (esc.creator == address(0))              revert EscrowNotFound();
        if (esc.creator != msg.sender)              revert NotCreator();
        if (esc.status != EscrowStatus.Locked)      revert WrongStatus(esc.status);

        esc.status     = EscrowStatus.Released;
        esc.proofHash  = proofHash;
        esc.settledAt  = uint64(block.timestamp);

        if (esc.token == address(0)) {
            _sendETH(esc.counterparty, esc.netAmount);
        } else {
            _sendERC20(esc.token, esc.counterparty, esc.netAmount);
        }

        emit EscrowReleased(escrowId, proofHash, esc.counterparty);
    }

    /// @inheritdoc IERC7753
    function refundEscrow(bytes32 escrowId) external override nonReentrant {
        Escrow storage esc = _escrows[escrowId];
        if (esc.creator == address(0))           revert EscrowNotFound();
        if (esc.status != EscrowStatus.Locked)   revert WrongStatus(esc.status);

        bool isCounterparty = msg.sender == esc.counterparty;
        bool isCreatorAfterExpiry = (msg.sender == esc.creator &&
                                     block.timestamp > esc.expiresAt);

        if (!isCounterparty && !isCreatorAfterExpiry) revert NotExpiredYet();

        esc.status    = EscrowStatus.Refunded;
        esc.settledAt = uint64(block.timestamp);

        if (esc.token == address(0)) {
            _sendETH(esc.creator, esc.netAmount);
        } else {
            _sendERC20(esc.token, esc.creator, esc.netAmount);
        }

        emit EscrowRefunded(escrowId, esc.creator);
    }

    /// @inheritdoc IERC7753
    function disputeEscrow(bytes32 escrowId) external override {
        Escrow storage esc = _escrows[escrowId];
        if (esc.creator == address(0))          revert EscrowNotFound();
        if (esc.status != EscrowStatus.Locked)  revert WrongStatus(esc.status);
        if (msg.sender != esc.creator && msg.sender != esc.counterparty)
            revert NotCreator();

        esc.status = EscrowStatus.Disputed;
        emit EscrowDisputed(escrowId, msg.sender);
    }

    /// @inheritdoc IERC7753
    function resolveDispute(bytes32 escrowId, bool releaseToCounterparty) external override nonReentrant {
        if (msg.sender != arbitrator) revert NotArbitrator();
        Escrow storage esc = _escrows[escrowId];
        if (esc.creator == address(0))           revert EscrowNotFound();
        if (esc.status != EscrowStatus.Disputed) revert WrongStatus(esc.status);

        esc.status    = EscrowStatus.Resolved;
        esc.settledAt = uint64(block.timestamp);

        address recipient = releaseToCounterparty ? esc.counterparty : esc.creator;
        if (esc.token == address(0)) {
            _sendETH(recipient, esc.netAmount);
        } else {
            _sendERC20(esc.token, recipient, esc.netAmount);
        }

        emit EscrowResolved(escrowId, releaseToCounterparty);
    }

    /// @inheritdoc IERC7753
    function setArbitrator(address _arbitrator) external override onlyOwner {
        arbitrator = _arbitrator;
    }

    /// @inheritdoc IERC7753
    function getEscrow(bytes32 escrowId) external view override returns (Escrow memory) {
        return _escrows[escrowId];
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function ESCROW_FEE_BPS()  external pure override returns (uint256) { return FEE_BPS; }
    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7753 || id == 0x01ffc9a7;
    }

    receive() external payable {}
}
