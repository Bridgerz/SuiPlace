module suiplace::canvas;

use std::string::String;
use sui::clock::{Self, Clock};
use sui::coin::Coin;
use sui::event;
use sui::sui::SUI;
use suiplace::paint::PAINT;

// constant for maximum number of pixels in a canvas (45x45)
const CANVAS_WIDTH: u64 = 45;
const PAINT_FEE: u64 = 100000000;
const VERSION: u64 = 1;

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

/// Represents a group of pixels on a grid
public struct Canvas has key, store {
    id: UID,
    pixels: vector<vector<Pixel>>,
    base_paint_fee: u64,
    pixel_price_multiplier_reset_ms: u64,
    cap: ID,
    version: u64,
}

/// Represents a key for a pixel (X, Y coordinates)
public struct PixelKey(u64, u64) has store, copy, drop;

/// Represents a pixel on the canvas
public struct Pixel has store {
    pixel_key: PixelKey,
    last_painter: Option<address>,
    price_multiplier: u64,
    last_painted_at: u64,
}

public struct CanvasCap has key, store { id: UID }

/// Event emitted when a pixel is painted
public struct PaintEvent has copy, drop {
    pixel_id: PixelKey,
    color: String,
    painter: address,
    fee_paid: u64,
    in_paint: bool,
    new_price_multiplier: u64,
    last_painted_at: u64,
}

/// Initializes a new MetaCanvas
fun init(ctx: &mut TxContext) {
    let canvas_cap = CanvasCap {
        id: object::new(ctx),
    };
    transfer::transfer(canvas_cap, ctx.sender());
}

public(package) fun new_canvas(canvas_cap: &CanvasCap, ctx: &mut TxContext): ID {
    let mut x = 1;
    let mut pixels: vector<vector<Pixel>> = vector::empty();
    while (x <= CANVAS_WIDTH) {
        let mut y = 1;
        let mut row: vector<Pixel> = vector::empty();
        while (y <= CANVAS_WIDTH) {
            let pixel_key = PixelKey(x, y);
            let pixel = Pixel {
                pixel_key: pixel_key,
                last_painter: option::none(),
                price_multiplier: 1,
                last_painted_at: 0,
            };
            row.push_back(pixel);
            y = y + 1;
        };
        pixels.push_back(row);
        x = x + 1;
    };

    let canvas = Canvas {
        id: object::new(ctx),
        pixels: pixels,
        base_paint_fee: 100000000, // .1 SUI
        pixel_price_multiplier_reset_ms: 300_000, // 5 minutes
        cap: canvas_cap.id.to_inner(),
        version: VERSION,
    };
    let canvas_id = canvas.id.to_inner();

    transfer::share_object(canvas);

    canvas_id
}

public fun new_pixel_key(x: u64, y: u64): PixelKey {
    PixelKey(x, y)
}

public fun paint_pixel(
    canvas: &mut Canvas,
    x: u64,
    y: u64,
    color: String,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let key = PixelKey(x, y);

    let pixel = canvas.pixel(key);

    let fee_amount = payment.value();

    let leftover = canvas.route_fees(pixel, fee_amount, payment, clock, ctx);

    // Emit paint event
    event::emit(PaintEvent {
        pixel_id: pixel.pixel_key,
        color,
        painter: tx_context::sender(ctx),
        fee_paid: fee_amount,
        in_paint: false,
        new_price_multiplier: pixel.price_multiplier,
        last_painted_at: pixel.last_painted_at,
    });

    // Update pixel data
    let price_expired = canvas.is_pixel_multiplier_expired(pixel, clock);

    canvas.update_pixel(key, clock, option::some(ctx.sender()), price_expired);

    leftover
}

