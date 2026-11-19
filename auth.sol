// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Standard Interface Detection (ERC-165)
 */
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Standard ERC-721 Interface for Non-Fungible Tokens
 */
interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/**
 * @dev Standard ERC-721 Metadata Interface
 */
interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/**
 * @title ERC-5192 Minimal Soulbound NFTs Interface
 * @notice Standard interface for non-transferable (soulbound) tokens.
 */
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    /// @notice Returns whether a token is soulbound/locked.
    function locked(uint256 tokenId) external view returns (bool);
}

/**
 * @dev Minimal ERC-20 Interface for Stablecoin Payments (USDC, RLUSD, etc.)
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title AuthSubscriptionNFT
 * @notice An NFT-based Authentication and Authorization Subscription Pass.
 * @dev Features:
 *      1. Annual Subscription Lifecycle: Access is automatically revoked if not renewed.
 *      2. Soulbound / Non-Transferable: Inextricably bound to the subscriber (minter) address.
 *         Cannot be transferred, approved, or sold (ERC-5192 compliant).
 *      3. Stablecoin Payments: First-class support for USDC and RLUSD (Ripple USD).
 *      4. Fiat Payment Provider Support: Allows authorized non-crypto payment gateways
 *         (e.g., Stripe, MoonPay, Apple Pay) to mint, renew, and manage subscriptions with
 *         idempotent replay protection and chargeback dispute revocation.
 *      5. Role-Based Access Control (RBAC): Tiers (Guest, Member, VIP, Admin) with granular gatekeeping.
 */
