module suiplace::MetaCanvas;

use std::string::String;
use sui::coin::Coin;
use sui::event;
use sui::object_table::{Self, ObjectTable};
use sui::sui::SUI;
use suiplace::Canvas::{Canvas, PixelKey, new_pixel_key};

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: ObjectTable<u64, Canvas>, // Maps canvas ID to Canvas objects
}

/// Event emitted when a pixel is painted
public struct MetaCanvasPaintEvent has copy, drop {
    meta_canvas_id: address, // MetaCanvas address
    canvas_index: u64, // Sub-canvas index
    pixel_key: PixelKey, // Key of the painted pixel
    color: String, // New color
    painter: address, // Address of the painter
    fee_paid: u64, // Fee paid for the painting
}

/// Initializes a new MetaCanvas
public fun init_meta_canvas(ctx: &mut TxContext) {
    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: object_table::new(ctx),
    };
    transfer::share_object(meta_canvas);
}

/// Adds a canvas to the MetaCanvas
public fun add_canvas(meta_canvas: &mut MetaCanvas, canvas: Canvas, ctx: &mut TxContext) {
    let total_canvases = meta_canvas.canvases.length();
    meta_canvas.canvases.add(total_canvases, canvas);
}

/// Retrieves a canvas from the MetaCanvas
public fun get_canvas(meta_canvas: &mut MetaCanvas, index: u64): &mut Canvas {
    meta_canvas.canvases.borrow_mut(index)
}

/// Paints a pixel on a specified canvas and emits a MetaCanvas-level event
public fun paint_pixel(
    meta_canvas: &mut MetaCanvas,
    canvas_index: u64,
    x: u64,
    y: u64,
    color: String,
    fee: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Retrieve the specified canvas
    let canvas = meta_canvas.get_canvas(canvas_index);

    // Delegate the paint operation to the canvas
    let leftover = canvas.paint_pixel(x, y, color, fee, ctx);

    // Emit a MetaCanvas-level event
    event::emit(MetaCanvasPaintEvent {
        meta_canvas_id: meta_canvas.id.to_address(),
        canvas_index: canvas_index,
        pixel_key: new_pixel_key(x, y),
        color,
        painter: tx_context::sender(ctx),
        fee_paid: leftover.value(),
    });

    leftover
}

// TODO: write some tests