public fun paint_pixel_with_paint(
    canvas: &mut Canvas,
    x: u64,
    y: u64,
    color: String,
    mut payment: Coin<PAINT>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<PAINT> {
    let key = PixelKey(x, y);
    let canvas_cap = canvas.cap.to_address();
    let pixel = canvas.pixel(key);

    assert!(payment.value() >= PAINT_FEE, EInsufficientFee);

    let paint_payment = payment.split(PAINT_FEE, ctx);

    // Emit paint event
    event::emit(PaintEvent {
        pixel_id: pixel.pixel_key,
        color,
        painter: tx_context::sender(ctx),
        fee_paid: paint_payment.value(),
        in_paint: true,
        new_price_multiplier: pixel.price_multiplier,
        last_painted_at: pixel.last_painted_at,
    });

    transfer::public_transfer(paint_payment, canvas_cap);

    // Update pixel data
    let price_expired = canvas.is_pixel_multiplier_expired(pixel, clock);
    canvas.update_pixel(key, clock, option::some(ctx.sender()), price_expired);

    payment
}

// Immutable reference to `pixel`
public fun pixel(canvas: &Canvas, key: PixelKey): &Pixel {
    &canvas.pixels[key.0][key.1]
}

// Mutable reference to `pixel`
public fun pixel_mut(canvas: &mut Canvas, key: PixelKey): &mut Pixel {
    &mut canvas.pixels[key.0][key.1]
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
        let key = new_pixel_key(x[i], y[i]);
        let pixel = canvas.pixel(key);
        cost = cost + canvas.calculate_pixel_paint_fee(pixel, clock);
        i = i + 1;
    };
    cost
}

public fun calculate_pixel_paint_fee(canvas: &Canvas, pixel: &Pixel, clock: &Clock): u64 {
    if (canvas.is_pixel_multiplier_expired(pixel, clock)) {
        canvas.base_paint_fee
    } else {
        canvas.base_paint_fee * pixel.price_multiplier
    }
}

public fun last_painter(pixel: &Pixel): Option<address> {
    pixel.last_painter
}

public fun id(canvas: &Canvas): ID {
    canvas.id.to_inner()
}

public fun is_pixel_multiplier_expired(canvas: &Canvas, pixel: &Pixel, clock: &Clock): bool {
    clock.timestamp_ms() - pixel.last_painted_at > canvas.pixel_price_multiplier_reset_ms()
}

public fun pixel_price_multiplier_reset_ms(canvas: &Canvas): u64 {
    canvas.pixel_price_multiplier_reset_ms
}

public fun update_base_paint_fee(canvas: &mut Canvas, _: &CanvasCap, base_paint_fee: u64) {
    canvas.base_paint_fee = base_paint_fee;
}

public fun update_pixel_price_multiplier_reset_ms(
    canvas: &mut Canvas,
    _: &CanvasCap,
    pixel_price_multiplier_reset_ms: u64,
) {
    canvas.pixel_price_multiplier_reset_ms = pixel_price_multiplier_reset_ms;
}

fun update_pixel(
    canvas: &mut Canvas,
    key: PixelKey,
    clock: &Clock,
    last_painter: Option<address>,
    price_expired: bool,
) {
    let pixel = canvas.pixel_mut(key);
    pixel.last_painter = last_painter;
    pixel.last_painted_at = clock.timestamp_ms();

    // if pixel price is expired, increase price multiplier, or reset to 1
    if (price_expired) {
        pixel.price_multiplier = 1;
    } else {
        pixel.price_multiplier = pixel.price_multiplier + 1;
    }
}

fun route_fees(
    canvas: &Canvas,
    pixel: &Pixel,
    fee_amount: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let cost = canvas.calculate_pixel_paint_fee(pixel, clock);
    assert!(fee_amount >= cost, EInsufficientFee);

    // Pay previous painter
    let painter_fee = payment.split(cost, ctx);

    let mut paint_fee_recipient = pixel.last_painter.borrow_with_default(&canvas.cap.to_address());

    // if pixel was reset (or first painted), paint fee goes to treasury
    if (cost == canvas.base_paint_fee) {
        paint_fee_recipient = &canvas.cap.to_address();
    };

    transfer::public_transfer(
        painter_fee,
        *paint_fee_recipient,
    );

    // return leftover
    payment
}

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

