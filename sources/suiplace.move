module suiplace::SuiPlace;

use std::string::String;
use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::event;
use sui::sui::SUI;

/// Custom error codes
const E_INSUFFICIENT_FUNDS: u64 = 1;
const E_PIXEL_ALREADY_EXISTS: u64 = 2;
const E_PIXEL_NOT_FOUND: u64 = 3;
const E_NOT_AUTHORIZED: u64 = 4;
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
public entry fun mint_pixels(amount: u8, ctx: &mut TxContext) {
    assert!(amount > 0, E_INVALID_PIXEL_MINT_AMOUNT);
    assert!(amount < 20, E_INVALID_PIXEL_MINT_AMOUNT);

    // TODO: how to get a random set of unmited pixels?
    let pixel_keys: vector<PixelKey> = vector<PixelKey>[];

    let len = vector::length(&pixel_keys);
    let mut i = 0;
    while (i < len) {
        let pixel_key = pixel_keys[i];
        mint_pixel(pixel_key, ctx);
    };
}

fun mint_pixel(pixel_key: PixelKey, ctx: &mut TxContext) {
    //TODO: how to assert pixel is not already minted?

    // Create the Pixel object
    let pixel = Pixel {
        id: object::new(ctx),
        last_painter: @0x0,
        pixel_key,
    };

    transfer::share_object(pixel);

    // Create the PixelOwnership NFT
    let ownership = PixelOwnership {
        id: object::new(ctx),
        pixel_key,
    };

    // Transfer the PixelOwnership to the recipient
    transfer::transfer(ownership, ctx.sender());
}

/// Allows anyone to paint a pixel by paying a fee
public entry fun paint(
    pixel: &mut Pixel,
    color: String,
    mut fee: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let fee_amount = fee.value();
    // TODO: dynamic pricing (price bonding curve and time decay)
    let pixel_cost = calculate_pixel_paint_fee(pixel);
    assert!(fee_amount >= pixel_cost, E_INSUFFICIENT_FUNDS);

    // Calculate fee distribution
    let owner_share = calculate_owner_fee(fee_amount);
    let previous_painter_share = fee_amount - owner_share;

    // Pay previous painter
    let painter_fee = fee.split(previous_painter_share, ctx);
    if (pixel.last_painter != @0x0) {
        transfer::public_transfer(painter_fee, pixel.last_painter);
    } else {
        // TODO: instead of burning the fee, send to treasury object
        painter_fee.destroy_zero();
    };

    // Accumulate owner's fees in the Pixel's owner_balance
    // TODO: how to store remaining fee for pixel owner to claim?
    // ideas: dynamic object field or simillar collection? store on Pixel object itself with claim guarded by PixelOwnershipCap?

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
public fun claim_fees(
    ownership: &PixelOwnership,
    pixel: &mut Pixel,
    ctx: &mut TxContext,
) {}

fun calculate_owner_fee(fee: u64): u64 {
    // TODO: confugurable owner fee percentage logic
    fee / 2
}

// TODO: dynamic pricing (price bonding curve and time decay)
public fun calculate_pixel_paint_fee(pixel: &Pixel): u64 {
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
