module sui_fusion_plus::escrow {
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use sui_fusion_plus::hashlock::{Self, HashLock};
    use sui_fusion_plus::timelock::{Self, Timelock};
    use sui_fusion_plus::constants;
    use sui_fusion_plus::fusion_order::{Self, FusionOrder};

    // - - - - ERROR CODES - - - -

    /// Invalid phase
    const EINVALID_PHASE: u64 = 1;
    /// Invalid caller
    const EINVALID_CALLER: u64 = 2;
    /// Invalid secret
    const EINVALID_SECRET: u64 = 3;
    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 4;
    /// Object does not exist
    const EOBJECT_DOES_NOT_EXIST: u64 = 5;

    // - - - - EVENTS - - - -

    /// Event emitted when an escrow is created
    public struct EscrowCreatedEvent has drop, store, copy {
        escrow: address,        // Escrow object address for tracking
        from: address,          // Address that created/funded the escrow
        to: address,            // Address that can withdraw the escrow
        resolver: address,      // Resolver managing this escrow
        coin_type: vector<u8>, // Asset coin type (must match across chains)
        amount: u64,            // Asset amount (must match across chains)
        chain_id: u64,         // Blockchain network identifier
        is_source_chain: bool  // TRUE = source chain, FALSE = destination chain
    }

    /// Event emitted when an escrow is withdrawn by the recipient
    public struct EscrowWithdrawnEvent has drop, store, copy {
        escrow: address,        // Escrow object that was withdrawn
        recipient: address,     // Address that successfully withdrew
        resolver: address,      // Resolver that processed the withdrawal
        coin_type: vector<u8>, // Asset coin type
        amount: u64             // Amount withdrawn
    }

    /// Event emitted when an escrow is recovered/cancelled
    public struct EscrowRecoveredEvent has drop, store, copy {
        escrow: address,        // Escrow object that was recovered
        recovered_by: address,  // Address that recovered the assets
        returned_to: address,   // Address that received the returned assets
        coin_type: vector<u8>, // Asset coin type
        amount: u64             // Amount recovered
    }

    // - - - - STRUCTS - - - -

    /// An Escrow Object that contains the assets that are being escrowed.
    /// Following Sui's object-centric model for rich on-chain assets.
    public struct Escrow has key, store {
        id: UID,
        coin_type: vector<u8>,
        amount: u64,
        from: address,
        to: address,
        resolver: address,
        chain_id: u64,
        timelock: Timelock,
        hashlock: HashLock,
        /// Asset storage using Sui's coin model
        asset_coin: Coin<u64>, // Main asset being escrowed
        safety_deposit_coin: Coin<u64>, // Safety deposit from resolver
    }

    // - - - - ENTRY FUNCTIONS - - - -

    /// Entry function for creating escrow from fusion order
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This creates a SOURCE CHAIN escrow (is_source_chain = true)
    /// - Called when resolver picks up a user's fusion order
    /// - Resolver must then create corresponding destination chain escrow
    /// 
    /// RESOLVER FLOW:
    /// 1. Call this function to accept fusion order
    /// 2. Listen for EscrowCreatedEvent with is_source_chain = true
    /// 3. Create matching escrow on destination chain
    /// 4. Monitor both escrows for withdrawal events
    public entry fun new_from_order_entry(
        fusion_order: FusionOrder,
        safety_deposit_coin: Coin<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let escrow = new_from_order(fusion_order, safety_deposit_coin, clock, ctx);
        // Transfer the escrow to the sender
        transfer::public_transfer(escrow, tx_context::sender(ctx));
    }

    /// Entry function for creating escrow directly from resolver
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This creates a DESTINATION CHAIN escrow (is_source_chain = false)
    /// - Called when resolver creates escrow on destination chain
    /// - Must match the source chain escrow parameters exactly
    /// 
    /// RESOLVER FLOW:
    /// 1. Call this function on destination chain
    /// 2. Provide same hash, amount, and metadata as source chain
    /// 3. Listen for EscrowCreatedEvent with is_source_chain = false
    /// 4. Both escrows now exist for atomic swap
    public entry fun new_from_resolver_entry(
        recipient_address: address,
        coin_type: vector<u8>,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        asset_coin: Coin<u64>,
        safety_deposit_coin: Coin<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let escrow = new_from_resolver(
            recipient_address,
            coin_type,
            amount,
            chain_id,
            hash,
            asset_coin,
            safety_deposit_coin,
            clock,
            ctx
        );
        // Transfer the escrow to the sender
        transfer::public_transfer(escrow, tx_context::sender(ctx));
    }

    // - - - - PUBLIC FUNCTIONS - - - -

