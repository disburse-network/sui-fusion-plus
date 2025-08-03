#[test_only]
module sui_fusion_plus::resolver_registry_tests_fixed {
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;

    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};

    // Test addresses
    const ADMIN_ADDRESS: address = @sui_fusion_plus;
    const RESOLVER_ADDRESS: address = @0x203;
    const NON_RESOLVER_ADDRESS: address = @0x204;

    fun setup_test(): (Scenario, Clock, ResolverRegistry) {
        let scenario = test_scenario::begin(ADMIN_ADDRESS);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        (scenario, clock, registry)
    }

    #[test]
    fun test_register_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register a new resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify resolver is registered and active
        assert!(resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 0);
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 1);
        assert!(resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry), 2);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // ENOT_AUTHORIZED
    fun test_register_resolver_by_non_admin() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Switch to non-admin account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to register resolver as non-admin
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // EALREADY_REGISTERED
    fun test_register_resolver_twice() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first time
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to register same resolver again
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_deactivate_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify resolver is deactivated
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 0);
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 1);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // ENOT_AUTHORIZED
    fun test_deactivate_resolver_by_non_admin() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Switch to non-admin account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to deactivate resolver as non-admin
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // ENOT_REGISTERED
    fun test_deactivate_unregistered_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Try to deactivate unregistered resolver
        resolver_registry::deactivate_resolver(
            NON_RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_reactivate_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Reactivate resolver
        resolver_registry::reactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify resolver is active again
        assert!(resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 0);
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 1);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // ENOT_AUTHORIZED
    fun test_reactivate_resolver_by_non_admin() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Switch to non-admin account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to reactivate resolver as non-admin
        resolver_registry::reactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // ENOT_REGISTERED
    fun test_reactivate_unregistered_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Try to reactivate unregistered resolver
        resolver_registry::reactivate_resolver(
            NON_RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify resolver is deactivated
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 0);
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 1);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // ENOT_AUTHORIZED
    fun test_remove_resolver_by_non_admin() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver first
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Switch to non-admin account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to deactivate resolver as non-admin
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // ENOT_REGISTERED
    fun test_remove_unregistered_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Try to deactivate unregistered resolver
        resolver_registry::deactivate_resolver(
            NON_RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_is_resolver_registered() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Initially, resolver should not be registered
        assert!(!resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 0);
        assert!(!resolver_registry::is_resolver_registered(NON_RESOLVER_ADDRESS, &registry), 1);

        // Register resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Now resolver should be registered
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 2);
        assert!(!resolver_registry::is_resolver_registered(NON_RESOLVER_ADDRESS, &registry), 3);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_is_resolver_active() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Initially, resolver should not be active
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 0);

        // Register resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Now resolver should be active
        assert!(resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 1);

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Now resolver should not be active
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 2);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_resolver_status() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Get resolver status
        let status = resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry);
        assert!(status, 0); // Should be active (true)

        // Deactivate resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Get resolver status again
        let status2 = resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry);
        assert!(!status2, 1); // Should be inactive (false)

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_resolvers() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register multiple resolvers
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        resolver_registry::register_resolver(
            NON_RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify both resolvers are registered and active
        assert!(resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 0);
        assert!(resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 1);
        assert!(resolver_registry::is_resolver_registered(NON_RESOLVER_ADDRESS, &registry), 2);
        assert!(resolver_registry::is_resolver_active(NON_RESOLVER_ADDRESS, &registry), 3);

        // Deactivate one resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify one is inactive, other is still active
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 4);
        assert!(resolver_registry::is_resolver_active(NON_RESOLVER_ADDRESS, &registry), 5);

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }
} 