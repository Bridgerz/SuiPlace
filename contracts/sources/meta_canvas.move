module suiplace::meta_canvas;

use std::string::String;
use std::u64;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::object_table::{Self, ObjectTable};
use sui::random::Random;
use sui::sui::SUI;
use suiplace::canvas::{Self, Canvas};
use suiplace::canvas_admin::{Self, CanvasRules, CanvasAdminCap};
use suiplace::events;
use suiplace::paint_coin::PAINT_COIN;
use suiplace::pixel::{Self, Pixel, Coordinates};
use suiplace::rewards;

const CANVAS_WIDTH: u64 = 45;

#[error]
const EInvalidPaintData: vector<u8> =
    b"Must provide equal number of x, y, and color values";

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: ObjectTable<Coordinates, Canvas>,
    rules: CanvasRules,
    ticket_odds: u64,
}

/// Initializes a new MetaCanvas
fun init(ctx: &mut TxContext) {
    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: object_table::new(ctx),
        rules: canvas_admin::new_rules(
            10000000,
            300000, // 5 minutes in milliseconds
            ctx.sender(),
            100000000,
        ),
        ticket_odds: 10000, // 10000 => 100%
    };
    transfer::share_object(meta_canvas);
}

/// Adds a canvas to the MetaCanvas
public fun add_new_canvas(
    meta_canvas: &mut MetaCanvas,
    canvas_admin_cap: &CanvasAdminCap,
    ctx: &mut TxContext,
) {
    let canvas = canvas::new_canvas(canvas_admin_cap, ctx);
    let total_canvases = meta_canvas.canvases.length();
    let canvas_id = object::id(&canvas);
    let canvas_location = calculate_next_canvas_location(total_canvases);
    meta_canvas.canvases.add(canvas_location, canvas);

    events::emit_canvas_added_event(canvas_id, total_canvases);
}

