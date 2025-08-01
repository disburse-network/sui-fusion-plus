module sui_fusion_plus::resolver_registry {

    use std::signer;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::object::{Self, Object, UID};

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

    #[event]
    /// Event emitted when a new resolver is registered
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This event indicates a new resolver has been whitelisted
    /// - Only registered resolvers can participate in cross-chain swaps
    /// - Resolvers must be registered before they can accept fusion orders
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor this event to know when new resolvers are added
    /// 2. Track registered resolver addresses for potential collaboration
    /// 3. Ensure you are registered before attempting cross-chain swaps
    /// 4. Use this for resolver network monitoring
    struct ResolverRegisteredEvent has drop, store {
        resolver: address,    // Address of the newly registered resolver
        registered_at: u64    // Timestamp when registration occurred
    }

    #[event]
    /// Event emitted when a resolver's status changes
    /// 
    /// CROSS-CHAIN RESOLVER LOGIC:
    /// - This event indicates a resolver has been activated or deactivated
    /// - is_active = true: Resolver can participate in cross-chain swaps
    /// - is_active = false: Resolver is temporarily disabled
    /// 
    /// RESOLVER SHOULD:
    /// 1. Monitor this event to track resolver status changes
    /// 2. Check if you are still active before accepting new orders
    /// 3. Handle deactivation gracefully (complete existing swaps)
    /// 4. Use this for resolver network health monitoring
    struct ResolverStatusEvent has drop, store {
        resolver: address,    // Address of the resolver whose status changed
        is_active: bool,      // TRUE = active, FALSE = inactive
        changed_at: u64       // Timestamp when status changed
    }

    // - - - - STRUCTS - - - -

    /// Resolver information stored in the registry.
    ///
    /// @param registered_at Timestamp when the resolver was registered.
    /// @param last_status_change Timestamp of the last status change (activation/deactivation).
    /// @param status Current status of the resolver (true = active, false = inactive).
    struct Resolver has store {
        registered_at: u64,
        last_status_change: u64,
        status: bool
    }

    /// Global resolver registry that stores all registered resolvers.
    ///
    /// @param resolvers Table mapping resolver addresses to their information.
    struct ResolverRegistry has key {
        id: UID,
        resolvers: Table<address, Resolver>
    }

    // - - - - INITIALIZATION - - - -

    /// Initializes the resolver registry module.
    /// This function is called during module deployment.
    ///
    /// @param signer The signer of the fusion_plus account.
    fun init_module(signer: &signer) {
        let resolver_registry =
            ResolverRegistry {
                id: object::new(signer),
                resolvers: table::new<address, Resolver>()
            };
        move_to(signer, resolver_registry);
    }

    // - - - - PUBLIC FUNCTIONS - - - -

    /// Registers a new resolver in the registry.
    /// Only the admin (@sui_fusion_plus) can register resolvers.
    ///
    /// @param signer The signer of the admin account.
    /// @param address The address of the resolver to register.
    ///
    /// @reverts ENOT_AUTHORIZED if the signer is not the admin.
    /// @reverts EALREADY_REGISTERED if the resolver is already registered.
    public entry fun register_resolver(
        signer: &signer, resolver_address: address
    ) acquires ResolverRegistry {
        let admin_address = signer::address_of(signer);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        let registry = borrow_global_mut<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        // Check if resolver is already registered
        assert!(!table::contains(&registry.resolvers, resolver_address), EALREADY_REGISTERED);

        let clock = clock::new_for_testing();
        let current_time = clock::timestamp_ms(&clock);

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
    /// Only the admin (@sui_fusion_plus) can activate resolvers.
    ///
    /// @param signer The signer of the admin account.
    /// @param resolver_address The address of the resolver to activate.
    ///
    /// @reverts ENOT_AUTHORIZED if the signer is not the admin.
    /// @reverts ENOT_REGISTERED if the resolver is not registered.
    /// @reverts EINVALID_STATUS_CHANGE if the resolver is already active.
    public entry fun activate_resolver(
        signer: &signer, resolver_address: address
    ) acquires ResolverRegistry {
        let admin_address = signer::address_of(signer);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        let registry = borrow_global_mut<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow_mut(&mut registry.resolvers, resolver_address);
        assert!(!resolver_info.status, EINVALID_STATUS_CHANGE);

        let clock = clock::new_for_testing();
        let current_time = clock::timestamp_ms(&clock);

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
    /// Only the admin (@sui_fusion_plus) can deactivate resolvers.
    ///
    /// @param signer The signer of the admin account.
    /// @param resolver_address The address of the resolver to deactivate.
    ///
    /// @reverts ENOT_AUTHORIZED if the signer is not the admin.
    /// @reverts ENOT_REGISTERED if the resolver is not registered.
    /// @reverts EINVALID_STATUS_CHANGE if the resolver is already inactive.
    public entry fun deactivate_resolver(
        signer: &signer, resolver_address: address
    ) acquires ResolverRegistry {
        let admin_address = signer::address_of(signer);
        assert!(admin_address == @sui_fusion_plus, ENOT_AUTHORIZED);

        let registry = borrow_global_mut<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow_mut(&mut registry.resolvers, resolver_address);
        assert!(resolver_info.status, EINVALID_STATUS_CHANGE);

        let clock = clock::new_for_testing();
        let current_time = clock::timestamp_ms(&clock);

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
    ///
    /// @param resolver_address The address of the resolver to check.
    /// @return bool True if the resolver is registered and active, false otherwise.
    public fun is_resolver_active(resolver_address: address): bool acquires ResolverRegistry {
        let registry = borrow_global<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        if (!table::contains(&registry.resolvers, resolver_address)) {
            return false
        };

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.status
    }

    /// Gets the registration timestamp of a resolver.
    ///
    /// @param resolver_address The address of the resolver.
    /// @return u64 The registration timestamp.
    ///
    /// @reverts ENOT_REGISTERED if the resolver is not registered.
    public fun get_resolver_registration_time(resolver_address: address): u64 acquires ResolverRegistry {
        let registry = borrow_global<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.registered_at
    }

    /// Gets the last status change timestamp of a resolver.
    ///
    /// @param resolver_address The address of the resolver.
    /// @return u64 The last status change timestamp.
    ///
    /// @reverts ENOT_REGISTERED if the resolver is not registered.
    public fun get_resolver_last_status_change(resolver_address: address): u64 acquires ResolverRegistry {
        let registry = borrow_global<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.last_status_change
    }

    /// Gets the current status of a resolver.
    ///
    /// @param resolver_address The address of the resolver.
    /// @return bool The current status (true = active, false = inactive).
    ///
    /// @reverts ENOT_REGISTERED if the resolver is not registered.
    public fun get_resolver_status(resolver_address: address): bool acquires ResolverRegistry {
        let registry = borrow_global<sui_fusion_plus::resolver_registry::ResolverRegistry>(
            @sui_fusion_plus
        );

        assert!(table::contains(&registry.resolvers, resolver_address), ENOT_REGISTERED);

        let resolver_info = table::borrow(&registry.resolvers, resolver_address);
        resolver_info.status
    }
} 