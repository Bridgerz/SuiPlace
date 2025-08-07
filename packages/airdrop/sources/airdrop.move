/// Module: airdrop
module airdrop::airdrop;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::table::{Self, Table};

public struct AirDrop<phantom T> has key, store {
    id: UID,
    claims: Table<address, u64>,
    balance: Balance<T>,
}

public struct AdminCap<phantom T> has key, store {
    id: UID,
    airdrop: ID,
}

public fun new_airdrop<T>(ctx: &mut TxContext): AdminCap<T> {
    let airdrop = AirDrop<T> {
        id: object::new(ctx),
        claims: table::new(ctx),
        balance: balance::zero(),
    };

    let admin_cap = AdminCap<T> {
        id: object::new(ctx),
        airdrop: object::id(&airdrop),
    };

    transfer::public_share_object(airdrop);

    admin_cap
}

public fun add_claims<T>(
    airdrop: &mut AirDrop<T>,
    _: &mut AdminCap<T>,
    recipients: vector<address>,
    amounts: vector<u64>,
    coins: Coin<T>,
) {
    let mut total_amount = 0;
    amounts.do_ref!(|amount| {
        assert!(*amount > 0);
        total_amount = total_amount + *amount;
    });

    assert!(coins.value() >= total_amount, 0);

    recipients.zip_do!(amounts, |recipient, amount| {
        if (airdrop.claims.contains(recipient)) {
            let claim = airdrop.claims.borrow_mut(recipient);
            *claim = *claim + amount;
        } else {
            airdrop.claims.add(recipient, amount);
        }
    });

    airdrop.balance.join(coins.into_balance());
}

public fun remove_claims<T>(
    airdrop: &mut AirDrop<T>,
    _: &mut AdminCap<T>,
    recipients: vector<address>,
    amounts: vector<u64>,
) {
    recipients.zip_do!(amounts, |recipient, amount| {
        let original_amount = airdrop.claims.remove(recipient);
        airdrop.claims.add(recipient, original_amount+ amount);
    });
}

public fun withdraw_balance<T>(airdrop: &mut AirDrop<T>, _: &mut AdminCap<T>): Balance<T> {
    let amount = airdrop.balance.value();
    airdrop.balance.split(amount)
}

entry fun claim<T>(airdrop: &mut AirDrop<T>, ctx: &mut TxContext) {
    let amount = airdrop.claims.remove(ctx.sender());
    assert!(amount > 0);
    let balance = airdrop.balance.split(amount);
    transfer::public_transfer(
        sui::coin::from_balance(balance, ctx),
        ctx.sender(),
    );
}

entry fun get_claim<T>(airdrop: &AirDrop<T>, recipient: address): u64 {
    *airdrop.claims.borrow(recipient)
}
