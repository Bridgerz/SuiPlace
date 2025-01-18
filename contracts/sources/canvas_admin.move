module suiplace::canvas_admin;

use sui::coin::Coin;
use sui::transfer::Receiving;

public struct CanvasAdminCap has key, store { id: UID }

/// Initializes a new CanvasAdminCap
fun init(ctx: &mut TxContext) {
    let canvas_cap = CanvasAdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(canvas_cap, ctx.sender());
}

public struct CanvasRules has store {
    base_paint_fee: u64,
    pixel_price_multiplier_reset_ms: u64,
    canvas_treasury: address,
    paint_coin_fee: u64,
}

public fun new_rules(
    base_paint_fee: u64,
    pixel_price_multiplier_reset_ms: u64,
    canvas_treasury: address,
    paint_coin_fee: u64,
): CanvasRules {
    CanvasRules {
        base_paint_fee,
        pixel_price_multiplier_reset_ms,
        canvas_treasury,
        paint_coin_fee,
    }
}

public fun base_paint_fee(rules: &CanvasRules): u64 {
    rules.base_paint_fee
}

public fun paint_coin_fee(rules: &CanvasRules): u64 {
    rules.paint_coin_fee
}

public fun pixel_price_multiplier_reset_ms(rules: &CanvasRules): u64 {
    rules.pixel_price_multiplier_reset_ms
}

public fun canvas_treasury(rules: &CanvasRules): address {
    rules.canvas_treasury
}

public fun id(cap: &CanvasAdminCap): ID {
    cap.id.to_inner()
}

public fun update_base_paint_fee(rules: &mut CanvasRules, base_paint_fee: u64) {
    rules.base_paint_fee = base_paint_fee;
}

public fun update_pixel_price_multiplier_reset_ms(
    rules: &mut CanvasRules,
    pixel_price_multiplier_reset_ms: u64,
) {
    rules.pixel_price_multiplier_reset_ms = pixel_price_multiplier_reset_ms;
}

public fun update_canvas_treasury(rules: &mut CanvasRules, canvas_treasury: address) {
    rules.canvas_treasury = canvas_treasury;
}

public fun claim_fees<T>(cap: &mut CanvasAdminCap, fee_ticket: Receiving<Coin<T>>): Coin<T> {
    let fee: Coin<T> = transfer::public_receive(&mut cap.id, fee_ticket);
    fee
}

#[test_only]
public fun create_canvas_admin_cap_for_testing(ctx: &mut TxContext): CanvasAdminCap {
    let canvas_cap = CanvasAdminCap {
        id: object::new(ctx),
    };

    canvas_cap
}