contract AuthSubscriptionNFT is IERC721Metadata, IERC5192 {
    // =============================================================
    //                           TYPES
    // =============================================================

    enum PassTier {
        None,       // 0: No access
        Guest,      // 1: Limited guest pass
        Member,     // 2: Standard authorized user / subscriber
        VIP,        // 3: Elevated access / premium subscriber
        Admin       // 4: Full administrative access
    }

    enum SubscriptionStatus {
        None,       // 0: Never subscribed / no token
        Active,     // 1: Subscribed and currently valid
        Expired,    // 2: Annual subscription expired (access revoked)
        Revoked     // 3: Manually revoked (e.g., dispute, chargeback, fraud)
    }

    struct Subscription {
        uint256 tokenId;        // Unique token ID
        address minter;         // Bound minter address (immutable)
        PassTier tier;          // Authorization level / tier
        uint64 expiresAt;       // Unix timestamp when pass expires
        uint64 issuedAt;        // Unix timestamp when pass was first issued
        uint64 lastRenewedAt;   // Unix timestamp of most recent renewal
        uint32 renewalCount;    // Number of annual renewals completed
        bool isManuallyRevoked; // Administrative or payment dispute revocation flag
    }

    // =============================================================
    //                        CONSTANTS
    // =============================================================

    /// @notice Duration added per annual subscription (365 days = 31,536,000 seconds)
    uint64 public constant SUBSCRIPTION_PERIOD = 365 days;

    // =============================================================
    //                     STATE VARIABLES
    // =============================================================

    // Administration
    address public contractOwner;
    address public treasury;
    bool public paused;

    // Token Metadata
    string private _name = "Guardian Pass";
    string private _symbol = "GUARD";
    string public baseURI;

    // Token Tracking
    uint256 private _nextTokenId = 1;
    uint256 public totalSupply;

    // Soulbound Storage
    // Mapping: tokenId => Owner (minter)
    mapping(uint256 => address) private _owners;
    // Mapping: User address => Balance (at most 1 active pass per address)
    mapping(address => uint256) private _balances;
    // Mapping: User address => Bound Token ID
    mapping(address => uint256) public subscriberTokenId;
    // Mapping: Token ID => Bound Minter address
    mapping(uint256 => address) public minterOf;
    // Mapping: Token ID => Subscription details
    mapping(uint256 => Subscription) public subscriptions;

    // Native Currency Payment Configuration (XRP on XRPL EVM, ETH, etc.)
    uint256 public annualNativePrice;
    mapping(PassTier => uint256) public tierNativePrice;

    // Stablecoin Payment Configuration (RLUSD, USDC, etc.)
    address public usdcToken;
    address public rlusdToken;
    mapping(address => bool) public isAcceptedPaymentToken;
    mapping(address => uint256) public annualPricePerToken;
    mapping(address => mapping(PassTier => uint256)) public tierAnnualPrice;

    // Non-Crypto / Fiat Payment Providers
    // Mapping: Payment Provider / Relayer Address => Authorization Status
    mapping(address => bool) public isAuthorizedPaymentProvider;
    // Mapping: Hash of External Payment ID => Processed Status (Replay Protection)
    mapping(bytes32 => bool) public processedFiatPayments;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event SubscriptionMinted(
        address indexed subscriber,
        uint256 indexed tokenId,
        PassTier tier,
        uint64 expiresAt,
        string paymentMethod
    );
    event SubscriptionRenewed(
        address indexed subscriber,
        uint256 indexed tokenId,
        uint64 newExpiresAt,
        uint32 yearsAdded,
        string paymentMethod
    );
    event SubscriptionRevoked(uint256 indexed tokenId, address indexed subscriber, string reason);
    event SubscriptionRestored(uint256 indexed tokenId, address indexed subscriber);
    event SubscriptionTierUpdated(uint256 indexed tokenId, PassTier oldTier, PassTier newTier);
    event PaymentTokenConfigured(address indexed token, bool isAccepted, uint256 baseAnnualPrice);
    event TierPriceConfigured(address indexed token, PassTier tier, uint256 annualPrice);
    event NativePriceConfigured(PassTier tier, uint256 annualPrice);
    event PaymentProviderUpdated(address indexed provider, bool isAuthorized);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FiatPaymentProcessed(
        address indexed subscriber,
        uint256 indexed tokenId,
        string externalPaymentId,
        uint32 yearsCount,
        uint64 newExpiresAt
    );
    event InterledgerPaymentProcessed(
        address indexed subscriber,
        uint256 indexed tokenId,
        string ilpPaymentId,
        uint32 yearsCount,
        uint64 newExpiresAt
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    // =============================================================
    //                        CUSTOM ERRORS
    // =============================================================

    error ZeroAddress();
    error NotContractOwner();
    error UnauthorizedPaymentProvider(address caller);
    error SoulboundTransferBlocked();
    error SoulboundApprovalBlocked();
    error TokenDoesNotExist();
    error SubscriptionAlreadyActive(uint256 existingTokenId);
    error SubscriptionDoesNotExist();
    error SubscriptionExpiredError(uint256 tokenId, uint64 expiredAt);
    error SubscriptionManuallyRevoked();
    error SubscriptionNotRevoked();
    error UnsupportedPaymentToken(address token);
    error PriceNotConfigured();
    error InsufficientPayment(uint256 provided, uint256 requiredAmount);
    error InvalidSubscriptionDuration();
    error InvalidPassTier();
    error InvalidFiatReference();
    error FiatPaymentAlreadyProcessed(string externalPaymentId);
    error PaymentTransferFailed();
    error ContractIsPaused();
    error NotTokenMinterOrOwner();

    // =============================================================
    //                        MODIFIERS
    // =============================================================

    modifier onlyContractOwner() {
        if (msg.sender != contractOwner) revert NotContractOwner();
        _;
    }

    modifier onlyPaymentProviderOrOwner() {
        if (msg.sender != contractOwner && !isAuthorizedPaymentProvider[msg.sender]) {
            revert UnauthorizedPaymentProvider(msg.sender);
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractIsPaused();
        _;
    }

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the subscription authorization contract.
     * @param initialOwner Contract admin address (defaults to msg.sender if address(0)).
     * @param initialTreasury Recipient address for stablecoin payments (defaults to msg.sender if address(0)).
     * @param _usdcToken Address of the USDC ERC-20 contract (optional during deployment).
     * @param _rlusdToken Address of the RLUSD ERC-20 contract (optional during deployment).
     * @param _usdcAnnualPrice Annual price in USDC base units (e.g., 100_000_000 for $100 USDC with 6 decimals).
     * @param _rlusdAnnualPrice Annual price in RLUSD base units (e.g., 100_000_000 for $100 RLUSD with 6 decimals).
     */
    constructor(
        address initialOwner,
        address initialTreasury,
        address _usdcToken,
        address _rlusdToken,
        uint256 _usdcAnnualPrice,
        uint256 _rlusdAnnualPrice
    ) {
        contractOwner = initialOwner != address(0) ? initialOwner : msg.sender;
        treasury = initialTreasury != address(0) ? initialTreasury : msg.sender;

        if (_usdcToken != address(0)) {
            usdcToken = _usdcToken;
            isAcceptedPaymentToken[_usdcToken] = true;
            annualPricePerToken[_usdcToken] = _usdcAnnualPrice;
            tierAnnualPrice[_usdcToken][PassTier.Member] = _usdcAnnualPrice;
            emit PaymentTokenConfigured(_usdcToken, true, _usdcAnnualPrice);
        }

        if (_rlusdToken != address(0)) {
            rlusdToken = _rlusdToken;
            isAcceptedPaymentToken[_rlusdToken] = true;
            annualPricePerToken[_rlusdToken] = _rlusdAnnualPrice;
            tierAnnualPrice[_rlusdToken][PassTier.Member] = _rlusdAnnualPrice;
            emit PaymentTokenConfigured(_rlusdToken, true, _rlusdAnnualPrice);
        }

        emit OwnershipTransferred(address(0), contractOwner);
        emit TreasuryUpdated(address(0), treasury);
    }

    // =============================================================
    //         NATIVE CURRENCY PAYMENTS (XRP / ETH)
    // =============================================================

    /**
     * @notice Purchase a subscription using the chain's native currency (XRP on XRPL EVM, ETH, etc.).
     * @param tier Authorization tier requested (e.g. Member, VIP).
     * @param yearsCount Number of years to purchase (1-10).
     */
    function subscribeWithNative(
        PassTier tier,
        uint32 yearsCount
    ) external payable whenNotPaused returns (uint256 tokenId) {
        uint256 totalCost = getSubscriptionNativePrice(tier, yearsCount);
        if (msg.value < totalCost) revert InsufficientPayment(msg.value, totalCost);

        (bool sent, ) = treasury.call{value: msg.value}("");
        if (!sent) revert PaymentTransferFailed();

        return _mintSubscription(msg.sender, tier, yearsCount, "Native_Currency");
    }

    /**
     * @notice Renew a subscription using the chain's native currency (XRP on XRPL EVM, ETH, etc.).
     * @param yearsCount Number of years to extend (1-10).
     */
    function renewWithNative(
        uint32 yearsCount
    ) external payable whenNotPaused returns (uint64 newExpiresAt) {
        uint256 tokenId = subscriberTokenId[msg.sender];
        if (tokenId == 0) revert SubscriptionDoesNotExist();

        PassTier tier = subscriptions[tokenId].tier;
        uint256 totalCost = getSubscriptionNativePrice(tier, yearsCount);
        if (msg.value < totalCost) revert InsufficientPayment(msg.value, totalCost);

        (bool sent, ) = treasury.call{value: msg.value}("");
        if (!sent) revert PaymentTransferFailed();

        return _renewSubscription(tokenId, yearsCount, "Native_Currency");
    }

    /**
     * @notice Retrieve the price in native currency (XRP/ETH) for a tier and duration.
     */
    function getSubscriptionNativePrice(
        PassTier tier,
        uint32 yearsCount
    ) public view returns (uint256) {
        if (yearsCount == 0 || yearsCount > 10) revert InvalidSubscriptionDuration();

        uint256 price = tierNativePrice[tier];
        if (price == 0) {
            price = annualNativePrice;
        }
        if (price == 0) revert PriceNotConfigured();

        return price * yearsCount;
    }

    // =============================================================
    //            CRYPTO PAYMENT SUBSCRIPTION (USDC / RLUSD)
    // =============================================================

    /**
     * @notice Purchase a new annual subscription pass using an accepted stablecoin (USDC or RLUSD).
     * @param token Address of the stablecoin payment token (e.g., USDC or RLUSD).
     * @param tier Authorization tier requested (e.g., Member, VIP).
     * @param yearsCount Number of years to purchase (1-10).
     * @return tokenId The newly minted Soulbound NFT ID bound to msg.sender.
     */
    function subscribeWithToken(
        address token,
        PassTier tier,
        uint32 yearsCount
    ) external whenNotPaused returns (uint256 tokenId) {
        uint256 totalCost = getSubscriptionPrice(token, tier, yearsCount);
        _safeTransferFrom(token, msg.sender, treasury, totalCost);
        return _mintSubscription(msg.sender, tier, yearsCount, "Stablecoin_Direct");
    }

    /**
     * @notice Renew an existing annual subscription pass using an accepted stablecoin.
     * @param token Address of the stablecoin payment token.
     * @param yearsCount Number of years to extend (1-10).
     * @return newExpiresAt The updated expiration timestamp.
     */
    function renewWithToken(
        address token,
        uint32 yearsCount
    ) external whenNotPaused returns (uint64 newExpiresAt) {
        uint256 tokenId = subscriberTokenId[msg.sender];
        if (tokenId == 0) revert SubscriptionDoesNotExist();

        PassTier tier = subscriptions[tokenId].tier;
        uint256 totalCost = getSubscriptionPrice(token, tier, yearsCount);
        _safeTransferFrom(token, msg.sender, treasury, totalCost);
        return _renewSubscription(tokenId, yearsCount, "Stablecoin_Direct");
    }

    /**
     * @notice Third-party or sponsored subscription: Pay with stablecoin on behalf of a subscriber.
     * @dev Used by fiat on-ramps or sponsors that settle in stablecoin on-chain.
     * @param subscriber The wallet address that will own and be bound to the Soulbound NFT.
     * @param token Address of the stablecoin payment token.
     * @param tier Authorization tier requested.
     * @param yearsCount Number of years to purchase (1-10).
     * @return tokenId The newly minted Soulbound NFT ID bound to subscriber.
     */
    function subscribeForWithToken(
        address subscriber,
        address token,
        PassTier tier,
        uint32 yearsCount
    ) external whenNotPaused returns (uint256 tokenId) {
        uint256 totalCost = getSubscriptionPrice(token, tier, yearsCount);
        _safeTransferFrom(token, msg.sender, treasury, totalCost);
        return _mintSubscription(subscriber, tier, yearsCount, "Stablecoin_Sponsored");
    }

    /**
     * @notice Third-party or sponsored renewal: Pay with stablecoin to extend someone's subscription.
     * @param subscriber The wallet address of the existing subscriber.
     * @param token Address of the stablecoin payment token.
     * @param yearsCount Number of years to extend (1-10).
     * @return newExpiresAt The updated expiration timestamp.
     */
    function renewForWithToken(
        address subscriber,
        address token,
        uint32 yearsCount
    ) external whenNotPaused returns (uint64 newExpiresAt) {
        uint256 tokenId = subscriberTokenId[subscriber];
        if (tokenId == 0) revert SubscriptionDoesNotExist();

        PassTier tier = subscriptions[tokenId].tier;
        uint256 totalCost = getSubscriptionPrice(token, tier, yearsCount);
        _safeTransferFrom(token, msg.sender, treasury, totalCost);
        return _renewSubscription(tokenId, yearsCount, "Stablecoin_Sponsored");
    }

    // =============================================================
    //         NON-CRYPTO PAYMENT PROVIDER INTEGRATION (FIAT)
    // =============================================================

    /**
     * @notice Unified processor for non-crypto payment providers (Stripe, MoonPay, credit card gateways).
     * @dev Automatically mints a new pass if subscriber has none, or renews their existing pass.
     *      Includes replay protection via externalPaymentId (e.g., Stripe PaymentIntent ID).
     * @param subscriber The recipient's wallet address.
     * @param tier Authorization tier granted.
     * @param yearsCount Duration purchased in years.
     * @param externalPaymentId Unique off-chain transaction/receipt ID to ensure idempotent processing.
     * @return tokenId The subscriber's Soulbound NFT ID.
     * @return expiresAt The new expiration timestamp.
     */
    function processFiatPayment(
        address subscriber,
        PassTier tier,
        uint32 yearsCount,
        string calldata externalPaymentId
    ) external onlyPaymentProviderOrOwner whenNotPaused returns (uint256 tokenId, uint64 expiresAt) {
        _verifyAndRecordFiatPayment(externalPaymentId);

        uint256 existingTokenId = subscriberTokenId[subscriber];
        if (existingTokenId == 0) {
            tokenId = _mintSubscription(subscriber, tier, yearsCount, "Fiat_Provider");
            expiresAt = subscriptions[tokenId].expiresAt;
        } else {
            tokenId = existingTokenId;
            if (tier != PassTier.None && tier != subscriptions[tokenId].tier) {
                PassTier oldTier = subscriptions[tokenId].tier;
                subscriptions[tokenId].tier = tier;
                emit SubscriptionTierUpdated(tokenId, oldTier, tier);
            }
            expiresAt = _renewSubscription(tokenId, yearsCount, "Fiat_Provider");
        }

        emit FiatPaymentProcessed(subscriber, tokenId, externalPaymentId, yearsCount, expiresAt);
    }

    /**
     * @notice Interledger Protocol (ILPv4 / Rafiki / Open Payments) payment processor.
     * @dev Settles payments completed over ILPv4 across any currency/rail through a Rafiki connector.
     * @param subscriber The recipient EVM wallet address.
     * @param tier Authorization tier granted.
     * @param yearsCount Duration purchased in years.
     * @param ilpPaymentRef Unique ILPv4 / Open Payments identifier (Incoming Payment URL or packet receipt).
     * @return tokenId The subscriber's Soulbound NFT ID.
     * @return expiresAt The new expiration timestamp.
     */
    function processInterledgerPayment(
        address subscriber,
        PassTier tier,
        uint32 yearsCount,
        string calldata ilpPaymentRef
    ) external onlyPaymentProviderOrOwner whenNotPaused returns (uint256 tokenId, uint64 expiresAt) {
        _verifyAndRecordFiatPayment(ilpPaymentRef);

        uint256 existingTokenId = subscriberTokenId[subscriber];
        if (existingTokenId == 0) {
            tokenId = _mintSubscription(subscriber, tier, yearsCount, "Interledger_ILPv4");
            expiresAt = subscriptions[tokenId].expiresAt;
        } else {
            tokenId = existingTokenId;
            if (tier != PassTier.None && tier != subscriptions[tokenId].tier) {
                PassTier oldTier = subscriptions[tokenId].tier;
                subscriptions[tokenId].tier = tier;
                emit SubscriptionTierUpdated(tokenId, oldTier, tier);
            }
            expiresAt = _renewSubscription(tokenId, yearsCount, "Interledger_ILPv4");
        }

        emit InterledgerPaymentProcessed(subscriber, tokenId, ilpPaymentRef, yearsCount, expiresAt);
    }

    /**
     * @notice Explicitly mint a new subscription pass from a verified fiat payment.
     * @param subscriber The recipient wallet address.
     * @param tier Authorization tier granted.
     * @param yearsCount Duration purchased in years.
     * @param externalPaymentId Unique off-chain transaction reference.
     */
    function mintFromFiat(
        address subscriber,
        PassTier tier,
        uint32 yearsCount,
        string calldata externalPaymentId
    ) external onlyPaymentProviderOrOwner whenNotPaused returns (uint256 tokenId) {
        _verifyAndRecordFiatPayment(externalPaymentId);
        tokenId = _mintSubscription(subscriber, tier, yearsCount, "Fiat_Provider");
        emit FiatPaymentProcessed(subscriber, tokenId, externalPaymentId, yearsCount, subscriptions[tokenId].expiresAt);
    }

    /**
     * @notice Explicitly renew an existing subscription pass from a verified fiat payment.
     * @param subscriber The existing subscriber wallet address.
     * @param yearsCount Duration extended in years.
     * @param externalPaymentId Unique off-chain transaction reference.
     */
    function renewFromFiat(
        address subscriber,
        uint32 yearsCount,
        string calldata externalPaymentId
    ) external onlyPaymentProviderOrOwner whenNotPaused returns (uint64 newExpiresAt) {
        _verifyAndRecordFiatPayment(externalPaymentId);
        uint256 tokenId = subscriberTokenId[subscriber];
        if (tokenId == 0) revert SubscriptionDoesNotExist();
        newExpiresAt = _renewSubscription(tokenId, yearsCount, "Fiat_Provider");
        emit FiatPaymentProcessed(subscriber, tokenId, externalPaymentId, yearsCount, newExpiresAt);
    }

    /**
     * @notice Internal replay protection check for fiat payment webhooks.
     */
    function _verifyAndRecordFiatPayment(string calldata externalPaymentId) internal {
        if (bytes(externalPaymentId).length == 0) revert InvalidFiatReference();
        bytes32 paymentHash = keccak256(bytes(externalPaymentId));
        if (processedFiatPayments[paymentHash]) {
            revert FiatPaymentAlreadyProcessed(externalPaymentId);
        }
        processedFiatPayments[paymentHash] = true;
    }

    // =============================================================
    //         AUTHENTICATION & AUTHORIZATION GATEKEEPING
    // =============================================================

    /**
     * @notice Primary access verification: Does the user have an active, valid subscription?
     * @dev Automatically revokes access if the user's annual subscription has expired.
     * @param user The wallet address to verify.
     * @return hasValidAccess True if pass exists, is not manually revoked, and has not expired.
     */
    function hasAccess(address user) public view returns (bool hasValidAccess) {
        uint256 tokenId = subscriberTokenId[user];
        if (tokenId == 0) return false;

        Subscription memory sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) return false;
        if (block.timestamp > sub.expiresAt) return false; // Non-renewal = Access Revoked

        return true;
    }

    /**
     * @notice Role-based access control: Does user have active access with at least required tier?
     * @param user The wallet address.
     * @param requiredTier The minimum required authorization tier.
     * @return authorized True if user has active pass meeting or exceeding tier.
     */
    function hasMinimumTier(address user, PassTier requiredTier) external view returns (bool authorized) {
        uint256 tokenId = subscriberTokenId[user];
        if (tokenId == 0) return false;

        Subscription memory sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) return false;
        if (block.timestamp > sub.expiresAt) return false; // Non-renewal = Access Revoked

        return uint8(sub.tier) >= uint8(requiredTier);
    }

    /**
     * @notice Comprehensive authorization query for dApps, APIs, and microservices.
     * @param user The wallet address to inspect.
     * @return authorized True if valid and unexpired.
     * @return tier Current authorization tier.
     * @return activeAuthId The NFT token ID.
     * @return expiresAt Timestamp when subscription ends.
     * @return statusMessage Human-readable status description.
     */
    function checkAuthorization(address user)
        external
        view
        returns (
            bool authorized,
            PassTier tier,
            uint256 activeAuthId,
            uint64 expiresAt,
            string memory statusMessage
        )
    {
        uint256 tokenId = subscriberTokenId[user];
        if (tokenId == 0) {
            return (false, PassTier.None, 0, 0, "No Subscription Pass Found");
        }

        Subscription memory sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) {
            return (false, sub.tier, tokenId, sub.expiresAt, "Subscription Manually Revoked");
        }
        if (block.timestamp > sub.expiresAt) {
            return (false, sub.tier, tokenId, sub.expiresAt, "Subscription Expired - Access Revoked");
        }

        return (true, sub.tier, tokenId, sub.expiresAt, "Authorized");
    }

    /**
     * @notice Query current subscription status details for a user.
     * @param user The wallet address.
     * @return status Enum representing current state (None, Active, Expired, Revoked).
     * @return tokenId The associated token ID.
     * @return expiresAt Timestamp when pass expires.
     * @return secondsRemaining Remaining valid time in seconds (0 if expired).
     */
    function getSubscriptionStatus(address user)
        external
        view
        returns (
            SubscriptionStatus status,
            uint256 tokenId,
            uint64 expiresAt,
            uint256 secondsRemaining
        )
    {
        tokenId = subscriberTokenId[user];
        if (tokenId == 0) {
            return (SubscriptionStatus.None, 0, 0, 0);
        }

        Subscription memory sub = subscriptions[tokenId];
        expiresAt = sub.expiresAt;

        if (sub.isManuallyRevoked) {
            return (SubscriptionStatus.Revoked, tokenId, expiresAt, 0);
        }

        if (block.timestamp > expiresAt) {
            return (SubscriptionStatus.Expired, tokenId, expiresAt, 0);
        }

        secondsRemaining = expiresAt - block.timestamp;
        return (SubscriptionStatus.Active, tokenId, expiresAt, secondsRemaining);
    }

    /**
     * @notice Check if a specific token ID is currently active.
     */
    function isSubscriptionActive(uint256 tokenId) public view returns (bool) {
        if (_owners[tokenId] == address(0)) return false;
        Subscription memory sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) return false;
        if (block.timestamp > sub.expiresAt) return false;
        return true;
    }

    /**
     * @notice Backward-compatible alias for isSubscriptionActive.
     */
    function isPassValid(uint256 authId) external view returns (bool) {
        return isSubscriptionActive(authId);
    }

    /**
     * @notice Backward-compatible alias for subscriberTokenId.
     */
    function userPrimaryAuthId(address user) external view returns (uint256) {
        return subscriberTokenId[user];
    }

    /**
     * @notice Backward-compatible view for passes query.
     */
    function passes(uint256 authId)
        external
        view
        returns (
            uint256 id,
            PassTier tier,
            uint64 validUntil,
            bool isRevoked
        )
    {
        Subscription memory sub = subscriptions[authId];
        return (sub.tokenId, sub.tier, sub.expiresAt, sub.isManuallyRevoked);
    }

    /**
     * @notice Retrieve the price for a subscription in a given token and tier.
     */
    function getSubscriptionPrice(
        address token,
        PassTier tier,
        uint32 yearsCount
    ) public view returns (uint256) {
        if (!isAcceptedPaymentToken[token]) revert UnsupportedPaymentToken(token);
        if (yearsCount == 0 || yearsCount > 10) revert InvalidSubscriptionDuration();

        uint256 annualPrice = tierAnnualPrice[token][tier];
        if (annualPrice == 0) {
            annualPrice = annualPricePerToken[token];
        }
        if (annualPrice == 0) revert PriceNotConfigured();

        return annualPrice * yearsCount;
    }

    // =============================================================
    //                 ADMIN & FRAUD MANAGEMENT
    // =============================================================

    /**
     * @notice Manually revoke access for a subscription pass (e.g. credit card chargeback, fraud, terms violation).
     * @param tokenId The pass token ID to revoke.
     * @param reason The documented reason for revocation.
     */
    function revokeAccess(uint256 tokenId, string calldata reason) external onlyPaymentProviderOrOwner {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        Subscription storage sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) revert SubscriptionManuallyRevoked();

        sub.isManuallyRevoked = true;
        emit SubscriptionRevoked(tokenId, sub.minter, reason);
    }

    /**
     * @notice Restore access after a dispute or chargeback is resolved.
     * @param tokenId The pass token ID to restore.
     */
    function restoreAccess(uint256 tokenId) external onlyPaymentProviderOrOwner {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        Subscription storage sub = subscriptions[tokenId];
        if (!sub.isManuallyRevoked) revert SubscriptionNotRevoked();

        sub.isManuallyRevoked = false;
        emit SubscriptionRestored(tokenId, sub.minter);
    }

    /**
     * @notice Complimentary / manual issuance of an auth pass by contract admin.
     */
    function adminIssuePass(
        address subscriber,
        PassTier tier,
        uint32 yearsCount
    ) external onlyContractOwner returns (uint256 tokenId) {
        return _mintSubscription(subscriber, tier, yearsCount, "Admin_Grant");
    }

    /**
     * @notice Manual extension of an existing subscription by contract admin.
     */
    function adminExtendSubscription(
        uint256 tokenId,
        uint32 yearsCount
    ) external onlyContractOwner returns (uint64 newExpiresAt) {
        return _renewSubscription(tokenId, yearsCount, "Admin_Grant");
    }

    /**
     * @notice Update a subscriber's tier directly.
     */
    function updateTier(uint256 tokenId, PassTier newTier) external onlyPaymentProviderOrOwner {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        if (newTier == PassTier.None) revert InvalidPassTier();

        PassTier oldTier = subscriptions[tokenId].tier;
        subscriptions[tokenId].tier = newTier;
        emit SubscriptionTierUpdated(tokenId, oldTier, newTier);
    }

    /**
     * @notice Configure tier-specific annual pricing for native currency (XRP on XRPL EVM, ETH, etc.).
     */
    function setNativePrice(
        PassTier tier,
        uint256 price
    ) external onlyContractOwner {
        tierNativePrice[tier] = price;
        emit NativePriceConfigured(tier, price);
    }

    /**
     * @notice Configure default annual pricing for native currency.
     */
    function setDefaultNativePrice(
        uint256 price
    ) external onlyContractOwner {
        annualNativePrice = price;
        emit NativePriceConfigured(PassTier.Member, price);
    }

    /**
     * @notice Configure support and base annual pricing for a payment token (RLUSD, USDC, etc.).
     */
    function setPaymentToken(
        address token,
        bool isAccepted,
        uint256 baseAnnualPrice
    ) external onlyContractOwner {
        if (token == address(0)) revert ZeroAddress();
        isAcceptedPaymentToken[token] = isAccepted;
        annualPricePerToken[token] = baseAnnualPrice;
        emit PaymentTokenConfigured(token, isAccepted, baseAnnualPrice);
    }

    /**
     * @notice Configure tier-specific annual pricing for an accepted token.
     */
    function setTierPrice(
        address token,
        PassTier tier,
        uint256 price
    ) external onlyContractOwner {
        if (token == address(0)) revert ZeroAddress();
        tierAnnualPrice[token][tier] = price;
        emit TierPriceConfigured(token, tier, price);
    }

    /**
     * @notice Authorize or deauthorize a non-crypto payment provider / relayer.
     */
    function setPaymentProvider(address provider, bool isAuthorized) external onlyContractOwner {
        if (provider == address(0)) revert ZeroAddress();
        isAuthorizedPaymentProvider[provider] = isAuthorized;
        emit PaymentProviderUpdated(provider, isAuthorized);
    }

    /**
     * @notice Update the recipient treasury address for stablecoin payments.
     */
    function setTreasury(address newTreasury) external onlyContractOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Set base URI for off-chain metadata hosting.
     */
    function setBaseURI(string calldata newBaseURI) external onlyContractOwner {
        baseURI = newBaseURI;
    }

    /**
     * @notice Circuit breaker: Pause new subscriptions.
     */
    function pause() external onlyContractOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause subscriptions.
     */
    function unpause() external onlyContractOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Transfer ownership of the contract.
     */
    function transferOwnership(address newOwner) external onlyContractOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = contractOwner;
        contractOwner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @notice Rescue stablecoin tokens accidentally held by the contract.
     */
    function withdrawReserves(address token, address to, uint256 amount) external onlyContractOwner {
        if (to == address(0)) revert ZeroAddress();
        _safeTransfer(token, to, amount);
    }

    /**
     * @notice Rescue native ETH/currency accidentally sent to contract.
     */
    function withdrawNative(address payable to) external onlyContractOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool success, ) = to.call{value: address(this).balance}("");
        if (!success) revert PaymentTransferFailed();
    }

    /**
     * @notice Allow subscriber or admin to voluntarily burn/cancel a subscription pass.
     */
    function burn(uint256 tokenId) external {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        if (msg.sender != owner && msg.sender != contractOwner) revert NotTokenMinterOrOwner();

        delete subscriberTokenId[owner];
        delete minterOf[tokenId];
        delete subscriptions[tokenId];
        delete _owners[tokenId];
        _balances[owner] = 0;
        totalSupply -= 1;

        emit Unlocked(tokenId);
        emit Transfer(owner, address(0), tokenId);
    }

    // =============================================================
    //                 INTERNAL CORE LOGIC
    // =============================================================

    function _mintSubscription(
        address subscriber,
        PassTier tier,
        uint32 yearsCount,
        string memory paymentMethod
    ) internal returns (uint256 tokenId) {
        if (subscriber == address(0)) revert ZeroAddress();
        if (yearsCount == 0 || yearsCount > 10) revert InvalidSubscriptionDuration();
        if (tier == PassTier.None) revert InvalidPassTier();
        if (subscriberTokenId[subscriber] != 0) {
            revert SubscriptionAlreadyActive(subscriberTokenId[subscriber]);
        }

        tokenId = _nextTokenId++;
        uint64 expiresAt = uint64(block.timestamp) + (uint64(yearsCount) * SUBSCRIPTION_PERIOD);

        subscriptions[tokenId] = Subscription({
            tokenId: tokenId,
            minter: subscriber,
            tier: tier,
            expiresAt: expiresAt,
            issuedAt: uint64(block.timestamp),
            lastRenewedAt: uint64(block.timestamp),
            renewalCount: 0,
            isManuallyRevoked: false
        });

        // Bind token directly and permanently to subscriber
        subscriberTokenId[subscriber] = tokenId;
        minterOf[tokenId] = subscriber;
        _owners[tokenId] = subscriber;
        _balances[subscriber] = 1;
        totalSupply += 1;

        emit Transfer(address(0), subscriber, tokenId);
        emit Locked(tokenId);
        emit SubscriptionMinted(subscriber, tokenId, tier, expiresAt, paymentMethod);
    }

    function _renewSubscription(
        uint256 tokenId,
        uint32 yearsCount,
        string memory paymentMethod
    ) internal returns (uint64 newExpiresAt) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        if (yearsCount == 0 || yearsCount > 10) revert InvalidSubscriptionDuration();

        Subscription storage sub = subscriptions[tokenId];
        if (sub.isManuallyRevoked) revert SubscriptionManuallyRevoked();

        uint64 durationToAdd = uint64(yearsCount) * SUBSCRIPTION_PERIOD;

        // If subscription is currently active, extend from existing expiration date.
        // If subscription is expired, extend starting from current timestamp.
        if (block.timestamp < sub.expiresAt) {
            newExpiresAt = sub.expiresAt + durationToAdd;
        } else {
            newExpiresAt = uint64(block.timestamp) + durationToAdd;
        }

        sub.expiresAt = newExpiresAt;
        sub.lastRenewedAt = uint64(block.timestamp);
        sub.renewalCount += yearsCount;

        emit SubscriptionRenewed(sub.minter, tokenId, newExpiresAt, yearsCount, paymentMethod);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert PaymentTransferFailed();
        }
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert PaymentTransferFailed();
        }
    }

    // =============================================================
    //                 ERC-5192 (SOULBOUND TOKEN)
    // =============================================================

    /**
     * @notice EIP-5192 standard: Returns whether the NFT is locked (soulbound).
     * @dev All valid subscription passes are permanently locked and cannot be transferred.
     */
    function locked(uint256 tokenId) external view override returns (bool) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return true;
    }

    // =============================================================
    //                 ERC-721 IMPLEMENTATION (SOULBOUND)
    // =============================================================

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    /**
     * @notice Approvals are blocked: Pass is non-transferable and cannot be sold.
     */
    function approve(address, uint256) external pure override {
        revert SoulboundApprovalBlocked();
    }

    /**
     * @notice Operator approvals are blocked: Pass is non-transferable.
     */
    function setApprovalForAll(address, bool) external pure override {
        revert SoulboundApprovalBlocked();
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return address(0);
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    /**
     * @notice Transfers are blocked: Pass is soulbound to the minter address.
     */
    function transferFrom(address, address, uint256) external pure override {
        revert SoulboundTransferBlocked();
    }

    /**
     * @notice Safe transfers are blocked: Pass is soulbound to the minter address.
     */
    function safeTransferFrom(address, address, uint256) external pure override {
        revert SoulboundTransferBlocked();
    }

    /**
     * @notice Safe transfers with data are blocked: Pass is soulbound to the minter address.
     */
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure override {
        revert SoulboundTransferBlocked();
    }

    /**
     * @notice Token metadata URI: Returns on-chain JSON traits or baseURI link.
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();

        if (bytes(baseURI).length > 0) {
            return string.concat(baseURI, _toString(tokenId));
        }

        Subscription memory sub = subscriptions[tokenId];
        string memory statusStr = "Active";
        if (sub.isManuallyRevoked) {
            statusStr = "Revoked";
        } else if (block.timestamp > sub.expiresAt) {
            statusStr = "Expired";
        }

        string memory tierStr = _tierToString(sub.tier);

        return string.concat(
            "data:application/json;utf8,{\"name\":\"",
            _name,
            " #",
            _toString(tokenId),
            "\",\"description\":\"Non-transferable Soulbound subscription NFT granting verified authentication and authorization credentials.\",\"attributes\":[{\"trait_type\":\"Status\",\"value\":\"",
            statusStr,
            "\"},{\"trait_type\":\"Tier\",\"value\":\"",
            tierStr,
            "\"},{\"trait_type\":\"Minter\",\"value\":\"",
            _toHexString(sub.minter),
            "\"},{\"trait_type\":\"ExpiresAt\",\"value\":",
            _toString(sub.expiresAt),
            "},{\"trait_type\":\"RenewalCount\",\"value\":",
            _toString(sub.renewalCount),
            "}]}"
        );
    }

    /**
     * @notice Interface detection for ERC-165, ERC-721, ERC-721Metadata, and ERC-5192.
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f || // ERC-721Metadata
            interfaceId == 0xb45a3c0e;   // ERC-5192 (Soulbound)
    }

    // =============================================================
    //                 INTERNAL STRING HELPERS
    // =============================================================

    function _tierToString(PassTier tier) internal pure returns (string memory) {
        if (tier == PassTier.Guest) return "Guest";
        if (tier == PassTier.Member) return "Member";
        if (tier == PassTier.VIP) return "VIP";
        if (tier == PassTier.Admin) return "Admin";
        return "None";
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 byteVal = uint8(uint160(addr) >> (8 * (19 - i)));
            uint8 hi = byteVal >> 4;
            uint8 lo = byteVal & 0x0f;
            buffer[2 + 2 * i] = hi < 10 ? bytes1(hi + 48) : bytes1(hi + 87);
            buffer[3 + 2 * i] = lo < 10 ? bytes1(lo + 48) : bytes1(lo + 87);
        }
        return string(buffer);
    }
}

/**
 * @title AuthIDPass
 * @dev Alias contract maintaining backward compatibility for existing deployments and interfaces.
 */
contract AuthIDPass is AuthSubscriptionNFT {
    constructor(
        address initialOwner,
        address initialTreasury,
        address _usdcToken,
        address _rlusdToken,
        uint256 _usdcAnnualPrice,
        uint256 _rlusdAnnualPrice
    ) AuthSubscriptionNFT(
        initialOwner,
        initialTreasury,
        _usdcToken,
        _rlusdToken,
        _usdcAnnualPrice,
        _rlusdAnnualPrice
    ) {}
}
