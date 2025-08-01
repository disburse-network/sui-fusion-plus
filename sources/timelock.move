module sui_fusion_plus::timelock {
    use sui::clock::{Self, Clock};
    use sui_fusion_plus::constants;

    /// Error codes
    const EINVALID_DURATION: u64 = 1;
    const EOVERFLOW: u64 = 2;
    const EINVALID_CHAIN_TYPE: u64 = 3;

    /// Chain type constants
    const CHAIN_TYPE_SOURCE: u8 = 0;
    const CHAIN_TYPE_DESTINATION: u8 = 1;

    /// Phase constants for Source Chain
    const SRC_PHASE_FINALITY_LOCK: u8 = 0;         // 0-12s: Finality lock (no actions)
    const SRC_PHASE_WITHDRAWAL: u8 = 1;            // 12-24s: Exclusive withdrawal
    const SRC_PHASE_PUBLIC_WITHDRAWAL: u8 = 2;     // 24-120s: Public withdrawal
    const SRC_PHASE_CANCELLATION: u8 = 3;          // 120-180s: Resolver cancellation
    const SRC_PHASE_PUBLIC_CANCELLATION: u8 = 4;   // 180-240s: Public cancellation

    /// Phase constants for Destination Chain
    const DST_PHASE_FINALITY_LOCK: u8 = 0;         // 0-12s: Finality lock (no actions)
    const DST_PHASE_WITHDRAWAL: u8 = 1;            // 12-24s: Exclusive withdrawal
    const DST_PHASE_PUBLIC_WITHDRAWAL: u8 = 2;     // 24-100s: Public withdrawal
    const DST_PHASE_CANCELLATION: u8 = 3;          // 100-160s: Resolver cancellation

    /// A timelock that enforces time-based phases for asset locking.
    /// Matches the 1inch Fusion+ EVM timelock structure with separate
    /// source and destination chain timelocks.
    ///
    /// @param created_at When this timelock was created.
    /// @param chain_type Whether this is source (0) or destination (1) chain.
    struct Timelock has copy, drop, store {
        created_at: u64,
        chain_type: u8
    }

    public fun new(): Timelock {
        new_internal(CHAIN_TYPE_SOURCE) // Default to source chain
    }

    /// Creates a new Timelock for the specified chain type.
    ///
    /// @param chain_type CHAIN_TYPE_SOURCE (0) or CHAIN_TYPE_DESTINATION (1)
    ///
    /// @reverts EINVALID_CHAIN_TYPE if chain_type is invalid.
    public fun new_internal(chain_type: u8): Timelock {
        assert!(chain_type == CHAIN_TYPE_SOURCE || chain_type == CHAIN_TYPE_DESTINATION, EINVALID_CHAIN_TYPE);

        Timelock {
            created_at: 0, // Will be set when used with clock
            chain_type
        }
    }

    /// Creates a new Timelock for source chain.
    public fun new_source(): Timelock {
        new_internal(CHAIN_TYPE_SOURCE)
    }

    /// Creates a new Timelock for destination chain.
    public fun new_destination(): Timelock {
        new_internal(CHAIN_TYPE_DESTINATION)
    }

    /// Gets the current phase of a Timelock based on elapsed time.
    ///
    /// @param timelock The Timelock to check.
    /// @param clock The clock object to get current time.
    /// @return u8 The current phase based on chain type and elapsed time.
    public fun get_phase(timelock: &Timelock, clock: &Clock): u8 {
        let now = clock::timestamp_ms(clock);
        let elapsed = now - timelock.created_at;

        if (timelock.chain_type == CHAIN_TYPE_SOURCE) {
            get_source_phase(elapsed)
        } else {
            get_destination_phase(elapsed)
        }
    }

    /// Gets the source chain phase based on elapsed time.
    fun get_source_phase(elapsed: u64): u8 {
        if (elapsed < constants::get_src_finality_lock()) {
            SRC_PHASE_FINALITY_LOCK
        } else if (elapsed < constants::get_src_withdrawal()) {
            SRC_PHASE_WITHDRAWAL
        } else if (elapsed < constants::get_src_public_withdrawal()) {
            SRC_PHASE_PUBLIC_WITHDRAWAL
        } else if (elapsed < constants::get_src_cancellation()) {
            SRC_PHASE_CANCELLATION
        } else if (elapsed < constants::get_src_public_cancellation()) {
            SRC_PHASE_PUBLIC_CANCELLATION
        } else {
            SRC_PHASE_PUBLIC_CANCELLATION // Final phase
        }
    }

    /// Gets the destination chain phase based on elapsed time.
    fun get_destination_phase(elapsed: u64): u8 {
        if (elapsed < constants::get_dst_finality_lock()) {
            DST_PHASE_FINALITY_LOCK
        } else if (elapsed < constants::get_dst_withdrawal()) {
            DST_PHASE_WITHDRAWAL
        } else if (elapsed < constants::get_dst_public_withdrawal()) {
            DST_PHASE_PUBLIC_WITHDRAWAL
        } else if (elapsed < constants::get_dst_cancellation()) {
            DST_PHASE_CANCELLATION
        } else {
            DST_PHASE_CANCELLATION // Final phase
        }
    }

    /// Checks if withdrawal is allowed in the current phase.
    ///
    /// @param timelock The Timelock to check.
    /// @param clock The clock object to get current time.
    /// @return bool True if withdrawal is allowed, false otherwise.
    public fun is_withdrawal_allowed(timelock: &Timelock, clock: &Clock): bool {
        let phase = get_phase(timelock, clock);
        phase == SRC_PHASE_WITHDRAWAL || phase == SRC_PHASE_PUBLIC_WITHDRAWAL ||
        phase == DST_PHASE_WITHDRAWAL || phase == DST_PHASE_PUBLIC_WITHDRAWAL
    }

    /// Checks if cancellation is allowed in the current phase.
    ///
    /// @param timelock The Timelock to check.
    /// @param clock The clock object to get current time.
    /// @return bool True if cancellation is allowed, false otherwise.
    public fun is_cancellation_allowed(timelock: &Timelock, clock: &Clock): bool {
        let phase = get_phase(timelock, clock);
        phase == SRC_PHASE_CANCELLATION || phase == SRC_PHASE_PUBLIC_CANCELLATION ||
        phase == DST_PHASE_CANCELLATION
    }

    /// Checks if we're in the cancellation phase (private cancellation).
    ///
    /// @param timelock The Timelock to check.
    /// @param clock The clock object to get current time.
    /// @return bool True if in cancellation phase, false otherwise.
    public fun is_in_cancellation_phase(timelock: &Timelock, clock: &Clock): bool {
        let phase = get_phase(timelock, clock);
        phase == SRC_PHASE_CANCELLATION || phase == DST_PHASE_CANCELLATION
    }

    /// Checks if we're in the public cancellation phase.
    ///
    /// @param timelock The Timelock to check.
    /// @param clock The clock object to get current time.
    /// @return bool True if in public cancellation phase, false otherwise.
    public fun is_in_public_cancellation_phase(timelock: &Timelock, clock: &Clock): bool {
        let phase = get_phase(timelock, clock);
        phase == SRC_PHASE_PUBLIC_CANCELLATION
    }

    /// Sets the creation timestamp for a timelock.
    ///
    /// @param timelock The Timelock to update.
    /// @param clock The clock object to get current time.
    public fun set_creation_time(timelock: &mut Timelock, clock: &Clock) {
        timelock.created_at = clock::timestamp_ms(clock);
    }

    /// Gets the creation timestamp of a timelock.
    ///
    /// @param timelock The Timelock to get the creation time from.
    /// @return u64 The creation timestamp.
    public fun get_creation_time(timelock: &Timelock): u64 {
        timelock.created_at
    }

    /// Gets the chain type of a timelock.
    ///
    /// @param timelock The Timelock to get the chain type from.
    /// @return u8 The chain type (0 = source, 1 = destination).
    public fun get_chain_type(timelock: &Timelock): u8 {
        timelock.chain_type
    }
} 