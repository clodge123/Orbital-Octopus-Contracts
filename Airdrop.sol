// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./IOrbitalOctopus.sol";
import "./library/SafeMath.sol";
import "./IOwnable.sol";

contract Airdrop is IOwnable {
    using SafeMath for uint256;

    IOrbitalOctopus public token;
    bytes32 public merkleRoot;
    address private _owner;
    address payable public walletAddress;
    mapping(address => bool) public claimed;
    mapping(address => uint256) public vestingAmounts;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public lastClaimTimestamp;
    mapping(address => address) public referrers; // Stores referrer addresses
    uint256 public totalClaimedTokens; // Variable to track total claimed tokens

    // List of addresses that have claimed tokens
    address[] public claimedAddresses;

    // Event emitted when referral fee percentage is updated
    event ReferralFeePercentageUpdated(uint256 newPercentage);
    event FundsWithdrawn(address indexed receiver, uint256 amount);

    // Address of the wallet that receives the fee
    address payable public feeWallet;

    // Fee percentage (5%)
    uint256 public referralFeePercentage = 5;

    // Event emitted when tokens are claimed with a referral
    event TokensClaimedWithReferral(address indexed claimer, uint256 amount, address indexed referrer);

    uint256 public constant VESTING_DURATION = 26 weeks; // Approximate 6 months

    event TokensClaimed(address indexed recipient, uint256 amount);

    constructor(address _tokenAddress, bytes32 _merkleRoot) {
        token = IOrbitalOctopus(_tokenAddress);
        merkleRoot = _merkleRoot;
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _owner = newOwner;
    }

    function revokeOwnership() external onlyOwner {
        _owner = address(0);
    }

    function distributeTokens(address recipient, uint256 amount) internal {
        // Transfer tokens from airdrop contract to recipient
        token.transfer(recipient, amount);
    }

    function claimTokens(uint256 amount, bytes32[] memory proof) external {
        require(!claimed[msg.sender], "Tokens already claimed");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));

        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid proof");

        uint256 fullAmount = amount * 10**9;

        claimed[msg.sender] = true;
        claimedAddresses.push(msg.sender); // Add to the list of claimed addresses

        // Calculate vesting amounts
        uint256 initialAmount = fullAmount.mul(10).div(100); // 10% initially
        uint256 lockedAmount = fullAmount.sub(initialAmount); // Remaining amount locked

        // Distribute initial amount immediately
        distributeTokens(msg.sender, initialAmount);

        // Set vesting amounts and claimed amounts
        vestingAmounts[msg.sender] = lockedAmount;
        claimedAmounts[msg.sender] = initialAmount;
        lastClaimTimestamp[msg.sender] = block.timestamp;
        
        // Update the total claimed tokens
        totalClaimedTokens = totalClaimedTokens.add(fullAmount);

        emit TokensClaimed(msg.sender, initialAmount);
    }

    function claimVestedTokens() external {
        require(claimed[msg.sender], "Tokens not claimed");
        require(vestingAmounts[msg.sender] > 0, "No tokens vested");

        uint256 currentTime = block.timestamp;
        uint256 timeSinceInitialClaim = currentTime.sub(lastClaimTimestamp[msg.sender]);

        // Ensure that we don't allow claiming more than the vesting duration allows
        if (timeSinceInitialClaim > VESTING_DURATION) {
            timeSinceInitialClaim = VESTING_DURATION;
        }

        // Calculate the total amount of tokens that can be unlocked up to this point
        uint256 unlockableTokens = vestingAmounts[msg.sender].mul(timeSinceInitialClaim).div(VESTING_DURATION);

        // Ensure unlockable tokens do not exceed vested amount
        if (unlockableTokens > vestingAmounts[msg.sender]) {
            unlockableTokens = vestingAmounts[msg.sender];
        }

        require(unlockableTokens > 0, "No tokens to claim yet");

        // Update the vesting balance and claimed amounts
        vestingAmounts[msg.sender] = vestingAmounts[msg.sender].sub(unlockableTokens);
        claimedAmounts[msg.sender] = claimedAmounts[msg.sender].add(unlockableTokens);

        // Note: Do not update lastClaimTimestamp here to prevent extending the vesting period on frequent claims.

        // Transfer the unlocked tokens to the user
        distributeTokens(msg.sender, unlockableTokens);

        emit TokensClaimed(msg.sender, unlockableTokens);
    }

    function getVestedTokens(address account) external view returns (uint256) {
        // Calculate unvested tokens (total allocated - claimed amount)
        return vestingAmounts[account];
    }

    function getLastClaimTimestamp(address account) external view returns (uint256) {
        return lastClaimTimestamp[account];
    }

    function setReferrer(address referrer) external {
        require(referrer != address(0) && referrer != msg.sender, "Invalid referrer address");

        // Store the referrer address for the caller
        referrers[msg.sender] = referrer;
    }

    function claimTokensWithReferral(uint256 amount, bytes32[] memory proof, address referrer) external {
        // Claim tokens first
        require(!claimed[msg.sender], "Tokens already claimed");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));

        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid proof");

        uint256 fullAmount = amount * 10**9;

        // Calculate initial amount and fee
        uint256 initialAmount = fullAmount.mul(10).div(100); // 10% initially
        uint256 fullAmountMinusInital = fullAmount.sub(initialAmount);
        uint256 feeAmount = fullAmountMinusInital.mul(referralFeePercentage).div(100);
        uint256 lockedAmount = fullAmount.sub(initialAmount).sub(feeAmount); // Remaining amount locked

        // Then check for a referrer and reward them
        if (referrer != address(0)) {
            distributeTokens(referrer, feeAmount); // Add fee to referral reward
        }

        claimed[msg.sender] = true;
        claimedAddresses.push(msg.sender); // Add to the list of claimed addresses

        // Distribute initial amount immediately
        distributeTokens(msg.sender, initialAmount);

        // Set vesting amounts and claimed amounts
        vestingAmounts[msg.sender] = lockedAmount;
        claimedAmounts[msg.sender] = initialAmount;
        lastClaimTimestamp[msg.sender] = block.timestamp;

        // Update the total claimed tokens
        totalClaimedTokens = totalClaimedTokens.add(fullAmount);

        emit TokensClaimedWithReferral(msg.sender, feeAmount, referrer);
    }

    function updateReferralFeePercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 100, "Percentage should be less than or equal to 100");
        referralFeePercentage = newPercentage;
        emit ReferralFeePercentageUpdated(newPercentage);
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");

        walletAddress.transfer(amount);
        emit FundsWithdrawn(msg.sender, amount);
    }

    function getAirdropTokenBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // New function to get the total claimed tokens
    function getTotalClaimedTokens() external view returns (uint256) {
        return totalClaimedTokens;
    }

    // Function to distribute remaining tokens to wallets with vested tokens
    function distributeRemainingTokens() external onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingTokens > 0, "No tokens remaining in the contract");

        for (uint256 i = 0; i < claimedAddresses.length; i++) {
            address recipient = claimedAddresses[i];
            uint256 vestedAmount = vestingAmounts[recipient];

            if (vestedAmount > 0) {
                uint256 unlockableTokens = vestedAmount;
                vestingAmounts[recipient] = 0;
                claimedAmounts[recipient] = claimedAmounts[recipient].add(unlockableTokens);

                distributeTokens(recipient, unlockableTokens);
                totalClaimedTokens = totalClaimedTokens.add(unlockableTokens);

                emit TokensClaimed(recipient, unlockableTokens);
            }
        }
    }

    // Function to get the list of claimed addresses
    function getClaimedAddresses() external view onlyOwner returns (address[] memory) {
        return claimedAddresses;
    }
}
