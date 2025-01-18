module suiplace::meta_canvas;

use sui::event;
use sui::table_vec::{Self, TableVec};
use suiplace::canvas;
use suiplace::canvas_admin::{CanvasAdminCap, CanvasRules};

/// Represents the MetaCanvas, a parent structure holding multiple canvases
public struct MetaCanvas has key, store {
    id: UID,
    canvases: TableVec<ID>,
}

public struct CanvasAddedEvent has copy, drop {
    canvas_id: ID,
    index: u64,
}

/// Initializes a new MetaCanvas
fun init(ctx: &mut TxContext) {
    let meta_canvas = MetaCanvas {
        id: object::new(ctx),
        canvases: table_vec::empty(ctx),
    };
    transfer::share_object(meta_canvas);
}

/// Adds a canvas to the MetaCanvas
public fun add_new_canvas(
    meta_canvas: &mut MetaCanvas,
    _: &CanvasAdminCap,
    rules: CanvasRules,
    ctx: &mut TxContext,
) {
    let canvas_id = canvas::new_canvas(rules, ctx);
    let total_canvases = meta_canvas.canvases.length();
    meta_canvas.canvases.push_back(canvas_id);

    event::emit(CanvasAddedEvent {
        canvas_id: canvas_id,
        index: total_canvases,
    });
}

#[test_only]
use sui::test_scenario;

#[test_only]
use suiplace::canvas_admin;

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

        let addmin_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());

        let rules = canvas_admin::new_rules(100, 1000, addmin_cap.id().to_address(), 100000000);

        meta_canvas.add_new_canvas(&addmin_cap, rules, scenario.ctx());
        assert!(meta_canvas.canvases.length() == 1);

        transfer::public_transfer(addmin_cap, @0x1);
        transfer::public_share_object(meta_canvas);
    };

    scenario.end();
}
