module sui_fusion_plus::fusion_order {
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use sui_fusion_plus::constants;

    // - - - - ERROR CODES - - - -

    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 1;
    /// Invalid hash
    const EINVALID_HASH: u64 = 6;

    // - - - - EVENTS - - - -

    /// Event emitted when a fusion order is created
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
    public struct FusionOrderCancelledEvent has drop, store, copy {
        fusion_order: address, // Order object that was cancelled
        owner: address,         // User who cancelled the order
        source_amount: u64                  // Amount that was cancelled
    }

    // - - - - STRUCTS - - - -

    /// A fusion order that represents a user's intent to swap assets across chains.
    /// Following Sui's object-centric model for rich on-chain assets.
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
} 