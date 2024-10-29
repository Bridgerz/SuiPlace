module suiplace::Canvas;

use std::string::String;
use sui::coin::Coin;
use sui::event;
use sui::sui::SUI;

// constant for maximum number of pixels in a canvas (50x50)
const CANVAS_WIDTH: u64 = 45;

#[error]
const EInsufficientFee: vector<u8> = b"Insufficient fee";

/// Represents a key for a pixel (X, Y coordinates)
public struct PixelKey(u64, u64) has store, copy, drop;

/// Represents a pixel on the canvas
public struct Pixel has store {
    pixel_key: PixelKey,
    last_painter: Option<address>,
    owner_cap: address,
    // price_multiplier: u64,
    // last_painted_at: u64,
}

/// Represents ownership of a pixel (tradable NFT)
/// update to pixelownershipcap
public struct PixelCap has key, store {
    id: UID,
}

/// Represents a group of pixels on a grid
public struct Canvas has key, store {
    id: UID,
    pixels: vector<vector<Pixel>>,
    base_paint_fee: u64,
    treasury: address,
}

public struct CanvasTreasuryCap has key, store { id: UID }

// Called only once, upon module publication. It must be
// private to prevent external invocation.
fun init(ctx: &mut TxContext) {
    let treasury_cap = CanvasTreasuryCap {
        id: object::new(ctx),
    };

    let mut x = 0;
    let mut pixels: vector<vector<Pixel>> = vector::empty();
    while (x < CANVAS_WIDTH) {
        let mut y = 0;
        let mut row: vector<Pixel> = vector::empty();
        while (y < CANVAS_WIDTH) {
            let pixel_cap = PixelCap {
                id: object::new(ctx),
            };
            let pixel = Pixel {
                pixel_key: PixelKey(x, y),
                last_painter: option::none(),
                owner_cap: pixel_cap.id.to_address(),
            };
            transfer::transfer(pixel_cap, ctx.sender());
            row.push_back(pixel);
            y = y + 1;
        };
        pixels.push_back(row);
        x = x + 1;
    };

    let canvas = Canvas {
        id: object::new(ctx),
        pixels: pixels,
        base_paint_fee: 10,
        treasury: treasury_cap.id.to_address(),
    };

    transfer::transfer(
        treasury_cap,
        ctx.sender(),
    );

    transfer::share_object(canvas);
}

public fun paint_pixel(
    canvas: &mut Canvas,
    key: PixelKey,
    color: String,
    mut fee: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI> {
    let canvas_treasury = canvas.treasury;

    // Get an immutable reference to `pixel` for cost calculation
    let pixel_ref = get_pixel(canvas, key);

    let fee_amount = fee.value();
    let cost = calculate_pixel_paint_fee(canvas, pixel_ref);
    assert!(fee_amount >= cost, EInsufficientFee);

    // Now get a mutable reference to `pixel` for modifications
    let pixel = get_pixel_mut(canvas, key);

    // Calculate fee distribution
    let owner_share = calculate_owner_fee(cost);
    let previous_painter_share = cost - owner_share;

    // Pay previous painter
    let painter_fee = fee.split(previous_painter_share, ctx);
    let owner_fee = fee.split(owner_share, ctx);

    // Transfer painter fee to previous painter or treasury
    transfer::public_transfer(
        painter_fee,
        *pixel.last_painter.borrow_with_default(&canvas_treasury),
    );

    // Transfer owner share to pixel cap object
    transfer::public_transfer(
        owner_fee,
        pixel.owner_cap,
    );

    // Update pixel data
    pixel.last_painter = option::some(ctx.sender());

    // Emit paint event
    event::emit(PaintEvent {
        pixel_id: pixel.pixel_key,
        color,
        painter: tx_context::sender(ctx),
        fee_paid: fee_amount,
    });

    fee
}

// Immutable reference to `pixel`
public fun get_pixel(canvas: &Canvas, key: PixelKey): &Pixel {
    &canvas.pixels[key.0][key.1]
}

// Mutable reference to `pixel`
public fun get_pixel_mut(canvas: &mut Canvas, key: PixelKey): &mut Pixel {
    &mut canvas.pixels[key.0][key.1]
}

public fun calculate_owner_fee(fee: u64): u64 {
    // TODO: confugurable owner fee percentage logic
    fee / 2
}

/// Calculates the total fee required to paint provided pixels
public fun calculate_pixels_paint_fee(canvas: &mut Canvas, keys: vector<PixelKey>): u64 {
    let mut cost = 0;
    let mut x = 0;
    while (x < keys.length()) {
        let pixel = get_pixel(canvas, keys[x]);
        // TODO: dynamic pricing (price bonding curve and time decay)
        cost = cost + canvas.base_paint_fee;
        x = x + 1;
    };
    cost
}

public fun calculate_pixel_paint_fee(canvas: &Canvas, _pixel: &Pixel): u64 {
    canvas.base_paint_fee
}

/// Event emitted when a pixel is painted
public struct PaintEvent has copy, drop {
    pixel_id: PixelKey,
    color: String,
    painter: address,
    fee_paid: u64,
}

/// Event emitted when owner claims their accumulated fees
// public struct ClaimFeesEvent has copy, drop {
//     pixel_id: PixelKey,
//     owner: address,
//     amount: u64,
// }

#[test_only]
use sui::test_scenario;

#[test_only]
use sui::coin::{Self};

#[test]
fun test_paint() {
    let (admin, bernard, manny) = (@0x1, @0x2, @0x3);

    let mut scenario = test_scenario::begin(admin);
    {
        init(scenario.ctx());
    };

    scenario.next_tx(admin);
    {
        let pixel_cap = scenario.take_from_address<PixelCap>(admin);

        transfer::public_transfer(pixel_cap, bernard);
    };

    scenario.next_tx(manny);
    {
        let mut canvas = scenario.take_shared<Canvas>();
        let coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());

        let key = PixelKey(44, 44);
        let color = b"red".to_string();

        let leftover = paint_pixel(&mut canvas, key, color, coin, scenario.ctx());

        let pixel = get_pixel(&canvas, key);

        assert!(pixel.last_painter == option::some(manny));

        assert!(leftover.value() == 10_000_000_000 - 10);

        transfer::public_transfer(leftover, manny);
        transfer::share_object(canvas);
    };

    scenario.next_tx(bernard);
    {
        let mut pixel_cap = scenario.take_from_sender<PixelCap>();

        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<Coin<SUI>>(pixel_cap
            .id
            .to_inner());

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let pixel_cap_balance = transfer::public_receive(&mut pixel_cap.id, ticket);

        assert!(pixel_cap_balance.value() == 5);

        transfer::public_transfer(pixel_cap_balance, bernard);
        scenario.return_to_sender(pixel_cap);
    };

    scenario.end();
}
