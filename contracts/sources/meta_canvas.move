module suiplace::meta_canvas;

use std::string::String;
use sui::clock::{Self, Clock};
use sui::coin::Coin;
use sui::event;
use sui::object_table::{Self, ObjectTable};
use sui::sui::SUI;
use suiplace::canvas::{Self, Canvas, PixelKey};

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: ObjectTable<u64, Canvas>, // Maps canvas ID to Canvas objects
    treasury: address,
}

public struct TreasuryCap has key, store { id: UID }

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
fun init(ctx: &mut TxContext) {
    let treasury_cap = TreasuryCap {
        id: object::new(ctx),
    };

    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: object_table::new(ctx),
        treasury: treasury_cap.id.to_address(),
    };
    transfer::share_object(meta_canvas);

    transfer::public_transfer(treasury_cap, ctx.sender());
}

/// Adds a canvas to the MetaCanvas
public fun add_new_canvas(
    meta_canvas: &mut MetaCanvas,
    treasury_cap: &TreasuryCap,
    ctx: &mut TxContext,
) {
    let canvas = canvas::new_canvas(treasury_cap.id.to_address(), ctx);
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
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Retrieve the specified canvas
    let canvas = meta_canvas.get_canvas(canvas_index);

    // Delegate the paint operation to the canvas
    let leftover = canvas.paint_pixel(x, y, color, fee, clock, ctx);

    // Emit a MetaCanvas-level event
    event::emit(MetaCanvasPaintEvent {
        meta_canvas_id: meta_canvas.id.to_address(),
        canvas_index: canvas_index,
        pixel_key: canvas::new_pixel_key(x, y),
        color,
        painter: tx_context::sender(ctx),
        fee_paid: leftover.value(),
    });

    leftover
}

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

#[test]
fun test_register_canvas() {
    // Create a new MetaCanvas
    let mut scenario = test_scenario::begin(@0x1);
    {
        init(scenario.ctx());
    };

    scenario.next_tx(@0x1);
    {
        let mut meta_canvas = scenario.take_shared<MetaCanvas>();

        let treasury_cap = scenario.take_from_address<TreasuryCap>(@0x1);

        meta_canvas.add_new_canvas(&treasury_cap, scenario.ctx());
        assert!(meta_canvas.canvases.length() == 1);

        transfer::public_transfer(treasury_cap, @0x1);
        transfer::public_share_object(meta_canvas);
    };

    scenario.next_tx(@0x1);
    {
        // check that the pixel_caps are transferred to admin
        let pixel_cap = scenario.take_from_address<canvas::PixelCap>(@0x1);

        transfer::public_transfer(pixel_cap, @0x1);
    };

    scenario.end();
}

#[test]
fun test_paint_pixel() {
    let (admin, manny) = (@0x1, @0x2);

    let mut meta_canvas;
    let canvas;
    let mut treasury_cap;
    let mut scenario = test_scenario::begin(admin);
    {
        init(scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        meta_canvas = scenario.take_shared<MetaCanvas>();
        treasury_cap = scenario.take_from_address<TreasuryCap>(admin);
        meta_canvas.add_new_canvas(&treasury_cap, scenario.ctx());
    };

    scenario.next_tx(manny);
    {
        let coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        let leftover = paint_pixel(
            &mut meta_canvas,
            0,
            44,
            44,
            color,
            coin,
            &clock,
            scenario.ctx(),
        );

        assert!(leftover.value() == 10_000_000_000 - 10);

        transfer::public_transfer(leftover, manny);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(admin);
    {
        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<
            Coin<SUI>,
        >(treasury_cap.id.to_inner());

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let treasury_cap_balance = transfer::public_receive(&mut treasury_cap.id, ticket);

        assert!(treasury_cap_balance.value() == 5);

        transfer::public_transfer(treasury_cap_balance, admin);
        transfer::public_share_object(meta_canvas);
        transfer::public_transfer(treasury_cap, admin);
    };

    scenario.end();
}
