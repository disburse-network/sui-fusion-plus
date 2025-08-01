module sui_fusion_plus::fusion_order {
    use std::signer;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, Object, UID};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::transfer;

    use sui_fusion_plus::constants;
    use sui_fusion_plus::resolver_registry;

    friend sui_fusion_plus::escrow;

    // - - - - ERROR CODES - - - -

    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 1;
    /// Insufficient balance
    const EINSUFFICIENT_BALANCE: u64 = 2;
    /// Invalid caller
    const EINVALID_CALLER: u64 = 3;
    /// Object does not exist
    const EOBJECT_DOES_NOT_EXIST: u64 = 4;
    /// Invalid resolver
    const EINVALID_RESOLVER: u64 = 5;
    /// Invalid hash
    const EINVALID_HASH: u64 = 6;

    // - - - - EVENTS - - - -

    #[event]
    /// Event emitted when a fusion order is created
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This event indicates a user wants to swap assets to a different chain
    /// - chain_id: Shows which blockchain the user wants to swap TO
    /// - source_amount: How much the user is depositing
    /// - destination_amount: How much they expect to receive
    /// - destination_recipient: EVM address that should receive destination assets
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor these events to find swap opportunities
    /// 2. Check if you have matching destination assets on the destination chain
    /// 3. Evaluate if the swap is profitable for you
    /// 4. Call resolver_accept_order() if you want to accept the order
    struct FusionOrderCreatedEvent has drop, store {
        fusion_order: Object<FusionOrder>, // Order object address for tracking
        owner: address,                     // User who created the order
        source_coin_type: vector<u8>,      // Asset type they're depositing
        source_amount: u64,                 // Amount they're depositing
        destination_asset: vector<u8>,      // Destination asset (EVM address or native)
        destination_amount: u64,            // Amount they expect to receive
        destination_recipient: vector<u8>,  // EVM address to receive destination assets
        chain_id: u64,                      // Destination chain ID
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        auction_start_time: u64,
        current_price: u64                  // Current Dutch auction price at creation time
    }

    #[event]
    /// Event emitted when a fusion order is cancelled by the owner
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - User cancelled their order before resolver picked it up
    /// - No action needed from resolver
    /// - Assets returned to user automatically
    /// 
    /// RESOLVER SHOULD:
    /// 1. Remove this order from your tracking
    /// 2. No cross-chain coordination needed
    struct FusionOrderCancelledEvent has drop, store {
        fusion_order: Object<FusionOrder>, // Order object that was cancelled
        owner: address,                     // User who cancelled the order
        source_coin_type: vector<u8>,      // Asset type
        source_amount: u64                  // Amount that was cancelled
    }

    #[event]
    /// Event emitted when a fusion order is accepted by a resolver
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Resolver has accepted the order and created source chain escrow
    /// - Resolver must now create matching destination chain escrow
    /// - This triggers the cross-chain atomic swap process
    /// 
    /// RESOLVER SHOULD:
    /// 1. Create matching escrow on destination chain with same parameters
    /// 2. Monitor both escrows for withdrawal events
    /// 3. Handle the complete cross-chain swap lifecycle
    /// 4. Ensure atomic swap completion or proper cancellation
    struct FusionOrderAcceptedEvent has drop, store {
        fusion_order: Object<FusionOrder>, // Order object that was accepted
        resolver: address,                  // Resolver who accepted the order
        owner: address,                     // Original user who created the order
        source_coin_type: vector<u8>,      // Source asset type
        source_amount: u64,                 // Source amount
        destination_asset: vector<u8>,      // Destination asset (EVM address or native)
        destination_amount: u64,            // Destination amount
        destination_recipient: vector<u8>,  // EVM address to receive destination assets
        chain_id: u64,                      // Destination chain ID
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        auction_start_time: u64,
        current_price: u64                  // Current Dutch auction price at acceptance time
    }

    // - - - - STRUCTS - - - -

    /// A fusion order that represents a user's intent to swap assets across chains.
    /// The order can be cancelled by the owner before a resolver picks it up.
    /// Once picked up by a resolver, the order is converted to an escrow.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Users only deposit source asset (no safety deposit)
    /// - Resolvers provide safety deposit when accepting orders
    /// - This matches the actual 1inch Fusion+ protocol design
    ///
    /// @param owner The address of the user who created this order.
    /// @param source_coin_type The coin type of the asset being deposited.
    /// @param source_amount The amount of the source asset being deposited.
    /// @param destination_asset The destination asset specification:
    ///                         - If all zeros (0x0000...): Native asset (ETH, SUI, etc.)
    ///                         - If contract address: ERC20/ERC721 token address on destination chain
    ///                         - Stored as vector<u8> to handle EVM addresses (20 bytes) and native asset (32 bytes)
    /// @param destination_amount The amount of destination asset expected.
    /// @param destination_recipient The EVM address that should receive destination assets:
    ///                              - Stored as vector<u8> to handle EVM address format (20 bytes)
    ///                              - This is the address on the destination chain (EVM format)
    /// @param safety_deposit_coin_type The coin type of the safety deposit asset (resolver provides).
    /// @param safety_deposit_amount The amount of safety deposit (always 0 for user orders).
    /// @param chain_id The destination chain ID for the swap.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param initial_destination_amount The starting price of the Dutch auction.
    /// @param min_destination_amount The minimum price of the Dutch auction.
    /// @param decay_per_second The price decay per second of the Dutch auction.
    /// @param auction_start_time The timestamp when the Dutch auction starts.
    struct FusionOrder has key, store {
        id: UID,
        owner: address,
        source_coin_type: vector<u8>,
        source_amount: u64,
        destination_asset: vector<u8>,      // EVM address or native asset identifier
        destination_amount: u64,
        destination_recipient: vector<u8>,  // EVM address (20 bytes) for destination recipient
        safety_deposit_coin_type: vector<u8>,
        safety_deposit_amount: u64, // Always 0 - resolver provides safety deposit
        chain_id: u64,
        hash: vector<u8>,
        /// Dutch auction fields
        initial_destination_amount: u64, // Starting price (e.g., 100200 USDC)
        min_destination_amount: u64,     // Minimum price (floor)
        decay_per_second: u64,           // Price decay per second
        auction_start_time: u64,         // Timestamp when auction starts
        /// Asset storage
        source_balance: Balance<Coin<u64>>, // User's source asset
    }

    // - - - - ENTRY FUNCTIONS - - - -

    /// Entry function for creating a new FusionOrder.
    public entry fun new_entry(
        signer: &signer,
        source_coin: Coin<u64>,
        destination_asset: vector<u8>,
        destination_amount: u64,
        destination_recipient: vector<u8>,
        chain_id: u64,
        hash: vector<u8>,
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        clock: &Clock
    ) {
        let source_coin_type = coin::get_coin_type(&source_coin);
        let source_amount = coin::value(&source_coin);
        
        new(signer, source_coin, destination_asset, destination_amount, destination_recipient, chain_id, hash, initial_destination_amount, min_destination_amount, decay_per_second, clock);
    }

    // - - - - PUBLIC FUNCTIONS - - - -

    /// Creates a new FusionOrder with the specified parameters.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - User creates order with only source asset (no safety deposit)
    /// - Resolver provides safety deposit when accepting order
    /// - This matches the actual 1inch Fusion+ protocol design
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor FusionOrderCreatedEvent to find orders
    /// 2. Provide safety deposit when accepting orders
    /// 3. Create matching destination chain escrow
    /// 4. Handle complete cross-chain swap lifecycle
    ///
    /// @param signer The signer of the user creating the order.
    /// @param source_coin The source coin being deposited.
    /// @param destination_asset The destination asset specification:
    ///                         - If all zeros (0x0000...): Native asset (ETH, SUI, etc.)
    ///                         - If contract address: ERC20/ERC721 token address on destination chain
    ///                         - Stored as vector<u8> to handle EVM addresses (20 bytes) and native asset (32 bytes)
    /// @param destination_amount The amount of destination asset expected.
    /// @param destination_recipient The EVM address that should receive destination assets:
    ///                              - Stored as vector<u8> to handle EVM address format (20 bytes)
    ///                              - This is the address on the destination chain (EVM format)
    /// @param chain_id The destination chain ID for the swap.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param initial_destination_amount The starting price of the Dutch auction.
    /// @param min_destination_amount The minimum price of the Dutch auction.
    /// @param decay_per_second The price decay per second of the Dutch auction.
    /// @param clock The clock object to get current time.
    ///
    /// @reverts EINVALID_AMOUNT if amount is zero.
    /// @reverts EINSUFFICIENT_BALANCE if user has insufficient balance for source asset.
    /// @return Object<FusionOrder> The created fusion order object.
    public fun new(
        signer: &signer,
        source_coin: Coin<u64>,
        destination_asset: vector<u8>,
        destination_amount: u64,
        destination_recipient: vector<u8>,
        chain_id: u64,
        hash: vector<u8>,
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        clock: &Clock
    ): Object<FusionOrder> {

        let signer_address = signer::address_of(signer);
        let source_coin_type = coin::get_coin_type(&source_coin);
        let source_amount = coin::value(&source_coin);

        // Validate inputs
        assert!(source_amount > 0, EINVALID_AMOUNT);
        assert!(destination_amount > 0, EINVALID_AMOUNT);
        assert!(is_valid_hash(&hash), EINVALID_HASH);
        
        // Validate destination asset specification
        // Must be either native asset (all zeros) or valid EVM contract address (20 bytes)
        assert!(
            is_native_asset(&destination_asset) || is_evm_contract_address(&destination_asset),
            EINVALID_AMOUNT
        );
        
        // Validate destination recipient address
        // Must be a valid EVM address (20 bytes)
        assert!(
            is_valid_evm_address(&destination_recipient),
            EINVALID_AMOUNT
        );

        // Validate Dutch auction parameters
        assert!(initial_destination_amount >= min_destination_amount, EINVALID_AMOUNT);
        assert!(decay_per_second > 0, EINVALID_AMOUNT);

        // Create the FusionOrder
        // NOTE: No safety deposit from user - only resolver provides safety deposit
        let fusion_order = FusionOrder {
            id: object::new(signer),
            owner: signer_address,
            source_coin_type,
            source_amount,
            destination_asset,      // EVM address or native asset identifier
            destination_amount,
            destination_recipient,  // EVM address (20 bytes) for destination recipient
            safety_deposit_coin_type: constants::get_safety_deposit_coin_type(),
            safety_deposit_amount: 0, // User doesn't provide safety deposit
            chain_id,
            hash,
            // Dutch auction fields
            initial_destination_amount, // Starting price (e.g., 100200 USDC)
            min_destination_amount,     // Minimum price (floor)
            decay_per_second,           // Price decay per second
            auction_start_time: clock::timestamp_ms(clock),         // Timestamp when auction starts
            // Asset storage
            source_balance: balance::zero(), // Will be filled with source coin
        };

        let initial_destination_amount_val = fusion_order.initial_destination_amount;
        let min_destination_amount_val = fusion_order.min_destination_amount;
        let decay_per_second_val = fusion_order.decay_per_second;
        let auction_start_time_val = fusion_order.auction_start_time;

        let current_price_val = calculate_current_dutch_auction_price(
            initial_destination_amount_val,
            min_destination_amount_val,
            decay_per_second_val,
            auction_start_time_val,
            clock
        );

        // Store the source coin in the fusion order
        balance::join(&mut fusion_order.source_balance, source_coin);

        let fusion_order_obj = object::share_object(fusion_order);

        // Emit creation event
        event::emit(
            FusionOrderCreatedEvent {
                fusion_order: fusion_order_obj,
                owner: signer_address,
                source_coin_type,
                source_amount,
                destination_asset,
                destination_amount,
                destination_recipient,
                chain_id,
                initial_destination_amount: initial_destination_amount_val,
                min_destination_amount: min_destination_amount_val,
                decay_per_second: decay_per_second_val,
                auction_start_time: auction_start_time_val,
                current_price: current_price_val
            }
        );

        fusion_order_obj
    }

    /// Cancels a fusion order and returns assets to the owner. This function can only be called by the owner before it is picked up by a resolver.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - User cancels order before resolver picks it up
    /// - Only main asset is returned (no safety deposit since user never provided one)
    /// - No cross-chain coordination needed
    ///
    /// @param signer The signer of the order owner.
    /// @param fusion_order The fusion order to cancel.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the fusion order does not exist.
    /// @reverts EINVALID_CALLER if the signer is not the order owner.
    public entry fun cancel(
        signer: &signer, fusion_order: Object<FusionOrder>
    ) acquires FusionOrder {
        let signer_address = signer::address_of(signer);

        assert!(order_exists(fusion_order), EOBJECT_DOES_NOT_EXIST);
        assert!(is_owner(fusion_order, signer_address), EINVALID_CALLER);

        let fusion_order_ref = borrow_fusion_order_mut(&fusion_order);

        // Store event data before deletion
        let owner = fusion_order_ref.owner;
        let source_coin_type = fusion_order_ref.source_coin_type;
        let source_amount = fusion_order_ref.source_amount;

        // Return main asset to owner
        // NOTE: No safety deposit to return since user never provided one
        let source_coin = balance::split(&mut fusion_order_ref.source_balance, source_amount);
        transfer::transfer(source_coin, signer_address);

        // Emit cancellation event
        event::emit(
            FusionOrderCancelledEvent { fusion_order, owner, source_coin_type, source_amount }
        );

        // Delete the fusion order
        let FusionOrder { id, source_balance, .. } = object::delete(fusion_order);
        balance::destroy_zero(source_balance);
    }

    /// Allows an active resolver to accept a fusion order.
    /// This function is called from the escrow module when creating an escrow from a fusion order.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This function extracts assets from fusion order and creates source chain escrow
    /// - Assets stay in escrow (not with resolver) for hashlock/timelock protection
    /// - Resolver must then create matching destination chain escrow
    /// - Emits FusionOrderAcceptedEvent for cross-chain coordination
    /// 
    /// RESOLVER FLOW:
    /// 1. Monitor FusionOrderCreatedEvent to find orders you want to accept
    /// 2. Call escrow::new_from_order_entry() which internally calls this function
    /// 3. This function creates source chain escrow with user's assets
    /// 4. Resolver must then create matching destination chain escrow
    /// 5. Monitor both escrows for withdrawal events
    /// 
    /// RESOLVER RESPONSIBILITIES:
    /// 1. Ensure you have matching assets on destination chain before accepting
    /// 2. Provide safety deposit when accepting order (this is your skin in the game)
    /// 3. Monitor FusionOrderAcceptedEvent to know when order is accepted
    /// 4. Create destination chain escrow with same parameters
    /// 5. Handle the complete cross-chain swap lifecycle
    ///
    /// @param signer The signer of the resolver accepting the order.
    /// @param fusion_order The fusion order to accept.
    /// @param clock The clock object to get current time.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the fusion order does not exist.
    /// @reverts EINVALID_RESOLVER if the signer is not an active resolver.
    /// @reverts EINSUFFICIENT_BALANCE if resolver has insufficient safety deposit.
    /// @return (Coin<u64>, Coin<u64>) The main asset and safety deposit asset for escrow creation.
    public(friend) fun resolver_accept_order(
        signer: &signer, fusion_order: Object<FusionOrder>, clock: &Clock
    ): (Coin<u64>, Coin<u64>) acquires FusionOrder {
        let signer_address = signer::address_of(signer);

        assert!(order_exists(fusion_order), EOBJECT_DOES_NOT_EXIST);
        assert!(
            resolver_registry::is_resolver_active(signer_address), EINVALID_RESOLVER
        );

        let fusion_order_ref = borrow_fusion_order_mut(&fusion_order);

        // Store event data before deletion
        // CROSS-CHAIN LOGIC: These values are used in FusionOrderAcceptedEvent
        // and must match the destination chain escrow parameters
        let owner = fusion_order_ref.owner;
        let source_coin_type = fusion_order_ref.source_coin_type;
        let source_amount = fusion_order_ref.source_amount;
        let destination_asset = fusion_order_ref.destination_asset;
        let destination_amount = fusion_order_ref.destination_amount;
        let destination_recipient = fusion_order_ref.destination_recipient;
        let chain_id = fusion_order_ref.chain_id;
        let initial_destination_amount = fusion_order_ref.initial_destination_amount;
        let min_destination_amount = fusion_order_ref.min_destination_amount;
        let decay_per_second = fusion_order_ref.decay_per_second;
        let auction_start_time = fusion_order_ref.auction_start_time;

        // Extract main asset from fusion order (user's asset)
        // CROSS-CHAIN LOGIC: This asset will be used to create source chain escrow
        let asset = balance::split(&mut fusion_order_ref.source_balance, source_amount);

        // Resolver provides safety deposit (user never provided one)
        // CROSS-CHAIN LOGIC: This ensures resolver has skin in the game
        let safety_deposit_coin = coin::from_balance(
            balance::split(&mut fusion_order_ref.source_balance, constants::get_safety_deposit_amount()),
            signer_address
        );

        // Emit acceptance event for cross-chain coordination
        // RESOLVER SHOULD MONITOR THIS EVENT:
        // - Track that order has been accepted
        // - Use metadata, amount, chain_id to create destination escrow
        // - Ensure matching parameters across both chains
        let current_price = calculate_current_dutch_auction_price(
            initial_destination_amount,
            min_destination_amount,
            decay_per_second,
            auction_start_time,
            clock
        );
        event::emit(
            FusionOrderAcceptedEvent {
                fusion_order,
                resolver: signer_address,
                owner,
                source_coin_type,
                source_amount,
                destination_asset,
                destination_amount,
                destination_recipient,
                chain_id,
                initial_destination_amount,
                min_destination_amount,
                decay_per_second,
                auction_start_time,
                current_price
            }
        );

        // Return assets for escrow creation (not for resolver to keep)
        // CROSS-CHAIN LOGIC: These assets will be locked in escrow
        (asset, safety_deposit_coin)
    }

    // - - - - GETTER FUNCTIONS - - - -

    /// Gets the owner address of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the owner from.
    /// @return address The owner address.
    public fun get_owner(fusion_order: Object<FusionOrder>): address acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.owner
    }

    /// Gets the coin type of the source asset in a fusion order.
    ///
    /// @param fusion_order The fusion order to get the coin type from.
    /// @return vector<u8> The coin type of the source asset.
    public fun get_source_coin_type(
        fusion_order: Object<FusionOrder>
    ): vector<u8> acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.source_coin_type
    }

    /// Gets the amount of the source asset in a fusion order.
    ///
    /// @param fusion_order The fusion order to get the amount from.
    /// @return u64 The amount of the source asset.
    public fun get_source_amount(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.source_amount
    }

    /// Gets the destination asset specification from a fusion order.
    ///
    /// @param fusion_order The fusion order to get the destination asset from.
    /// @return vector<u8> The destination asset specification:
    ///                     - If all zeros (0x0000...): Native asset (ETH, SUI, etc.)
    ///                     - If contract address: ERC20/ERC721 token address on destination chain
    ///                     - Stored as vector<u8> to handle EVM addresses (20 bytes) and native asset (32 bytes)
    public fun get_destination_asset(
        fusion_order: Object<FusionOrder>
    ): vector<u8> acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.destination_asset
    }

    /// Gets the destination amount from a fusion order.
    ///
    /// @param fusion_order The fusion order to get the destination amount from.
    /// @return u64 The amount of destination asset expected.
    public fun get_destination_amount(
        fusion_order: Object<FusionOrder>
    ): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.destination_amount
    }

    /// Gets the destination recipient address from a fusion order.
    ///
    /// @param fusion_order The fusion order to get the destination recipient from.
    /// @return vector<u8> The EVM address that should receive destination assets:
    ///                     - Stored as vector<u8> to handle EVM address format (20 bytes)
    ///                     - This is the address on the destination chain (EVM format)
    public fun get_destination_recipient(
        fusion_order: Object<FusionOrder>
    ): vector<u8> acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.destination_recipient
    }

    /// Gets the coin type of the safety deposit asset in a fusion order.
    /// NOTE: Users don't provide safety deposits - only resolvers do
    ///
    /// @param fusion_order The fusion order to get the safety deposit coin type from.
    /// @return vector<u8> The coin type of the safety deposit asset.
    public fun get_safety_deposit_coin_type(
        fusion_order: Object<FusionOrder>
    ): vector<u8> acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.safety_deposit_coin_type
    }

    /// Gets the amount of the safety deposit in a fusion order.
    /// NOTE: This will always be 0 since users don't provide safety deposits
    /// Resolvers provide safety deposits when accepting orders
    ///
    /// @param fusion_order The fusion order to get the safety deposit amount from.
    /// @return u64 The amount of the safety deposit (always 0 for user orders).
    public fun get_safety_deposit_amount(
        fusion_order: Object<FusionOrder>
    ): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.safety_deposit_amount // Always 0 since user doesn't provide safety deposit
    }

    /// Gets the initial destination amount of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the initial destination amount from.
    /// @return u64 The initial destination amount.
    public fun get_initial_destination_amount(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.initial_destination_amount
    }

    /// Gets the minimum destination amount of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the minimum destination amount from.
    /// @return u64 The minimum destination amount.
    public fun get_min_destination_amount(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.min_destination_amount
    }

    /// Gets the decay per second of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the decay per second from.
    /// @return u64 The decay per second.
    public fun get_decay_per_second(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.decay_per_second
    }

    /// Gets the auction start time of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the auction start time from.
    /// @return u64 The auction start time.
    public fun get_auction_start_time(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.auction_start_time
    }

    /// Gets the destination chain ID of a fusion order.
    ///
    /// @param fusion_order The fusion order to get the chain ID from.
    /// @return u64 The destination chain ID.
    public fun get_chain_id(fusion_order: Object<FusionOrder>): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.chain_id
    }

    /// Gets the hash of the secret in a fusion order.
    ///
    /// @param fusion_order The fusion order to get the hash from.
    /// @return vector<u8> The hash of the secret.
    public fun get_hash(fusion_order: Object<FusionOrder>): vector<u8> acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.hash
    }

    /// Checks if a hash value is valid (non-empty).
    ///
    /// @param hash The hash value to check.
    /// @return bool True if the hash is valid, false otherwise.
    public fun is_valid_hash(hash: &vector<u8>): bool {
        hash.length() > 0
    }

    /// Checks if a destination asset specification represents a native asset.
    /// Native assets are represented as all zeros (0x0000...).
    ///
    /// @param destination_asset The destination asset specification to check.
    /// @return bool True if the asset is native, false if it's a contract address.
    public fun is_native_asset(destination_asset: &vector<u8>): bool {
        let len = destination_asset.length();
        if (len == 0) { return true }; // Empty vector is considered native
        
        let i = 0;
        while (i < len) {
            if (destination_asset[i] != 0) {
                return false
            };
            i += 1;
        };
        true
    }

    /// Checks if a destination asset specification represents a valid EVM contract address.
    /// EVM addresses are 20 bytes long.
    ///
    /// @param destination_asset The destination asset specification to check.
    /// @return bool True if the asset is a valid EVM contract address, false otherwise.
    public fun is_evm_contract_address(destination_asset: &vector<u8>): bool {
        !is_native_asset(destination_asset) && destination_asset.length() == 20
    }

    /// Checks if a destination recipient address is a valid EVM address.
    /// EVM addresses are 20 bytes long.
    ///
    /// @param destination_recipient The destination recipient address to check.
    /// @return bool True if the address is a valid EVM address, false otherwise.
    public fun is_valid_evm_address(destination_recipient: &vector<u8>): bool {
        destination_recipient.length() == 20
    }

    /// Checks if a fusion order exists.
    ///
    /// @param fusion_order The fusion order object to check.
    /// @return bool True if the fusion order exists, false otherwise.
    public fun order_exists(fusion_order: Object<FusionOrder>): bool {
        object::exists(object::uid_to_address(&fusion_order))
    }

    /// Checks if an address is the owner of a fusion order.
    ///
    /// @param fusion_order The fusion order to check.
    /// @param address The address to check against.
    /// @return bool True if the address is the owner, false otherwise.
    public fun is_owner(
        fusion_order: Object<FusionOrder>, address: address
    ): bool acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        fusion_order_ref.owner == address
    }

    /// Calculates the current Dutch auction price based on elapsed time.
    /// Formula: current_price = max(min_price, initial_price - decay_rate * elapsed_seconds)
    ///
    /// @param initial_destination_amount The initial price of the Dutch auction.
    /// @param min_destination_amount The minimum price (floor) of the Dutch auction.
    /// @param decay_per_second The price decay per second.
    /// @param auction_start_time The timestamp when the auction started.
    /// @param clock The clock object to get current time.
    /// @return u64 The current price at the given time.
    public fun calculate_current_dutch_auction_price(
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        auction_start_time: u64,
        clock: &Clock
    ): u64 {
        let current_time = clock::timestamp_ms(clock);
        let elapsed_seconds = current_time - auction_start_time;
        let total_decay = decay_per_second * elapsed_seconds;
        
        if (total_decay >= initial_destination_amount) {
            // Price has decayed to or below minimum
            min_destination_amount
        } else {
            let current_price = initial_destination_amount - total_decay;
            if (current_price < min_destination_amount) {
                min_destination_amount
            } else {
                current_price
            }
        }
    }

    /// Gets the current Dutch auction price for a fusion order.
    ///
    /// @param fusion_order The fusion order to get the current price for.
    /// @param clock The clock object to get current time.
    /// @return u64 The current price at the current time.
    public fun get_current_dutch_auction_price(
        fusion_order: Object<FusionOrder>,
        clock: &Clock
    ): u64 acquires FusionOrder {
        let fusion_order_ref = borrow_fusion_order(&fusion_order);
        calculate_current_dutch_auction_price(
            fusion_order_ref.initial_destination_amount,
            fusion_order_ref.min_destination_amount,
            fusion_order_ref.decay_per_second,
            fusion_order_ref.auction_start_time,
            clock
        )
    }

    // - - - - BORROW FUNCTIONS - - - -

    /// Borrows an immutable reference to the FusionOrder.
    ///
    /// @param fusion_order_obj The fusion order object.
    /// @return &FusionOrder Immutable reference to the fusion order.
    inline fun borrow_fusion_order(
        fusion_order_obj: &Object<FusionOrder>
    ): &FusionOrder {
        borrow_global<FusionOrder>(object::uid_to_address(fusion_order_obj))
    }

    /// Borrows a mutable reference to the FusionOrder.
    ///
    /// @param fusion_order_obj The fusion order object.
    /// @return &mut FusionOrder Mutable reference to the fusion order.
    inline fun borrow_fusion_order_mut(
        fusion_order_obj: &Object<FusionOrder>
    ): &mut FusionOrder {
        borrow_global_mut<FusionOrder>(object::uid_to_address(fusion_order_obj))
    }
} 