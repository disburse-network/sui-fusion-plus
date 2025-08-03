#[test_only]
module sui_fusion_plus::simple_test {
    use std::hash;
    use sui::test_scenario::{Self, Scenario};
    use sui_fusion_plus::constants;
    use sui_fusion_plus::hashlock::{Self, HashLock};
    use sui_fusion_plus::timelock::{Self, Timelock};

    const TEST_SECRET: vector<u8> = b"test_secret_123";

    #[test]
    fun test_hashlock_basic() {
        let scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create hashlock
        let hashlock = hashlock::create_hashlock(hash::sha3_256(TEST_SECRET));
        
        // Test basic functionality
        assert!(hashlock::get_hash(&hashlock) == hash::sha3_256(TEST_SECRET), 0);
        assert!(hashlock::is_valid_secret(&TEST_SECRET), 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_timelock_basic() {
        let scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = sui::clock::create_for_testing(ctx);
        
        // Create timelock
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);
        
        // Test basic functionality
        assert!(timelock::get_chain_type(&timelock) == 0, 0);
        assert!(timelock::is_source_chain(&timelock), 1);
        
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