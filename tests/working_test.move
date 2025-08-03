#[test_only]
module sui_fusion_plus::working_test {
    use std::hash;
    use sui::test_scenario::{Self, Scenario};
    use sui_fusion_plus::hashlock::{Self};
    use sui_fusion_plus::constants;

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";

    #[test]
    fun test_hashlock_basic() {
        let mut scenario = test_scenario::begin(@0x201);
        
        // Create hashlock
        let hashlock = hashlock::create_hashlock_for_test(TEST_SECRET);
        
        // Test basic functionality
        assert!(hashlock::verify_hashlock(&hashlock, TEST_SECRET), 0);
        assert!(!hashlock::verify_hashlock(&hashlock, b"wrong secret"), 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_constants() {
        // Test that constants are accessible
        let safety_deposit = constants::get_safety_deposit_amount();
        assert!(safety_deposit > 0, 0);
        
        let src_finality = constants::get_src_finality_lock();
        assert!(src_finality > 0, 1);
    }
} 