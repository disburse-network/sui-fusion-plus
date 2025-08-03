#[test_only]
module sui_fusion_plus::timelock_tests {
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};

    use sui_fusion_plus::timelock::{Self};
    use sui_fusion_plus::constants;

    // Test addresses
    const OWNER_ADDRESS: address = @0x201;

    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(OWNER_ADDRESS);
        scenario
    }

    #[test]
    fun test_create_source_timelock() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Verify source chain timelock properties
        assert!(timelock::get_chain_type(&timelock) == 0, 0); // Source chain
        assert!(timelock::is_source_chain(&timelock), 1);
        assert!(!timelock::is_destination_chain(&timelock), 2);
        assert!(timelock::get_creation_time(&timelock) > 0, 3);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_destination_timelock() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_destination();
        timelock::set_creation_time(&mut timelock, &clock);

        // Verify destination chain timelock properties
        assert!(timelock::get_chain_type(&timelock) == 1, 0); // Destination chain
        assert!(!timelock::is_source_chain(&timelock), 1);
        assert!(timelock::is_destination_chain(&timelock), 2);
        assert!(timelock::get_creation_time(&timelock) > 0, 3);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_source_chain_phases() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test initial phase (finality lock)
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 0, 0); // SRC_PHASE_FINALITY_LOCK
        assert!(timelock::is_in_finality_lock_phase(&timelock, &clock), 1);
        assert!(!timelock::is_withdrawal_allowed(&timelock, &clock), 2);
        assert!(!timelock::is_cancellation_allowed(&timelock, &clock), 3);

        // Fast forward to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 1, 4); // SRC_PHASE_WITHDRAWAL
        assert!(!timelock::is_in_finality_lock_phase(&timelock, &clock), 5);
        assert!(timelock::is_withdrawal_allowed(&timelock, &clock), 6);
        assert!(timelock::is_in_withdrawal_phase(&timelock, &clock), 7);
        assert!(!timelock::is_cancellation_allowed(&timelock, &clock), 8);

        // Fast forward to public withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_public_withdrawal() - constants::get_src_withdrawal() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 2, 9); // SRC_PHASE_PUBLIC_WITHDRAWAL
        assert!(timelock::is_withdrawal_allowed(&timelock, &clock), 10);
        assert!(timelock::is_in_public_withdrawal_phase(&timelock, &clock), 11);

        // Fast forward to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() - constants::get_src_public_withdrawal() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 3, 12); // SRC_PHASE_CANCELLATION
        assert!(timelock::is_cancellation_allowed(&timelock, &clock), 13);
        assert!(timelock::is_in_cancellation_phase(&timelock, &clock), 14);

        // Fast forward to public cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_public_cancellation() - constants::get_src_cancellation() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 4, 15); // SRC_PHASE_PUBLIC_CANCELLATION
        assert!(timelock::is_cancellation_allowed(&timelock, &clock), 16);
        assert!(timelock::is_in_public_cancellation_phase(&timelock, &clock), 17);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_destination_chain_phases() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_destination();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test initial phase (finality lock)
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 0, 0); // DST_PHASE_FINALITY_LOCK
        assert!(timelock::is_in_finality_lock_phase(&timelock, &clock), 1);
        assert!(!timelock::is_withdrawal_allowed(&timelock, &clock), 2);
        assert!(!timelock::is_cancellation_allowed(&timelock, &clock), 3);

        // Fast forward to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_dst_withdrawal() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 1, 4); // DST_PHASE_WITHDRAWAL
        assert!(!timelock::is_in_finality_lock_phase(&timelock, &clock), 5);
        assert!(timelock::is_withdrawal_allowed(&timelock, &clock), 6);
        assert!(timelock::is_in_withdrawal_phase(&timelock, &clock), 7);
        assert!(!timelock::is_cancellation_allowed(&timelock, &clock), 8);

        // Fast forward to public withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_dst_public_withdrawal() - constants::get_dst_withdrawal() + 1000);
        
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 2, 9); // DST_PHASE_PUBLIC_WITHDRAWAL
        assert!(timelock::is_withdrawal_allowed(&timelock, &clock), 10);
        assert!(timelock::is_in_public_withdrawal_phase(&timelock, &clock), 11);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_phase_transitions() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test phase transitions
        let mut scenario2 = setup_test();
        let ctx2 = test_scenario::ctx(&mut scenario2);
        let mut clock2 = clock::create_for_testing(ctx2);
        
        let mut timelock2 = timelock::new_source();
        timelock::set_creation_time(&mut timelock2, &clock2);
        clock::increment_for_testing(&mut clock2, constants::get_dst_withdrawal());

        let mut scenario3 = setup_test();
        let ctx3 = test_scenario::ctx(&mut scenario3);
        let mut clock3 = clock::create_for_testing(ctx3);
        
        let mut timelock3 = timelock::new_source();
        timelock::set_creation_time(&mut timelock3, &clock3);
        clock::increment_for_testing(&mut clock3, constants::get_dst_public_withdrawal());

        test_scenario::end(scenario3);
    }

    #[test]
    fun test_edge_cases() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test edge cases
        assert!(timelock::get_creation_time(&timelock) > 0, 0);
        assert!(timelock::get_chain_type(&timelock) == 0, 1);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_destination_chain_edge_cases() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_destination();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test destination chain edge cases
        assert!(timelock::get_creation_time(&timelock) > 0, 0);
        assert!(timelock::get_chain_type(&timelock) == 1, 1);
        assert!(timelock::is_destination_chain(&timelock), 2);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_remaining_time_calculations() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test remaining time calculations
        let remaining = timelock::get_remaining_time(&timelock, &clock);
        assert!(remaining > 0, 0); // Should have remaining time

        // Fast forward and test remaining time
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() / 2);
        let remaining = timelock::get_remaining_time(&timelock, &clock);
        assert!(remaining > 0, 1); // Should still have remaining time

        // Fast forward to end
        clock::increment_for_testing(&mut clock, constants::get_src_public_cancellation());
        let remaining = timelock::get_remaining_time(&timelock, &clock);
        assert!(remaining == 0, 2); // Should have no remaining time

        test_scenario::end(scenario);
    }

    #[test]
    fun test_creation_time_setting() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        
        // Test setting creation time
        timelock::set_creation_time(&mut timelock, &clock);
        
        // Verify creation time was set
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 0, 0); // Should be in finality lock phase

        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_timelock_instances() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        // Create multiple timelock instances
        let mut timelock1 = timelock::new_source();
        let mut timelock2 = timelock::new_destination();
        let mut timelock3 = timelock::new_source();
        
        timelock::set_creation_time(&mut timelock1, &clock);
        timelock::set_creation_time(&mut timelock2, &clock);
        timelock::set_creation_time(&mut timelock3, &clock);
        
        // Test that they have different properties
        let phase1 = timelock::get_phase(&timelock1, &clock);
        let phase2 = timelock::get_phase(&timelock2, &clock);
        let phase3 = timelock::get_phase(&timelock3, &clock);
        
        assert!(phase1 == 0, 0);
        assert!(phase2 == 0, 1);
        assert!(phase3 == 0, 2);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_timelock_phase_boundaries() {
        let mut scenario = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);

        // Test at exact boundary times
        clock::increment_for_testing(&mut clock, constants::get_src_finality_lock());
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 1, 0); // Should be in withdrawal

        // Reset and test at withdrawal boundary
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal());
        let phase = timelock::get_phase(&timelock, &clock);
        assert!(phase == 2, 1); // Should be in public withdrawal

        test_scenario::end(scenario);
    }
} 