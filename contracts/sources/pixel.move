module suiplace::pixel;

use std::string::String;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::sui::SUI;
use suiplace::canvas_admin::CanvasRules;
use suiplace::paint_coin::PAINT_COIN;

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

/// Represents a coordinate on a grid (X, Y coordinates)
public struct Coordinates(u64, u64) has copy, drop, store;

public struct Pixel has store {
    coordinates: Coordinates,
    last_painter: Option<address>,
    price_multiplier: u64,
    last_painted_at: u64,
    color: String,
}

public(package) fun new_pixel(x: u64, y: u64): Pixel {
    Pixel {
        coordinates: new_coordinates(x, y),
        last_painter: option::none(),
        price_multiplier: 1,
        last_painted_at: 0,
        color: b"".to_string(),
    }
}

public fun new_coordinates(x: u64, y: u64): Coordinates {
    Coordinates(x, y)
}

// make entry and rethink how to deal with fees
// have coin splitting logic in the PTB layer
// other option is to have coin be mutable
public(package) fun paint(
    pixel: &mut Pixel,
    color: String,
    rules: &CanvasRules,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &TxContext,
) {
    let fee_amount = payment.value();

    assert!(fee_amount == rules.base_paint_fee(), EInsufficientFee);

    pixel.route_fees(rules, fee_amount, payment, clock);

    // Update pixel data
    pixel.update(color, rules, clock, option::some(ctx.sender()));
}

public(package) fun paint_with_paint(
    pixel: &mut Pixel,
    color: String,
    rules: &CanvasRules,
    payment: Coin<PAINT_COIN>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(payment.value() == rules.paint_coin_fee(), EInsufficientFee);

    transfer::public_transfer(payment, rules.canvas_treasury());

    // Update pixel data
    pixel.update(color, rules, clock, option::some(ctx.sender()));
}

public fun calculate_fee(
    pixel: &Pixel,
    rules: &CanvasRules,
    clock: &Clock,
): u64 {
    if (pixel.is_multiplier_expired(rules, clock)) {
        rules.base_paint_fee()
    } else {
        rules.base_paint_fee() * pixel.price_multiplier
    }
}

public fun is_multiplier_expired(
    pixel: &Pixel,
    rules: &CanvasRules,
    clock: &Clock,
): bool {
    clock.timestamp_ms() - pixel.last_painted_at > rules.pixel_price_multiplier_reset_ms()
}

public fun last_painter(pixel: &Pixel): Option<address> {
    pixel.last_painter
}

public fun last_painted_at(pixel: &Pixel): u64 {
    pixel.last_painted_at
}

public fun price_multiplier(pixel: &Pixel): u64 {
    pixel.price_multiplier
}

fun update(
    pixel: &mut Pixel,
    color: String,
    rules: &CanvasRules,
    clock: &Clock,
    last_painter: Option<address>,
) {
    let price_expired = pixel.is_multiplier_expired(rules, clock);

    pixel.last_painter = last_painter;
    pixel.last_painted_at = clock.timestamp_ms();
    pixel.color = color;

    // if pixel price is expired, increase price multiplier, or reset to 1
    if (price_expired) {
        pixel.price_multiplier = 1;
    } else {
        pixel.price_multiplier = pixel.price_multiplier + 1;
    }
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
        .last_painter
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

public fun x(key: Coordinates): u64 {
    key.0
}

public fun y(key: Coordinates): u64 {
    key.1
}

public fun coordinates(pixel: &Pixel): Coordinates {
    pixel.coordinates
}
