// SPDX-License-Identifier: Apache-2.0

module suiplace::paint_coin;

use sui::coin::{Self, TreasuryCap};
use sui::url;

public struct PAINT_COIN has drop {}

const DECIMAL: u8 = 8;

fun init(otw: PAINT_COIN, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        otw,
        DECIMAL,
        b"PAINT",
        b"Paint",
        b"SuiPlace Paint coins used to paint pixels",
        option::some(
            url::new_unsafe_from_bytes(
                b"https://imagedelivery.net/YczTHwtAzWOsAYRMOu2oYw/8a0be8c3-dd61-4e24-be26-86cced428d00/public",
            ),
        ),
        ctx,
    );
    transfer::public_transfer(metadata, ctx.sender());
    transfer::public_transfer(treasury, ctx.sender())
}

public fun mint(
    treasury_cap: &mut TreasuryCap<PAINT_COIN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(coin, recipient)
}
