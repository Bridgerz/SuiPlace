module suiplace::canvas;

use std::string::String;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use suiplace::canvas_admin::{CanvasRules, CanvasAdminCap};
use suiplace::paint_coin::PAINT_COIN;
use suiplace::pixel::{Self, Pixel, Coordinates};

// constant for maximum number of pixels in a canvas (45x45)
const CANVAS_WIDTH: u64 = 45;
const VERSION: u64 = 1;

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

/// Represents a group of pixels on a grid
public struct Canvas has key, store {
    id: UID,
    pixels: vector<vector<Pixel>>,
    version: u64,
}

public(package) fun new_canvas(
    _: &CanvasAdminCap,
    ctx: &mut TxContext,
): Canvas {
    let mut x = 0;
    let mut pixels: vector<vector<Pixel>> = vector::empty();
    while (x < CANVAS_WIDTH) {
        let mut y = 0;
        let mut row: vector<Pixel> = vector::empty();
        while (y < CANVAS_WIDTH) {
            row.push_back(pixel::new_pixel(x, y));
            y = y + 1;
        };
        pixels.push_back(row);
        x = x + 1;
    };

    let canvas = Canvas {
        id: object::new(ctx),
        pixels: pixels,
        version: VERSION,
    };

    canvas
}

public(package) fun paint_pixel(
    canvas: &mut Canvas,
    rules: &CanvasRules,
    x: u64,
    y: u64,
    color: String,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &TxContext,
) {
    let fee_amount = canvas.pixels[x][y].calculate_fee(rules, clock);

    assert!(payment.value() == fee_amount, EInsufficientFee);

    route_fees(&canvas.pixels[x][y], rules, fee_amount, payment, clock);

    canvas.pixels[x][y].paint(color, rules, clock, ctx);
}

public(package) fun paint_pixel_with_paint(
    canvas: &mut Canvas,
    rules: &CanvasRules,
    x: u64,
    y: u64,
    color: String,
    payment: Coin<PAINT_COIN>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(payment.value() == rules.paint_coin_fee(), EInsufficientFee);

    transfer::public_transfer(payment, rules.canvas_treasury());

    canvas.pixels[x][y].paint(color, rules, clock, ctx);
}

/// Calculates the total fee required to paint provided pixels
public fun calculate_pixels_paint_fee(
    canvas: &mut Canvas,
    rules: &CanvasRules,
    x: vector<u64>,
    y: vector<u64>,
    clock: &Clock,
): u64 {
    let mut cost = 0;
    let mut i = 0;
    while (i < x.length()) {
        cost =
            cost + canvas.calculate_pixel_paint_fee(rules, x[i], y[i], clock);
        i = i + 1;
    };
    cost
}

public fun calculate_pixel_paint_fee(
    canvas: &Canvas,
    rules: &CanvasRules,
    x: u64,
    y: u64,
    clock: &Clock,
): u64 {
    let coordinates = pixel::new_coordinates(x, y);
    let pixel = canvas.pixel(coordinates);
    pixel.calculate_fee(rules, clock)
}

public fun id(canvas: &Canvas): ID {
    canvas.id.to_inner()
}

// Immutable reference to `pixel`
public fun pixel(canvas: &Canvas, coordinates: Coordinates): &Pixel {
    &canvas.pixels[coordinates.x()][coordinates.y()]
}

fun route_fees(
    pixel: &Pixel,
    rules: &CanvasRules,
    fee_amount: u64,
    payment: Coin<SUI>,
    clock: &Clock,
) {
    let cost = pixel.calculate_fee(rules, clock);
    assert!(fee_amount >= cost, EInsufficientFee);

    let mut paint_fee_recipient = pixel
        .last_painter()
        .borrow_with_default(&rules.canvas_treasury());

    // if pixel was reset (or first painted), paint fee goes to treasury
    if (cost == rules.base_paint_fee()) {
        paint_fee_recipient = &rules.canvas_treasury();
    };

    transfer::public_transfer(
        payment,
        *paint_fee_recipient,
    );
}
