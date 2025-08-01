module sui_fusion_plus::common {
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, Object};
    use sui::transfer;

    /// Creates a test clock for testing purposes
    public fun create_test_clock(): Clock {
        clock::new_for_testing()
    }

    /// Creates a test coin with the specified amount
    public fun create_test_coin(amount: u64): Coin<u64> {
        coin::from_balance(balance::zero(), @0x0)
    }

    /// Helper function to get a test address
    public fun get_test_address(): address {
        @0x1
    }

    /// Helper function to get another test address
    public fun get_test_address_2(): address {
        @0x2
    }

    /// Helper function to get resolver test address
    public fun get_resolver_address(): address {
        @0x3
    }
} 