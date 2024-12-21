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

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

/// Represents a group of pixels on a grid
public struct Canvas has key, store {
    id: UID,
    pixels: vector<vector<Pixel>>,
    treasury: address,
    base_paint_fee: u64,
    pixel_owner_fee_bps: u64,
    pixel_price_multiplier_reset_ms: u64,
}

/// Represents a key for a pixel (X, Y coordinates)
public struct PixelKey(u64, u64) has store, copy, drop;

/// Represents a pixel on the canvas
public struct Pixel has store {
    pixel_key: PixelKey,
    last_painter: Option<address>,
    owner_cap: address,
    price_multiplier: u64,
    last_painted_at: u64,
}

/// Represents ownership of a pixel (tradable NFT)
public struct PixelOwner has key, store {
    id: UID,
    key: PixelKey,
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

// Called only once, upon module publication. It must be
// private to prevent external invocation.
public(package) fun new_canvas(ctx: &mut TxContext): ID {
    let mut x = 1;
    let mut pixels: vector<vector<Pixel>> = vector::empty();
    while (x <= CANVAS_WIDTH) {
        let mut y = 1;
        let mut row: vector<Pixel> = vector::empty();
        while (y <= CANVAS_WIDTH) {
            let pixel_key = PixelKey(x, y);
            let pixel_owner = PixelOwner {
                id: object::new(ctx),
                key: pixel_key,
            };
            let pixel = Pixel {
                pixel_key: pixel_key,
                last_painter: option::none(),
                owner_cap: pixel_owner.id.to_address(),
                price_multiplier: 1,
                last_painted_at: 0,
            };
            transfer::transfer(pixel_owner, ctx.sender());
            row.push_back(pixel);
            y = y + 1;
        };
        pixels.push_back(row);
        x = x + 1;
    };

    let canvas = Canvas {
        id: object::new(ctx),
        pixels: pixels,
        treasury: ctx.sender(),
        base_paint_fee: 100000000, // .1 SUI
        pixel_owner_fee_bps: 0, // initialize owner fee to 0
        pixel_price_multiplier_reset_ms: 300_000, // 5 minutes
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
    let canvas_treasury = canvas.treasury;
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

    transfer::public_transfer(paint_payment, canvas_treasury);

    // Update pixel data
    let last_painter = pixel.last_painter;
    let price_expired = canvas.is_pixel_multiplier_expired(pixel, clock);

    canvas.update_pixel(key, clock, last_painter, price_expired);

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

public fun calculate_owner_fee(canvas: &Canvas, fee: u64): u64 {
    (fee as u128 * (canvas.pixel_owner_fee_bps as u128) / 10_000) as u64
}

public fun update_base_paint_fee(canvas: &mut Canvas, _: &CanvasCap, base_paint_fee: u64) {
    canvas.base_paint_fee = base_paint_fee;
}

public fun update_pixel_owner_fee_bps(
    canvas: &mut Canvas,
    _: &CanvasCap,
    pixel_owner_fee_bps: u64,
) {
    canvas.pixel_owner_fee_bps = pixel_owner_fee_bps;
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

    // Calculate fee distribution
    let owner_share = canvas.calculate_owner_fee(cost);
    let previous_painter_share = cost - owner_share;

    // Pay previous painter
    let painter_fee = payment.split(previous_painter_share, ctx);
    let owner_fee = payment.split(owner_share, ctx);

    let mut paint_fee_recipient = pixel.last_painter.borrow_with_default(&canvas.treasury);
    // if pixel was reset (or first painted), paint fee goes to treasury
    if (cost == canvas.base_paint_fee) {
        paint_fee_recipient = &canvas.treasury;
    };

    transfer::public_transfer(
        painter_fee,
        *paint_fee_recipient,
    );

    transfer::public_transfer(
        owner_fee,
        pixel.owner_cap,
    );

    // return leftover
    payment
}

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

// TODO: fix this test (don't include pixel_owner fee)
#[test]
fun test_paint() {
    let (admin, bernard, manny) = (@0x1, @0x2, @0x3);

    let mut canvas;

    let mut scenario = test_scenario::begin(admin);
    {
        new_canvas(scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();

        let pixel_owner = scenario.take_from_address<PixelOwner>(admin);

        transfer::public_transfer(pixel_owner, bernard);
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

    scenario.next_tx(bernard);
    {
        let mut pixel_owner = scenario.take_from_sender<PixelOwner>();

        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<
            Coin<SUI>,
        >(pixel_owner.id.to_inner());

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let pixel_owner_balance = transfer::public_receive(&mut pixel_owner.id, ticket);

        assert!(pixel_owner_balance.value() == 0);

        transfer::public_transfer(pixel_owner_balance, bernard);
        scenario.return_to_sender(pixel_owner);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test]
fun test_paint_with_paint_coin() {
    let (admin, bernard, manny) = (@0x1, @0x2, @0x3);

    let mut canvas;

    let mut scenario = test_scenario::begin(admin);
    {
        new_canvas(scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        canvas = scenario.take_shared<Canvas>();

        let pixel_owner = scenario.take_from_address<PixelOwner>(admin);

        transfer::public_transfer(pixel_owner, bernard);
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

        assert!(pixel.last_painter == option::none());

        assert!(leftover.value() == 10_000_000_000 - PAINT_FEE);

        transfer::public_transfer(leftover, manny);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(admin);
    {
        // check admin got PAINT coin from the paint fee
        let admin_paint_balance = scenario.take_from_address<Coin<PAINT>>(admin);
        assert!(admin_paint_balance.value() == PAINT_FEE);
        scenario.return_to_sender(admin_paint_balance);
    };

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test]
fun test_pixel_paint_fee_calculation() {
    let mut canvas;

    let mut scenario = test_scenario::begin(@0x1);
    {
        new_canvas(scenario.ctx());
    };

    scenario.next_tx(@0x1);
    {
        canvas = scenario.take_shared<Canvas>();

        let pixel_owner = scenario.take_from_address<PixelOwner>(@0x1);

        transfer::public_transfer(pixel_owner, @0x1);
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

    // paint pixel and make sure fee is calculated correctly
    //  - make sure fee is routed correctly

    // let time pass to reset price multiplier
    //  - make sure fee is routed correctly

    transfer::public_share_object(canvas);
    scenario.end();
}

#[test_only]
public fun create_canvas_cap_for_testing(ctx: &mut TxContext): CanvasCap {
    let canvas_cap = CanvasCap {
        id: object::new(ctx),
    };

    canvas_cap
}
