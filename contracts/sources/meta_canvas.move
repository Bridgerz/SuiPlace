module suiplace::meta_canvas;

use sui::table::{Self, Table};
use suiplace::canvas::{Self, CanvasCap};

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: Table<u64, ID>, // Maps canvas index to canvas ID
}

/// Initializes a new MetaCanvas
fun init(ctx: &mut TxContext) {
    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: table::new(ctx),
    };
    transfer::share_object(meta_canvas);
}

/// Adds a canvas to the MetaCanvas
public fun add_new_canvas(meta_canvas: &mut MetaCanvas, _: &CanvasCap, ctx: &mut TxContext) {
    let canvas_id = canvas::new_canvas(ctx);
    let total_canvases = meta_canvas.canvases.length();
    meta_canvas.canvases.add(total_canvases, canvas_id);
}

/// Retrieves a canvas from the MetaCanvas
public fun get_canvas_id(meta_canvas: &mut MetaCanvas, index: u64): &ID {
    meta_canvas.canvases.borrow(index)
}

#[test_only]
use sui::test_scenario;

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

        let meta_cap = canvas::create_canvas_cap_for_testing(scenario.ctx());

        meta_canvas.add_new_canvas(&meta_cap, scenario.ctx());
        assert!(meta_canvas.canvases.length() == 1);

        transfer::public_transfer(meta_cap, @0x1);
        transfer::public_share_object(meta_canvas);
    };

    scenario.next_tx(@0x1);
    {
        // check that the pixel_owneres are transferred to admin
        let pixel_owner = scenario.take_from_address<canvas::PixelOwner>(@0x1);

        transfer::public_transfer(pixel_owner, @0x1);
    };

    scenario.end();
}
