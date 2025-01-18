module suiplace::bulk_paint;

use std::string::String;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use suiplace::canvas::Canvas;

entry fun paint_pixels(
    canvas: &mut Canvas,
    x: vector<u64>,
    y: vector<u64>,
    colors: vector<String>,
    clock: &Clock,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(x.length() == y.length() && y.length() == colors.length());
    let mut i = 0;
    let mut payments = vector<Coin<SUI>>[];
    while (i < x.length()) {
        let fee = canvas.calculate_pixel_paint_fee(x[i], y[i], clock);
        let pixel_payment = payment.split(fee, ctx);
        payments.push_back(pixel_payment);
        i = i + 1;
    };
    i = 0;
    payments.reverse();
    while (!payments.is_empty()) {
        canvas.paint_pixel(x[i], y[i], colors[i], payments.pop_back(), clock, ctx);
        i = i + 1;
    };

    payments.destroy_empty();

    // return leftover to sender
    transfer::public_transfer(payment, ctx.sender());
}

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

#[test_only]
use sui::clock;

#[test_only]
use suiplace::canvas;

#[test_only]
use suiplace::canvas_admin;

#[test_only]
use suiplace::pixel;

#[test]
fun test_bulk_paint() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let canvas_cap;

    let mut scenario = test_scenario::begin(admin);
    {
        canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
        let rules = canvas_admin::new_rules(100, 1000, admin, 100);
        canvas::new_canvas(rules, scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(manny);
    {
        let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();
        let pixels_x = vector<u64>[42, 43, 44];
        let pixels_y = vector<u64>[42, 43, 44];
        let colors = vector<String>[color, color, color];
        let fee_amount = canvas.calculate_pixels_paint_fee(pixels_x, pixels_y, &clock);

        let payment = coin.split(fee_amount, scenario.ctx());

        paint_pixels(
            &mut canvas,
            pixels_x,
            pixels_y,
            colors,
            &clock,
            payment,
            scenario.ctx(),
        );

        let key1 = pixel::new_pixel_key(44, 44);
        let key2 = pixel::new_pixel_key(43, 43);
        let key3 = pixel::new_pixel_key(42, 42);

        let pixel1 = canvas.pixel(key1);
        let pixel2 = canvas.pixel(key2);
        let pixel3 = canvas.pixel(key3);

        assert!(pixel1.last_painter() == option::some(manny));
        assert!(pixel2.last_painter() == option::some(manny));
        assert!(pixel3.last_painter() == option::some(manny));

        clock::destroy_for_testing(clock);
        coin::burn_for_testing(coin);
    };
    transfer::public_share_object(canvas);
    transfer::public_transfer(canvas_cap, admin);
    scenario.end();
}
