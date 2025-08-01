#[test_only]
module sui_fusion_plus::simple_test {
    use sui::test_scenario::{Self, Scenario};
    use sui_fusion_plus::hashlock;
    use sui_fusion_plus::constants;

    #[test]
    fun test_hashlock_creation() {
        let scenario = test_scenario::begin(@0x1);
        
        // Test hashlock creation
        let hash = b"test_hash_32_bytes_long_for_testing";
        let hashlock = hashlock::create_hashlock(hash);
        
        // Verify the hashlock was created correctly
        assert!(hashlock::get_hash(&hashlock) == hash, 0);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_constants() {
        let scenario = test_scenario::begin(@0x1);
        
        // Test constants
        assert!(constants::get_safety_deposit_amount() == 100_000, 0);
        assert!(constants::get_source_chain_id() == 1, 0);
        
        test_scenario::end(scenario);
    }
} 