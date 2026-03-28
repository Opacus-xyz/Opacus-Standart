// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7754}      from "./interfaces/IERC7754.sol";
import {OpacusFeeBase} from "./lib/OpacusFeeBase.sol";

/**
 * @title  ERC7754CrossChainMint
 * @notice 💸 Cross-Chain Token Mint Standard — reference implementation.
 *
 *         Fee model
 *         ─────────
 *         On initiateTransfer() (source chain):
 *           fee = gross × 1 %  → OPACUS_TREASURY (instant)
 *           net = gross × 99 % → locked in contract (burn-equivalent)
 *
 *         Destination chain flow:
 *           1. Relayer calls attestTransfer() with zk/oracle proof
 *           2. Minter calls mintTransfer() to release net to recipient
 *
 *         Both relayer and minter registries are managed by owner.
 */
contract ERC7754CrossChainMint is IERC7754, OpacusFeeBase {
    // ─── ERC-165 ──────────────────────────────────────────────────────────────
    bytes4 private constant _INTERFACE_ID_ERC7754 = 0x43584d54; // "CXMT"

    // ─── State ────────────────────────────────────────────────────────────────
    address public owner;
    uint256 private _nonce;

    mapping(bytes32  => CrossTransfer) private _transfers;
    mapping(address  => bool)          private _relayers;
    mapping(address  => bool)          private _minters;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error TransferNotFound();
    error NotRelayer();
    error NotMinter();
    error NotSender();
    error WrongStatus(TransferStatus current);
    error ZeroAmount();
    error EthMismatch();
    error Expired();

    constructor() { owner = msg.sender; }

    modifier onlyOwner()   { if (msg.sender != owner)          revert NotOwner();    _; }
    modifier onlyRelayer() { if (!_relayers[msg.sender])       revert NotRelayer();  _; }
    modifier onlyMinter()  { if (!_minters[msg.sender])        revert NotMinter();   _; }

    // ─── IERC7754 ─────────────────────────────────────────────────────────────

    /// @inheritdoc IERC7754
    function initiateTransfer(
        address recipient,
        uint64  destChainId,
        address sourceToken,
        uint256 gross,
        uint64  ttlSeconds
    ) external payable override nonReentrant returns (bytes32 transferId) {
        if (gross == 0) revert ZeroAmount();

        uint256 net;
        uint256 fee;
        if (sourceToken == address(0)) {
            if (msg.value != gross) revert EthMismatch();
            net = _collectETH(msg.sender, gross);
        } else {
            net = _collectERC20(sourceToken, msg.sender, gross);
        }
        (fee,) = _splitFee(gross);

        transferId = keccak256(abi.encodePacked(msg.sender, recipient, block.timestamp, ++_nonce));

        _transfers[transferId] = CrossTransfer({
            sender:           msg.sender,
            recipient:        recipient,
            sourceToken:      sourceToken,
            sourceChainId:    uint64(block.chainid),
            destChainId:      destChainId,
            grossAmount:      gross,
            feeAmount:        fee,
            netAmount:        net,
            attestationHash:  bytes32(0),
            status:           TransferStatus.Initiated,
            initiatedAt:      uint64(block.timestamp),
            mintedAt:         0,
            expiresAt:        uint64(block.timestamp + ttlSeconds)
        });

        emit TransferInitiated(transferId, msg.sender, recipient, destChainId, gross, fee);
    }

    /// @inheritdoc IERC7754
    function cancelTransfer(bytes32 transferId) external override nonReentrant {
        CrossTransfer storage xfer = _transfers[transferId];
        if (xfer.sender == address(0))                  revert TransferNotFound();
        if (xfer.sender != msg.sender)                  revert NotSender();
        if (xfer.status != TransferStatus.Initiated)    revert WrongStatus(xfer.status);

        xfer.status      = TransferStatus.Cancelled;
        xfer.mintedAt    = uint64(block.timestamp);

        if (xfer.sourceToken == address(0)) {
            _sendETH(xfer.sender, xfer.netAmount);
        } else {
            _sendERC20(xfer.sourceToken, xfer.sender, xfer.netAmount);
        }

        emit TransferCancelled(transferId);
    }

    /// @inheritdoc IERC7754
    function attestTransfer(bytes32 transferId, bytes32 attestationHash)
        external override onlyRelayer
    {
        CrossTransfer storage xfer = _transfers[transferId];
        if (xfer.sender == address(0))                   revert TransferNotFound();
        if (xfer.status != TransferStatus.Initiated)     revert WrongStatus(xfer.status);
        if (block.timestamp > xfer.expiresAt)            revert Expired();

        xfer.attestationHash = attestationHash;
        xfer.status          = TransferStatus.Attested;

        emit TransferAttested(transferId, attestationHash);
    }

    /// @inheritdoc IERC7754
    function mintTransfer(bytes32 transferId) external override nonReentrant onlyMinter {
        CrossTransfer storage xfer = _transfers[transferId];
        if (xfer.sender == address(0))                  revert TransferNotFound();
        if (xfer.status != TransferStatus.Attested)     revert WrongStatus(xfer.status);

        xfer.status   = TransferStatus.Minted;
        xfer.mintedAt = uint64(block.timestamp);

        // On destination chain: net is minted/released to recipient.
        // In this single-chain reference implementation, we release the locked net.
        if (xfer.sourceToken == address(0)) {
            _sendETH(xfer.recipient, xfer.netAmount);
        } else {
            _sendERC20(xfer.sourceToken, xfer.recipient, xfer.netAmount);
        }

        emit TransferMinted(transferId, xfer.netAmount);
    }

    /// @inheritdoc IERC7754
    function setRelayer(address relayer, bool allowed) external override onlyOwner {
        _relayers[relayer] = allowed;
    }

    /// @inheritdoc IERC7754
    function getTransfer(bytes32 transferId) external view override returns (CrossTransfer memory) {
        return _transfers[transferId];
    }

    // ─── Admin ────────────────────────────────────────────────────────────────
    function setMinter(address minter, bool allowed) external onlyOwner {
        _minters[minter] = allowed;
    }

    // ─── Protocol constants ───────────────────────────────────────────────────

    function MINT_FEE_BPS()    external pure override returns (uint256) { return FEE_BPS; }
    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == _INTERFACE_ID_ERC7754 || id == 0x01ffc9a7;
    }

    receive() external payable {}
}
