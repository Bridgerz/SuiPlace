#[test_only]
module suiplace::canvas_tests;

use sui::clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario;
use suiplace::canvas;
use suiplace::canvas_admin;
use suiplace::pixel;

#[test]
fun test_paint() {
    let (admin, manny) = (@0x1, @0x2);

    let mut canvas;
    let mut admin_cap;
    let canvas_rules;

    let mut scenario = test_scenario::begin(admin);
    {
        admin_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
        canvas = canvas::new_canvas(&admin_cap, scenario.ctx());
        canvas_rules =
            canvas_admin::new_rules(
                100000000,
                1000,
                admin_cap.id().to_address(),
                100000000,
            );
    };

    scenario.next_tx(manny);
    {
        let mut coin = coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        let color = b"red".to_string();

        let fee_amount = canvas.calculate_pixel_paint_fee(
            &canvas_rules,
            44,
            44,
            &clock,
        );

        let payment = coin.split(fee_amount, scenario.ctx());

        canvas.paint_pixel(
            &canvas_rules,
            44,
            44,
            color,
            payment,
            &clock,
            scenario.ctx(),
        );
        let coordinates = pixel::new_coordinates(44, 44);
        let pixel = canvas.pixel(coordinates);

        assert!(pixel.last_painter() == option::some(manny));

        clock::destroy_for_testing(clock);
        coin::burn_for_testing(coin);
    };

    // test admin gets first paint fee
    scenario.next_tx(admin);
    {
        let receivable_ids = test_scenario::receivable_object_ids_for_owner_id<Coin<SUI>>(
            object::id(&admin_cap),
        );

        let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(receivable_ids[0]);
        let admin_cap_owner_balance = admin_cap.claim_fees(ticket);

        assert!(admin_cap_owner_balance.value() == canvas_rules.base_paint_fee());

        transfer::public_transfer(admin_cap_owner_balance, admin);
        transfer::public_transfer(admin_cap, admin);
    };

    transfer::public_transfer(canvas, admin);
    scenario.end();
}

// #[test]
// fun test_paint_with_paint_coin() {
//     let (admin, manny) = (@0x1, @0x2);

//     let mut canvas;
//     let admin_cap;

//     let mut scenario = test_scenario::begin(admin);
//     {
//         admin_cap = canvas_admin::create_canvas_admin_cap_for_testing(scenario.ctx());
//         new_canvas(&admin_cap, scenario.ctx());
//     };

//     scenario.next_tx(admin);
//     {
//         canvas = scenario.take_shared<Canvas>();
//     };

//     scenario.next_tx(manny);
//     {
//         let paint_coin = coin::mint_for_testing<PAINT_COIN>(100000000, scenario.ctx());
//         let clock = clock::create_for_testing(scenario.ctx());
//         let color = b"red".to_string();

//         paint_pixel_with_paint(
//             &mut canvas,
//             44,
//             44,
//             color,
//             paint_coin,
//             &clock,
//             scenario.ctx(),
//         );

//         let key = pixel::new_pixel_key(44, 44);

//         let pixel = canvas.pixel(key);

//         assert!(pixel.last_painter() == option::some(manny));
//         clock::destroy_for_testing(clock);
//     };

//     transfer::public_share_object(canvas);
//     transfer::public_transfer(admin_cap, admin);
//     scenario.end();
// }
