#[test_only]
module sui_fusion_plus::fusion_order_tests {
    use std::hash;
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};

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

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(fusion_order, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_zero_amount() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(0, ctx); // Zero amount

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            0, // Zero destination amount
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6)] // EINVALID_HASH
    fun test_create_fusion_order_with_invalid_hash() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            vector::empty<u8>(), // Invalid empty hash
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_destination_asset() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Invalid destination asset (not empty and not 20 bytes)
        let invalid_asset = b"\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11"; // 21 bytes

        let _fusion_order = fusion_order::new(
            source_coin,
            invalid_asset,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_destination_amount() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            0, // Invalid zero destination amount
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_initial_destination_amount() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            0, // Invalid zero initial destination amount
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_min_destination_amount() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            0, // Invalid zero min destination amount
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_decay_per_second() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            0, // Invalid zero decay per second
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_destination_recipient() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Invalid destination recipient (not 20 bytes)
        let invalid_recipient = b"\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22"; // 21 bytes

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            invalid_recipient,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_invalid_dutch_auction_params() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Invalid Dutch auction parameters (initial < min)
        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100000, // initial_destination_amount
            100200, // min_destination_amount (greater than initial)
            20,
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_AMOUNT
    fun test_create_fusion_order_with_zero_decay() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        let _fusion_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            0, // Zero decay per second
            &clock,
            ctx
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_fusion_order() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Cancel the fusion order
        fusion_order::cancel(
            fusion_order,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // EINVALID_CALLER
    fun test_cancel_fusion_order_by_non_owner() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Switch to non-owner account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to cancel as non-owner
        fusion_order::cancel(
            fusion_order,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_resolver_accept_order() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Create safety deposit coin
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));

        // Resolver accepts the order
        let (_source_coin, _safety_deposit_coin) = fusion_order::resolver_accept_order(
            fusion_order,
            safety_deposit,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify the returned coins
        assert!(coin::value(&_source_coin) == ASSET_AMOUNT, 0);
        assert!(coin::value(&_safety_deposit_coin) == constants::get_safety_deposit_amount(), 1);

        // Consume the returned coins
        transfer::public_transfer(_source_coin, @0x0);
        transfer::public_transfer(_safety_deposit_coin, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINSUFFICIENT_BALANCE
    fun test_resolver_accept_order_with_insufficient_safety_deposit() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Create insufficient safety deposit coin
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount() - 1, test_scenario::ctx(&mut scenario));

        // Try to accept with insufficient safety deposit
        let (_source_coin, _safety_deposit_coin) = fusion_order::resolver_accept_order(
            fusion_order,
            safety_deposit,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume the returned coins
        transfer::public_transfer(_source_coin, @0x0);
        transfer::public_transfer(_safety_deposit_coin, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_with_evm_contract_address() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Create fusion order with EVM contract address
        let fusion_order = fusion_order::new(
            source_coin,
            EVM_CONTRACT_ADDRESS,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            20,
            &clock,
            ctx
        );

        // Verify EVM contract address is stored correctly
        assert!(fusion_order::get_destination_asset(&fusion_order) == EVM_CONTRACT_ADDRESS, 0);

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(fusion_order, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_dutch_auction_price_calculation() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Test initial price
        let initial_price = fusion_order::get_current_dutch_auction_price(&fusion_order, &clock);
        assert!(initial_price == 100200, 0); // Should be at initial price

        // Fast forward time
        clock::increment_for_testing(&mut clock, 1000); // 1 second
        let current_price = fusion_order::get_current_dutch_auction_price(&fusion_order, &clock);
        assert!(current_price < 100200, 1); // Should be less than initial price

        // Fast forward more time
        clock::increment_for_testing(&mut clock, 5000); // 5 more seconds
        let min_price = fusion_order::get_current_dutch_auction_price(&fusion_order, &clock);
        assert!(min_price == 100000, 2); // Should be at minimum price

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(fusion_order, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fusion_order_getter_functions() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Test all getter functions
        assert!(fusion_order::get_owner(&fusion_order) == OWNER_ADDRESS, 0);
        assert!(fusion_order::get_source_amount(&fusion_order) == ASSET_AMOUNT, 1);
        assert!(fusion_order::get_destination_asset(&fusion_order) == NATIVE_ASSET, 2);
        assert!(fusion_order::get_destination_recipient(&fusion_order) == DESTINATION_RECIPIENT, 3);
        assert!(fusion_order::get_chain_id(&fusion_order) == CHAIN_ID, 4);
        assert!(fusion_order::get_hash(&fusion_order) == hash::sha3_256(TEST_SECRET), 5);
        assert!(fusion_order::get_initial_destination_amount(&fusion_order) == 100200, 6);
        assert!(fusion_order::get_decay_per_second(&fusion_order) == 20, 7);
        assert!(fusion_order::get_auction_start_time(&fusion_order) > 0, 8);

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(fusion_order, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_utility_functions() {
        // Test hash validation
        assert!(fusion_order::is_valid_hash(&hash::sha3_256(TEST_SECRET)), 0);
        assert!(!fusion_order::is_valid_hash(&vector::empty<u8>()), 1);

        // Test native asset validation
        assert!(fusion_order::is_native_asset(&NATIVE_ASSET), 2);
        assert!(fusion_order::is_native_asset(&vector::empty<u8>()), 3);
        assert!(!fusion_order::is_native_asset(&EVM_CONTRACT_ADDRESS), 4);

        // Test EVM contract address validation
        assert!(fusion_order::is_evm_contract_address(&EVM_CONTRACT_ADDRESS), 5);
        assert!(!fusion_order::is_evm_contract_address(&NATIVE_ASSET), 6);
        assert!(!fusion_order::is_evm_contract_address(&vector::empty<u8>()), 7);

        // Test EVM address validation
        assert!(fusion_order::is_valid_evm_address(&DESTINATION_RECIPIENT), 8);
        assert!(!fusion_order::is_valid_evm_address(&vector::empty<u8>()), 9);
        assert!(!fusion_order::is_valid_evm_address(&b"\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11"), 10); // 21 bytes
    }

    #[test]
    fun test_dutch_auction_edge_cases() {
        let (mut scenario, _owner_addr, _) = setup_test();
        
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let source_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);

        // Test high decay rate
        let high_decay_order = fusion_order::new(
            source_coin,
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100200,
            100000,
            1000, // High decay rate
            &clock,
            ctx
        );

        // Test equal initial and min amounts
        let equal_order = fusion_order::new(
            coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx),
            NATIVE_ASSET,
            ASSET_AMOUNT,
            DESTINATION_RECIPIENT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            100000, // Same as min
            100000,
            20,
            &clock,
            ctx
        );

        // Test price calculations
        let high_price = fusion_order::get_current_dutch_auction_price(&high_decay_order, &clock);
        assert!(high_price == 100200, 0); // Should stay at initial price
        let equal_price = fusion_order::get_current_dutch_auction_price(&equal_order, &clock);
        assert!(equal_price == 100000, 1); // Should stay at minimum

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(high_decay_order, @0x0);
        transfer::public_transfer(equal_order, @0x0);

        test_scenario::end(scenario);
    }
} 