#[test_only]
module suiplace::meta_canvas_tests;

use std::string::String;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;
use suiplace::canvas_admin;
use suiplace::meta_canvas;
use suiplace::pixel;

#[test]
fun test_get_canvas_coordinates_from_pixel() {
    let cord_1 = meta_canvas::get_canvas_coordinates_from_pixel(0, 0);

    let cord_2 = meta_canvas::get_canvas_coordinates_from_pixel(45, 45);

    let cord_3 = meta_canvas::get_canvas_coordinates_from_pixel(90, 90);

    let cord_4 = meta_canvas::get_canvas_coordinates_from_pixel(100, 100);

    assert!(cord_1.x() == 0 && cord_1.y() == 0);
    assert!(cord_2.x() == 1 && cord_2.y() == 1);
    assert!(cord_3.x() == 2 && cord_3.y() == 2);
    assert!(cord_4.x() == 2 && cord_4.y() == 2);
}

#[test]
fun test_paint_pixels() {
    let (admin, painter) = (@0x1, @0x2);

    let mut scenario = test_scenario::begin(admin);

    let canvas_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
    let mut meta_canvas = meta_canvas::create_meta_canvas_for_testing(scenario.ctx());

    scenario.next_tx(admin);

    let canvas_1_coordinates = pixel::new_coordinates(0, 0);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        scenario.ctx(),
    );

    let canvas_2_coordinates = pixel::new_coordinates(0, 1);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        scenario.ctx(),
    );

    let canvas_3_coordinates = pixel::new_coordinates(1, 1);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        scenario.ctx(),
    );

    let canvas_4_coordinates = pixel::new_coordinates(1, 0);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        scenario.ctx(),
    );

    scenario.next_tx(painter);

    let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let color = b"red".to_string();
    let pixels_x = vector<u64>[44, 44, 45, 45];
    let pixels_y = vector<u64>[44, 45, 45, 44];
    let colors = vector<String>[color, color, color, color];
    let fee_amount = meta_canvas.calculate_pixels_paint_fee(
        pixels_x,
        pixels_y,
        &clock,
    );

    let payment = coin.split(fee_amount, scenario.ctx());

    meta_canvas.paint_pixels(
        pixels_x,
        pixels_y,
        colors,
        &clock,
        payment,
        scenario.ctx(),
    );

    scenario.next_tx(admin);

    // get painted canvases

    let canvas_1 = meta_canvas.get_canvas(canvas_1_coordinates);
    let canvas_2 = meta_canvas.get_canvas(canvas_2_coordinates);
    let canvas_3 = meta_canvas.get_canvas(canvas_3_coordinates);
    let canvas_4 = meta_canvas.get_canvas(canvas_4_coordinates);

    // painted pixels
    let (pixel_1_x, pixel_1_y) = meta_canvas::offset_pixel_coordinates(
        44,
        44,
        canvas_1_coordinates,
    );
    let pixel_1_coordinates = pixel::new_coordinates(
        pixel_1_x,
        pixel_1_y,
    );

    let (pixel_2_x, pixel_2_y) = meta_canvas::offset_pixel_coordinates(
        44,
        45,
        canvas_2_coordinates,
    );
    let pixel_2_coordinates = pixel::new_coordinates(
        pixel_2_x,
        pixel_2_y,
    );

    let (pixel_3_x, pixel_3_y) = meta_canvas::offset_pixel_coordinates(
        45,
        45,
        canvas_3_coordinates,
    );
    let pixel_3_coordinates = pixel::new_coordinates(pixel_3_x, pixel_3_y);

    let (pixel_4_x, pixel_4_y) = meta_canvas::offset_pixel_coordinates(
        45,
        44,
        canvas_4_coordinates,
    );
    let pixel_4_coordinates = pixel::new_coordinates(pixel_4_x, pixel_4_y);

    let pixel1 = canvas_1.pixel(pixel_1_coordinates);
    let pixel2 = canvas_2.pixel(pixel_2_coordinates);
    let pixel3 = canvas_3.pixel(pixel_3_coordinates);
    let pixel4 = canvas_4.pixel(pixel_4_coordinates);

    assert!(pixel1.last_painter() == option::some(painter));
    assert!(pixel2.last_painter() == option::some(painter));
    assert!(pixel3.last_painter() == option::some(painter));
    assert!(pixel4.last_painter() == option::some(painter));

    scenario.next_tx(admin);

    clock::destroy_for_testing(clock);
    coin::burn_for_testing(coin);
    transfer::public_transfer(meta_canvas, admin);
    transfer::public_transfer(canvas_cap, admin);
    scenario.end();
}

#[test]
fun test_calculate_next_canvas_location() {
    let location_1 = meta_canvas::calculate_next_canvas_location(0);
    let location_2 = meta_canvas::calculate_next_canvas_location(1);
    let location_3 = meta_canvas::calculate_next_canvas_location(2);
    let location_4 = meta_canvas::calculate_next_canvas_location(3);
    let location_5 = meta_canvas::calculate_next_canvas_location(4);
    let location_6 = meta_canvas::calculate_next_canvas_location(5);
    let location_7 = meta_canvas::calculate_next_canvas_location(6);
    let location_8 = meta_canvas::calculate_next_canvas_location(7);
    let location_9 = meta_canvas::calculate_next_canvas_location(8);
    let location_10 = meta_canvas::calculate_next_canvas_location(9);
    let location_11 = meta_canvas::calculate_next_canvas_location(10);
    let location_12 = meta_canvas::calculate_next_canvas_location(11);
    let location_13 = meta_canvas::calculate_next_canvas_location(12);
    let location_14 = meta_canvas::calculate_next_canvas_location(13);
    let location_15 = meta_canvas::calculate_next_canvas_location(14);
    let location_16 = meta_canvas::calculate_next_canvas_location(15);

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
        let _location = meta_canvas::calculate_next_canvas_location(x);
        x = x + 1;
    };
}