entry fun paint_pixels(
    meta_canvas: &mut MetaCanvas,
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
    let mut i = 0;
    while (i < x.length()) {
        let canvas_coordinates = get_canvas_coordinates_from_pixel(x[i], y[i]);
        let canvas = meta_canvas.canvases.borrow_mut(canvas_coordinates);
        let (offset_x, offset_y) = offset_pixel_coordinates(
            x[i],
            y[i],
            canvas_coordinates,
        );
        let fee = canvas.calculate_pixel_paint_fee(
            &meta_canvas.rules,
            offset_x,
            offset_y,
            clock,
        );
        let pixel_payment = payment.split(fee, ctx);
        canvas.paint_pixel(
            &meta_canvas.rules,
            offset_x,
            offset_y,
            colors[i],
            pixel_payment,
            clock,
            ctx,
        );
        i = i + 1;
    };

    let ticket = rewards::create_ticket(
        meta_canvas.ticket_odds,
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

    events::emit_pixels_painted_event(x, y, colors);

    transfer::public_transfer(payment, ctx.sender());
}

entry fun paint_pixels_with_paint(
    meta_canvas: &mut MetaCanvas,
    x: vector<u64>,
    y: vector<u64>,
    colors: vector<String>,
    clock: &Clock,
    mut payment: Coin<PAINT_COIN>,
    ctx: &mut TxContext,
) {
    assert!(
        x.length() == y.length() && y.length() == colors.length(),
        EInvalidPaintData,
    );
    let mut i = 0;
    while (i < x.length()) {
        let canvas_coordinates = get_canvas_coordinates_from_pixel(x[i], y[i]);
        let canvas = meta_canvas.canvases.borrow_mut(canvas_coordinates);
        let (offset_x, offset_y) = offset_pixel_coordinates(
            x[i],
            y[i],
            canvas_coordinates,
        );
        let fee = meta_canvas.rules.paint_coin_fee();
        let pixel_payment = payment.split(fee, ctx);
        canvas.paint_pixel_with_paint(
            &meta_canvas.rules,
            offset_x,
            offset_y,
            colors[i],
            pixel_payment,
            clock,
            ctx,
        );
        i = i + 1;
    };

    events::emit_pixels_painted_event(x, y, colors);

    transfer::public_transfer(payment, ctx.sender());
}

public fun get_canvas_coordinates_from_pixel(x: u64, y: u64): Coordinates {
    let offset_x = x / CANVAS_WIDTH;
    let offset_y = y / CANVAS_WIDTH;
    pixel::new_coordinates(offset_x, offset_y)
}

public fun get_pixel(meta_canvas: &MetaCanvas, x: u64, y: u64): &Pixel {
    let canvas_coordinates = get_canvas_coordinates_from_pixel(x, y);
    let canvas = meta_canvas.canvases.borrow(canvas_coordinates);
    let (x, y) = offset_pixel_coordinates(
        x,
        y,
        canvas_coordinates,
    );
    canvas.pixel(pixel::new_coordinates(x, y))
}

public fun rules(meta_canvas: &MetaCanvas): &CanvasRules {
    &meta_canvas.rules
}

/// Calculates the next location (x,y) based on the index `length`.
public fun calculate_next_canvas_location(length: u64): Coordinates {
    // If this is the very first canvas, it goes to (0,0).
    if (length == 0) {
        return pixel::new_coordinates(0, 0)
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
        return pixel::new_coordinates(x, y)
    } else {
        let x = r;
        let y = (2 * r) - offset;
        return pixel::new_coordinates(x, y)
    }
}

public fun offset_pixel_coordinates(
    x: u64,
    y: u64,
    canvas_coordinates: Coordinates,
): (u64, u64) {
    let offset_x = x - (canvas_coordinates.x() * CANVAS_WIDTH);
    let offset_y = y - (canvas_coordinates.y() * CANVAS_WIDTH);
    (offset_x, offset_y)
}

public fun calculate_pixels_paint_fee(
    meta_canvas: &MetaCanvas,
    x: vector<u64>,
    y: vector<u64>,
    clock: &Clock,
): u64 {
    let mut total_fee = 0;
    let mut i = 0;
    while (i < x.length()) {
        let canvas_coordinates = get_canvas_coordinates_from_pixel(x[i], y[i]);
        let canvas = meta_canvas.canvases.borrow(canvas_coordinates);
        let (offset_x, offset_y) = offset_pixel_coordinates(
            x[i],
            y[i],
            canvas_coordinates,
        );
        total_fee =
            total_fee + canvas.calculate_pixel_paint_fee(&meta_canvas.rules, offset_x, offset_y, clock);
        i = i + 1;
    };
    total_fee
}

public fun get_canvas(
    meta_canvas: &MetaCanvas,
    coordinates: Coordinates,
): &Canvas {
    meta_canvas.canvases.borrow(coordinates)
}

public fun update_base_paint_fee(
    _: &CanvasAdminCap,
    meta_canvas: &mut MetaCanvas,
    base_paint_fee: u64,
) {
    meta_canvas.rules.update_base_paint_fee(base_paint_fee);
}

public fun update_pixel_price_multiplier_reset_ms(
    _: &CanvasAdminCap,
    meta_canvas: &mut MetaCanvas,
    pixel_price_multiplier_reset_ms: u64,
) {
    meta_canvas
        .rules
        .update_pixel_price_multiplier_reset_ms(
            pixel_price_multiplier_reset_ms,
        );
}

public fun update_canvas_treasury(
    _: &CanvasAdminCap,
    meta_canvas: &mut MetaCanvas,
    canvas_treasury: address,
) {
    meta_canvas.rules.update_canvas_treasury(canvas_treasury);
}

public fun update_ticket_odds(
    _: &CanvasAdminCap,
    meta_canvas: &mut MetaCanvas,
    ticket_odds: u64,
) {
    meta_canvas.ticket_odds = ticket_odds;
}

#[test_only]
public fun create_meta_canvas_for_testing(ctx: &mut TxContext): MetaCanvas {
    MetaCanvas {
        id: object::new(ctx),
        canvases: object_table::new(ctx),
        rules: canvas_admin::new_rules(
            100000000,
            1000,
            ctx.sender(),
            100000000,
        ),
        ticket_odds: 100,
    }
}
