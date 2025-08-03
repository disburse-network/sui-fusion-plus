#[test_only]
module sui_fusion_plus::simple_test {
    use std::hash;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui_fusion_plus::constants;
    use sui_fusion_plus::hashlock::{Self, HashLock};
    use sui_fusion_plus::timelock::{Self, Timelock};
    use sui_fusion_plus::fusion_order::{Self, FusionOrder};
    use sui_fusion_plus::resolver_registry;
    use sui::object;


    // Test constants
    const CHAIN_ID: u64 = 20;
    // Test amounts
    const MINT_AMOUNT: u64 = 100000000; // 100 token
    const ASSET_AMOUNT: u64 = 1000000; // 1 token

    // Add these constants at the top for destination asset/recipient
    const DESTINATION_ASSET: vector<u8> = b"\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11";
    const DESTINATION_RECIPIENT: vector<u8> = b"\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22";

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";

    // Dutch auction parameters
    const INITIAL_DESTINATION_AMOUNT: u64 = 100200;
    const MIN_DESTINATION_AMOUNT: u64 = 100000;
    const DECAY_PER_SECOND: u64 = 20;

    #[test]
    fun test_hashlock_basic() {
        let mut scenario = test_scenario::begin(@0x201);
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
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        // Create timelock
        let mut timelock = timelock::new_source();
        timelock::set_creation_time(&mut timelock, &clock);
        
        // Test basic functionality
        assert!(timelock::get_chain_type(&timelock) == 0, 0);
        assert!(timelock::is_source_chain(&timelock), 1);
        
        // Clock will be consumed by test scenario automatically
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

    #[test]
    fun test_create_fusion_order() {
        let mut scenario = test_scenario::begin(@0x201);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        
        // Create a test coin for the fusion order
        let test_coin = coin::mint_for_testing(ASSET_AMOUNT, ctx);

        // Create a fusion order
        let fusion_order =
            fusion_order::new(
                test_coin,
                DESTINATION_ASSET,
                ASSET_AMOUNT,
                DESTINATION_RECIPIENT,
                CHAIN_ID,
                hash::sha3_256(TEST_SECRET),
                INITIAL_DESTINATION_AMOUNT,
                MIN_DESTINATION_AMOUNT,
                DECAY_PER_SECOND,
                &clock,
                ctx
            );

        // Verify initial state
        assert!(
            fusion_order::get_owner(&fusion_order) == @0x201, 0
        );
        assert!(fusion_order::get_source_amount(&fusion_order) == ASSET_AMOUNT, 0);
        assert!(fusion_order::get_chain_id(&fusion_order) == CHAIN_ID, 0);
        assert!(fusion_order::get_hash(&fusion_order) == hash::sha3_256(TEST_SECRET), 0);

        // Verify Dutch auction parameters
        assert!(fusion_order::get_initial_destination_amount(&fusion_order) == INITIAL_DESTINATION_AMOUNT, 0);
        assert!(fusion_order::get_min_destination_amount(&fusion_order) == MIN_DESTINATION_AMOUNT, 0);

        // Verify destination asset and recipient
        assert!(fusion_order::get_destination_asset(&fusion_order) == DESTINATION_ASSET, 0);
        assert!(fusion_order::get_destination_recipient(&fusion_order) == DESTINATION_RECIPIENT, 0);

        // Verify auction start time
        assert!(fusion_order::get_auction_start_time(&fusion_order) > 0, 0);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }
}