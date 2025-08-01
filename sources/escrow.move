module sui_fusion_plus::escrow {
    use std::signer;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, Object, UID};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::transfer;

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

    #[event]
    /// Event emitted when an escrow is created
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - is_source_chain = true: This escrow is on the source chain (where user deposited assets)
    /// - is_source_chain = false: This escrow is on the destination chain (where recipient will claim)
    /// - chain_id: Identifies which blockchain network this escrow is on
    /// - hash: The secret hash that must match across both chains for atomic swap
    /// - from/to: Shows asset flow direction (from user to resolver, or resolver to recipient)
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor these events on both chains
    /// 2. Ensure matching escrows exist on both chains with same hash
    /// 3. Track escrow lifecycle for cross-chain coordination
    struct EscrowCreatedEvent has drop, store {
        escrow: Object<Escrow>,        // Escrow object address for tracking
        from: address,                  // Address that created/funded the escrow
        to: address,                    // Address that can withdraw the escrow
        resolver: address,              // Resolver managing this escrow
        coin_type: vector<u8>,         // Asset coin type (must match across chains)
        amount: u64,                    // Asset amount (must match across chains)
        chain_id: u64,                 // Blockchain network identifier
        is_source_chain: bool          // TRUE = source chain, FALSE = destination chain
    }

    #[event]
    /// Event emitted when an escrow is withdrawn by the recipient
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - When this event fires on destination chain, resolver should release source chain escrow
    /// - When this event fires on source chain, resolver should release destination chain escrow
    /// - This ensures atomic swap completion across chains
    /// 
    /// RESOLVER SHOULD:
    /// 1. Listen for this event on both chains
    /// 2. Trigger corresponding withdrawal on the other chain
    /// 3. Verify the secret was correct before releasing other chain
    struct EscrowWithdrawnEvent has drop, store {
        escrow: Object<Escrow>,        // Escrow object that was withdrawn
        recipient: address,             // Address that successfully withdrew
        resolver: address,              // Resolver that processed the withdrawal
        coin_type: vector<u8>,         // Asset coin type
        amount: u64                     // Amount withdrawn
    }

    #[event]
    /// Event emitted when an escrow is recovered/cancelled
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This indicates escrow cancellation or recovery
    /// - Resolver should handle cleanup on the other chain
    /// - May need to cancel corresponding escrow on other chain
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor for recovery events on both chains
    /// 2. Cancel corresponding escrow on other chain if needed
    /// 3. Handle partial swap scenarios
    struct EscrowRecoveredEvent has drop, store {
        escrow: Object<Escrow>,        // Escrow object that was recovered
        recovered_by: address,          // Address that recovered the assets
        returned_to: address,           // Address that received the returned assets
        coin_type: vector<u8>,         // Asset coin type
        amount: u64                     // Amount recovered
    }

    // - - - - STRUCTS - - - -

    /// An Escrow Object that contains the assets that are being escrowed.
    /// The object can be stored in other structs because it has the `store` ability.
    ///
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - from: On source chain = user address, on destination chain = resolver address
    /// - to: On source chain = resolver address, on destination chain = recipient address
    /// - resolver: Always the resolver address (same on both chains)
    /// - chain_id: Identifies which blockchain this escrow is on
    /// - hash: Must be identical across both chains for atomic swap
    /// - timelock: Controls phase-based access (finality -> exclusive -> cancellation phases)
    /// - hashlock: Protects assets with secret verification
    ///
    /// @param coin_type The coin type of the asset.
    /// @param amount The amount of the asset being escrowed.
    /// @param from The address that created the escrow (source).
    /// @param to The address that can withdraw the escrow (destination).
    /// @param resolver The resolver address managing this escrow.
    /// @param chain_id Chain ID where this asset originated.
    /// @param timelock The timelock controlling the asset phases.
    /// @param hashlock The hashlock protecting the asset.
    struct Escrow has key, store {
        id: UID,
        coin_type: vector<u8>,
        amount: u64,
        from: address,
        to: address,
        resolver: address,
        chain_id: u64,
        timelock: Timelock,
        hashlock: HashLock,
        /// Asset storage
        asset_balance: Balance<Coin<u64>>, // Main asset being escrowed
        safety_deposit_balance: Balance<Coin<u64>>, // Safety deposit from resolver
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
        resolver: &signer, fusion_order: Object<FusionOrder>, clock: &Clock
    ) {
        new_from_order(resolver, fusion_order, clock);
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
    /// 2. Provide same hash, amount, and coin_type as source chain
    /// 3. Listen for EscrowCreatedEvent with is_source_chain = false
    /// 4. Both escrows now exist for atomic swap
    public entry fun new_from_resolver_entry(
        resolver: &signer,
        recipient_address: address,
        coin_type: vector<u8>,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock
    ) {
        new_from_resolver(
            resolver,
            recipient_address,
            coin_type,
            amount,
            chain_id,
            hash,
            clock
        );
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
    /// @param resolver The signer of the resolver accepting the order.
    /// @param fusion_order The fusion order to convert to escrow.
    /// @param clock The clock object to get current time.
    ///
    /// @return Object<Escrow> The created escrow object.
    public fun new_from_order(
        resolver: &signer, fusion_order: Object<FusionOrder>, clock: &Clock
    ): Object<Escrow> {
        let owner_address = fusion_order::get_owner(fusion_order);
        let resolver_address = signer::address_of(resolver);
        let chain_id = fusion_order::get_chain_id(fusion_order);
        let hash = fusion_order::get_hash(fusion_order);
        let (asset, safety_deposit_asset) =
            fusion_order::resolver_accept_order(resolver, fusion_order, clock);
        new_internal(
            resolver,
            asset,
            safety_deposit_asset,
            owner_address, //from
            resolver_address, //to
            resolver_address, //resolver
            chain_id,
            hash,
            clock
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
    /// 2. Use same hash, amount, and coin_type as source chain
    /// 3. Monitor both escrows for withdrawal events
    /// 4. Handle cancellation scenarios on both chains
    ///
    /// @param resolver The signer of the resolver creating the escrow.
    /// @param recipient_address The address that can withdraw the escrow.
    /// @param coin_type The coin type of the asset being escrowed.
    /// @param amount The amount of the asset being escrowed.
    /// @param chain_id The chain ID where this asset originated.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param clock The clock object to get current time.
    ///
    /// @reverts EINVALID_AMOUNT if amount is zero.
    /// @reverts EINSUFFICIENT_BALANCE if resolver has insufficient balance.
    /// @return Object<Escrow> The created escrow object.
    public fun new_from_resolver(
        resolver: &signer,
        recipient_address: address,
        coin_type: vector<u8>,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock
    ): Object<Escrow> {
        let resolver_address = signer::address_of(resolver);

        // Validate inputs
        assert!(amount > 0, EINVALID_AMOUNT);
        assert!(hashlock::is_valid_hash(&hash), EINVALID_SECRET);

        // Create coins from resolver's balance
        let asset = coin::from_balance(
            balance::split(&mut balance::zero(), amount),
            resolver_address
        );

        let safety_deposit_asset = coin::from_balance(
            balance::split(&mut balance::zero(), constants::get_safety_deposit_amount()),
            resolver_address
        );

        new_internal(
            resolver,
            asset,
            safety_deposit_asset,
            resolver_address, // from
            recipient_address, // to
            resolver_address, // resolver
            chain_id,
            hash,
            clock
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
    /// @param signer The signer creating the escrow.
    /// @param asset The coin to escrow.
    /// @param safety_deposit_asset The safety deposit coin.
    /// @param from The address that created the escrow.
    /// @param to The address that can withdraw the escrow.
    /// @param resolver The resolver address managing this escrow.
    /// @param chain_id The chain ID where this asset originated.
    /// @param hash The hash of the secret for the cross-chain swap.
    /// @param clock The clock object to get current time.
    ///
    /// @return Object<Escrow> The created escrow object.
    fun new_internal(
        signer: &signer,
        asset: Coin<u64>,
        safety_deposit_asset: Coin<u64>,
        from: address,
        to: address,
        resolver: address,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock
    ): Object<Escrow> {

        // Create timelock based on chain type
        let mut timelock = if (chain_id == constants::get_source_chain_id()) {
            timelock::new_source()
        } else {
            timelock::new_destination()
        };
        timelock::set_creation_time(&mut timelock, clock);
        
        let hashlock = hashlock::create_hashlock(hash);

        let coin_type = coin::get_coin_type(&asset);
        let amount = coin::value(&asset);

        // Create the Escrow
        let escrow = Escrow {
            id: object::new(signer),
            coin_type,
            amount,
            from,
            to,
            resolver,
            chain_id,
            timelock,
            hashlock,
            asset_balance: balance::zero(),
            safety_deposit_balance: balance::zero(),
        };

        // Store the assets in the escrow
        balance::join(&mut escrow.asset_balance, asset);
        balance::join(&mut escrow.safety_deposit_balance, safety_deposit_asset);

        let escrow_obj = object::share_object(escrow);

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
                escrow: escrow_obj,
                from,
                to,
                resolver,
                coin_type,
                amount,
                chain_id,
                is_source_chain
            }
        );

        escrow_obj
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
    /// @param signer The signer of the resolver (only resolvers can withdraw).
    /// @param escrow The escrow to withdraw from.
    /// @param secret The secret to verify against the hashlock.
    /// @param clock The clock object to get current time.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the escrow does not exist.
    /// @reverts EINVALID_CALLER if the signer is not the resolver.
    /// @reverts EINVALID_PHASE if not in exclusive phase.
    /// @reverts EINVALID_SECRET if the secret does not match the hashlock.
    public entry fun withdraw(
        signer: &signer, escrow: Object<Escrow>, secret: vector<u8>, clock: &Clock
    ) acquires Escrow {
        let signer_address = signer::address_of(signer);

        assert!(escrow_exists(escrow), EOBJECT_DOES_NOT_EXIST);

        let escrow_ref = borrow_escrow_mut(&escrow);
        assert!(escrow_ref.resolver == signer_address, EINVALID_CALLER);

        let timelock = escrow_ref.timelock;
        // Check if withdrawal is allowed (not in finality lock and in withdrawal phase)
        assert!(
            timelock::is_withdrawal_allowed(&timelock, clock), 
            EINVALID_PHASE
        );

        // Verify the secret matches the hashlock
        // CROSS-CHAIN LOGIC: Same secret must work on both chains
        assert!(
            hashlock::verify_hashlock(&escrow_ref.hashlock, secret), EINVALID_SECRET
        );

        // Store event data before deletion
        let recipient = escrow_ref.to;
        let coin_type = escrow_ref.coin_type;
        let amount = escrow_ref.amount;

        // Transfer main assets to recipient (user on destination, resolver on source)
        let asset_coin = balance::split(&mut escrow_ref.asset_balance, amount);
        transfer::transfer(asset_coin, recipient);

        // Return safety deposit to resolver
        let safety_deposit_coin = balance::split(&mut escrow_ref.safety_deposit_balance, constants::get_safety_deposit_amount());
        transfer::transfer(safety_deposit_coin, signer_address);

        // Emit withdrawal event for cross-chain coordination
        // RESOLVER SHOULD MONITOR THIS EVENT:
        // - Trigger corresponding withdrawal on other chain
        // - Ensure atomic swap completion
        // - Handle partial swap scenarios
        event::emit(
            EscrowWithdrawnEvent {
                escrow,
                recipient,
                resolver: signer_address,
                coin_type,
                amount
            }
        );

        // Delete the escrow
        let Escrow { id, asset_balance, safety_deposit_balance, .. } = object::delete(escrow);
        balance::destroy_zero(asset_balance);
        balance::destroy_zero(safety_deposit_balance);
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
    /// @param signer The signer attempting to recover the escrow.
    /// @param escrow The escrow to recover from.
    /// @param clock The clock object to get current time.
    ///
    /// @reverts EOBJECT_DOES_NOT_EXIST if the escrow does not exist.
    /// @reverts EINVALID_CALLER if the signer is not the resolver during private cancellation.
    /// @reverts EINVALID_PHASE if not in cancellation phase.
    public entry fun recovery(
        signer: &signer, escrow: Object<Escrow>, clock: &Clock
    ) acquires Escrow {
        let signer_address = signer::address_of(signer);

        assert!(escrow_exists(escrow), EOBJECT_DOES_NOT_EXIST);

        let escrow_ref = borrow_escrow_mut(&escrow);
        let timelock = escrow_ref.timelock;

        // Check if cancellation is allowed (not in finality lock and in cancellation phase)
        assert!(
            timelock::is_cancellation_allowed(&timelock, clock), 
            EINVALID_PHASE
        );

        // Check if we're in private cancellation phase (only resolver can cancel)
        if (timelock::is_in_cancellation_phase(&timelock, clock)) {
            // Private cancellation: only resolver can cancel
            assert!(signer_address == escrow_ref.resolver, EINVALID_CALLER);
        } else {
            // Public cancellation: anyone can cancel (no caller validation needed)
            assert!(
                timelock::is_in_public_cancellation_phase(&timelock, clock), 
                EINVALID_PHASE
            );
        };

        // Store event data before deletion
        let recovered_by = signer_address;
        let returned_to = escrow_ref.from;
        let coin_type = escrow_ref.coin_type;
        let amount = escrow_ref.amount;

        // Return main assets to original depositor
        let asset_coin = balance::split(&mut escrow_ref.asset_balance, amount);
        transfer::transfer(asset_coin, returned_to);

        // Return safety deposit to resolver
        let safety_deposit_coin = balance::split(&mut escrow_ref.safety_deposit_balance, constants::get_safety_deposit_amount());
        transfer::transfer(safety_deposit_coin, signer_address);

        // Emit recovery event for cross-chain coordination
        event::emit(
            EscrowRecoveredEvent { escrow, recovered_by, returned_to, coin_type, amount }
        );

        // Delete the escrow
        let Escrow { id, asset_balance, safety_deposit_balance, .. } = object::delete(escrow);
        balance::destroy_zero(asset_balance);
        balance::destroy_zero(safety_deposit_balance);
    }

    // - - - - GETTER FUNCTIONS - - - -

    /// Gets the coin type of the asset in an escrow.
    ///
    /// @param escrow The escrow to get the coin type from.
    /// @return vector<u8> The coin type of the asset.
    public fun get_coin_type(escrow: Object<Escrow>): vector<u8> acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.coin_type
    }

    /// Gets the amount of the asset in an escrow.
    ///
    /// @param escrow The escrow to get the amount from.
    /// @return u64 The amount of the asset.
    public fun get_amount(escrow: Object<Escrow>): u64 acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.amount
    }

    /// Gets the 'from' address of an escrow.
    ///
    /// @param escrow The escrow to get the 'from' address from.
    /// @return address The address that created the escrow.
    public fun get_from(escrow: Object<Escrow>): address acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.from
    }

    /// Gets the 'to' address of an escrow.
    ///
    /// @param escrow The escrow to get the 'to' address from.
    /// @return address The address that can withdraw the escrow.
    public fun get_to(escrow: Object<Escrow>): address acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.to
    }

    /// Gets the resolver address of an escrow.
    ///
    /// @param escrow The escrow to get the resolver from.
    /// @return address The resolver address.
    public fun get_resolver(escrow: Object<Escrow>): address acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.resolver
    }

    /// Gets the chain ID of an escrow.
    ///
    /// @param escrow The escrow to get the chain ID from.
    /// @return u64 The chain ID.
    public fun get_chain_id(escrow: Object<Escrow>): u64 acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.chain_id
    }

    /// Gets the timelock of an escrow.
    ///
    /// @param escrow The escrow to get the timelock from.
    /// @return Timelock The timelock object.
    public fun get_timelock(escrow: Object<Escrow>): Timelock acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.timelock
    }

    /// Gets the hashlock of an escrow.
    ///
    /// @param escrow The escrow to get the hashlock from.
    /// @return HashLock The hashlock object.
    public fun get_hashlock(escrow: Object<Escrow>): HashLock acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.hashlock
    }

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
    public fun is_source_chain(escrow: Object<Escrow>): bool acquires Escrow {
        let escrow_ref = borrow_escrow(&escrow);
        escrow_ref.to == escrow_ref.resolver
    }

    // - - - - UTILITY FUNCTIONS - - - -

    /// Checks if an escrow exists.
    ///
    /// @param escrow The escrow object to check.
    /// @return bool True if the escrow exists, false otherwise.
    public fun escrow_exists(escrow: Object<Escrow>): bool {
        object::exists(object::uid_to_address(&escrow))
    }

    // - - - - BORROW FUNCTIONS - - - -

    /// Borrows an immutable reference to the Escrow.
    ///
    /// @param escrow_obj The escrow object.
    /// @return &Escrow Immutable reference to the escrow.
    inline fun borrow_escrow(escrow_obj: &Object<Escrow>): &Escrow {
        borrow_global<Escrow>(object::uid_to_address(escrow_obj))
    }

    /// Borrows a mutable reference to the Escrow.
    ///
    /// @param escrow_obj The escrow object.
    /// @return &mut Escrow Mutable reference to the escrow.
    inline fun borrow_escrow_mut(escrow_obj: &Object<Escrow>): &mut Escrow {
        borrow_global_mut<Escrow>(object::uid_to_address(escrow_obj))
    }
} 