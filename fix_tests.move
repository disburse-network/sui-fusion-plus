#[test_only]
module sui_fusion_plus::fix_tests {
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui_fusion_plus::resolver_registry::{Self, ResolverRegistry};
    use sui_fusion_plus::escrow::{Self, Escrow};
    use sui_fusion_plus::fusion_order::{Self, FusionOrder};

    /// Helper function to consume test objects that don't have drop ability
    public fun consume_clock(clock: Clock) {
        transfer::public_transfer(clock, @0x0);
    }

    /// Helper function to consume registry
    public fun consume_registry(registry: ResolverRegistry) {
        transfer::public_transfer(registry, @0x0);
    }

    /// Helper function to consume escrow
    public fun consume_escrow(escrow: Escrow) {
        transfer::public_transfer(escrow, @0x0);
    }

    /// Helper function to consume fusion order
    public fun consume_fusion_order(fusion_order: FusionOrder) {
        transfer::public_transfer(fusion_order, @0x0);
    }

    /// Helper function to consume clock and registry
    public fun consume_clock_and_registry(clock: Clock, registry: ResolverRegistry) {
        transfer::public_transfer(clock, @0x0);
        transfer::public_transfer(registry, @0x0);
    }

    /// Helper function to consume all test objects
    public fun consume_all_objects(
        clock: Clock,
        registry: ResolverRegistry,
        escrow: Escrow,
        fusion_order: FusionOrder
    ) {
        transfer::public_transfer(clock, @0x0);
        transfer::public_transfer(registry, @0x0);
        transfer::public_transfer(escrow, @0x0);
        transfer::public_transfer(fusion_order, @0x0);
    }
} 