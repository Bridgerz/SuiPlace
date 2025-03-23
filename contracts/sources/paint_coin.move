// SPDX-License-Identifier: Apache-2.0

module suiplace::paint_coin;

use sui::coin::{Self, TreasuryCap};

public struct PAINT_COIN has drop {}

const DECIMAL: u8 = 8;

fun init(otw: PAINT_COIN, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        otw,
        DECIMAL,
        b"PAINT",
        b"Paint",
        b"SuiPlace Paint coins used to paint pixels",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
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
