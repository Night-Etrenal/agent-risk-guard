// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title AIRiskOracle
/// @notice Origin-chain oracle that posts AI risk verdicts for agent intents.
/// @dev Deployed on Base Sepolia. Emits RiskFlagged when score >= threshold so a
///      Reactive contract on Lasna can freeze the agent vault via callback.
contract AIRiskOracle {
    /// @notice Emitted when an AI score crosses the risk threshold.
    event RiskFlagged(
        address indexed agent,
        address indexed to,
        uint256 amount,
        bytes32 intentHash,
        uint8 score
    );

    /// @notice Emitted for every verdict (including below-threshold).
    event VerdictPosted(
        address indexed agent,
        address indexed to,
        uint256 amount,
        bytes32 intentHash,
        uint8 score,
        string rationale
    );

    address public owner;
    address public poster;
    uint8 public threshold;

    error NotAuthorized();
    error InvalidThreshold();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    modifier onlyPoster() {
        if (msg.sender != poster && msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(uint8 threshold_) {
        if (threshold_ == 0 || threshold_ > 100) revert InvalidThreshold();
        owner = msg.sender;
        poster = msg.sender;
        threshold = threshold_;
    }

    function setPoster(address poster_) external onlyOwner {
        poster = poster_;
    }

    function setThreshold(uint8 threshold_) external onlyOwner {
        if (threshold_ == 0 || threshold_ > 100) revert InvalidThreshold();
        threshold = threshold_;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Post an AI risk verdict for an agent spend intent.
    /// @param agent Agent address that attempted / will attempt the spend.
    /// @param to Destination of the spend.
    /// @param amount Amount in wei.
    /// @param intentHash Hash of the natural-language / structured intent.
    /// @param score Risk score 0-100 from the off-chain AI oracle.
    /// @param rationale Short rationale string (for explorers / demos).
    function postVerdict(
        address agent,
        address to,
        uint256 amount,
        bytes32 intentHash,
        uint8 score,
        string calldata rationale
    ) external onlyPoster {
        emit VerdictPosted(agent, to, amount, intentHash, score, rationale);
        if (score >= threshold) {
            emit RiskFlagged(agent, to, amount, intentHash, score);
        }
    }
}
