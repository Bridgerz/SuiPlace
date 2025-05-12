module suiplace::fee_router;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::sui::SUI;
use sui::table::{Self, Table};

public struct FeeRouter has key, store {
    id: UID,
    fees: Table<address, u64>,
    balance: Balance<SUI>,
}

public(package) fun new_fee_router(ctx: &mut TxContext): FeeRouter {
    FeeRouter {
        id: object::new(ctx),
        fees: table::new(ctx),
        balance: balance::zero(),
    }
}

public(package) fun record_fee(
    fee_router: &mut FeeRouter,
    sender: address,
    amount: u64,
) {
    assert!(amount > 0);
    if (!fee_router.fees.contains(sender)) {
        fee_router.fees.add(sender, amount);
    } else {
        let fee = fee_router.fees.borrow_mut(sender);
        let value = *fee;
        *fee = value + amount;
    }
}

public fun deposit_payment(fee_router: &mut FeeRouter, payment: Coin<SUI>) {
    fee_router.balance.join(payment.into_balance());
}

public fun withdraw_fees(
    fee_router: &mut FeeRouter,
    ctx: &mut TxContext,
): Balance<SUI> {
    assert!(fee_router.fees.contains(ctx.sender()));
    let fee = fee_router.fees.borrow_mut(ctx.sender());
    assert!(*fee > 0);
    let withdrawal = fee_router.balance.split(*fee);
    *fee = 0;
    withdrawal
}

public fun get_accrued_fees(fee_router: &FeeRouter, recipient: address): u64 {
    assert!(fee_router.fees.contains(recipient));
    *fee_router.fees.borrow(recipient)
}
