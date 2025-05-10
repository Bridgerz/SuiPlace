module suiplace::canvas;

use std::string::String;
use std::u64;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::dynamic_field as df;
use sui::object_table::{Self, ObjectTable};
use sui::random::Random;
use sui::sui::SUI;
use suiplace::canvas_admin::{Self, CanvasRules, CanvasAdminCap};
use suiplace::events;
use suiplace::paint_coin::PAINT_COIN;
use suiplace::rewards;

const CHUNK_WIDTH: u64 = 64;

#[error]
const EInvalidPaintData: vector<u8> =
    b"Must provide equal number of x, y, and color values";

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

public struct Coordinate(u64, u64) has copy, drop, store;

public struct Canvas has key, store {
    id: UID,
    chunks: ObjectTable<Coordinate, CanvasChunk>,
    rules: CanvasRules,
    ticket_odds: u64,
}

public struct CanvasChunk has key, store {
    id: UID,
}

public struct Pixel has copy, drop, store {
    color: String,
    cost: u64,
    last_painter: address,
    last_painted_at: u64,
}

/// Initializes a new Canvas
fun init(ctx: &mut TxContext) {
    let canvas = Canvas {
        id: object::new(ctx),
        chunks: object_table::new(ctx),
        rules: canvas_admin::new_rules(
            10000000,
            2177280000000, // 69 years in milliseconds
            ctx.sender(),
            100000000,
        ),
        ticket_odds: 10000, // 10000 => 100%
    };
    transfer::share_object(canvas);
}

/// Adds a chunk to a Canvas
public fun add_new_chunk(
    canvas: &mut Canvas,
    _: &CanvasAdminCap,
    ctx: &mut TxContext,
) {
    let chunk = CanvasChunk {
        id: object::new(ctx),
    };

    let total_chunks = canvas.chunks.length();
    let chunk_id = object::id(&chunk);
    let chunk_location = get_next_chunk_location(total_chunks);
    canvas.chunks.add(chunk_location, chunk);

    events::emit_canvas_added_event(chunk_id, total_chunks);
}

entry fun paint_pixels(
    canvas: &mut Canvas,
    x: vector<u64>,
    y: vector<u64>,
    colors: vector<String>,
    clock: &Clock,
    random: &Random,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(
        x.length() == y.length() && y.length() == colors.length(),
        EInvalidPaintData,
    );

    let total_pixels = x.length();
    let payment_amount = payment.value();
    let rules = canvas.rules;
    x.length().do!(|i| {
        let pixel = canvas.get_or_create_pixel(
            x[i],
            y[i],
        );

        let fee = pixel.get_cost(
            &rules,
            clock,
        );

        let pixel_payment = payment.split(fee, ctx);

        transfer::public_transfer(pixel_payment, pixel.last_painter);

        pixel.paint(
            &rules,
            colors[i],
            clock,
            ctx,
        );
    });

    let ticket = rewards::create_ticket(
        canvas.ticket_odds,
        total_pixels as u16,
        random,
        ctx,
    );

    events::emit_reward_event(object::id(&ticket), ticket.is_valid());

    if (ticket.is_valid()) {
        transfer::public_transfer(ticket, ctx.sender());
    } else {
        transfer::public_transfer(ticket, @0x0);
    };

    events::emit_pixels_painted_event(
        x,
        y,
        colors,
        ctx.sender(),
        payment_amount - payment.value(),
    );

    transfer::public_transfer(payment, ctx.sender());
}

entry fun paint_pixels_with_paint(
    canvas: &mut Canvas,
    x: vector<u64>,
    y: vector<u64>,
    colors: vector<String>,
    clock: &Clock,
    payment: Coin<PAINT_COIN>,
    ctx: &TxContext,
) {
    assert!(
        x.length() == y.length() && y.length() == colors.length(),
        EInvalidPaintData,
    );

    let payment_amount = payment.value();
    assert!(
        payment.value() >= calculate_cost_in_paint(canvas.rules(), x.length()),
        EInsufficientFee,
    );

    transfer::public_transfer(payment, canvas.rules().canvas_treasury());

    let rules = canvas.rules;

    x.length().do!(|i| {
        let pixel = canvas.get_or_create_pixel(
            x[i],
            y[i],
        );

        pixel.paint(
            &rules,
            colors[i],
            clock,
            ctx,
        );
    });

    events::emit_pixels_painted_event(
        x,
        y,
        colors,
        ctx.sender(),
        payment_amount,
    );
}

public fun paint(
    pixel: &mut Pixel,
    rules: &CanvasRules,
    color: String,
    clock: &Clock,
    ctx: &TxContext,
) {
    let price_expired = pixel.is_multiplier_expired(rules, clock);

    pixel.last_painter = ctx.sender();
    pixel.last_painted_at = clock.timestamp_ms();
    pixel.color = color;

    if (price_expired) {
        pixel.cost = rules.base_paint_fee() * 2;
    } else {
        pixel.cost = pixel.cost * 2;
    };
}

public fun get_chunk_coordinate_from_pixel(x: u64, y: u64): Coordinate {
    let offset_x = x / CHUNK_WIDTH;
    let offset_y = y / CHUNK_WIDTH;
    Coordinate(offset_x, offset_y)
}

public fun pixel(canvas: &Canvas, x: u64, y: u64): &Pixel {
    let chunk_coordinate = get_chunk_coordinate_from_pixel(x, y);
    let chunk = canvas.chunks.borrow(chunk_coordinate);
    let (x, y) = offset_pixel_coordinate(
        x,
        y,
        chunk_coordinate,
    );

    df::borrow(&chunk.id, Coordinate(x, y))
}

