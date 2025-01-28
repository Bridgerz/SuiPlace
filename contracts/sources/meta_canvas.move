module suiplace::meta_canvas;

use std::string::String;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use sui::object_table::{Self, ObjectTable};
use sui::sui::SUI;
use suiplace::canvas::{Self, Canvas};
use suiplace::canvas_admin::{Self, CanvasRules, CanvasAdminCap};
use suiplace::pixel::{Self, Coordinates};

const CANVAS_WIDTH: u64 = 45;

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: ObjectTable<Coordinates, Canvas>,
    rules: CanvasRules,
}

public struct CanvasAddedEvent has copy, drop {
    canvas_id: ID,
    index: u64,
}

/// Event emitted when a pixel is painted
public struct PixelsPaintedEvent has copy, drop {
    pixels_x: vector<u64>,
    pixels_y: vector<u64>,
    color: vector<String>,
}

/// Initializes a new MetaCanvas
fun init(ctx: &mut TxContext) {
    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: object_table::new(ctx),
        rules: canvas_admin::new_rules(
            10000000,
            1000,
            ctx.sender(),
            100000000,
        ),
    };
    transfer::share_object(meta_canvas);
}

/// Adds a canvas to the MetaCanvas
/// TODO: enable automatic canvas placement based on a grid pattern and remove
/// canvas_location
public fun add_new_canvas(
    meta_canvas: &mut MetaCanvas,
    canvas_admin_cap: &CanvasAdminCap,
    canvas_location: Coordinates,
    ctx: &mut TxContext,
) {
    let canvas = canvas::new_canvas(canvas_admin_cap, ctx);
    let total_canvases = meta_canvas.canvases.length();
    let canvas_id = object::id(&canvas);
    meta_canvas.canvases.add(canvas_location, canvas);

    event::emit(CanvasAddedEvent {
        canvas_id,
        index: total_canvases,
    });
}

entry fun paint_pixels(
    meta_canvas: &mut MetaCanvas,
    x: vector<u64>,
    y: vector<u64>,
    colors: vector<String>,
    clock: &Clock,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(x.length() == y.length() && y.length() == colors.length());
    let mut i = 0;
    while (i < x.length()) {
        let canvas_coordinates = get_canvas_coordinates(x[i], y[i]);
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

    event::emit(PixelsPaintedEvent {
        pixels_x: x,
        pixels_y: y,
        color: colors,
    });

    transfer::public_transfer(payment, ctx.sender());
}

// TODO: add paint pixels with paint function

public fun get_canvas_coordinates(x: u64, y: u64): Coordinates {
    let offset_x = x / CANVAS_WIDTH;
    let offset_y = y / CANVAS_WIDTH;
    pixel::new_coordinates(offset_x, offset_y)
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
        let canvas_coordinates = get_canvas_coordinates(x[i], y[i]);
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
    }
}
