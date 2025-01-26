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
fun test_get_canvas_coordinates() {
    let cord_1 = meta_canvas::get_canvas_coordinates(0, 0);

    let cord_2 = meta_canvas::get_canvas_coordinates(45, 45);

    let cord_3 = meta_canvas::get_canvas_coordinates(90, 90);

    let cord_4 = meta_canvas::get_canvas_coordinates(100, 100);

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
        canvas_1_coordinates,
        scenario.ctx(),
    );

    let canvas_2_coordinates = pixel::new_coordinates(0, 1);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        canvas_2_coordinates,
        scenario.ctx(),
    );

    let canvas_3_coordinates = pixel::new_coordinates(1, 1);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        canvas_3_coordinates,
        scenario.ctx(),
    );

    let canvas_4_coordinates = pixel::new_coordinates(1, 0);
    meta_canvas.add_new_canvas(
        &canvas_cap,
        canvas_4_coordinates,
        scenario.ctx(),
    );

    scenario.next_tx(painter);

    let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let color = b"red".to_string();
    let pixels_x = vector<u64>[44, 44, 45, 45];
    let pixels_y = vector<u64>[44, 45, 45, 44];
    let colors = vector<String>[color, color, color, color];
    let fee_amount = meta_canvas.calculate_pixels_paint_fee(pixels_x, pixels_y, &clock);

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
