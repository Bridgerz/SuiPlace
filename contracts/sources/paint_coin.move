// SPDX-License-Identifier: Apache-2.0

module suiplace::paint_coin;

use sui::coin;

public struct PAINT_COIN has drop {}

const DECIMAL: u8 = 8;

fun init(otw: PAINT_COIN, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        otw,
        DECIMAL,
        b"PAINT",
        b"Paint",
        b"Paint token used to paint SuiPlace canvas pixels",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, ctx.sender())
}
