#[test_only]
module sui_fusion_plus::resolver_registry_tests {
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};

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
        assert!(!resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry), 2);

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

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // ENOT_REGISTERED
    fun test_deactivate_unregistered_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Try to deactivate unregistered resolver
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_STATUS_CHANGE
    fun test_deactivate_already_deactivated_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver
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

        // Try to deactivate again
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_reactivate_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver
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
        assert!(resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry), 1);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // ENOT_AUTHORIZED
    fun test_reactivate_resolver_by_non_admin() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register and deactivate resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        resolver_registry::deactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Switch to non-admin account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to reactivate as non-admin
        resolver_registry::reactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // ENOT_REGISTERED
    fun test_reactivate_unregistered_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Try to reactivate unregistered resolver
        resolver_registry::reactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_STATUS_CHANGE
    fun test_reactivate_already_active_resolver() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver (starts active)
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to reactivate already active resolver
        resolver_registry::reactivate_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_resolvers() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        let resolver1 = @0x301;
        let resolver2 = @0x302;
        let resolver3 = @0x303;

        // Register multiple resolvers
        resolver_registry::register_resolver(
            resolver1,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        resolver_registry::register_resolver(
            resolver2,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );
        resolver_registry::register_resolver(
            resolver3,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify all are active
        assert!(resolver_registry::is_resolver_active(resolver1, &registry), 0);
        assert!(resolver_registry::is_resolver_active(resolver2, &registry), 1);
        assert!(resolver_registry::is_resolver_active(resolver3, &registry), 2);

        // Deactivate one
        resolver_registry::deactivate_resolver(
            resolver2,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify status
        assert!(resolver_registry::is_resolver_active(resolver1, &registry), 3);
        assert!(!resolver_registry::is_resolver_active(resolver2, &registry), 4);
        assert!(resolver_registry::is_resolver_active(resolver3, &registry), 5);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_resolver_getter_functions() {
        let (mut scenario, clock, mut registry) = setup_test();
        
        // Register resolver
        resolver_registry::register_resolver(
            RESOLVER_ADDRESS,
            &mut registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Test getter functions
        let registration_time = resolver_registry::get_resolver_registration_time(RESOLVER_ADDRESS, &registry);
        let last_status_change = resolver_registry::get_resolver_last_status_change(RESOLVER_ADDRESS, &registry);
        let status = resolver_registry::get_resolver_status(RESOLVER_ADDRESS, &registry);

        assert!(registration_time > 0, 0);
        assert!(last_status_change > 0, 1);
        assert!(status, 2); // Should be active

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // ENOT_REGISTERED
    fun test_getter_functions_for_unregistered_resolver() {
        let (mut scenario, _clock, registry) = setup_test();
        
        // Try to get info for unregistered resolver
        resolver_registry::get_resolver_registration_time(RESOLVER_ADDRESS, &registry);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_edge_cases() {
        let (mut scenario, _clock, registry) = setup_test();
        
        // Test that unregistered resolver is not active
        assert!(!resolver_registry::is_resolver_active(RESOLVER_ADDRESS, &registry), 0);
        assert!(!resolver_registry::is_resolver_registered(RESOLVER_ADDRESS, &registry), 1);

        // Test with zero address
        assert!(!resolver_registry::is_resolver_active(@0x0, &registry), 2);
        assert!(!resolver_registry::is_resolver_registered(@0x0, &registry), 3);

        test_scenario::end(scenario);
    }
} 