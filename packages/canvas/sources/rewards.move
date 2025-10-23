module suiplace::rewards;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::event;
use sui::object_bag::{Self, ObjectBag};
use sui::random::{Random, new_generator};
use sui::transfer::Receiving;
use sui::vec_map::VecMap;
use suiplace::canvas_admin::CanvasAdminCap;
use suiplace::events;

const BPS_SCALE: u64 = 10_000; // scaling factor for basis points
const RAND_MAX: u32 = 1_000_000_000;

#[error]
const EWheelIsPaused: vector<u8> = b"Wheel is paused";

#[error]
const EInvalidTicket: vector<u8> = b"Ticket is not valid for spinning";

public struct RewardWheel has key, store {
    id: UID,
    paused: bool,
    rewards: ObjectBag,
    metadata: VecMap<String, String>,
}

public struct Ticket has key, store {
    id: UID,
    valid: bool,
}

public struct Reward has key, store {
    id: UID,
}

public struct RewardV2 has key, store {
    id: UID,
    reward: TypeName,
    amount: u64,
    reward_id: ID,
}

public struct RewardEvent has copy, drop {
    reward: TypeName,
    amount: u64,
    reward_item_id: ID,
    reward_parent_id: ID,
}

public fun create_reward_wheel(
    _: &CanvasAdminCap,
    metadata: VecMap<String, String>,
    ctx: &mut TxContext,
) {
    let wheel = RewardWheel {
        id: object::new(ctx),
        paused: false,
        rewards: object_bag::new(ctx),
        metadata: metadata,
    };

    events::emit_wheel_created_event(wheel.id.to_inner(), ctx.sender());

    transfer::share_object(wheel);
}

#[deprecated(note = b"Use `add_rewards_v2` instead")]
public fun add_rewards<T: key + store>(
    wheel: &mut RewardWheel,
    _: &CanvasAdminCap,
    items: vector<T>,
    ctx: &mut TxContext,
) {
    items.do!(|item| {
        // create reward object
        let reward = Reward {
            id: object::new(ctx),
        };

        let reward_address = object::id(&reward).to_address();
        transfer::public_transfer(item, reward_address);

        // add reward to wheel
        let i = wheel.rewards.length();
        wheel.rewards.add(i as u32, reward);
    });
}

public fun add_rewards_v2<T: key + store>(
    wheel: &mut RewardWheel,
    _: &CanvasAdminCap,
    items: vector<T>,
    amounts: vector<u64>,
    ctx: &mut TxContext,
) {
    items.zip_do!(amounts, |item, amount| {
        // create reward object
        let reward = RewardV2 {
            id: object::new(ctx),
            reward: type_name::with_defining_ids<T>(),
            amount,
            reward_id: object::id(&item),
        };

        let reward_address = object::id(&reward).to_address();
        transfer::public_transfer(item, reward_address);

        // add reward to wheel
        let i = wheel.rewards.length();
        wheel.rewards.add(i as u32, reward);
    });
}

public fun withdraw_from_reward_wheel<T: key + store>(
    _: &CanvasAdminCap,
    wheel: &mut RewardWheel,
    key: u32,
): T {
    wheel.rewards.remove(key)
}

entry fun toggle_reward_wheel(_: &CanvasAdminCap, wheel: &mut RewardWheel) {
    wheel.paused = !wheel.paused;
}

public fun set_reward_wheel_metadata(
    _: &CanvasAdminCap,
    wheel: &mut RewardWheel,
    metadata: VecMap<String, String>,
) {
    wheel.metadata = metadata;
}

#[deprecated(note = b"Use `spin_v2` instead")]
entry fun spin(
    wheel: &mut RewardWheel,
    ticket: Ticket,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(!wheel.paused, EWheelIsPaused);
    assert!(ticket.valid, EInvalidTicket);
    let mut generator = r.new_generator(ctx);
    let index = generator.generate_u32_in_range(
        1,
        (wheel.rewards.length() as u32),
    );

    let reward: Reward = wheel.rewards.remove(index);

    ticket.destroy();
    transfer::public_transfer(
        reward,
        ctx.sender(),
    );
}

entry fun spin_v2(
    wheel: &mut RewardWheel,
    ticket: Ticket,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(!wheel.paused, EWheelIsPaused);
    assert!(ticket.valid, EInvalidTicket);
    let mut generator = r.new_generator(ctx);
    let index = generator.generate_u32_in_range(
        1,
        (wheel.rewards.length() as u32),
    );

    let reward: RewardV2 = wheel.rewards.remove(index);

    event::emit(RewardEvent {
        reward: reward.reward,
        amount: reward.amount,
        reward_item_id: reward.reward_id,
        reward_parent_id: object::id(&reward),
    });

    ticket.destroy();
    transfer::public_transfer(
        reward,
        ctx.sender(),
    );
}

#[deprecated(note = b"Use `claim_reward_v2` instead")]
public fun claim_reward<T: key + store>(
    reward: &mut Reward,
    reward_ticket: Receiving<T>,
): T {
    transfer::public_receive(&mut reward.id, reward_ticket)
}

public fun claim_reward_v2<T: key + store>(
    mut reward: RewardV2,
    reward_ticket: Receiving<T>,
    ctx: &mut TxContext,
) {
    let item = transfer::public_receive(&mut reward.id, reward_ticket);
    let RewardV2 { id, reward: _, amount: _, reward_id: _ } = reward;
    id.delete();

    transfer::public_transfer(item, ctx.sender());
}

public fun create_ticket_admin(
    _: &CanvasAdminCap,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    amount.do!(|_| {
        let ticket = Ticket {
            id: object::new(ctx),
            valid: true,
        };
        transfer::public_transfer(ticket, recipient);
    });
}

public(package) fun create_ticket(
    odds: u64,
    num_chances: u16,
    r: &Random,
    ctx: &mut TxContext,
): Ticket {
    let mut generator = r.new_generator(ctx);

    let mut running = BPS_SCALE;
    num_chances.do!(|_| {
        running = (running * (BPS_SCALE - odds)) / BPS_SCALE;
    });

    let prob_success_scaled = BPS_SCALE - running;
    let threshold = (prob_success_scaled * (RAND_MAX as u64)) / BPS_SCALE;

    let roll = generator.generate_u32_in_range(1, RAND_MAX);
    let success = (roll as u64) <= threshold;

    Ticket {
        id: object::new(ctx),
        valid: success,
    }
}

public use fun destroy_ticket as Ticket.destroy;

public fun destroy_ticket(ticket: Ticket) {
    let Ticket { id, valid: _ } = ticket;
    object::delete(id);
}

public fun rewards_mut(wheel: &mut RewardWheel): &mut ObjectBag {
    &mut wheel.rewards
}

public fun is_valid(ticket: &Ticket): bool {
    ticket.valid
}

#[test_only]
public fun create_ticket_for_testing(
    is_valid: bool,
    ctx: &mut TxContext,
): Ticket {
    Ticket {
        id: object::new(ctx),
        valid: is_valid,
    }
}
