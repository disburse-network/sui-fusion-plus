#[test_only]
module sui_fusion_plus::escrow_tests {
    use std::vector;
    use std::hash;
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object;
    use sui_fusion_plus::constants;
    use sui_fusion_plus::hashlock;
    use sui_fusion_plus::timelock;
    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};
    use sui_fusion_plus::escrow::{Self, Escrow};
    use sui_fusion_plus::fusion_order::{Self, FusionOrder};

    // Test constants
    const TEST_SECRET: vector<u8> = b"my secret";
    const RESOLVER_ADDRESS: address = @0x123;
    const CHAIN_ID: u64 = 1;
    const ASSET_AMOUNT: u64 = 1000;
    const MINT_AMOUNT: u64 = 100000000; // 100 token

    // Test setup function
    fun setup_test(): (Scenario, address, address) {
        let mut scenario = test_scenario::begin(@0x201);
        let owner_addr = @0x202;
        let resolver_addr = @0x203;
        
        // Initialize accounts
        test_scenario::next_tx(&mut scenario, owner_addr);
        
        (scenario, owner_addr, resolver_addr)
    }

    // Helper function to create fusion order
    fun create_fusion_order_with_defaults(
        scenario: &mut Scenario,
        owner_addr: address,
        amount: u64,
        chain_id: u64,
        hash: vector<u8>,
        clock: &Clock
    ): FusionOrder {
        let ctx = test_scenario::ctx(scenario);
        let source_coin = coin::mint_for_testing<u64>(amount, ctx);
        
        fusion_order::new(
            source_coin,
            b"", // destination_asset (empty for native)
            amount, // destination_amount
            b"0x1234567890123456789012345678901234567890", // destination_recipient
            chain_id,
            hash,
            100200, // initial_destination_amount
            100000, // min_destination_amount
            20, // decay_per_second
            clock,
            ctx
        )
    }

    #[test]
    fun test_create_escrow_from_order() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create fusion order
        let fusion_order = create_fusion_order_with_defaults(
            &mut scenario,
            owner_addr,
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            &clock
        );

        // Create safety deposit
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        
        // Create escrow
        let escrow = escrow::new_from_order(
            fusion_order,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_escrow_from_resolver() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create asset coin
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, test_scenario::ctx(&mut scenario));
        
        // Create safety deposit
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        
        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);
        
        // Create escrow from resolver
        let escrow = escrow::new_from_resolver(
            owner_addr,
            b"", // coin_type (empty for native)
            ASSET_AMOUNT,
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // EINVALID_SECRET
    fun test_create_escrow_with_invalid_secret() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create asset coin
        let asset_coin = coin::mint_for_testing<u64>(ASSET_AMOUNT, test_scenario::ctx(&mut scenario));
        
        // Create safety deposit
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        
        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);
        
        // Try to create escrow with invalid secret
        let escrow = escrow::new_from_resolver(
            owner_addr,
            b"", // coin_type (empty for native)
            ASSET_AMOUNT,
            CHAIN_ID,
            b"", // Invalid empty secret
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)] // EINVALID_PHASE
    fun test_withdraw_during_finality_lock() {
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

        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Try to withdraw during finality lock (no time increment)
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // EINVALID_CALLER
    fun test_withdraw_by_non_owner() {
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

        // Switch to non-resolver account
        test_scenario::next_tx(&mut scenario, @0x999);

        // Try to withdraw with non-resolver account
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_withdraw_by_resolver_during_withdrawal() {
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

        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);

        // Resolver can withdraw during withdrawal phase
        escrow::withdraw(
            escrow,
            TEST_SECRET,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically
        
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

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically
        
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

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 4)] // EINVALID_AMOUNT
    fun test_create_escrow_with_invalid_amount() {
        let (mut scenario, owner_addr, _resolver_addr) = setup_test();
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);
        let registry = resolver_registry::get_test_registry(ctx);
        
        // Create asset coin with zero amount
        let asset_coin = coin::mint_for_testing<u64>(0, test_scenario::ctx(&mut scenario));
        
        // Create safety deposit
        let safety_deposit = coin::mint_for_testing<u64>(constants::get_safety_deposit_amount(), test_scenario::ctx(&mut scenario));
        
        // Switch to resolver account
        test_scenario::next_tx(&mut scenario, RESOLVER_ADDRESS);
        
        // Try to create escrow with invalid amount
        let escrow = escrow::new_from_resolver(
            owner_addr,
            b"", // coin_type (empty for native)
            0, // Invalid zero amount
            CHAIN_ID,
            hash::sha3_256(TEST_SECRET),
            asset_coin,
            safety_deposit,
            &registry,
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Consume objects with 'store' ability
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);
        // Clock will be consumed by test scenario automatically
        
        test_scenario::end(scenario);
    }
} 