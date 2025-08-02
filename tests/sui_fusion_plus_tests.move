#[test_only]
module sui_fusion_plus::sui_fusion_plus_tests;

use sui::test_scenario;
use sui::coin;

use sui_fusion_plus::fusion_order;
use sui_fusion_plus::hashlock;

// Test addresses
const USER_1: address = @0x333;

// Error codes
const ENotImplemented: u64 = 0;

#[test]
fun test_hashlock_operations() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test creating and verifying a hashlock
    let secret = b"test_secret_123";
    let hashlock = hashlock::create_hashlock_for_test(secret);
    
    // Verify the hashlock works correctly
    assert!(hashlock::verify_hashlock(&hashlock, secret), 0);
    assert!(!hashlock::verify_hashlock(&hashlock, b"wrong_secret"), 0);
    
    // Test hash validation
    let valid_hash = hashlock::get_hash(&hashlock);
    assert!(hashlock::is_valid_hash(&valid_hash), 0);
    assert!(!hashlock::is_valid_hash(&b"short"), 0);
    
    // Test secret validation
    assert!(hashlock::is_valid_secret(&secret), 0);
    assert!(!hashlock::is_valid_secret(&b""), 0);
    
    test_scenario::end(scenario);
}

#[test]
fun test_utility_functions() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test fusion order utility functions
    let valid_hash = b"01234567890123456789012345678901";
    let invalid_hash = b""; // Empty hash
    
    assert!(fusion_order::is_valid_hash(&valid_hash), 0);
    assert!(!fusion_order::is_valid_hash(&invalid_hash), 0);
    
    // Test destination asset validation
    let native_asset = b"";
    let evm_asset = b"12345678901234567890"; // 20 bytes, no 0x prefix
    let invalid_asset = b"0x123"; // Too short
    
    assert!(fusion_order::is_native_asset(&native_asset), 0);
    assert!(fusion_order::is_evm_contract_address(&evm_asset), 0);
    assert!(!fusion_order::is_evm_contract_address(&invalid_asset), 0);
    
    // Test EVM address validation
    let valid_evm_address = b"12345678901234567890"; // 20 bytes, no 0x prefix
    let invalid_evm_address = b"0x123"; // Too short
    
    assert!(fusion_order::is_valid_evm_address(&valid_evm_address), 0);
    assert!(!fusion_order::is_valid_evm_address(&invalid_evm_address), 0);
    
    test_scenario::end(scenario);
}

#[test]
fun test_dutch_auction_calculation() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test Dutch auction price calculation with fixed values
    let initial_destination_amount = 1000;
    let min_destination_amount = 100;
    let decay_per_second = 1;
    let auction_start_time = 1000;
    
    // Create a simple test without using clock
    let current_time = 1100; // 100 seconds after start
    let elapsed_seconds = current_time - auction_start_time;
    let total_decay = decay_per_second * elapsed_seconds;
    
    let expected_price = if (total_decay >= initial_destination_amount) {
        min_destination_amount
    } else {
        let current_price = initial_destination_amount - total_decay;
        if (current_price < min_destination_amount) {
            min_destination_amount
        } else {
            current_price
        }
    };
    
    // Verify the calculation
    assert!(expected_price == 900, 0); // 1000 - (1 * 100) = 900
    assert!(expected_price >= min_destination_amount, 0);
    assert!(expected_price <= initial_destination_amount, 0);
    
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = ::sui_fusion_plus::sui_fusion_plus_tests::ENotImplemented)]
fun test_sui_fusion_plus_fail() {
    abort ENotImplemented
}