fun get_or_create_pixel(canvas: &mut Canvas, x: u64, y: u64): &mut Pixel {
    let chunk_coordinate = get_chunk_coordinate_from_pixel(x, y);
    let chunk = canvas.chunks.borrow_mut(chunk_coordinate);
    let (x, y) = offset_pixel_coordinate(
        x,
        y,
        chunk_coordinate,
    );
    if (!df::exists_(&chunk.id, Coordinate(x, y))) {
        let pixel = Pixel {
            color: b"".to_string(),
            cost: canvas.rules.base_paint_fee(),
            last_painter: canvas.rules.canvas_treasury(),
            last_painted_at: 0,
        };
        df::add(&mut chunk.id, Coordinate(x, y), pixel);
    };
    df::borrow_mut(&mut chunk.id, Coordinate(x, y))
}

public fun calculate_pixels_paint_fee(
    canvas: &Canvas,
    x: vector<u64>,
    y: vector<u64>,
    clock: &Clock,
): u64 {
    let mut total_fee = 0;
    x.length().do!(|i| {
        let chunk_coordinate = get_chunk_coordinate_from_pixel(x[i], y[i]);
        let chunk = canvas.chunks.borrow(chunk_coordinate);
        let (x, y) = offset_pixel_coordinate(
            x[i],
            y[i],
            chunk_coordinate,
        );
        if (!df::exists_(&chunk.id, Coordinate(x, y))) {
            total_fee = total_fee + canvas.rules.base_paint_fee();
            return
        };

        let pixel: &Pixel = df::borrow(&chunk.id, Coordinate(x, y));

        total_fee =
            total_fee + pixel.get_cost(
            &canvas.rules,
            clock,
        );
    });
    total_fee
}

/// Calculates the next location (x,y) based on the index `length`.
public fun get_next_chunk_location(length: u64): Coordinate {
    // If this is the very first canvas, it goes to (0,0).
    if (length == 0) {
        return Coordinate(0, 0)
    };

    // Identify which "ring" we're on by taking the integer sqrt
    let r = u64::sqrt(length);

    // How far into ring r we are
    let offset = length - (r * r);

    // If we're on ring 0, it's always (0,0), but length=0
    // is already handled above, so r > 0 from here.

    // The ring has 2r+1 points, offset in [0..2r].
    // The first (r+1) of them are moving horizontally,
    // and the last r of them move vertically downward.
    // Segment 1: offset in [0..r]   => x = offset, y = r
    // Segment 2: offset in (r..2r] => x = r,       y = 2r - offset

    if (offset <= r) {
        let x = offset;
        let y = r;
        return Coordinate(x, y)
    } else {
        let x = r;
        let y = (2 * r) - offset;
        return Coordinate(x, y)
    }
}

public fun offset_pixel_coordinate(
    x: u64,
    y: u64,
    chunk_coordinate: Coordinate,
): (u64, u64) {
    let offset_x = x - (chunk_coordinate.x() * CHUNK_WIDTH);
    let offset_y = y - (chunk_coordinate.y() * CHUNK_WIDTH);
    (offset_x, offset_y)
}

public fun get_cost(pixel: &Pixel, rules: &CanvasRules, clock: &Clock): u64 {
    if (pixel.is_multiplier_expired(rules, clock)) {
        rules.base_paint_fee()
    } else {
        pixel.cost
    }
}

public fun calculate_cost_in_paint(rules: &CanvasRules, pixels: u64): u64 {
    rules.paint_coin_fee() * pixels
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

public fun rules(canvas: &Canvas): &CanvasRules {
    &canvas.rules
}

public fun x(key: Coordinate): u64 {
    key.0
}

public fun y(key: Coordinate): u64 {
    key.1
}

public fun color(pixel: &Pixel): String {
    pixel.color
}

public fun cost(pixel: &Pixel): u64 {
    pixel.cost
}

public fun last_painted_at(pixel: &Pixel): u64 {
    pixel.last_painted_at
}

public fun last_painter(pixel: &Pixel): address {
    pixel.last_painter
}

public fun update_base_paint_fee(
    _: &CanvasAdminCap,
    canvas: &mut Canvas,
    base_paint_fee: u64,
) {
    canvas.rules.update_base_paint_fee(base_paint_fee);
}

public fun update_pixel_price_multiplier_reset_ms(
    _: &CanvasAdminCap,
    canvas: &mut Canvas,
    pixel_price_multiplier_reset_ms: u64,
) {
    canvas
        .rules
        .update_pixel_price_multiplier_reset_ms(
            pixel_price_multiplier_reset_ms,
        );
}

public fun update_canvas_treasury(
    _: &CanvasAdminCap,
    canvas: &mut Canvas,
    canvas_treasury: address,
) {
    canvas.rules.update_canvas_treasury(canvas_treasury);
}

public fun update_ticket_odds(
    _: &CanvasAdminCap,
    canvas: &mut Canvas,
    ticket_odds: u64,
) {
    canvas.ticket_odds = ticket_odds;
}

#[test_only]
public fun create_canvas_for_testing(
    admin_cap: &CanvasAdminCap,
    ctx: &mut TxContext,
): Canvas {
    let mut canvas = Canvas {
        id: object::new(ctx),
        chunks: object_table::new(ctx),
        rules: canvas_admin::new_rules(
            100000000,
            1000,
            admin_cap.id().to_address(),
            100000000,
        ),
        ticket_odds: 100,
    };

    add_new_chunk(
        &mut canvas,
        admin_cap,
        ctx,
    );

    canvas
}
