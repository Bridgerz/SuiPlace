module suiplace::rewards;

use std::u64;
use sui::object_bag::{Self, ObjectBag};
use sui::random::{Random, new_generator};
use suiplace::canvas_admin::CanvasAdminCap;

const BPS_SCALE: u64 = 10_000; // scaling factor for basis points
const RAND_MAX: u32 = 1_000_000_000;

public struct RewardPool has key {
    id: UID,
    paused: bool,
    rewards: ObjectBag,
}

public struct Ticket has key {
    id: UID,
    valid: bool,
}

public fun create_reward_pool<T: key + store>(
    _: &CanvasAdminCap,
    items: &mut vector<T>,
    ctx: &mut TxContext,
) {
    let mut pool = RewardPool {
        id: object::new(ctx),
        paused: false,
        rewards: object_bag::new(ctx),
    };
    let mut i = 0;
    while (i < items.length() as u32) {
        pool.rewards_mut().add(i, items.pop_back());
        i = i + 1;
    };

    transfer::share_object(pool);

    // TODO: emit event
}

public fun restock_reward_pool<T: key + store>(
    pool: &mut RewardPool,
    items: &mut vector<T>,
) {
    // TODO: error message
    assert!(!pool.paused);
    let mut i = 0;
    while (i < items.length()) {
        pool.rewards.add(i, items.pop_back());
        i = i + 1;
    };

    // TODO: emit event
}

entry fun spin_the_wheel<T: key + store>(
    pool: &mut RewardPool,
    ticket: Ticket,
    r: &Random,
    ctx: &mut TxContext,
) {
    // TODO: error message
    assert!(!pool.paused);
    // TODO: error message
    assert!(ticket.valid);
    let mut generator = r.new_generator(ctx);
    let index = generator.generate_u32_in_range(
        1,
        (pool.rewards.length() as u32),
    );

    let reward: T = pool.rewards.remove(index);

    ticket.destroy();
    transfer::public_transfer(
        reward,
        ctx.sender(),
    );

    // TODO: emit event
}

/// Anyone can play and receive a ticket.
public(package) fun create_ticket(
    odds: u64,
    num_chances: u8,
    r: &Random,
    ctx: &mut TxContext,
): Ticket {
    let mut generator = r.new_generator(ctx);

    let base_full = u64::pow(BPS_SCALE, num_chances);
    let base_missed = u64::pow(BPS_SCALE - odds, num_chances);
    let success_prob_num = base_full - base_missed;
    let success_prob_den = base_full;

    let winner = generator.generate_u32_in_range(1, RAND_MAX);

    let threshold = (success_prob_num * (RAND_MAX as u64)) / success_prob_den;

    if ((winner as u64) <= threshold) {
        Ticket {
            id: object::new(ctx),
            valid: true,
        }
    } else {
        Ticket {
            id: object::new(ctx),
            valid: false,
        }
    }
}

public use fun destroy_ticket as Ticket.destroy;

public fun destroy_ticket(ticket: Ticket) {
    let Ticket { id, valid: _ } = ticket;
    object::delete(id);
}

public fun rewards_mut(pool: &mut RewardPool): &mut ObjectBag {
    &mut pool.rewards
}
