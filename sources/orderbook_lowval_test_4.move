#[test_only]
module orderbookmodule::orders_lowval_tests_four {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{mint_for_testing as mint};
    use orderbookmodule::orders::{Self, OrderbookManagerCap, Orderbook};
    use std::option::{Self};
    use std::debug;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};

    struct SUI {}
    struct USDT {}

     #[test] fun test_one_exact_bid_ask_match_with_low_value() {
        let scenario = scenario();
        test_one_exact_bid_ask_match_with_low_value_(&mut scenario);
        test::end(scenario);
    }

    fun test_init_orderbook_(test: &mut Scenario) {
        let (owner, _, _, _, _) = people();

        next_tx(test, owner);

        {
            orders::init_for_testing(ctx(test))
        };

        next_tx(test, owner);

        {
            let witness = test::take_from_sender<OrderbookManagerCap>(test);
            orders::create_orderbook<SUI, USDT>(&witness, ctx(test));
            test::return_to_sender(test, witness);
        };

        next_tx(test, owner);

        {
            let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);
            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<SUI, USDT>(&orderbook);
            
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 0, 0);
            assert!(asset_b_len == 0, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_one_exact_bid_ask_match_with_low_value_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);
            let clock = clock::create_for_testing(ctx(test));
            orders::add_bid_order<SUI, USDT>(447_000_000, &mut orderbook, mint<USDT>(223_500_000, ctx(test)), &clock, ctx(test));
            clock::destroy_for_testing(clock);
            test::return_shared(orderbook);
        };

         next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);
            let clock = clock::create_for_testing(ctx(test));
            orders::add_bid_order<SUI, USDT>(446_000_000, &mut orderbook, mint<USDT>(111_500_000, ctx(test)), &clock, ctx(test));
            clock::destroy_for_testing(clock);
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);
            let clock = clock::create_for_testing(ctx(test));
            orders::add_ask_order<SUI, USDT>(446_000_000, &mut orderbook, mint<SUI>(1_750_000_000, ctx(test)), &clock, ctx(test));
            clock::destroy_for_testing(clock);
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);

            let coin = test::take_from_sender<Coin<USDT>>(test);
            debug::print(&9999999999999999);
            debug::print(&coin::value(&coin));
            debug::print(&9999999999999999);
            // assert!(coin::value(&coin) == 447_000_000 * 1, 1);
            transfer::public_transfer(coin, ivan);

            // let john_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            // assert!(john_wallet_amount == 0, 0);

            test::return_shared(orderbook);
        };

        //  next_tx(test, john);

        // {
        //     let orderbook = test::take_shared<Orderbook<SUI, USDT>>(test);

        //     let coin = test::take_from_sender<Coin<SUI>>(test);
        //     debug::print(&coin::value(&coin));
        //     assert!(coin::value(&coin) == 1_000_000_000, 1);
        //     transfer::public_transfer(coin, john);
            
        //     let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
        //     assert!(john_wallet_amount == 0, 0);
        
        //     test::return_shared(orderbook);
        // };
    }

    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address, address, address, address) { (@0xBEEF, @0x1337, @0xcafe, @0xA11CE, @0x2222) }
}