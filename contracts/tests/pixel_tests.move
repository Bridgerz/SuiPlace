#[test_only]
module suiplace::pixel_tests;

use sui::clock;
use sui::test_scenario;
use suiplace::canvas_admin;
use suiplace::pixel;

#[test]
fun test_paint_individual_pixel() {
    let painter = @0x1;
    let mut scenario = test_scenario::begin(painter);

    scenario.next_tx(painter);

    // create rules
    let canvas_rules = canvas_admin::new_rules(
        100000000,
        1000,
        painter,
        100000000,
    );
    let mut clock = clock::create_for_testing(scenario.ctx());

    let mut pixel = pixel::new_pixel(0, 0);
    let color = b"red".to_string();

    // check initial pixel state
    assert!(pixel.color() == b"".to_string());
    assert!(pixel.price_multiplier() == 1);
    assert!(pixel.last_painter() == option::none());
    assert!(pixel.last_painted_at() == 0);

    scenario.next_tx(painter);

    pixel::paint(
        &mut pixel,
        color,
        &canvas_rules,
        &clock,
        scenario.ctx(),
    );

    // check pixel state after painting
    assert!(pixel.color() == color);
    assert!(pixel.price_multiplier() == 2);
    assert!(pixel.last_painter() == option::some(painter));
    assert!(pixel.last_painted_at() == clock.timestamp_ms());
    let mut new_cost = pixel::calculate_fee(&pixel, &canvas_rules, &clock);
    assert!(new_cost == 200000000);

    scenario.next_tx(painter);

    // move time forward to reset pixel
    let current_timestamp = clock.timestamp_ms();
    clock.set_for_testing(current_timestamp + 1000); // add 1 second

    scenario.next_tx(painter);

    pixel::paint(
        &mut pixel,
        color,
        &canvas_rules,
        &clock,
        scenario.ctx(),
    );

    scenario.next_tx(painter);

    // check pixel state after painting
    assert!(pixel.color() == color);
    assert!(pixel.price_multiplier() == 3);
    assert!(pixel.last_painter() == option::some(painter));
    assert!(pixel.last_painted_at() == clock.timestamp_ms());
    new_cost = pixel::calculate_fee(&pixel, &canvas_rules, &clock);

    assert!(new_cost == 400000000);

    // move time forward to reset pixel
    let current_timestamp = clock.timestamp_ms();
    clock.set_for_testing(current_timestamp + 1000); // add 1 second

    // check pixel state has not reset
    assert!(pixel.color() == color);
    assert!(pixel.price_multiplier() == 3);
    assert!(pixel.last_painter() == option::some(painter));
    assert!(pixel.last_painted_at() == current_timestamp);

    scenario.next_tx(painter);
    clock.set_for_testing(current_timestamp + 1001); // add 1 second (+ 1 ms to reset)

    let new_cost = pixel::calculate_fee(&pixel, &canvas_rules, &clock);
    assert!(new_cost == 100000000);

    clock::destroy_for_testing(clock);

    scenario.end();
}
