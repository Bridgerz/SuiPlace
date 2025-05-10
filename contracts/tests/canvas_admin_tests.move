#[test_only]
module suiplace::canvas_admin_tests;

use sui::test_scenario;
use suiplace::canvas;
use suiplace::canvas_admin;

#[test]
fun test_update_pixel_price_multiplier() {
    let admin = @0x1;

    let mut scenario = test_scenario::begin(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    let mut canvas = canvas::create_canvas_for_testing(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    assert!(canvas.rules().base_paint_fee() == 100000000);
    assert!(canvas.rules().pixel_price_multiplier_reset_ms() == 1000);
    assert!(canvas.rules().canvas_treasury() == canvas_cap.id().to_address());

    canvas::update_base_paint_fee(
        &canvas_cap,
        &mut canvas,
        200000000,
    );

    canvas::update_pixel_price_multiplier_reset_ms(
        &canvas_cap,
        &mut canvas,
        2000,
    );

    canvas::update_canvas_treasury(
        &canvas_cap,
        &mut canvas,
        @0x2,
    );

    scenario.next_tx(admin);

    assert!(canvas.rules().base_paint_fee() == 200000000);
    assert!(canvas.rules().pixel_price_multiplier_reset_ms() == 2000);
    assert!(canvas.rules().canvas_treasury() == @0x2);

    transfer::public_transfer(canvas_cap, admin);
    transfer::public_transfer(canvas, admin);

    scenario.end();
}

#[test]
fun test_update_base_paint_fee() {}

#[test]
fun test_update_treasury() {}
