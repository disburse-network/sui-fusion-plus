#[test_only]
module sui_fusion_plus::basic_working_test {
    use std::hash;
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;

    use sui_fusion_plus::hashlock::{Self};
    use sui_fusion_plus::constants;

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";

    #[test]
    fun test_hashlock_basic() {
        let scenario = test_scenario::begin(@0x201);
        
        // Test hashlock creation and verification
        let hashlock = hashlock::create_hashlock_for_test(TEST_SECRET);
        
        // Verify hashlock properties
        assert!(hashlock::verify_hashlock(&hashlock, TEST_SECRET), 0);
        assert!(!hashlock::verify_hashlock(&hashlock, b"wrong secret"), 1);
        
        // Consume the hashlock
        transfer::public_transfer(hashlock, @0x0);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_constants() {
        let scenario = test_scenario::begin(@0x201);
        
        // Test that constants are accessible
        let safety_deposit = constants::get_safety_deposit_amount();
        
        // Verify constants have reasonable values
        assert!(safety_deposit > 0, 0);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_hashlock_validation() {
        let scenario = test_scenario::begin(@0x201);
        
        // Test hash validation
        assert!(hashlock::is_valid_hash(&hash::sha3_256(TEST_SECRET)), 0);
        assert!(!hashlock::is_valid_hash(&vector::empty<u8>()), 1);
        
        // Test secret validation
        assert!(hashlock::is_valid_secret(&TEST_SECRET), 2);
        assert!(!hashlock::is_valid_secret(&vector::empty<u8>()), 3);
        
        test_scenario::end(scenario);
    }
} 