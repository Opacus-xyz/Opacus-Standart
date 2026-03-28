// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC7754 — Cross-Chain Mint Standard
 * @notice Interface for burn-and-mint cross-chain token transfers.
 *         1% of every bridged amount → OPACUS_TREASURY on the source chain.
 */
interface IERC7754 {
    // ─── Structs ──────────────────────────────────────────────────────────────
    enum TransferStatus { Initiated, Attested, Minted, Cancelled, Expired }

    struct CrossTransfer {
        address  sender;
        address  recipient;       // address on dest chain
        address  sourceToken;     // token burned / locked on source
        uint64   sourceChainId;
        uint64   destChainId;
        uint256  grossAmount;
        uint256  feeAmount;       // 1% to treasury at initiation
        uint256  netAmount;       // 99% bridged / minted
        bytes32  attestationHash; // relayer proof
        TransferStatus status;
        uint64   initiatedAt;
        uint64   mintedAt;
        uint64   expiresAt;
    }

    // ─── Events ───────────────────────────────────────────────────────────────
    event TransferInitiated(
        bytes32 indexed transferId,
        address indexed sender,
        address indexed recipient,
        uint64  destChainId,
        uint256 grossAmount,
        uint256 feeAmount
    );
    event TransferAttested(bytes32 indexed transferId, bytes32 attestationHash);
    event TransferMinted(bytes32 indexed transferId, uint256 netAmount);
    event TransferCancelled(bytes32 indexed transferId);

    // ─── Source-chain functions ───────────────────────────────────────────────

    /**
     * @notice Burn or lock `gross` tokens on the source chain and initiate
     *         a cross-chain mint. 1% fee → OPACUS_TREASURY immediately.
     * @param recipient     Wallet on the destination chain.
     * @param destChainId   EVM chain ID of the destination.
     * @param sourceToken   Token to burn/lock (address(0) = native ETH).
     * @param gross         Total amount the sender provides.
     * @param ttlSeconds    Seconds before transfer auto-expires.
     * @return transferId   Unique transfer identifier.
     */
    function initiateTransfer(
        address recipient,
        uint64  destChainId,
        address sourceToken,
        uint256 gross,
        uint64  ttlSeconds
    ) external payable returns (bytes32 transferId);

    /**
     * @notice Cancel an un-attested transfer and reclaim the net amount.
     *         Only callable after TTL expires or by sender before attestation.
     */
    function cancelTransfer(bytes32 transferId) external;

    // ─── Destination-chain functions ─────────────────────────────────────────

    /**
     * @notice Relayer submits cross-chain attestation (dst chain only).
     * @param transferId      Transfer to attest.
     * @param attestationHash keccak256 of relayer proof bundle.
     */
    function attestTransfer(bytes32 transferId, bytes32 attestationHash) external;

    /**
     * @notice Mint the net amount to the recipient on the destination chain.
     *         Only callable by an authorised minter after attestation.
     */
    function mintTransfer(bytes32 transferId) external;

    /// @notice Register an authorised relayer/minter.
    function setRelayer(address relayer, bool authorised) external;

    /// @notice Return full transfer details.
    function getTransfer(bytes32 transferId) external view returns (CrossTransfer memory);

    // ─── Protocol constants ───────────────────────────────────────────────────
    function MINT_FEE_BPS()     external pure returns (uint256); // 100
    function supportsInterface(bytes4 id) external view returns (bool);
}
