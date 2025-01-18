module suiplace::canvas;

use std::string::String;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use sui::sui::SUI;
use suiplace::canvas_admin::CanvasRules;
use suiplace::paint_coin::PAINT_COIN;
use suiplace::pixel::{Self, Pixel, PixelKey};

// constant for maximum number of pixels in a canvas (45x45)
const CANVAS_WIDTH: u64 = 45;
const VERSION: u64 = 1;

/// Represents a group of pixels on a grid
public struct Canvas has key, store {
    id: UID,
    pixels: vector<vector<Pixel>>,
    paint_rules: CanvasRules,
    version: u64,
}

/// Event emitted when a pixel is painted
public struct PaintEvent has copy, drop {
    pixel: PixelKey,
    color: String,
    painter: address,
    fee_paid: u64,
    in_paint: bool,
    new_price_multiplier: u64,
    last_painted_at: u64,
}

public(package) fun new_canvas(rules: CanvasRules, ctx: &mut TxContext): ID {
    let mut x = 1;
    let mut pixels: vector<vector<Pixel>> = vector::empty();
    while (x <= CANVAS_WIDTH) {
        let mut y = 1;
        let mut row: vector<Pixel> = vector::empty();
        while (y <= CANVAS_WIDTH) {
            row.push_back(pixel::new_pixel(x, y));
            y = y + 1;
        };
        pixels.push_back(row);
        x = x + 1;
    };

    let canvas = Canvas {
        id: object::new(ctx),
        pixels: pixels,
        paint_rules: rules,
        version: VERSION,
    };
    let canvas_id = canvas.id.to_inner();

    transfer::share_object(canvas);

    canvas_id
}

// make entry and rethink how to deal with fees
// have coin splitting logic in the PTB layer
// other option is to have coin be mutable
public fun paint_pixel(
    canvas: &mut Canvas,
    x: u64,
    y: u64,
    color: String,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &TxContext,
) {
    let payment_amount = payment.value();

    canvas.pixels[x][y].paint(&canvas.paint_rules, payment, clock, ctx);

    // Emit paint event
    event::emit(PaintEvent {
        pixel: canvas.pixels[x][y].key(),
        color,
        painter: tx_context::sender(ctx),
        fee_paid: payment_amount,
        new_price_multiplier: canvas.pixels[x][y].price_multiplier(),
        last_painted_at: canvas.pixels[x][y].last_painted_at(),
        in_paint: false,
    });
}

public fun paint_pixel_with_paint(
    canvas: &mut Canvas,
    x: u64,
    y: u64,
    color: String,
    payment: Coin<PAINT_COIN>,
    clock: &Clock,
    ctx: &TxContext,
) {
    canvas.pixels[x][y].paint_with_paint(&canvas.paint_rules, payment, clock, ctx);

    // Emit paint event
    event::emit(PaintEvent {
        pixel: canvas.pixels[x][y].key(),
        color,
        painter: tx_context::sender(ctx),
        fee_paid: canvas.paint_rules.paint_coin_fee(),
        new_price_multiplier: canvas.pixels[x][y].price_multiplier(),
        last_painted_at: canvas.pixels[x][y].last_painted_at(),
        in_paint: true,
    });
}

// Immutable reference to `pixel`
public fun pixel(canvas: &Canvas, key: PixelKey): &Pixel {
    &canvas.pixels[key.x()][key.y()]
}

/// Calculates the total fee required to paint provided pixels
public fun calculate_pixels_paint_fee(
    canvas: &mut Canvas,
    x: vector<u64>,
    y: vector<u64>,
    clock: &Clock,
): u64 {
    let mut cost = 0;
    let mut i = 0;
    while (i < x.length()) {
        cost = cost + calculate_pixel_paint_fee(canvas, x[i], y[i], clock);
        i = i + 1;
    };
    cost
}

public fun calculate_pixel_paint_fee(canvas: &mut Canvas, x: u64, y: u64, clock: &Clock): u64 {
    let key = pixel::new_pixel_key(x, y);
    let pixel = canvas.pixel(key);
    pixel.calculate_fee(&canvas.paint_rules, clock)
}

public fun id(canvas: &Canvas): ID {
    canvas.id.to_inner()
}

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

#[test_only]
use sui::clock;

#[test_only]
use suiplace::canvas_admin;

#[test]
fun test_paint() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let mut admin_cap;

    let mut scenario = test_scenario::begin(admin);
    {
        admin_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
        let rules = canvas_admin::new_rules(100, 1000, admin_cap.id().to_address(), 100000000);
        new_canvas(rules, scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(manny);
    {
        let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        let fee_amount = canvas.calculate_pixel_paint_fee(
            44,
            44,
            &clock,
        );

        let payment = coin.split(fee_amount, scenario.ctx());

        paint_pixel(
            &mut canvas,
            44,
            44,
            color,
            payment,
            &clock,
            scenario.ctx(),
        );
        let key = pixel::new_pixel_key(44, 44);
        let pixel = canvas.pixel(key);

        assert!(pixel.last_painter() == option::some(manny));

        clock::destroy_for_testing(clock);
        coin::burn_for_testing(coin);
    };

    // test admin gets first paint fee
    scenario.next_tx(admin);
    {
        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<Coin<SUI>>(
            object::id(&admin_cap),
        );

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let admin_cap_owner_balance = admin_cap.claim_fees(ticket);

        assert!(admin_cap_owner_balance.value() == canvas.paint_rules.base_paint_fee());

        transfer::public_transfer(admin_cap_owner_balance, admin);
        transfer::public_transfer(admin_cap, admin);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test]
fun test_paint_with_paint_coin() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;

    let mut scenario = test_scenario::begin(admin);
    {
        let rules = canvas_admin::new_rules(100, 1000, admin, 100000000);
        new_canvas(rules, scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(manny);
    {
        let paint_coin = coin::mint_for_testing<PAINT_COIN>(100000000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        paint_pixel_with_paint(
            &mut canvas,
            44,
            44,
            color,
            paint_coin,
            &clock,
            scenario.ctx(),
        );

        let key = pixel::new_pixel_key(44, 44);

        let pixel = canvas.pixel(key);

        assert!(pixel.last_painter() == option::some(manny));
        clock::destroy_for_testing(clock);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}
