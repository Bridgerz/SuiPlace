#[test_only]
module suiplace::rewards_tests;

use std::string::String;
use sui::coin::{Self, Coin};
use sui::random::{Self, Random};
use sui::sui::SUI;
use sui::test_scenario;
use sui::vec_map;
use suiplace::canvas_admin;
use suiplace::paint_coin::PAINT_COIN;
use suiplace::rewards::{Self, RewardWheel, Reward};

#[test_only]
public struct TestReward has key, store {
    id: UID,
}

#[test]
fun spin_wheel() {
    create_test_wheel();

    let system = @0x0;
    let admin = @0x1;
    let player = @0x2;

    let mut scenario = test_scenario::begin(system);
    random::create_for_testing(scenario.ctx());
    scenario.next_tx(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());

    scenario.next_tx(player);

    let ticket = rewards::create_ticket_for_testing(
        true,
        scenario.ctx(),
    );

    scenario.next_tx(player);

    let mut wheel = scenario.take_shared<RewardWheel>();

    scenario.next_tx(system);

    let mut random: Random = scenario.take_shared();
    random.update_randomness_state_for_testing(
        0,
        x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F",
        scenario.ctx(),
    );
    scenario.next_tx(player);

    wheel.spin(ticket, &random, scenario.ctx());

    scenario.next_tx(player);

    let reward = scenario.take_from_address<Reward>(player);

    assert!(object::id(&reward).to_address().to_string().length() > 0);

    transfer::public_transfer(reward, player);
    transfer::public_transfer(canvas_cap, admin);
    transfer::public_share_object(wheel);

    test_scenario::return_shared(random);
    scenario.end();
}

#[test]
public(package) fun create_test_wheel() {
    let admin = @0x1;

    let mut scenario = test_scenario::begin(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());

    scenario.next_tx(admin);

    let metadata = vec_map::empty<String, String>();

    rewards::create_reward_wheel(
        &canvas_cap,
        metadata,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    let mut wheel = scenario.take_shared<RewardWheel>();

    scenario.next_tx(admin);

    let sui_reward = coin::mint_for_testing<SUI>(
        10_000_000_000,
        scenario.ctx(),
    );

    let paint_reward = coin::mint_for_testing<PAINT_COIN>(
        10_000_000_000,
        scenario.ctx(),
    );

    let test_object = TestReward {
        id: object::new(scenario.ctx()),
    };

    wheel.add_rewards(
        &canvas_cap,
        vector<Coin<SUI>>[sui_reward],
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    wheel.add_rewards(
        &canvas_cap,
        vector<Coin<PAINT_COIN>>[paint_reward],
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    wheel.add_rewards(
        &canvas_cap,
        vector<TestReward>[test_object],
        scenario.ctx(),
    );

    transfer::public_share_object(wheel);
    transfer::public_transfer(canvas_cap, admin);
    scenario.end();
}
