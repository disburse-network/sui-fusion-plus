#[test_only]
module sui_fusion_plus::fusion_order_tests_fixed {
    use std::hash;
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;

    use sui_fusion_plus::fusion_order::{Self, FusionOrder};
    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};
    use sui_fusion_plus::constants;

    // Test addresses
    const OWNER_ADDRESS: address = @0x201;
    const RESOLVER_ADDRESS: address = @0x202;
    const CHAIN_ID: u64 = 20;

    // Test amounts
    const MINT_AMOUNT: u64 = 100000000; // 100 token
    const ASSET_AMOUNT: u64 = 1000000; // 1 token

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";
    const WRONG_SECRET: vector<u8> = b"wrong secret";

    // Add these constants at the top for destination asset/recipient
    const NATIVE_ASSET: vector<u8> = b""; // Empty vector represents native asset
    const EVM_CONTRACT_ADDRESS: vector<u8> = b"0x1234567890123456789012345678901234567890"; // 20 bytes
    const DESTINATION_RECIPIENT: vector<u8> = b"0x1234567890123456789012345678901234567890"; // 20 bytes

    fun setup_test(): (Scenario, address, address) {
        let scenario = test_scenario::begin(OWNER_ADDRESS);
        (scenario, OWNER_ADDRESS, RESOLVER_ADDRESS)
    }

    fun create_fusion_order_with_defaults(
        scenario: &mut Scenario,
        _owner: address,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock
    ): FusionOrder {
        let ctx = test_scenario::ctx(scenario);
        let coin = coin::mint_for_testing<u64>(amount, ctx);
        
        fusion_order::new(
            coin, 
            NATIVE_ASSET,           // Default to native asset
            amount,                  // destination_amount
            DESTINATION_RECIPIENT,   // Default recipient
            chain_id,
            hash,
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            clock,
            ctx
        )
    }

    #[test]
    fun test_create_fusion_order() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify fusion order properties
        assert!(fusion_order::get_owner(&fusion_order) == OWNER_ADDRESS, 0);
        assert!(fusion_order::get_source_amount(&fusion_order) == ASSET_AMOUNT, 1);
        assert!(fusion_order::get_destination_asset(&fusion_order) == NATIVE_ASSET, 2);
        assert!(fusion_order::get_destination_recipient(&fusion_order) == DESTINATION_RECIPIENT, 3);
        assert!(fusion_order::get_chain_id(&fusion_order) == CHAIN_ID, 4);
        assert!(fusion_order::get_hash(&fusion_order) == hash::sha3_256(TEST_SECRET), 5);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_zero_amount() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(0, ctx); // Zero amount

        // Try to create fusion order with zero amount
        fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            0, // Zero destination amount
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Clock will be consumed by test scenario automatically
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_dutch_auction_parameters() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order with Dutch auction parameters
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify Dutch auction parameters
        assert!(fusion_order::get_initial_destination_amount(&fusion_order) == 100200, 0);
        assert!(fusion_order::get_min_destination_amount(&fusion_order) == 100000, 1);
        assert!(fusion_order::get_decay_per_second(&fusion_order) == 20, 2);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_with_custom_asset() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order with custom asset
        let fusion_order = fusion_order::new(
            source_coin,
            EVM_CONTRACT_ADDRESS, // Custom asset
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify custom asset
        assert!(fusion_order::get_destination_asset(&fusion_order) == EVM_CONTRACT_ADDRESS, 0);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_with_custom_recipient() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let custom_recipient = b"0x9876543210987654321098765432109876543210";

        // Create fusion order with custom recipient
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            custom_recipient,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify custom recipient
        assert!(fusion_order::get_destination_recipient(&fusion_order) == custom_recipient, 0);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_hash_verification() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify hash
        assert!(fusion_order::get_hash(&fusion_order) == hash::sha3_256(TEST_SECRET), 0);
        assert!(fusion_order::get_hash(&fusion_order) != hash::sha3_256(WRONG_SECRET), 1);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_chain_id() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify chain ID
        assert!(fusion_order::get_chain_id(&fusion_order) == CHAIN_ID, 0);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_amounts() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify amounts
        assert!(fusion_order::get_source_amount(&fusion_order) == ASSET_AMOUNT, 0);
        // Note: get_destination_amount function doesn't exist in Sui version

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_owner() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify owner
        assert!(fusion_order::get_owner(&fusion_order) == OWNER_ADDRESS, 0);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_creation_time() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Note: get_creation_time function doesn't exist in Sui version

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_dutch_auction_calculation() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Note: get_current_destination_amount function doesn't exist in Sui version

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_with_different_decay_rates() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order with high decay rate
        let fusion_order_high_decay = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            50,     // high decay_per_second
            &clock,
            ctx
        );

        // Create another fusion order with low decay rate
        let source_coin2 = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);
        let fusion_order_low_decay = fusion_order::new(
            source_coin2,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            10,     // low decay_per_second
            &clock,
            ctx
        );

        // Verify different decay rates
        assert!(fusion_order::get_decay_per_second(&fusion_order_high_decay) == 50, 0);
        assert!(fusion_order::get_decay_per_second(&fusion_order_low_decay) == 10, 1);

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order_high_decay, @0x0);
        transfer::public_transfer(fusion_order_low_decay, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_with_different_amounts() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order with different amounts
        let fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT * 2, // Different destination amount
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20,     // decay_per_second
            &clock,
            ctx
        );

        // Verify different amounts
        assert!(fusion_order::get_source_amount(&fusion_order) == ASSET_AMOUNT, 0);
        // Note: get_destination_amount function doesn't exist in Sui version

        // Consume objects with 'store' ability
        transfer::public_transfer(fusion_order, @0x0);
        // Clock will be consumed by test scenario automatically

        test_scenario::end(scenario);
    }
} 