#[test_only]
module suiplace::canvas_admin_tests;

use sui::test_scenario;
use suiplace::canvas_admin;
use suiplace::meta_canvas;

#[test]
fun test_update_pixel_price_multiplier() {
    let admin = @0x1;

    let mut scenario = test_scenario::begin(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    let mut meta_canvas = meta_canvas::create_meta_canvas_for_testing(scenario.ctx());

    scenario.next_tx(admin);

    assert!(meta_canvas.rules().base_paint_fee() == 100000000);
    assert!(meta_canvas.rules().pixel_price_multiplier_reset_ms() == 1000);
    assert!(meta_canvas.rules().canvas_treasury() == admin);

    meta_canvas::update_base_paint_fee(
        &canvas_cap,
        &mut meta_canvas,
        200000000,
    );

    meta_canvas::update_pixel_price_multiplier_reset_ms(
        &canvas_cap,
        &mut meta_canvas,
        2000,
    );

    meta_canvas::update_canvas_treasury(
        &canvas_cap,
        &mut meta_canvas,
        @0x2,
    );

    scenario.next_tx(admin);

    assert!(meta_canvas.rules().base_paint_fee() == 200000000);
    assert!(meta_canvas.rules().pixel_price_multiplier_reset_ms() == 2000);
    assert!(meta_canvas.rules().canvas_treasury() == @0x2);

    transfer::public_transfer(canvas_cap, admin);
    transfer::public_transfer(meta_canvas, admin);

    scenario.end();
}

#[test]
fun test_update_base_paint_fee() {}

#[test]
fun test_update_treasury() {}
