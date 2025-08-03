#[test_only]
module sui_fusion_plus::hashlock_tests {
    use std::hash;
    use sui::test_scenario::{Self, Scenario};

    use sui_fusion_plus::hashlock::{Self};

    // Test addresses
    const OWNER_ADDRESS: address = @0x201;

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";
    const WRONG_SECRET: vector<u8> = b"wrong secret";
    const EMPTY_SECRET: vector<u8> = b"";
    const LONG_SECRET: vector<u8> = b"this is a very long secret that should still work";

    fun setup_test(): Scenario {
        let scenario = test_scenario::begin(OWNER_ADDRESS);
        scenario
    }

    #[test]
    fun test_create_hashlock() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(TEST_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Verify hashlock properties
        assert!(hashlock::get_hash(&hashlock) == hash, 0);
        assert!(hashlock::is_valid_hash(&hash), 1);

        test_scenario::end(_scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_HASH
    fun test_create_hashlock_with_invalid_hash() {
        let mut _scenario = setup_test();
        
        let invalid_hash = vector::empty<u8>(); // Empty hash
        hashlock::create_hashlock(invalid_hash);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_verify_hashlock_with_correct_secret() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(TEST_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Verify with correct secret
        let result = hashlock::verify_hashlock(&hashlock, TEST_SECRET);
        assert!(result, 0);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_verify_hashlock_with_wrong_secret() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(TEST_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Verify with wrong secret
        let result = hashlock::verify_hashlock(&hashlock, WRONG_SECRET);
        assert!(!result, 0);

        test_scenario::end(_scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)] // EINVALID_SECRET
    fun test_verify_hashlock_with_empty_secret() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(TEST_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Try to verify with empty secret
        hashlock::verify_hashlock(&hashlock, EMPTY_SECRET);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_verify_hashlock_with_long_secret() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(LONG_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Verify with long secret
        let result = hashlock::verify_hashlock(&hashlock, LONG_SECRET);
        assert!(result, 0);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_hash_validation() {
        // Test valid hash (32 bytes)
        let valid_hash = hash::sha3_256(TEST_SECRET);
        assert!(hashlock::is_valid_hash(&valid_hash), 0);

        // Test invalid hash (empty)
        let invalid_hash = vector::empty<u8>();
        assert!(!hashlock::is_valid_hash(&invalid_hash), 1);

        // Test invalid hash (wrong length)
        let short_hash = b"\x11\x22\x33"; // 3 bytes
        assert!(!hashlock::is_valid_hash(&short_hash), 2);
    }

    #[test]
    fun test_secret_validation() {
        // Test valid secret (non-empty)
        assert!(hashlock::is_valid_secret(&TEST_SECRET), 0);
        assert!(hashlock::is_valid_secret(&LONG_SECRET), 1);

        // Test invalid secret (empty)
        assert!(!hashlock::is_valid_secret(&EMPTY_SECRET), 2);
    }

    #[test]
    fun test_hashlock_edge_cases() {
        let mut _scenario = setup_test();
        
        // Test with single byte secret
        let single_byte_secret = b"a";
        let single_byte_hash = hash::sha3_256(single_byte_secret);
        let single_byte_hashlock = hashlock::create_hashlock(single_byte_hash);
        
        let result = hashlock::verify_hashlock(&single_byte_hashlock, single_byte_secret);
        assert!(result, 0);

        // Test with very long secret
        let very_long_secret = b"this is an extremely long secret that contains many characters and should still work correctly with the hashlock verification system";
        let very_long_hash = hash::sha3_256(very_long_secret);
        let very_long_hashlock = hashlock::create_hashlock(very_long_hash);
        
        let result = hashlock::verify_hashlock(&very_long_hashlock, very_long_secret);
        assert!(result, 1);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_hashlock_with_special_characters() {
        let mut _scenario = setup_test();
        
        // Test with special characters
        let special_secret = b"!@#$%^&*()_+-=[]{}|;':\",./<>?";
        let special_hash = hash::sha3_256(special_secret);
        let special_hashlock = hashlock::create_hashlock(special_hash);
        
        let result = hashlock::verify_hashlock(&special_hashlock, special_secret);
        assert!(result, 0);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_hashlock_with_binary_data() {
        let mut _scenario = setup_test();
        
        // Test with binary data
        let binary_secret = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f";
        let binary_hash = hash::sha3_256(binary_secret);
        let binary_hashlock = hashlock::create_hashlock(binary_hash);
        
        let result = hashlock::verify_hashlock(&binary_hashlock, binary_secret);
        assert!(result, 0);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_multiple_hashlocks() {
        let mut _scenario = setup_test();
        
        // Create multiple hashlocks with different secrets
        let secret1 = b"secret1";
        let secret2 = b"secret2";
        let secret3 = b"secret3";
        
        let hash1 = hash::sha3_256(secret1);
        let hash2 = hash::sha3_256(secret2);
        let hash3 = hash::sha3_256(secret3);
        
        let hashlock1 = hashlock::create_hashlock(hash1);
        let hashlock2 = hashlock::create_hashlock(hash2);
        let hashlock3 = hashlock::create_hashlock(hash3);
        
        // Verify each hashlock with its correct secret
        assert!(hashlock::verify_hashlock(&hashlock1, secret1), 0);
        assert!(hashlock::verify_hashlock(&hashlock2, secret2), 1);
        assert!(hashlock::verify_hashlock(&hashlock3, secret3), 2);
        
        // Verify that wrong secrets don't work
        assert!(!hashlock::verify_hashlock(&hashlock1, secret2), 3);
        assert!(!hashlock::verify_hashlock(&hashlock2, secret3), 4);
        assert!(!hashlock::verify_hashlock(&hashlock3, secret1), 5);

        test_scenario::end(_scenario);
    }

    #[test]
    fun test_hashlock_getter_functions() {
        let mut _scenario = setup_test();
        
        let hash = hash::sha3_256(TEST_SECRET);
        let hashlock = hashlock::create_hashlock(hash);

        // Test getter function
        let retrieved_hash = hashlock::get_hash(&hashlock);
        assert!(retrieved_hash == hash, 0);

        test_scenario::end(_scenario);
    }
} 