#[test]
fun test_paint() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let mut canvas_cap;

    let mut scenario = test_scenario::begin(admin);
    {
        canvas_cap = create_canvas_cap_for_testing(scenario.ctx());
        new_canvas(&canvas_cap, scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(manny);
    {
        let coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        let leftover = paint_pixel(
            &mut canvas,
            44,
            44,
            color,
            coin,
            &clock,
            scenario.ctx(),
        );

        let key = new_pixel_key(44, 44);

        let pixel = canvas.pixel(key);

        assert!(pixel.last_painter == option::some(manny));

        assert!(leftover.value() == 10_000_000_000 - canvas.base_paint_fee);

        transfer::public_transfer(leftover, manny);
        clock::destroy_for_testing(clock);
    };

    // test admin gets first paint fee
    scenario.next_tx(admin);
    {
        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<Coin<SUI>>(canvas_cap
            .id
            .to_inner());

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let canvas_cap_owner_balance = transfer::public_receive(&mut canvas_cap.id, ticket);

        assert!(canvas_cap_owner_balance.value() == canvas.base_paint_fee);

        transfer::public_transfer(canvas_cap_owner_balance, admin);
        transfer::public_transfer(canvas_cap, admin);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test]
fun test_paint_with_paint_coin() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let mut canvas_cap;

    let mut scenario = test_scenario::begin(admin);
    {
        canvas_cap = create_canvas_cap_for_testing(scenario.ctx());
        new_canvas(&canvas_cap, scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(manny);
    {
        let paint_coin = coin::mint_for_testing<PAINT>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        let leftover = paint_pixel_with_paint(
            &mut canvas,
            44,
            44,
            color,
            paint_coin,
            &clock,
            scenario.ctx(),
        );

        let key = new_pixel_key(44, 44);

        let pixel = canvas.pixel(key);

        assert!(pixel.last_painter == option::some(manny));

        assert!(leftover.value() == 10_000_000_000 - PAINT_FEE);

        transfer::public_transfer(leftover, manny);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(admin);
    {
        // check canvas_cap got PAINT coin from the paint fee
        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<
            Coin<PAINT>,
        >(canvas_cap.id.to_inner());

        let ticket = test_scenario::receiving_ticket_by_id<Coin<PAINT>>(receivable_ids[0]);
        let canvas_cap_owner_balance = transfer::public_receive(&mut canvas_cap.id, ticket);

        assert!(canvas_cap_owner_balance.value() == canvas.base_paint_fee);

        transfer::public_transfer(canvas_cap_owner_balance, admin);
        transfer::public_transfer(canvas_cap, admin);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test]
fun test_pixel_paint_fee_calculation() {
    let canvas;
    let canvas_cap;

    let mut scenario = test_scenario::begin(@0x1);
    {
        canvas_cap = create_canvas_cap_for_testing(scenario.ctx());
        new_canvas(&canvas_cap, scenario.ctx());
    };

    scenario.next_tx(@0x1);
    {
        canvas = scenario.take_shared<Canvas>();
    };

    scenario.next_tx(@0x1);
    {
        let key = new_pixel_key(1, 1);

        let pixel = canvas.pixel(key);

        let clock = clock::create_for_testing(scenario.ctx());

        let paint_fee = canvas.calculate_pixel_paint_fee(pixel, &clock);

        assert!(paint_fee == canvas.base_paint_fee);

        clock::destroy_for_testing(clock);
    };

    transfer::public_share_object(canvas);
    transfer::public_transfer(canvas_cap, @0x1);
    scenario.end();
}

#[test_only]
public fun create_canvas_cap_for_testing(ctx: &mut TxContext): CanvasCap {
    let canvas_cap = CanvasCap {
        id: object::new(ctx),
    };

    canvas_cap
}
