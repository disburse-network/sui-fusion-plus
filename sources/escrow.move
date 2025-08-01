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

    // - - - - ERROR CODES - - - -

    /// Invalid phase
    const EINVALID_PHASE: u64 = 1;
    /// Invalid caller
    const EINVALID_CALLER: u64 = 2;
    /// Invalid secret
    const EINVALID_SECRET: u64 = 3;
    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 4;

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

    /// Entry function for creating escrow directly from resolver
    /// Following Sui's pattern for entry functions with proper parameter ordering.
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

    /// Creates a new Escrow directly from a resolver.
    /// Following Sui's Move language patterns for safety and expressivity.
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

        // Validate inputs using Move's safety features
        assert!(amount > 0, EINVALID_AMOUNT);
        assert!(hashlock::is_valid_hash(&hash), EINVALID_SECRET);

        // Create timelock based on chain type
        let mut timelock = if (chain_id == constants::get_source_chain_id()) {
            timelock::new_source()
        } else {
            timelock::new_destination()
        };
        timelock::set_creation_time(&mut timelock, clock);
        
        let hashlock = hashlock::create_hashlock(hash);

        // Create the Escrow using Sui's object model
        let escrow = Escrow {
            id: object::new(ctx),
            coin_type,
            amount,
            from: resolver_address, // from
            to: recipient_address,   // to
            resolver: resolver_address, // resolver
            chain_id,
            timelock,
            hashlock,
            // Asset storage using Sui's coin model
            asset_coin, // Main asset being escrowed
            safety_deposit_coin, // Safety deposit from resolver
        };

        // Determine if this is on source chain (resolver == to)
        let is_source_chain = resolver_address == recipient_address;

        // Emit creation event with cross-chain coordination details
        event::emit(
            EscrowCreatedEvent {
                escrow: object::uid_to_address(&escrow.id),
                from: resolver_address,
                to: recipient_address,
                resolver: resolver_address,
                coin_type,
                amount,
                chain_id,
                is_source_chain
            }
        );

        escrow
    }

    /// Withdraws assets from an escrow using the correct secret.
    /// Using Sui's transfer model for safe asset movement.
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
    /// Using Sui's transfer model for safe asset movement.
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

    // - - - - UTILITY FUNCTIONS - - - -

    /// Checks if an escrow is on the source chain.
    /// Following Sui's pattern for cross-chain coordination logic.
    public fun is_source_chain(escrow: &Escrow): bool {
        escrow.to == escrow.resolver
    }
} 