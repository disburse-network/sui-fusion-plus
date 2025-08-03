#[test_only]
module sui_fusion_plus::common {
    use std::option::{Self};
    use std::string::utf8;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::{Self, TxContext};

    public fun initialize_account_with_fa(scenario: &mut Scenario, addr: address): address {
        // In Sui, we use test_scenario to create accounts
        // This is a simplified version for testing
        addr
    }

    public fun create_test_token(
        scenario: &mut Scenario,
        seed: vector<u8>
    ): (address, address) {
        let ctx = test_scenario::ctx(scenario);
        
        // For testing purposes, we'll use a simple address
        // In real implementation, this would create proper coin metadata
        let metadata_address = @0x123;
        
        (metadata_address, metadata_address)
    }

    public fun mint_fa(
        scenario: &mut Scenario,
        metadata_address: address,
        amount: u64,
        addr: address
    ) {
        let ctx = test_scenario::ctx(scenario);
        
        // Simplified minting for testing
        // In real implementation, this would mint actual coins
    }
} 