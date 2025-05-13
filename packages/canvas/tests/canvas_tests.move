#[test_only]
module suiplace::canvas_tests;

use std::string::String;
use sui::clock;
use sui::coin::{Self, Coin};
use sui::random::{Self, Random};
use sui::sui::SUI;
use sui::test_scenario;
use suiplace::canvas;
use suiplace::canvas_admin;
use suiplace::paint_coin::PAINT_COIN;

#[test]
fun test_paint_pixel() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let admin_cap;

    let mut scenario = test_scenario::begin(admin);

    admin_cap =
        canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    canvas = canvas::create_canvas_for_testing(&admin_cap, scenario.ctx());

    scenario.next_tx(manny);

    let mut coin = coin::mint_for_testing<SUI>(
        10_000_000_000,
        scenario.ctx(),
    );
    let mut clock = clock::create_for_testing(scenario.ctx());
    let color = b"red".to_string();

    let fee_amount = canvas.rules().base_paint_fee();

    let payment = coin.split(fee_amount, scenario.ctx());

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    scenario.next_tx(@0x0);

    let mut random: Random = scenario.take_shared();
    random.update_randomness_state_for_testing(
        0,
        x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F",
        scenario.ctx(),
    );

    scenario.next_tx(manny);

    clock.set_for_testing(1);

    canvas.paint_pixels(
        vector<u64>[44],
        vector<u64>[44],
        vector<String>[color],
        &clock,
        &random,
        payment,
        scenario.ctx(),
    );

    let pixel = canvas.pixel(44, 44);

    // check pixel state after painting
    assert!(pixel.color() == color);
    assert!(pixel.cost() == 200000000);
    assert!(pixel.last_painter() == manny);
    assert!(pixel.last_painted_at() == clock.timestamp_ms());

    // move time forward to reset pixel
    let current_timestamp = clock.timestamp_ms();
    clock.set_for_testing(current_timestamp + 1000); // add 1 second

    // check pixel state has not reset
    assert!(pixel.color() == color);
    assert!(pixel.cost() == 200000000);
    assert!(pixel.last_painter() == manny);
    assert!(pixel.last_painted_at() == current_timestamp);

    scenario.next_tx(manny);
    clock.set_for_testing(current_timestamp + 1001); // add 1 second (+ 1 ms to reset)

    scenario.next_tx(manny);

    let new_cost = pixel.get_cost(canvas.rules(), &clock);

    assert!(new_cost == 100000000);

    clock::destroy_for_testing(clock);
    coin::burn_for_testing(coin);

    // test admin gets first paint fee
    scenario.next_tx(admin);

    let accrued_fees = canvas.fee_router_mut().get_accrued_fees(admin);

    assert!(accrued_fees == canvas.rules().base_paint_fee());

    transfer::public_transfer(admin_cap, admin);

    transfer::public_transfer(canvas, admin);
    test_scenario::return_shared(random);
    scenario.end();
}

#[test]
fun test_paint_pixel_with_paint_coin() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let admin_cap;
    let canvas_rules;

    let mut scenario = test_scenario::begin(admin);

    admin_cap =
        canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    canvas = canvas::create_canvas_for_testing(&admin_cap, scenario.ctx());
    canvas_rules =
        canvas_admin::new_rules(
            100000000,
            1000,
            admin_cap.id().to_address(),
            100000000,
        );

    scenario.next_tx(manny);

    let clock = clock::create_for_testing(scenario.ctx());
    let color = b"red".to_string();

    let payment = coin::mint_for_testing<PAINT_COIN>(
        1_00000000,
        scenario.ctx(),
    );

    canvas.paint_pixels_with_paint(
        vector<u64>[44],
        vector<u64>[44],
        vector<String>[color],
        &clock,
        payment,
        scenario.ctx(),
    );

    let pixel = canvas.pixel(44, 44);

    assert!(pixel.last_painter() == manny);

    clock::destroy_for_testing(clock);

    // test treasury gets PAINT_COIN fee
    scenario.next_tx(admin);

    let admin_balance = scenario.take_from_address<Coin<PAINT_COIN>>(admin);

    assert!(admin_balance.value() == canvas_rules.paint_coin_fee());

    transfer::public_transfer(admin_balance, admin);
    transfer::public_transfer(admin_cap, admin);

    transfer::public_transfer(canvas, admin);
    scenario.end();
}

#[test]
fun test_get_chunk_coordinates_from_pixel() {
    let cord_1 = canvas::get_chunk_coordinate_from_pixel(0, 0);

    let cord_2 = canvas::get_chunk_coordinate_from_pixel(64, 64);

    let cord_3 = canvas::get_chunk_coordinate_from_pixel(128, 128);

    let cord_4 = canvas::get_chunk_coordinate_from_pixel(130, 130);

    assert!(cord_1.x() == 0 && cord_1.y() == 0);
    assert!(cord_2.x() == 1 && cord_2.y() == 1);
    assert!(cord_3.x() == 2 && cord_3.y() == 2);
    assert!(cord_4.x() == 2 && cord_4.y() == 2);
}

