module sui_fusion_plus::resolver_registry {

    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    // - - - - ERROR CODES - - - -

    /// Unauthorized access attempt
    const ENOT_AUTHORIZED: u64 = 0;
    /// Invalid status change (e.g., deactivating already inactive resolver)
    const EINVALID_STATUS_CHANGE: u64 = 1;
    /// Resolver not found in registry
    const ENOT_REGISTERED: u64 = 2;
    /// Resolver already registered
    const EALREADY_REGISTERED: u64 = 3;

    // - - - - EVENTS - - - -

    /// Event emitted when a new resolver is registered
    public struct ResolverRegisteredEvent has drop, store, copy {
        resolver: address,    // Address of the newly registered resolver
        registered_at: u64    // Timestamp when registration occurred
    }

    /// Event emitted when a resolver's status changes
    public struct ResolverStatusEvent has drop, store, copy {
        resolver: address,    // Address of the resolver whose status changed
        is_active: bool,      // TRUE = active, FALSE = inactive
        changed_at: u64       // Timestamp when status changed
    }

    // - - - - STRUCTS - - - -

    /// Resolver information stored in the registry.
    /// Following Sui's object-centric model for rich on-chain data.
    public struct Resolver has store {
        registered_at: u64,
        last_status_change: u64,
        status: bool
    }

    /// Global resolver registry that stores all registered resolvers.
    /// Using Sui's Table for efficient data storage.
    public struct ResolverRegistry has key, store {
        id: UID,
        resolvers: Table<address, Resolver>
    }

    // - - - - INITIALIZATION - - - -

    /// Initializes the resolver registry module.
    /// Following Sui's pattern for module initialization.
    fun init_module(ctx: &mut TxContext) {
        let resolver_registry =
            ResolverRegistry {
                id: object::new(ctx),
                resolvers: table::new<address, Resolver>(ctx)
            };
        transfer::public_transfer(resolver_registry, tx_context::sender(ctx));
    }

    // - - - - PUBLIC FUNCTIONS - - - -

    /// Registers a new resolver in the registry.
    /// Following Sui's pattern for entry functions with proper parameter ordering.
    public entry fun register_resolver(
        resolver_address: address,
        registry: &mut ResolverRegistry,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        // Check if resolver is already registered
        assert!(!table::contains(&registry.resolvers, resolver_address), EALREADY_REGISTERED);

        let current_time = 0; // Placeholder for timestamp

        let resolver_info = Resolver {
            registered_at: current_time,
            last_status_change: current_time,
            status: true // Default to active
        };

        table::add(&mut registry.resolvers, resolver_address, resolver_info);

        // Emit registration event
        event::emit(
            ResolverRegisteredEvent {
                resolver: resolver_address,
                registered_at: current_time
            }
        );
    }

    /// Activates a resolver in the registry.
    /// Using Sui's pattern for status management.
    public entry fun activate_resolver(
        resolver_address: address,
        registry: &mut ResolverRegistry,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow_mut(&mut registry.resolvers, resolver_address);
        assert!(!resolver_info.status, EINVALID_STATUS_CHANGE);

        let current_time = 0; // Placeholder for timestamp

        resolver_info.status = true;
        resolver_info.last_status_change = current_time;

        // Emit status change event
        event::emit(
            ResolverStatusEvent {
                resolver: resolver_address,
                is_active: true,
                changed_at: current_time
            }
        );
    }

    /// Deactivates a resolver in the registry.
    /// Using Sui's pattern for status management.
    public entry fun deactivate_resolver(
        resolver_address: address,
        registry: &mut ResolverRegistry,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow_mut(&mut registry.resolvers, resolver_address);
        assert!(resolver_info.status, EINVALID_STATUS_CHANGE);

        let current_time = 0; // Placeholder for timestamp

        resolver_info.status = false;
        resolver_info.last_status_change = current_time;

        // Emit status change event
        event::emit(
            ResolverStatusEvent {
                resolver: resolver_address,
                is_active: false,
                changed_at: current_time
            }
        );
    }

    /// Checks if a resolver is registered and active.
    /// Following Sui's pattern for data access.
    public fun is_resolver_active(resolver_address: address, registry: &ResolverRegistry): bool {
        if (!table::contains(&registry.resolvers, resolver_address)) {
            return false
        };

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.status
    }

    /// Gets the registration timestamp of a resolver.
    public fun get_resolver_registration_time(resolver_address: address, registry: &ResolverRegistry): u64 {
        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.registered_at
    }

    /// Gets the last status change timestamp of a resolver.
    public fun get_resolver_last_status_change(resolver_address: address, registry: &ResolverRegistry): u64 {
        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.last_status_change
    }

    /// Gets the current status of a resolver.
    public fun get_resolver_status(resolver_address: address, registry: &ResolverRegistry): bool {
        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.status
    }
} 