    /// Creates a new Escrow from a fusion order.
    /// This function is called when a resolver picks up a fusion order.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Creates SOURCE CHAIN escrow (is_source_chain = true)
    /// - Assets from user's fusion order are locked in escrow
    /// - Resolver must create matching destination chain escrow
    /// - Assets stay in escrow for hashlock/timelock protection
    /// 
    /// RESOLVER FLOW:
    /// 1. Call this function to accept fusion order
    /// 2. Assets are locked in source chain escrow
    /// 3. Create matching destination chain escrow
    /// 4. Monitor both escrows for withdrawal events
    /// 5. Call withdraw on destination first, then source
    /// 
    /// RESOLVER RESPONSIBILITIES:
    /// 1. Ensure you have matching assets on destination chain before accepting
    /// 2. Create destination escrow with same parameters
    /// 3. Monitor both escrows for withdrawal events
    /// 4. Handle the complete cross-chain swap lifecycle
    ///
    /// @param fusion_order The fusion order to convert to escrow.
    /// @param safety_deposit_coin The safety deposit coin from the resolver.
    /// @param clock The clock object to get current time.
    /// @param ctx The transaction context.
    ///
    /// @return Escrow The created escrow object.
    public fun new_from_order(
        fusion_order: FusionOrder,
        safety_deposit_coin: Coin<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Escrow {
        let owner_address = fusion_order::get_owner(&fusion_order);
        let resolver_address = tx_context::sender(ctx);
        let chain_id = fusion_order::get_chain_id(&fusion_order);
        let hash = fusion_order::get_hash(&fusion_order);
        
        // Extract assets from fusion order
        let (asset_coin, safety_deposit_asset) = fusion_order::resolver_accept_order(
            fusion_order,
            safety_deposit_coin,
            ctx
        );
        
        new_internal(
            asset_coin,
            safety_deposit_asset,
            owner_address, //from
            resolver_address, //to
            resolver_address, //resolver
            chain_id,
            hash,
            clock,
            ctx
        )
    }

    /// Creates a new Escrow directly from a resolver.
    /// This function is called when a resolver creates an escrow without a fusion order.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Creates DESTINATION CHAIN escrow (is_source_chain = false)
    /// - Assets come from resolver's own balance
    /// - Must match source chain escrow parameters exactly
    /// 
    /// RESOLVER RESPONSIBILITIES:
    /// 1. Ensure you have sufficient assets on destination chain
    /// 2. Use same hash, amount, and metadata as source chain
    /// 3. Monitor both escrows for withdrawal events
    /// 4. Handle cancellation scenarios on both chains
    ///
    /// @param recipient_address The address that can withdraw the escrow.
    /// @param coin_type The coin type of the asset being escrowed.
    /// @param amount The amount of the asset being escrowed.
    /// @param chain_id The chain ID where this asset originated.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param asset_coin The asset coin being escrowed.
    /// @param safety_deposit_coin The safety deposit coin from the resolver.
    /// @param clock The clock object to get current time.
    /// @param ctx The transaction context.
    ///
    /// @reverts EINVALID_AMOUNT if amount is zero.
    /// @reverts EINSUFFICIENT_BALANCE if resolver has insufficient balance.
    /// @return Escrow The created escrow object.
    public fun new_from_resolver(
        recipient_address: address,
        coin_type: vector<u8>,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        asset_coin: Coin<u64>,
        safety_deposit_coin: Coin<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Escrow {
        let resolver_address = tx_context::sender(ctx);

        // Validate inputs
        assert!(amount > 0, EINVALID_AMOUNT);
        assert!(hashlock::is_valid_hash(&hash), EINVALID_SECRET);

        new_internal(
            asset_coin,
            safety_deposit_coin,
            resolver_address, // from
            recipient_address, // to
            resolver_address, // resolver
            chain_id,
            hash,
            clock,
            ctx
        )
    }

    /// Internal function to create a new Escrow with the specified parameters.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Determines is_source_chain based on resolver == to relationship
    /// - Emits EscrowCreatedEvent with all cross-chain coordination details
    /// - Stores assets in escrow object for secure holding
    /// 
    /// RESOLVER SHOULD MONITOR:
    /// - EscrowCreatedEvent for cross-chain state tracking
    /// - is_source_chain flag to know which chain this escrow is on
    /// - chain_id to identify the blockchain network
    /// - hash to ensure matching escrows across chains
    ///
    /// @param asset_coin The asset coin to escrow.
    /// @param safety_deposit_coin The safety deposit coin.
    /// @param from The address that created the escrow.
    /// @param to The address that can withdraw the escrow.
    /// @param resolver The resolver address managing this escrow.
    /// @param chain_id The chain ID where this asset originated.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param clock The clock object to get current time.
    /// @param ctx The transaction context.
    ///
    /// @return Escrow The created escrow object.
    fun new_internal(
        asset_coin: Coin<u64>,
        safety_deposit_coin: Coin<u64>,
        from: address,
        to: address,
        resolver: address,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Escrow {

        // Create timelock based on chain type
        let mut timelock = if (chain_id == constants::get_source_chain_id()) {
            timelock::new_source()
        } else {
            timelock::new_destination()
        };
        timelock::set_creation_time(&mut timelock, clock);
        
        let hashlock = hashlock::create_hashlock(hash);

        let amount = coin::value(&asset_coin);
        let coin_type = b"0x2::sui::SUI"; // Placeholder - in real implementation this would be extracted from coin

        // Create the Escrow using Sui's object model
        let escrow = Escrow {
            id: object::new(ctx),
            coin_type,
            amount,
            from,
            to,
            resolver,
            chain_id,
            timelock,
            hashlock,
            // Asset storage using Sui's coin model
            asset_coin, // Main asset being escrowed
            safety_deposit_coin, // Safety deposit from resolver
        };

        // Determine if this is on source chain (resolver == to)
        // CROSS-CHAIN LOGIC: This determines which chain the escrow is on
        // - TRUE: Source chain (user -> resolver)
        // - FALSE: Destination chain (resolver -> recipient)
        let is_source_chain = resolver == to;

        // Emit creation event with cross-chain coordination details
        // RESOLVER SHOULD MONITOR THIS EVENT:
        // - Track escrow creation on both chains
        // - Ensure matching escrows exist with same hash
        // - Use is_source_chain to know which chain this is on
        event::emit(
            EscrowCreatedEvent {
                escrow: object::uid_to_address(&escrow.id),
                from,
                to,
                resolver,
                coin_type,
                amount,
                chain_id,
                is_source_chain
            }
        );

        escrow
    }

    /// Withdraws assets from an escrow using the correct secret.
    /// This function can only be called by the resolver during the exclusive phase.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Only resolvers call withdraw (users never call withdraw)
    /// - Requires correct secret for hashlock verification
    /// - Emits EscrowWithdrawnEvent for cross-chain coordination
    /// 
    /// WITHDRAW FLOW:
    /// 1. Resolver calls withdraw on destination chain escrow
    ///    - Tokens transferred to user
    ///    - Safety deposit returned to resolver
    /// 2. Resolver calls withdraw on source chain escrow  
    ///    - Tokens transferred to resolver
    ///    - Safety deposit returned to resolver
    /// 
    /// RESOLVER RESPONSIBILITIES:
    /// 1. Monitor EscrowWithdrawnEvent on both chains
    /// 2. Call withdraw on destination chain first (user gets tokens)
    /// 3. Then call withdraw on source chain (resolver gets tokens)
    /// 4. Ensure atomic swap completion across chains
    ///
    /// @param escrow The escrow to withdraw from.
    /// @param secret The secret to verify against the hashlock.
    /// @param clock The clock object to get current time.
    /// @param ctx The transaction context.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the escrow does not exist.
    /// @reverts EINVALID_CALLER if the signer is not the resolver.
    /// @reverts EINVALID_PHASE if not in exclusive phase.
    /// @reverts EINVALID_SECRET if the secret does not match the hashlock.
    public entry fun withdraw(
        escrow: Escrow, 
        secret: vector<u8>, 
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let signer_address = tx_context::sender(ctx);

        assert!(escrow.resolver == signer_address, EINVALID_CALLER);

        let timelock = escrow.timelock;
        // Check if withdrawal is allowed
        assert!(
            timelock::is_withdrawal_allowed(&timelock, clock), 
            EINVALID_PHASE
        );

        // Verify the secret matches the hashlock
        // CROSS-CHAIN LOGIC: Same secret must work on both chains
        assert!(
            hashlock::verify_hashlock(&escrow.hashlock, secret), EINVALID_SECRET
        );

        // Store event data before deletion
        let recipient = escrow.to;
        let coin_type = escrow.coin_type;
        let amount = escrow.amount;

        // Transfer main assets to recipient using Sui's transfer model
        let Escrow { id, asset_coin, safety_deposit_coin, .. } = escrow;
        transfer::public_transfer(asset_coin, recipient);

        // Return safety deposit to resolver
        transfer::public_transfer(safety_deposit_coin, signer_address);

        // Emit withdrawal event for cross-chain coordination
        // RESOLVER SHOULD MONITOR THIS EVENT:
        // - Trigger corresponding withdrawal on other chain
        // - Ensure atomic swap completion
        // - Handle partial swap scenarios
        event::emit(
            EscrowWithdrawnEvent {
                escrow: object::uid_to_address(&id),
                recipient,
                resolver: signer_address,
                coin_type,
                amount
            }
        );

        // Delete the escrow object
        object::delete(id);
    }

    /// Recovers assets from an escrow during cancellation phases.
    /// This function can be called by the resolver during private cancellation phase
    /// or by anyone during public cancellation phase.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - Private cancellation: Only resolver can recover (admin control)
    /// - Public cancellation: Anyone can recover (emergency access)
    /// - Emits EscrowRecoveredEvent for cross-chain coordination
    /// 
    /// RESOLVER RESPONSIBILITIES:
    /// 1. Monitor EscrowRecoveredEvent on both chains
    /// 2. Cancel corresponding escrow on other chain if needed
    /// 3. Handle partial swap scenarios
    /// 4. Ensure proper cleanup across chains
    ///
    /// @param escrow The escrow to recover from.
    /// @param clock The clock object to get current time.
    /// @param ctx The transaction context.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the escrow does not exist.
    /// @reverts EINVALID_CALLER if the signer is not the resolver during private cancellation.
    /// @reverts EINVALID_PHASE if not in cancellation phase.
    public entry fun recovery(
        escrow: Escrow, 
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let signer_address = tx_context::sender(ctx);

        let timelock = escrow.timelock;

        // Check if cancellation is allowed
        assert!(
            timelock::is_cancellation_allowed(&timelock, clock), 
            EINVALID_PHASE
        );

        // Check if we're in private cancellation phase (only resolver can cancel)
        if (timelock::is_in_cancellation_phase(&timelock, clock)) {
            // Private cancellation: only resolver can cancel
            assert!(signer_address == escrow.resolver, EINVALID_CALLER);
        } else {
            // Public cancellation: anyone can cancel (no caller validation needed)
            assert!(
                timelock::is_in_public_cancellation_phase(&timelock, clock), 
                EINVALID_PHASE
            );
        };

        // Store event data before deletion
        let recovered_by = signer_address;
        let returned_to = escrow.from;
        let coin_type = escrow.coin_type;
        let amount = escrow.amount;

        // Return main assets to original depositor using Sui's transfer model
        let Escrow { id, asset_coin, safety_deposit_coin, .. } = escrow;
        transfer::public_transfer(asset_coin, returned_to);

        // Return safety deposit to resolver
        transfer::public_transfer(safety_deposit_coin, signer_address);

        // Emit recovery event for cross-chain coordination
        event::emit(
            EscrowRecoveredEvent { 
                escrow: object::uid_to_address(&id), 
                recovered_by, 
                returned_to, 
                coin_type, 
                amount 
            }
        );

        // Delete the escrow object
        object::delete(id);
    }

    // - - - - GETTER FUNCTIONS - - - -

    /// Gets the coin type of the asset in an escrow.
    public fun get_coin_type(escrow: &Escrow): vector<u8> {
        escrow.coin_type
    }

    /// Gets the amount of the asset in an escrow.
    public fun get_amount(escrow: &Escrow): u64 {
        escrow.amount
    }

    /// Gets the 'from' address of an escrow.
    public fun get_from(escrow: &Escrow): address {
        escrow.from
    }

    /// Gets the 'to' address of an escrow.
    public fun get_to(escrow: &Escrow): address {
        escrow.to
    }

    /// Gets the resolver address of an escrow.
    public fun get_resolver(escrow: &Escrow): address {
        escrow.resolver
    }

    /// Gets the chain ID of an escrow.
    public fun get_chain_id(escrow: &Escrow): u64 {
        escrow.chain_id
    }

    /// Gets the timelock of an escrow.
    public fun get_timelock(escrow: &Escrow): Timelock {
        escrow.timelock
    }

    /// Gets the hashlock of an escrow.
    public fun get_hashlock(escrow: &Escrow): HashLock {
        escrow.hashlock
    }

    // - - - - UTILITY FUNCTIONS - - - -

    /// Checks if an escrow is on the source chain.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - TRUE: This escrow is on the source chain (user -> resolver)
    /// - FALSE: This escrow is on the destination chain (resolver -> recipient)
    /// 
    /// RESOLVER SHOULD USE:
    /// - To determine which chain this escrow is on
    /// - For cross-chain coordination logic
    /// - To ensure matching escrows exist on both chains
    ///
    /// @param escrow The escrow to check.
    /// @return bool True if the escrow is on the source chain, false otherwise.
    public fun is_source_chain(escrow: &Escrow): bool {
        escrow.to == escrow.resolver
    }
} 