#[test]
fun test_paint_pixels() {
    let (admin, painter) = (@0x1, @0x2);

    let mut scenario = test_scenario::begin(@0x0);
    random::create_for_testing(scenario.ctx());

    scenario.next_tx(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    let mut canvas = canvas::create_canvas_for_testing(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(@0x0);

    let mut random: Random = scenario.take_shared();
    random.update_randomness_state_for_testing(
        0,
        x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F",
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    canvas.add_new_chunk(
        &canvas_cap,
        scenario.ctx(),
    );

    canvas.add_new_chunk(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(painter);

    let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1);

    let color = b"red".to_string();
    let pixels_x = vector<u64>[63, 63, 64];
    let pixels_y = vector<u64>[63, 64, 64];
    let colors = vector<String>[color, color, color];

    let fee_amount = canvas.calculate_pixels_paint_fee(
        pixels_x,
        pixels_y,
        &clock,
    );

    assert!(fee_amount == 300000000);

    let payment = coin.split(fee_amount, scenario.ctx());

    canvas.paint_pixels(
        pixels_x,
        pixels_y,
        colors,
        &clock,
        &random,
        payment,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    let new_fee_amount = canvas.calculate_pixels_paint_fee(
        pixels_x,
        pixels_y,
        &clock,
    );

    assert!(new_fee_amount == 600000000);

    // get painted canvases

    let pixel1 = canvas.pixel(63, 63);
    let pixel2 = canvas.pixel(63, 64);
    let pixel3 = canvas.pixel(64, 64);

    assert!(pixel1.last_painter() == painter);
    assert!(pixel2.last_painter() == painter);
    assert!(pixel3.last_painter() == painter);

    scenario.next_tx(admin);

    clock::destroy_for_testing(clock);
    coin::burn_for_testing(coin);
    transfer::public_transfer(canvas, admin);
    transfer::public_transfer(canvas_cap, admin);
    test_scenario::return_shared(random);

    scenario.end();
}

#[test]
fun test_paint_pixels_with_paint() {
    let (admin, painter) = (@0x1, @0x2);

    let mut scenario = test_scenario::begin(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    let mut canvas = canvas::create_canvas_for_testing(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    canvas.add_new_chunk(
        &canvas_cap,
        scenario.ctx(),
    );

    canvas.add_new_chunk(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(painter);

    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1);
    let color = b"red".to_string();
    let pixels_x = vector<u64>[63, 63, 64];
    let pixels_y = vector<u64>[63, 64, 64];
    let colors = vector<String>[color, color, color];

    let payment = coin::mint_for_testing<PAINT_COIN>(
        3_00000000,
        scenario.ctx(),
    );

    canvas.paint_pixels_with_paint(
        pixels_x,
        pixels_y,
        colors,
        &clock,
        payment,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    // painted pixels

    let pixel1 = canvas.pixel(63, 63);
    let pixel2 = canvas.pixel(63, 64);
    let pixel3 = canvas.pixel(64, 64);

    assert!(pixel1.last_painter() == painter);
    assert!(pixel2.last_painter() == painter);
    assert!(pixel3.last_painter() == painter);

    scenario.next_tx(admin);

    clock::destroy_for_testing(clock);
    transfer::public_transfer(canvas, admin);
    transfer::public_transfer(canvas_cap, admin);
    scenario.end();
}

#[test]
fun test_calculate_next_chunk_location() {
    let location_1 = canvas::get_next_chunk_location(0);
    let location_2 = canvas::get_next_chunk_location(1);
    let location_3 = canvas::get_next_chunk_location(2);
    let location_4 = canvas::get_next_chunk_location(3);
    let location_5 = canvas::get_next_chunk_location(4);
    let location_6 = canvas::get_next_chunk_location(5);
    let location_7 = canvas::get_next_chunk_location(6);
    let location_8 = canvas::get_next_chunk_location(7);
    let location_9 = canvas::get_next_chunk_location(8);
    let location_10 = canvas::get_next_chunk_location(9);
    let location_11 = canvas::get_next_chunk_location(10);
    let location_12 = canvas::get_next_chunk_location(11);
    let location_13 = canvas::get_next_chunk_location(12);
    let location_14 = canvas::get_next_chunk_location(13);
    let location_15 = canvas::get_next_chunk_location(14);
    let location_16 = canvas::get_next_chunk_location(15);

    assert!(location_1.x() == 0 && location_1.y() == 0);
    assert!(location_2.x() == 0 && location_2.y() == 1);
    assert!(location_3.x() == 1 && location_3.y() == 1);
    assert!(location_4.x() == 1 && location_4.y() == 0);
    assert!(location_5.x() == 0 && location_5.y() == 2);
    assert!(location_6.x() == 1 && location_6.y() == 2);
    assert!(location_7.x() == 2 && location_7.y() == 2);
    assert!(location_8.x() == 2 && location_8.y() == 1);
    assert!(location_9.x() == 2 && location_9.y() == 0);
    assert!(location_10.x() == 0 && location_10.y() == 3);
    assert!(location_11.x() == 1 && location_11.y() == 3);
    assert!(location_12.x() == 2 && location_12.y() == 3);
    assert!(location_13.x() == 3 && location_13.y() == 3);
    assert!(location_14.x() == 3 && location_14.y() == 2);
    assert!(location_15.x() == 3 && location_15.y() == 1);
    assert!(location_16.x() == 3 && location_16.y() == 0);

    let mut x = 0;
    while (x < 1000) {
        let _location = canvas::get_next_chunk_location(x);
        x = x + 1;
    };
}
