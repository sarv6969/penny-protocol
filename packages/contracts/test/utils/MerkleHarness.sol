// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Test-only binary Merkle tree matching OpenZeppelin MerkleProof semantics
///         (pairs sorted before hashing; odd nodes duplicate the last element).
contract MerkleHarness {
    function rootOf(bytes32[] memory leaves) public pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        bytes32[] memory level = leaves;
        while (level.length > 1) {
            uint256 m = level.length / 2 + (level.length % 2);
            bytes32[] memory next = new bytes32[](m);
            for (uint256 i = 0; i < level.length; i += 2) {
                bytes32 a = level[i];
                bytes32 b = i + 1 < level.length ? level[i + 1] : a;
                next[i / 2] = _hashPair(a, b);
            }
            level = next;
        }
        return level[0];
    }

    function proofFor(bytes32[] memory leaves, uint256 index) public pure returns (bytes32[] memory proof) {
        bytes32 target = leaves[index];
        bytes32[] memory level = leaves;
        while (level.length > 1) {
            uint256 pos = _indexOf(level, target);
            bytes32 sibling = (pos % 2 == 0) ? (pos + 1 < level.length ? level[pos + 1] : level[pos]) : level[pos - 1];

            bytes32[] memory acc = new bytes32[](proof.length + 1);
            for (uint256 i = 0; i < proof.length; i++) {
                acc[i] = proof[i];
            }
            acc[proof.length] = sibling;
            proof = acc;

            uint256 m = level.length / 2 + (level.length % 2);
            bytes32[] memory next = new bytes32[](m);
            for (uint256 i = 0; i < level.length; i += 2) {
                next[i / 2] = _hashPair(level[i], i + 1 < level.length ? level[i + 1] : level[i]);
            }
            level = next;
        }
        return proof;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _indexOf(bytes32[] memory arr, bytes32 v) internal pure returns (uint256 pos) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == v) return i;
        }
        revert("MH: leaf missing");
    }
}
