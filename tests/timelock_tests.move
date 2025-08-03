#[test_only]
module sui_fusion_plus::timelock_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui_fusion_plus::timelock::{Self, Timelock};
    use sui::object;

    #[test]
    fun test_create_timelock() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let timelock = timelock::new_source();

        // Verify timelock properties
        assert!(timelock::is_source_chain(&timelock), 0);
        assert!(!timelock::is_destination_chain(&timelock), 0);

        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_destination_timelock() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let timelock = timelock::new_destination();

        // Verify timelock properties
        assert!(!timelock::is_source_chain(&timelock), 0);
        assert!(timelock::is_destination_chain(&timelock), 0);

        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_chain_type_functions() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let source_timelock = timelock::new_source();
        let dest_timelock = timelock::new_destination();

        // Test chain type getters
        assert!(timelock::get_chain_type(&source_timelock) == timelock::get_chain_type_source(), 0);
        assert!(timelock::get_chain_type(&dest_timelock) == timelock::get_chain_type_destination(), 0);

        // Test chain type checks
        assert!(timelock::is_source_chain(&source_timelock), 0);
        assert!(!timelock::is_source_chain(&dest_timelock), 0);
        assert!(!timelock::is_destination_chain(&source_timelock), 0);
        assert!(timelock::is_destination_chain(&dest_timelock), 0);

        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = timelock::EINVALID_CHAIN_TYPE)]
    fun test_invalid_chain_type() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        // Try to create timelock with invalid chain type
        timelock::new_for_test(99); // Invalid chain type

        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_phase_getter_functions() {
        // Test source chain phase constants
        assert!(timelock::get_src_phase_finality_lock() == 0, 0);
        assert!(timelock::get_src_phase_withdrawal() == 1, 0);
        assert!(timelock::get_src_phase_public_withdrawal() == 2, 0);
        assert!(timelock::get_src_phase_cancellation() == 3, 0);
        assert!(timelock::get_src_phase_public_cancellation() == 4, 0);

        // Test destination chain phase constants
        assert!(timelock::get_dst_phase_finality_lock() == 0, 0);
        assert!(timelock::get_dst_phase_withdrawal() == 1, 0);
        assert!(timelock::get_dst_phase_public_withdrawal() == 2, 0);
        assert!(timelock::get_dst_phase_cancellation() == 3, 0);
    }

    #[test]
    fun test_creation_time() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        let mut timelock = timelock::new_source();
        
        // Set creation time
        timelock::set_creation_time(&mut timelock, &clock);
        
        // Get creation time
        let creation_time = timelock::get_creation_time(&timelock);
        assert!(creation_time > 0, 0);

        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }
} 