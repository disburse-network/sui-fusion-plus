module sui_fusion_plus::common {
    use sui::clock::{Self, Clock};

    /// Creates a test clock for testing purposes
    public fun create_test_clock(): Clock {
        clock::new_for_testing()
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