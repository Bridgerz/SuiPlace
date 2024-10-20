module suiplace::SuiPlace;

use std::string::String;
use sui::coin::{Self, Coin};
use sui::dynamic_object_field as dof;
use sui::event;
use sui::sui::SUI;

/// Custom error codes
const E_INSUFFICIENT_FUNDS: u64 = 1;
// const E_PIXEL_ALREADY_EXISTS: u64 = 2;
// const E_PIXEL_NOT_FOUND: u64 = 3;
// const E_NOT_AUTHORIZED: u64 = 4;
const E_PIXEL_ID_MISMATCH: u64 = 5;
const E_INVALID_PIXEL_MINT_AMOUNT: u64 = 6;

/// Represents a pixel on the canvas
public struct Pixel has key {
    id: UID,
    pixel_key: PixelKey,
    last_painter: address,
    // price: u64,
    // last_painted_at: u64,
}

/// Represents a key for a pixel (X, Y coordinates)
public struct PixelKey has copy, drop, store {
    x: u64,
    y: u64,
}

public struct PixelOwnerBalanceKey has copy, drop, store {}

/// Represents ownership of a pixel (tradable NFT)
public struct PixelOwnership has key, store {
    id: UID,
    pixel_key: PixelKey,
}

/// Mints a Pixel and its corresponding PixelOwnership NFT
public fun mint_pixels(
    amount: u8,
    ctx: &mut TxContext,
): vector<PixelOwnership> {
    assert!(amount > 0, E_INVALID_PIXEL_MINT_AMOUNT);
    assert!(amount < 20, E_INVALID_PIXEL_MINT_AMOUNT);

    // TODO: how to get a random set of unmited pixels?
    let pixel_keys: vector<PixelKey> = vector<PixelKey>[];

    let len = vector::length(&pixel_keys);
    let mut i = 0;
    let mut pixels: vector<PixelOwnership> = vector::empty();
    while (i < len) {
        let pixel_key = pixel_keys[i];
        pixels.push_back(mint_pixel(pixel_key, ctx));
        i = i + 1;
    };
    pixels
}

fun mint_pixel(pixel_key: PixelKey, ctx: &mut TxContext): PixelOwnership {
    //TODO: how to assert pixel is not already minted?

    // Create the Pixel object
    let mut pixel = Pixel {
        id: object::new(ctx),
        last_painter: @0x0,
        pixel_key,
    };

    dof::add(&mut pixel.id, b"owner_balance", coin::zero<SUI>(ctx));

    transfer::share_object(pixel);
    // Initialize the Pixel's owner_balance object field to zero

    // Create the PixelOwnership NFT
    let ownership = PixelOwnership {
        id: object::new(ctx),
        pixel_key,
    };

    // Transfer the PixelOwnership to the recipient
    ownership
}

/// Allows anyone to paint a pixel by paying a fee
public entry fun paint(
    pixel: &mut Pixel,
    color: String,
    mut fee: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let fee_amount = fee.value();
    let pixel_cost = calculate_pixel_paint_fee(pixel);
    assert!(fee_amount >= pixel_cost, E_INSUFFICIENT_FUNDS);

    // Calculate fee distribution
    let owner_share = calculate_owner_fee(fee_amount);
    let previous_painter_share = fee_amount - owner_share;

    // Pay previous painter
    if (pixel.last_painter != @0x0) {
        let painter_fee = fee.split(previous_painter_share, ctx);
        transfer::public_transfer(painter_fee, pixel.last_painter);
    } else {};
    // TODO: distribute painter_fee to treassury if no previous painter

    // Accumulate owner's fees in the Pixel's owner_balance
    let owner_balance: &mut Coin<SUI> = dof::borrow_mut(
        &mut pixel.id,
        b"owner_balance",
    );

    owner_balance.join(fee);

    // Update pixel data
    pixel.last_painter = tx_context::sender(ctx);

    // Emit paint event
    event::emit(PaintEvent {
        pixel_id: pixel.pixel_key,
        color,
        painter: tx_context::sender(ctx),
        fee_paid: fee_amount,
    });
}

/// Allows the pixel owner to claim their accumulated fees
public fun claim_owner_balance(
    ownership: &PixelOwnership,
    pixel: &mut Pixel,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(ownership.pixel_key == pixel.pixel_key, E_PIXEL_ID_MISMATCH);

    let owner_balance: Coin<SUI> = dof::remove(&mut pixel.id, b"owner_balance");

    assert!(owner_balance.value() > 0, E_INSUFFICIENT_FUNDS);

    dof::add(&mut pixel.id, b"owner_balance", coin::zero<SUI>(ctx));

    // Emit claim fees event
    event::emit(ClaimFeesEvent {
        pixel_id: pixel.pixel_key,
        owner: ctx.sender(),
        amount: owner_balance.value(),
    });

    owner_balance
}

fun calculate_owner_fee(fee: u64): u64 {
    // TODO: confugurable owner fee percentage logic
    fee / 2
}

// TODO: dynamic pricing (price bonding curve and time decay)
public fun calculate_pixel_paint_fee(_pixel: &Pixel): u64 {
    1
}

/// Event emitted when a pixel is painted
public struct PaintEvent has copy, drop {
    pixel_id: PixelKey,
    color: String,
    painter: address,
    fee_paid: u64,
}

/// Event emitted when owner claims their accumulated fees
public struct ClaimFeesEvent has copy, drop {
    pixel_id: PixelKey,
    owner: address,
    amount: u64,
}

#[test_only]
use sui::test_scenario;

#[test]
fun test_mint_and_paint() {
    let (bernard, manny, fran) = (@0x1, @0x2, @0x3);

    let mut scenario = test_scenario::begin(bernard);

    let pixel_key = PixelKey { x: 0, y: 0 };

    let ownership = mint_pixel(pixel_key, scenario.ctx());

    let _prev_effects = scenario.next_tx(manny);

    let mut pixel = scenario.take_shared<Pixel>();

    let coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());

    paint(
        &mut pixel,
        b"red".to_string(),
        coin,
        scenario.ctx(),
    );

    assert!(pixel.last_painter == manny);

    let _prev_effects = scenario.next_tx(bernard);

    let ownership_fee = claim_owner_balance(
        &ownership,
        &mut pixel,
        scenario.ctx(),
    );

    assert!(ownership_fee.value() == 10_000_000_000);

    // consume objects
    transfer::public_transfer(ownership_fee, fran);
    transfer::public_transfer(ownership, fran);
    transfer::share_object(pixel);

    scenario.end();
}
