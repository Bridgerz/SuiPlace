module suiplace::pixel;

use std::string::String;
use std::u64;
use sui::clock::Clock;
use suiplace::canvas_admin::CanvasRules;

/// Represents a coordinate on a grid (X, Y coordinates)
public struct Coordinates(u64, u64) has copy, drop, store;

public struct Pixel has store, drop {
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

public(package) fun paint(
    pixel: &mut Pixel,
    color: String,
    rules: &CanvasRules,
    clock: &Clock,
    ctx: &TxContext,
) {
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
        rules.base_paint_fee() * u64::pow(2, (pixel.price_multiplier - 1) as u8)
    }
}

public fun is_multiplier_expired(
    pixel: &Pixel,
    rules: &CanvasRules,
    clock: &Clock,
): bool {
    if (pixel.last_painted_at == 0) {
        false
    } else {
        clock.timestamp_ms() - pixel.last_painted_at > rules.pixel_price_multiplier_reset_ms()
    }
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

public fun color(pixel: &Pixel): String {
    pixel.color
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

public fun x(key: Coordinates): u64 {
    key.0
}

public fun y(key: Coordinates): u64 {
    key.1
}

public fun coordinates(pixel: &Pixel): Coordinates {
    pixel.coordinates
}
