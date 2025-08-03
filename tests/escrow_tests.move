#[test_only]
module sui_fusion_plus::escrow_tests {
    use std::hash;
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::object;

    use sui_fusion_plus::escrow::{Self};
    use sui_fusion_plus::fusion_order::{Self, FusionOrder};
    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};
    use sui_fusion_plus::timelock::{Self};
    use sui_fusion_plus::hashlock::{Self};
    use sui_fusion_plus::constants;

    // Test accounts
    const CHAIN_ID: u64 = 20;

    // Test amounts
    const MINT_AMOUNT: u64 = 100000000; // 100 token
    const ASSET_AMOUNT: u64 = 1000000; // 1 token

    // Add these constants at the top for destination asset/recipient
    const NATIVE_ASSET: vector<u8> = b""; // Empty vector represents native asset
    const EVM_CONTRACT_ADDRESS: vector<u8> = b"0x1234567890123456789012345678901234567890"; // 20 bytes
    const DESTINATION_RECIPIENT: address = @0x2222222222222222222222222222222222222222222222222222222222222222;

    // Test secrets and hashes
    const TEST_SECRET: vector<u8> = b"my secret";
    const WRONG_SECRET: vector<u8> = b"wrong secret";

    // Test addresses
    const OWNER_ADDRESS: address = @0x201;
    const RESOLVER_ADDRESS: address = @0x202;
    // Removed unused RECIPIENT_ADDRESS

    fun setup_test(): (Scenario, address, address) {
        let scenario = test_scenario::begin(@0x201);
        (scenario, @0x201, @0x202)
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
            NATIVE_ASSET,           // destination_asset (native)
            amount,                  // destination_amount
            EVM_CONTRACT_ADDRESS,    // destination_recipient (20 bytes)
            chain_id,                // chain_id
            hash,                    // hash
            amount + 200,           // initial_destination_amount
            amount,                  // min_destination_amount
            20,                      // decay_per_second
            clock,
            ctx
        )
    }

    #[test]
    fun test_create_escrow_from_order() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create a fusion order first
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Create safety deposit coin
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));

        // Create escrow from order
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify escrow properties
        assert!(escrow::get_from(&escrow) == OWNER_ADDRESS, 0);
        assert!(escrow::get_to(&escrow) == RESOLVER_ADDRESS, 1);

        assert!(escrow::get_resolver(&escrow) == RESOLVER_ADDRESS, 2);
        assert!(escrow::get_chain_id(&escrow) == CHAIN_ID, 3);
        assert!(escrow::get_amount(&escrow) == ASSET_AMOUNT, 4);
        assert!(escrow::is_source_chain(&escrow), 5);

        // Consume objects
        transfer::public_transfer(clock, @0x0);
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_escrow_from_resolver() {
        let (mut scenario, _, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), ctx);

        // Create escrow directly from resolver
        let escrow = escrow::new_from_resolver(
            RESOLVER_ADDRESS,
            b"0x2::sui::SUI", // Use hardcoded SUI type name
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify escrow properties
        assert!(escrow::get_from(&escrow) == RESOLVER_ADDRESS, 0);
        assert!(escrow::get_to(&escrow) == RESOLVER_ADDRESS, 1);
        assert!(escrow::get_resolver(&escrow) == RESOLVER_ADDRESS, 2);
        assert!(escrow::get_chain_id(&escrow) == CHAIN_ID, 3);
        assert!(escrow::get_amount(&escrow) == ASSET_AMOUNT, 4);
        assert!(!escrow::is_source_chain(&escrow), 5);

        // Consume objects
        transfer::public_transfer(clock, @0x0);
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_withdraw_with_correct_secret() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);

        // Withdraw with correct secret
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // EINVALID_SECRET
    fun test_withdraw_with_wrong_secret() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);

        // Withdraw with wrong secret
        escrow::withdraw(
            escrow,
            WRONG_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_PHASE
    fun test_withdraw_during_finality_lock() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to withdraw during finality lock (no time increment)
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINVALID_CALLER
    fun test_withdraw_by_non_owner() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);

        // Switch to non-owner account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to withdraw as non-owner
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_recovery_by_resolver_during_cancellation() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() + 1000);

        // Recover by resolver
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINVALID_CALLER
    fun test_recovery_by_non_resolver_during_private_cancellation() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() + 1000);

        // Switch to non-resolver account
        test_scenario::next_tx(&mut scenario, owner_addr);

        // Try to recover as non-resolver during private cancellation
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_recovery_by_anyone_during_public_cancellation() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to public cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_public_cancellation() + 1000);

        // Switch to non-resolver account
        test_scenario::next_tx(&mut scenario, owner_addr);

        // Anyone can recover during public cancellation
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_PHASE
    fun test_recovery_during_finality_lock() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to recover during finality lock (no time increment)
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_withdraw_by_owner_during_withdrawal() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);

        // Withdraw by owner
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINVALID_CALLER
    fun test_withdraw_by_non_owner_during_withdrawal() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to withdrawal phase
        clock::increment_for_testing(&mut clock, constants::get_src_withdrawal() + 1000);

        // Switch to non-owner account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to withdraw as non-owner
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_PHASE
    fun test_withdraw_during_cancellation() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() + 1000);

        // Try to withdraw during cancellation
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_escrow() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() + 1000);

        // Cancel escrow
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINVALID_CALLER
    fun test_cancel_by_non_owner() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_cancellation() + 1000);

        // Switch to different account and try to cancel
        test_scenario::next_tx(&mut scenario, @0x999);

        // Try to cancel with different account (should fail)
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_public_cancel() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Fast forward time to public cancellation phase
        clock::increment_for_testing(&mut clock, constants::get_src_public_cancellation() + 1000);

        // Public cancel (anyone can cancel)
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_PHASE
    fun test_public_cancel_too_early() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            OWNER_ADDRESS,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to public cancel too early (should fail)
        escrow::recovery(
            escrow,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 4)] // EINVALID_AMOUNT
    fun test_create_escrow_with_invalid_amount() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Try to create escrow with invalid amount
        let asset_coin = coin::mint_for_testing<u64>(0, ctx); // Invalid zero amount
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), ctx);
        
        let _escrow = escrow::new_from_resolver(
            owner_addr,
            b"0x2::sui::SUI", // coin_type
            0, // Invalid zero amount
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // EINVALID_SECRET
    fun test_create_escrow_with_invalid_secret() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Try to create escrow with invalid secret
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), ctx);
        
        let _escrow = escrow::new_from_resolver(
            owner_addr,
            b"0x2::sui::SUI", // coin_type
            ASSET_AMOUNT,
            CHAIN_ID,
            vector::empty<u8>(), // Invalid empty secret
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::end(scenario);
    }

    #[test]
    fun test_escrow_getter_functions() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Test all getter functions
        assert!(escrow::get_from(&escrow) == owner_addr, 0);
        assert!(escrow::get_to(&escrow) == RESOLVER_ADDRESS, 1);
        assert!(escrow::get_resolver(&escrow) == RESOLVER_ADDRESS, 2);
        assert!(escrow::get_chain_id(&escrow) == CHAIN_ID, 3);
        assert!(escrow::get_amount(&escrow) == ASSET_AMOUNT, 4);
        assert!(escrow::is_source_chain(&escrow), 5);

        // Test timelock and hashlock getters
        let timelock = escrow::get_timelock(&escrow);
        let hashlock = escrow::get_hashlock(&escrow);
        
        assert!(timelock::get_chain_type(&timelock) == 0, 6); // Source chain
        assert!(hashlock::get_hash(&hashlock) == hash::sha3_256(TEST_SECRET), 7);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_destination_chain_escrow() {
        let (mut scenario, _owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create destination chain escrow
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, test_scenario::ctx(&mut scenario));
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        
        let escrow = escrow::new_from_resolver(
            DESTINATION_RECIPIENT,
            b"0x2::sui::SUI", // Use hardcoded SUI type name
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify destination chain escrow properties
        assert!(escrow::get_chain_id(&escrow) == CHAIN_ID, 0);
        assert!(escrow::get_amount(&escrow) == ASSET_AMOUNT, 1);
        let hashlock = escrow::get_hashlock(&escrow);
        assert!(hashlock::get_hash(&hashlock) == hash::sha3_256(TEST_SECRET), 2);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_hashlock() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, ctx);
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), ctx);
        
        let escrow = escrow::new_from_resolver(
            owner_addr,
            b"0x2::sui::SUI", // coin_type
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Get hashlock
        let hashlock = escrow::get_hashlock(&escrow);
        assert!(hashlock::get_hash(&hashlock) == hash::sha3_256(TEST_SECRET), 0);

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(escrow, @0x0);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_hashlock_from_order() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create escrow from order
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Get hashlock
        let hashlock = escrow::get_hashlock(&escrow);
        assert!(hashlock::get_hash(&hashlock) == hash::sha3_256(TEST_SECRET), 0);

        // Consume objects to satisfy drop constraint
        transfer::public_transfer(escrow, @0x0);

        test_scenario::end(scenario);
    }
} 