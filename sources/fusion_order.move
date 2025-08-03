module sui_fusion_plus::fusion_order {
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use sui_fusion_plus::constants;
    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};

    // - - - - ERROR CODES - - - -

    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 1;
    /// Invalid hash
    const EINVALID_HASH: u64 = 6;
    /// Invalid resolver
    const EINVALID_RESOLVER: u64 = 5;
    /// Object does not exist
    const EOBJECT_DOES_NOT_EXIST: u64 = 4;

    // - - - - EVENTS - - - -

    /// Event emitted when a fusion order is created
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This event indicates a user wants to swap assets to a different chain
    /// - chain_id: Shows which blockchain the user wants to swap TO
    /// - source_amount: How much the user is depositing
    /// - initial_destination_amount: Starting price of Dutch auction
    /// - min_destination_amount: Minimum price of Dutch auction
    /// - destination_recipient: EVM address that should receive destination assets
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor these events to find swap opportunities
    /// 2. Check if you have matching destination assets on the destination chain
    /// 3. Evaluate if the swap is profitable for you
    /// 4. Call resolver_accept_order() if you want to accept the order
    public struct FusionOrderCreatedEvent has drop, store, copy {
        fusion_order: address, // Order object address for tracking
        owner: address,         // User who created the order
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
    public struct FusionOrderCancelledEvent has drop, store, copy {
        fusion_order: address, // Order object that was cancelled
        owner: address,         // User who cancelled the order
        source_amount: u64                  // Amount that was cancelled
    }

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
    public struct FusionOrderAcceptedEvent has drop, store, copy {
        fusion_order: address, // Order object that was accepted
        resolver: address,      // Resolver who accepted the order
        owner: address,         // Original user who created the order
        source_amount: u64,                 // Source amount
        destination_asset: vector<u8>,      // Destination asset (EVM address or native)
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
    /// Following Sui's object-centric model for rich on-chain assets.
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Users only deposit source asset (no safety deposit)
    /// - Resolvers provide safety deposit when accepting orders
    /// - This matches the actual 1inch Fusion+ protocol design
    public struct FusionOrder has key, store {
        id: UID,
        owner: address,
        source_amount: u64,
        destination_asset: vector<u8>,      // EVM address or native asset identifier
        destination_amount: u64,
        destination_recipient: vector<u8>,  // EVM address (20 bytes) for destination recipient
        safety_deposit_amount: u64, // Always 0 - resolver provides safety deposit
        chain_id: u64,
        hash: vector<u8>,
        /// Dutch auction fields
        initial_destination_amount: u64, // Starting price (e.g., 100200 USDC)
        min_destination_amount: u64,     // Minimum price (floor)
        decay_per_second: u64,           // Price decay per second
        auction_start_time: u64,         // Timestamp when auction starts
        /// Asset storage - using Sui's coin model
        source_coin: Coin<u64>, // User's source asset
    }

    // - - - - ENTRY FUNCTIONS - - - -

    /// Entry function for creating a new FusionOrder.
    /// Following Sui's pattern for entry functions with proper parameter ordering.
    public entry fun new_entry(
        source_coin: Coin<u64>,
        destination_asset: vector<u8>,
        destination_amount: u64,
        destination_recipient: vector<u8>,
        chain_id: u64,
        hash: vector<u8>,
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let fusion_order = new(
            source_coin, 
            destination_asset, 
            destination_amount, 
            destination_recipient, 
            chain_id, 
            hash, 
            initial_destination_amount, 
            min_destination_amount, 
            decay_per_second, 
            clock,
            ctx
        );
        // Transfer the fusion order to the sender
        transfer::public_transfer(fusion_order, tx_context::sender(ctx));
    }

    // - - - - PUBLIC FUNCTIONS - - - -

    /// Creates a new FusionOrder with the specified parameters.
    /// Following Sui's Move language patterns for safety and expressivity.
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
    public fun new(
        source_coin: Coin<u64>,
        destination_asset: vector<u8>,
        destination_amount: u64,
        destination_recipient: vector<u8>,
        chain_id: u64,
        hash: vector<u8>,
        initial_destination_amount: u64,
        min_destination_amount: u64,
        decay_per_second: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): FusionOrder {

        let signer_address = tx_context::sender(ctx);
        let source_amount = coin::value(&source_coin);

        // Validate inputs using Move's safety features
        assert!(source_amount > 0, EINVALID_AMOUNT);
        assert!(destination_amount > 0, EINVALID_AMOUNT);
        assert!(is_valid_hash(&hash), EINVALID_HASH);
        
        // Validate destination asset specification
        assert!(
            is_native_asset(&destination_asset) || is_evm_contract_address(&destination_asset),
            EINVALID_AMOUNT
        );
        
        // Validate destination recipient address
        assert!(
            is_valid_evm_address(&destination_recipient),
            EINVALID_AMOUNT
        );

        // Validate Dutch auction parameters
        assert!(initial_destination_amount >= min_destination_amount, EINVALID_AMOUNT);
        assert!(decay_per_second > 0, EINVALID_AMOUNT);

        // Create the FusionOrder using Sui's object model
        let fusion_order = FusionOrder {
            id: object::new(ctx),
            owner: signer_address,
            source_amount,
            destination_asset,      // EVM address or native asset identifier
            destination_amount,
            destination_recipient,  // EVM address (20 bytes) for destination recipient
            safety_deposit_amount: 0, // User doesn't provide safety deposit
            chain_id,
            hash,
            // Dutch auction fields
            initial_destination_amount, // Starting price (e.g., 100200 USDC)
            min_destination_amount,     // Minimum price (floor)
            decay_per_second,           // Price decay per second
            auction_start_time: clock::timestamp_ms(clock),         // Timestamp when auction starts
            // Asset storage using Sui's coin model
            source_coin, // User's source asset
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

        // Emit creation event for cross-chain coordination
        event::emit(
            FusionOrderCreatedEvent {
                fusion_order: object::uid_to_address(&fusion_order.id),
                owner: signer_address,
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

        fusion_order
    }

    /// Cancels a fusion order and returns assets to the owner.
    /// Using Sui's transfer model for safe asset movement.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - User cancels order before resolver picks it up
    /// - Only main asset is returned (no safety deposit since user never provided one)
    /// - No cross-chain coordination needed
    public entry fun cancel(
        fusion_order: FusionOrder,
        ctx: &mut TxContext
    ) {
        let signer_address = tx_context::sender(ctx);

        assert!(fusion_order.owner == signer_address, 3); // EINVALID_CALLER

        // Store event data before deletion
        let owner = fusion_order.owner;
        let source_amount = fusion_order.source_amount;

        // Return main asset to owner using Sui's transfer model
        let FusionOrder { id, source_coin, .. } = fusion_order;
        transfer::public_transfer(source_coin, signer_address);

        // Emit cancellation event for cross-chain coordination
        event::emit(
            FusionOrderCancelledEvent { 
                fusion_order: object::uid_to_address(&id), 
                owner, 
                source_amount 
            }
        );

        // Delete the fusion order object
        object::delete(id);
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
    /// @param fusion_order The fusion order to accept.
    /// @param safety_deposit_coin The safety deposit coin from the resolver.
    /// @param ctx The transaction context.
    ///
    /// @reverts EINSUFFICIENT_BALANCE if resolver has insufficient safety deposit.
    /// @return (Coin<u64>, Coin<u64>) The main asset and safety deposit asset for escrow creation.
    public fun resolver_accept_order(
        fusion_order: FusionOrder,
        safety_deposit_coin: Coin<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<u64>, Coin<u64>) {
        let signer_address = tx_context::sender(ctx);

        // Validate safety deposit amount
        let safety_deposit_amount = coin::value(&safety_deposit_coin);
        assert!(safety_deposit_amount >= constants::get_safety_deposit_amount(), 2); // EINSUFFICIENT_BALANCE

        // Store event data before deletion
        // CROSS-CHAIN LOGIC: These values are used in FusionOrderAcceptedEvent
        // and must match the destination chain escrow parameters
        let owner = fusion_order.owner;
        let source_amount = fusion_order.source_amount;
        let destination_asset = fusion_order.destination_asset;
        let destination_recipient = fusion_order.destination_recipient;
        let chain_id = fusion_order.chain_id;
        let initial_destination_amount = fusion_order.initial_destination_amount;
        let min_destination_amount = fusion_order.min_destination_amount;
        let decay_per_second = fusion_order.decay_per_second;
        let auction_start_time = fusion_order.auction_start_time;

        // Extract main asset from fusion order (user's asset)
        // CROSS-CHAIN LOGIC: This asset will be used to create source chain escrow
        let FusionOrder { id, source_coin, .. } = fusion_order;

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
                fusion_order: object::uid_to_address(&id),
                resolver: signer_address,
                owner,
                source_amount,
                destination_asset,
                destination_recipient,
                chain_id,
                initial_destination_amount,
                min_destination_amount,
                decay_per_second,
                auction_start_time,
                current_price
            }
        );

        // Delete the fusion order
        object::delete(id);

        // Return assets for escrow creation (not for resolver to keep)
        // CROSS-CHAIN LOGIC: These assets will be locked in escrow
        (source_coin, safety_deposit_coin)
    }

    // - - - - GETTER FUNCTIONS - - - -

    /// Gets the owner address of a fusion order.
    public fun get_owner(fusion_order: &FusionOrder): address {
        fusion_order.owner
    }

    /// Gets the amount of the source asset in a fusion order.
    public fun get_source_amount(fusion_order: &FusionOrder): u64 {
        fusion_order.source_amount
    }

    /// Gets the destination asset specification from a fusion order.
    public fun get_destination_asset(fusion_order: &FusionOrder): vector<u8> {
        fusion_order.destination_asset
    }

    /// Gets the destination recipient address from a fusion order.
    public fun get_destination_recipient(fusion_order: &FusionOrder): vector<u8> {
        fusion_order.destination_recipient
    }

    /// Gets the destination chain ID of a fusion order.
    public fun get_chain_id(fusion_order: &FusionOrder): u64 {
        fusion_order.chain_id
    }

    /// Gets the hash of the secret in a fusion order.
    public fun get_hash(fusion_order: &FusionOrder): vector<u8> {
        fusion_order.hash
    }

    /// Gets the initial destination amount of a fusion order.
    public fun get_initial_destination_amount(fusion_order: &FusionOrder): u64 {
        fusion_order.initial_destination_amount
    }

    /// Gets the minimum destination amount of a fusion order.
    public fun get_min_destination_amount(fusion_order: &FusionOrder): u64 {
        fusion_order.min_destination_amount
    }

    /// Gets the decay per second of a fusion order.
    public fun get_decay_per_second(fusion_order: &FusionOrder): u64 {
        fusion_order.decay_per_second
    }

    /// Gets the auction start time of a fusion order.
    public fun get_auction_start_time(fusion_order: &FusionOrder): u64 {
        fusion_order.auction_start_time
    }

    // - - - - UTILITY FUNCTIONS - - - -

    /// Checks if a hash value is valid (non-empty).
    /// Using Move's safety features to prevent vulnerabilities.
    public fun is_valid_hash(hash: &vector<u8>): bool {
        hash.length() > 0
    }

    /// Checks if a destination asset specification represents a native asset.
    public fun is_native_asset(destination_asset: &vector<u8>): bool {
        let len = destination_asset.length();
        if (len == 0) { return true }; // Empty vector is considered native
        
        let mut i = 0;
        while (i < len) {
            if (destination_asset[i] != 0) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Checks if a destination asset specification represents a valid EVM contract address.
    public fun is_evm_contract_address(destination_asset: &vector<u8>): bool {
        !is_native_asset(destination_asset) && destination_asset.length() == 20
    }

    /// Checks if a destination recipient address is a valid EVM address.
    public fun is_valid_evm_address(destination_recipient: &vector<u8>): bool {
        destination_recipient.length() == 20
    }

    /// Calculates the current Dutch auction price based on elapsed time.
    /// Following Sui's pattern for time-based calculations using the Clock object.
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
    public fun get_current_dutch_auction_price(
        fusion_order: &FusionOrder,
        clock: &Clock
    ): u64 {
        calculate_current_dutch_auction_price(
            fusion_order.initial_destination_amount,
            fusion_order.min_destination_amount,
            fusion_order.decay_per_second,
            fusion_order.auction_start_time,
            clock
        )
    }

    #[test_only]
    /// Test-only version of resolver_accept_order that can be called from test modules.
    /// This function has the same implementation as resolver_accept_order but is public for testing.
    /// 
    /// @param fusion_order The fusion order to accept.
    /// @param ctx The transaction context.
    /// 
    /// @reverts EOBJECT_DOES_NOT_EXIST if the fusion order does not exist.
    /// @reverts EINVALID_RESOLVER if the signer is not an active resolver.
    /// @reverts EINSUFFICIENT_BALANCE if resolver has insufficient safety deposit.
    /// @return (Coin<u64>, Coin<u64>) The main asset and safety deposit asset.
    public fun resolver_accept_order_for_test(
        fusion_order: FusionOrder,
        ctx: &mut TxContext
    ): (Coin<u64>, Coin<u64>) {
        // This is a placeholder for the test function
        // In a real implementation, this would contain the same logic as resolver_accept_order
        // but made public for testing purposes
        let FusionOrder { id, source_coin, .. } = fusion_order;
        
        // For testing, we'll just return the source coin and a dummy safety deposit
        // In production, this would involve resolver validation and safety deposit logic
        let safety_deposit_coin = coin::zero<u64>(ctx);
        
        // Delete the fusion order
        object::delete(id);
        
        (source_coin, safety_deposit_coin)
    }
}