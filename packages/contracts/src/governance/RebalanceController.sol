// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IStockTokenVerifier} from "./IStockTokenVerifier.sol";
import {IRebalanceWeights} from "../basket/IRebalanceWeights.sol";

/// @notice Basket policy contract for a ROTATING basket (D033). Launches with the five
///         founding constituents at 2,000 bps; REBALANCE_ROLE may add and remove constituents
///         through the timelock (each removal requires a published onchain reason), previously
///         removed stocks may be re-admitted, and the basket can never rotate below
///         MIN_CONSTITUENTS or above MAX_CONSTITUENTS. Rotation only redirects FUTURE fee
///         purchases: historical purchases, entitlements and claims are token-address-keyed
///         and never change. Equal weighting across active constituents sums to exactly
///         10,000 bps. It holds no funds.
contract RebalanceController is AccessControl, IRebalanceWeights {
    uint8 public constant MAX_CONSTITUENTS = 8;
    uint8 public constant MIN_CONSTITUENTS = 5;
    uint8 public constant FOUNDING_COUNT = 5;
    uint16 public constant TARGET_TOTAL_BPS = 10_000;
    uint16 public constant FOUNDING_WEIGHT_BPS = 2_000;

    bytes32 public constant REBALANCE_ROLE = keccak256("REBALANCE_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 public immutable timelockDelay;
    IStockTokenVerifier public immutable verifier;

    address[] public basket;
    mapping(address => uint256) public admittedAt;
    mapping(address => bool) public wasAdmitted;
    mapping(address => bool) public isActive;

    struct PendingChange {
        bool exists;
        bool isRemoval;
        uint256 index;
        address token;
        uint64 submittedAt;
    }
    PendingChange internal _pending;

    event ConstituentProposed(address indexed token, uint256 submittedAt);
    event RemovalProposed(uint256 index, address indexed token, uint256 submittedAt, string reason);
    event ConstituentAdmitted(address indexed token, uint256 activeCount, uint256 submittedAt);
    event ConstituentRemoved(uint256 index, address indexed token, uint256 submittedAt);

    constructor(address[] memory founding, IStockTokenVerifier verifier_, uint256 timelockDelay_) {
        require(address(verifier_) != address(0), "REBAL: zero verifier");
        require(timelockDelay_ > 0, "REBAL: zero delay");
        require(founding.length == FOUNDING_COUNT, "REBAL: need 5 founding");

        verifier = verifier_;
        timelockDelay = timelockDelay_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < founding.length; i++) {
            address t = founding[i];
            require(t != address(0), "REBAL: zero founding");
            require(!wasAdmitted[t], "REBAL: duplicate founding");
            require(verifier_.isVerifiedCanonicalToken(t), "REBAL: founding unverified");
            _pushConstituent(t);
        }
        uint16[] memory w = weights();
        uint256 total;
        for (uint256 i = 0; i < w.length; i++) {
            total += w[i];
        }
        require(total == TARGET_TOTAL_BPS, "REBAL: launch weights != 10000");
    }

    function activeCount() public view returns (uint256) {
        return basket.length;
    }

    function getBasket() external view returns (address[] memory) {
        return basket;
    }

    function pending() external view returns (bool exists, bool isRemoval, uint256 index, address token, uint64 submittedAt) {
        PendingChange storage p = _pending;
        return (p.exists, p.isRemoval, p.index, p.token, p.submittedAt);
    }

    /// @notice Deterministic equal weights across all active constituents.
    function weights() public view returns (uint16[] memory) {
        uint256 n = basket.length;
        uint16[] memory w = new uint16[](n);
        if (n == 0) return w;
        uint256 base = TARGET_TOTAL_BPS / n;
        uint256 residue = TARGET_TOTAL_BPS % n;
        for (uint256 i = 0; i < n; i++) {
            w[i] = uint16(base + (i < residue ? 1 : 0));
        }
        return w;
    }

    /// @notice Propose adding a constituent (rotation-in, D033). Re-admission of a previously
    ///         removed stock is allowed; it must simply not be active right now and must pass
    ///         canonical verification again.
    function proposeAddition(address token) external onlyRole(REBALANCE_ROLE) {
        require(token != address(0), "REBAL: zero token");
        require(!isActive[token], "REBAL: already active");
        require(basket.length < MAX_CONSTITUENTS, "REBAL: at ceiling");
        require(verifier.isVerifiedCanonicalToken(token), "REBAL: unverified token");
        require(!_pending.exists, "REBAL: pending exists");

        _pending = PendingChange(true, false, 0, token, uint64(block.timestamp));
        emit ConstituentProposed(token, block.timestamp);
    }

    /// @notice Propose removing a constituent (rotation-out, D033). Routine rotation and
    ///         emergency delisting share one path: REBALANCE_ROLE or EMERGENCY_ROLE, a public
    ///         onchain reason, the timelock, and the MIN_CONSTITUENTS floor. Removal never
    ///         touches historical purchases or entitlements — it only stops future buying.
    function proposeRemoval(uint256 index, string calldata reason) external {
        require(hasRole(REBALANCE_ROLE, msg.sender) || hasRole(EMERGENCY_ROLE, msg.sender), "REBAL: not authorized");
        bytes32 encodedReason = keccak256(bytes(reason));
        require(encodedReason != keccak256(""), "REBAL: empty reason");
        require(index < basket.length, "REBAL: bad index");
        require(basket.length > MIN_CONSTITUENTS, "REBAL: at floor");
        address token = basket[index];
        require(!_pending.exists, "REBAL: pending exists");

        _pending = PendingChange(true, true, index, token, uint64(block.timestamp));
        emit RemovalProposed(index, token, block.timestamp, reason);
    }

    function activateChange() external {
        PendingChange memory m = _pending;
        require(m.exists, "REBAL: none pending");
        require(block.timestamp >= m.submittedAt + timelockDelay, "REBAL: delay not elapsed");

        _pending = PendingChange(false, false, 0, address(0), 0);

        if (m.isRemoval) {
            require(m.index < basket.length && basket[m.index] == m.token, "REBAL: stale removal");
            address removed = basket[m.index];
            isActive[removed] = false;
            basket[m.index] = basket[basket.length - 1];
            basket.pop();
            emit ConstituentRemoved(m.index, removed, block.timestamp);
        } else {
            _pushConstituent(m.token);
            emit ConstituentAdmitted(m.token, basket.length, block.timestamp);
        }
    }

    function _pushConstituent(address token) internal {
        wasAdmitted[token] = true;
        isActive[token] = true;
        admittedAt[token] = block.timestamp;
        basket.push(token);
    }
}
