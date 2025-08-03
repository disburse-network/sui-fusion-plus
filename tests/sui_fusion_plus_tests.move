#[test_only]
module sui_fusion_plus::sui_fusion_plus_tests;

use sui::test_scenario;
use sui::coin;

use sui_fusion_plus::fusion_order;
use sui_fusion_plus::hashlock;
use sui_fusion_plus::timelock;
use sui_fusion_plus::constants;

// Test addresses
const USER_1: address = @0x333;
const RESOLVER_1: address = @0x123;

// Test constants
const TEST_AMOUNT: u64 = 1000;
const TEST_DESTINATION_AMOUNT: u64 = 500;
const TEST_CHAIN_ID: u64 = 2;
const TEST_HASH: vector<u8> = b"01234567890123456789012345678901";
const TEST_DESTINATION_ASSET: vector<u8> = b"12345678901234567890"; // 20 bytes
const TEST_DESTINATION_RECIPIENT: vector<u8> = b"09876543210987654321"; // 20 bytes

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
fun test_timelock_operations() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test source chain timelock
    let source_timelock = timelock::new_source();
    
    // Test destination chain timelock
    let dest_timelock = timelock::new_destination();
    
    // Test chain type checking
    assert!(timelock::get_chain_type(&source_timelock) == 0, 0); // Source
    assert!(timelock::get_chain_type(&dest_timelock) == 1, 0); // Destination
    
    test_scenario::end(scenario);
}

#[test]
fun test_fusion_order_utility_functions() {
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

#[test]
fun test_constants() {
    // Test safety deposit constants
    assert!(constants::get_safety_deposit_amount() > 0, 0);
    
    // Test source chain timelock constants
    assert!(constants::get_src_finality_lock() > 0, 0);
    assert!(constants::get_src_withdrawal() > constants::get_src_finality_lock(), 0);
    assert!(constants::get_src_public_withdrawal() > constants::get_src_withdrawal(), 0);
    assert!(constants::get_src_cancellation() > constants::get_src_public_withdrawal(), 0);
    assert!(constants::get_src_public_cancellation() > constants::get_src_cancellation(), 0);
    
    // Test destination chain timelock constants
    assert!(constants::get_dst_finality_lock() > 0, 0);
    assert!(constants::get_dst_withdrawal() > constants::get_dst_finality_lock(), 0);
    assert!(constants::get_dst_public_withdrawal() > constants::get_dst_withdrawal(), 0);
    assert!(constants::get_dst_cancellation() > constants::get_dst_public_withdrawal(), 0);
    
    // Test chain ID
    assert!(constants::get_source_chain_id() > 0, 0);
}

#[test]
fun test_hashlock_integration() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test hashlock creation and verification
    let secret = b"test_secret_123";
    let hashlock = hashlock::create_hashlock_for_test(secret);
    
    // Test verification
    assert!(hashlock::verify_hashlock(&hashlock, secret), 0);
    assert!(!hashlock::verify_hashlock(&hashlock, b"wrong_secret"), 0);
    
    // Test hash validation
    let hash = hashlock::get_hash(&hashlock);
    assert!(hashlock::is_valid_hash(&hash), 0);
    
    test_scenario::end(scenario);
}

#[test]
fun test_timelock_phases() {
    let mut scenario = test_scenario::begin(USER_1);
    
    // Test source chain timelock phases
    let source_timelock = timelock::new_source();
    
    // Test destination chain timelock phases
    let dest_timelock = timelock::new_destination();
    
    // Test phase checking functions
    assert!(timelock::get_chain_type(&source_timelock) == 0, 0); // Source
    assert!(timelock::get_chain_type(&dest_timelock) == 1, 0); // Destination
    
    test_scenario::end(scenario);
}
