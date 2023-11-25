// #[test_only]
// module orderbookmodule::orders_tests {
//     use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
//     use sui::coin::{mint_for_testing as mint};
//     use orderbookmodule::orders::{Self, OrderbookManagerCap, Orderbook};
//     use std::option::{Self};
//     use std::debug;
//     use sui::coin::{Self, Coin};
//     use sui::transfer;
//     use sui::clock::{Self, Clock};

//     struct ASSET_A {}
//     struct ASSET_B {}

//     #[test] fun test_init_orderbook() {
//         let scenario = scenario();
//         test_init_orderbook_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_add_order() {
//         let scenario = scenario();
//         test_add_bid_order_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_remove_order() {
//         let scenario = scenario();
//         test_remove_order_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_add_ask() {
//         let scenario = scenario();
//         test_add_ask_order_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_remove_ask() {
//         let scenario = scenario();
//         test_remove_ask_order_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_one_bid_ask_match() {
//         let scenario = scenario();
//         test_one_bid_ask_match_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_one_exact_bid_ask_match() {
//         let scenario = scenario();
//         test_one_exact_bid_ask_match_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_one_exact_ask_bid_match() {
//         let scenario = scenario();
//         test_one_exact_ask_bid_match_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_another_bid_ask_match() {
//         let scenario = scenario();
//         test_another_bid_ask_match_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_ask_bids_match() {
//         let scenario = scenario();
//         test_ask_bids_match_(&mut scenario);
//         test::end(scenario);
//     }

//     #[test] fun test_add_remove_ask() {
//         let scenario = scenario();
//         test_add_remove_ask_(&mut scenario);
//         test::end(scenario);
//     } 

//     fun test_add_remove_ask_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, _, thegirl, _, _) = people();

//         next_tx(test, thegirl);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000, ctx(test)), &clock, ctx(test));
            
//             let thegirl_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            
//             assert!(thegirl_wallet_amount == 1_000_000_000, 0);

//             // todo parent_limit_price is the same as price
//             let (orderbook_entry_id, parent_limit_price,next,prev,price,init_quantity,cur_quantity,user) = orders::get_ask_order_info(&orderbook, 0);
           
//             assert!(option::is_none(&next), 0);
//             assert!(option::is_none(&prev), 0);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(init_quantity == 1_000_000_000,0);
//             assert!(cur_quantity == 1_000_000_000,0);
//             assert!(user == thegirl, 0);

//             let (price, head, tail) = orders::get_ask_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit_price);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(head == option::some(orderbook_entry_id), 0);
//             assert!(tail == option::some(orderbook_entry_id), 0);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 1, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 1, 0);
//             assert!(asset_b_len == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, thegirl);

//         {
//         let clock = clock::create_for_testing(ctx(test));
//         let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
        
//         let (orderbook_entry_id, _parent_limit,_next,_prev,_price,_init_quantity,_cur_quantity,_user) = orders::get_ask_order_info(&orderbook, 0);
//         orders::remove_ask_order(orderbook_entry_id, &mut orderbook, &clock, ctx(test));
//         clock::destroy_for_testing(clock);
//         test::return_shared(orderbook);
//         };

//          next_tx(test, thegirl);

//         {
//              let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
//             let the_girl_balance = orders::get_user_asset_a_balance(&orderbook, thegirl);
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_b_len == 0, 0);
//             assert!(the_girl_balance == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             test::return_shared(orderbook);
//         }
//     }

//     fun test_init_orderbook_(test: &mut Scenario) {
//         let (owner, _, _, _, _) = people();

//         next_tx(test, owner);

//         {
//             orders::init_for_testing(ctx(test))
//         };

//         next_tx(test, owner);

//         {
//             let witness = test::take_from_sender<OrderbookManagerCap>(test);
//             orders::create_orderbook<ASSET_A, ASSET_B>(&witness, ctx(test));
//             test::return_to_sender(test, witness);
//         };

//         next_tx(test, owner);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_a_len == 0, 0);
//             assert!(asset_b_len == 0, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             test::return_shared(orderbook);
//         }
//     }

//     fun test_add_bid_order_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, theguy, _, _, _) = people();

//         next_tx(test, theguy);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 10, ctx(test)), &clock, ctx(test));
            
//             let theguy_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(theguy_wallet_amount == 309_000_000_000_0, 0);

//             let (orderbook_entry_id, parent_limit_price,next,prev,price,init_quantity,cur_quantity,user) = orders::get_bid_order_info(&orderbook, 0);
           
//             assert!(option::is_none(&next), 0);
//             assert!(option::is_none(&prev), 0);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(init_quantity == 309_000_000_000_0,0);
//             assert!(cur_quantity == 309_000_000_000_0,0);
//             assert!(user == theguy, 0);

//             // todo parent_limit_price is the same as price
//             let (price, head, tail) = orders::get_bid_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit_price);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(head == option::some(orderbook_entry_id), 0);
//             assert!(tail == option::some(orderbook_entry_id), 0);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

//             assert!(bids_len == 1, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 1, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_b_len == 1, 0);
//             assert!(asset_a_len == 0, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         }
//     }

//     fun test_remove_order_(test: &mut Scenario) {
//         test_add_bid_order_(test);

//          let (_, theguy,_, _, _) = people();

//         next_tx(test, theguy);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             let (orderbook_entry_id, _parent_limit,_next,_prev,_price,_init_quantity,_cur_quantity,_user) = orders::get_bid_order_info(&orderbook, 0);
//             orders::remove_bid_order(orderbook_entry_id, &mut orderbook, &clock, ctx(test));
        
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, theguy);

//         {
//              let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
//             let the_guy_balance = orders::get_user_balance(&orderbook, theguy);
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_b_len == 1, 0);
//             assert!(the_guy_balance == 0, 0);
//             assert!(asset_a_len == 0, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             test::return_shared(orderbook);
//         }
//     }

//     fun test_add_ask_order_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, _, thegirl, _, _) = people();

//         next_tx(test, thegirl);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 10, ctx(test)), &clock, ctx(test));
            
//             let thegirl_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            
//             assert!(thegirl_wallet_amount == 10_000_000_000, 0);

//             // todo parent_limit_price is the same as price
//             let (orderbook_entry_id, parent_limit_price,next,prev,price,init_quantity,cur_quantity,user) = orders::get_ask_order_info(&orderbook, 0);
           
//             assert!(option::is_none(&next), 0);
//             assert!(option::is_none(&prev), 0);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(init_quantity == 10_000_000_000,0);
//             assert!(cur_quantity == 10_000_000_000,0);
//             assert!(user == thegirl, 0);

//             let (price, head, tail) = orders::get_ask_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit_price);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(head == option::some(orderbook_entry_id), 0);
//             assert!(tail == option::some(orderbook_entry_id), 0);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 1, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 1, 0);
//             assert!(asset_b_len == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         }
//     }

//     fun test_remove_ask_order_(test: &mut Scenario) {
//         test_add_ask_order_(test);

//          let (_, _,thegirl, _, _) = people();

//         next_tx(test, thegirl);

//         {
//         let clock = clock::create_for_testing(ctx(test));
//         let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
        
//         let (orderbook_entry_id, _parent_limit,_next,_prev,_price,_init_quantity,_cur_quantity,_user) = orders::get_ask_order_info(&orderbook, 0);
//         orders::remove_ask_order(orderbook_entry_id, &mut orderbook, &clock, ctx(test));
//         clock::destroy_for_testing(clock);
//         test::return_shared(orderbook);
//         };

//          next_tx(test, thegirl);

//         {
//              let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
//             let the_girl_balance = orders::get_user_asset_a_balance(&orderbook, thegirl);
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_b_len == 0, 0);
//             assert!(the_girl_balance == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             test::return_shared(orderbook);
//         }
//     }

//     fun test_ask_bids_match_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, john, ivan, julia, alex) = people();

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 10, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };
        

//         next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(308 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(308 * 1_000_000_000 * 5, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(307 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(307 * 1_000_000_000 * 1, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, julia);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(311 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 8, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);    
//         };

//          next_tx(test, alex);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 12, ctx(test)), &clock, ctx(test));
           
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
      
//         };

//         // intermediate check 
//         next_tx(test, alex);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
//             assert!(bids_len == 3, 0);
//             assert!(asks_len == 1, 0);
//             assert!(bid_limits_len == 3, 0);
//             assert!(ask_limits_len == 1, 0);
//             assert!(asset_a_len == 2, 0);
//             assert!(asset_b_len == 2, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             let alex_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(alex_ask_wallet_amount == 0, 0);

//             let alex_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(alex_bid_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
//             assert!(coin::value(&coin) == 3_708_000_000_000, 1);
//             transfer::public_transfer(coin, alex);
           
//             test::return_shared(orderbook);
//         };

//         // intermediate check 
//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let john_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(john_ask_wallet_amount == 0, 0);

//             let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             // todo here wrong assertion
//             assert!(john_ask_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
//             assert!(coin::value(&coin) == 10_000_000_000, 1);
//             transfer::public_transfer(coin, john);
           
//             test::return_shared(orderbook);
//         };

//         // intermediate check 
//         next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let ivan_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(ivan_ask_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
//             assert!(coin::value(&coin) == 2_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);
           
//             test::return_shared(orderbook);
//         };

//         next_tx(test, julia);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(313 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, julia);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(315 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 2, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };


//         next_tx(test, julia);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(308 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 3, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         // intermediate check 
//         next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
//             let ivan_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(ivan_bid_wallet_amount == 307_000_000_000, 0);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            
//             assert!(coin::value(&coin) == 2_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);
//         //    orders::test(&orderbook);
//             test::return_shared(orderbook);
//         };

//         // // intermediate check 
//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
//             let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
           
//             assert!(john_bid_wallet_amount == 1_232_000_000_000, 0);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
         
//             assert!(coin::value(&coin) == 1_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);
        
//             test::return_shared(orderbook);
//         };
//         next_tx(test, alex);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(306 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         // // intermediate check 
//         next_tx(test, alex);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let alex_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));

//             assert!(alex_ask_wallet_amount == 0, 0);
//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            
//             assert!(coin::value(&coin) == 1_224_000_000_000, 1); // todo aler alert probably in each next_tx asset a reset when public transfer if so than right but in real case it should be 3_708_000_000_000 + 1_224_000_000_000 
//             transfer::public_transfer(coin, ivan);
        
//             test::return_shared(orderbook);
//         };

//         // intermediate check 
//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
//             let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
          
//             assert!(john_bid_wallet_amount == 8_000_000_000, 0);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
         
//             assert!(coin::value(&coin) == 4_000_000_000, 1); 
//             transfer::public_transfer(coin, ivan);
        
//             test::return_shared(orderbook);
//         };

//         // intermediate check 
//         next_tx(test, julia);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
//             let julia_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
          
//             assert!(julia_ask_wallet_amount == 14_000_000_000, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            
//             transfer::public_transfer(coin, ivan);
        
//             test::return_shared(orderbook);
//         };
//     }

//     fun test_one_bid_ask_match_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, john, ivan, _, _) = people();

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(306 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
//             assert!(bids_len == 1, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 1, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_b_len == 1, 0);
//              assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);
            
//             let (_orderbook_entry_id, _parent_limit,next,prev,price,_init_quantity,cur_quantity,user) = orders::get_bid_order_info(&orderbook, 0);
           
//             assert!(option::is_none(&next), 0);
//             assert!(option::is_none(&prev), 0);
//             assert!(price == 309 * 1_000_000_000, 0);
//             assert!(cur_quantity == 12_000_000_000,0);
//             assert!(user == john, 0);

//             let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(ivan_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
//             assert!(coin::value(&coin) == 1_224_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);
            
//             test::return_shared(orderbook);
//         };

//          next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
//             assert!(coin::value(&coin) == 4_000_000_000, 1);
//             transfer::public_transfer(coin, john);
            
      
//             test::return_shared(orderbook);
//         };
//     }

//     fun test_one_exact_bid_ask_match_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, john, ivan, _, _) = people();

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_b_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(ivan_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
//             assert!(coin::value(&coin) == 1_236_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);

//             let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(john_wallet_amount == 0, 0);

//             test::return_shared(orderbook);
//         };

//          next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
//             assert!(coin::value(&coin) == 4_000_000_000, 1);
//             transfer::public_transfer(coin, john);
            
//             let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(john_wallet_amount == 0, 0);
        
//             test::return_shared(orderbook);
//         };
//     }

//     fun test_one_exact_ask_bid_match_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, john, ivan, _, _) = people();

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//          next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
//             assert!(bids_len == 0, 0);
//             assert!(asks_len == 0, 0);
//             assert!(bid_limits_len == 0, 0);
//             assert!(ask_limits_len == 0, 0);
//             assert!(asset_a_len == 1, 0);
//             assert!(asset_b_len == 1, 0);
//             assert!(asset_a_tmp_len == 0, 0);
//             assert!(asset_b_tmp_len == 0, 0);

//             let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
//             assert!(ivan_wallet_amount == 0, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
//             assert!(coin::value(&coin) == 1_236_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);

//             test::return_shared(orderbook);
//         };

//          next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
//             assert!(coin::value(&coin) == 4_000_000_000, 1);
//             transfer::public_transfer(coin, john);
            
//             let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(john_wallet_amount == 0, 0);
          
//             test::return_shared(orderbook);
//         };
//     }

//     fun test_another_bid_ask_match_(test: &mut Scenario) {
//         test_init_orderbook_(test);

//         let (_, john, ivan, _, _) = people();

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 1, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, ivan);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_ask_order<ASSET_A, ASSET_B>(310 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 5, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, john);

//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
//             let clock = clock::create_for_testing(ctx(test));
//             orders::add_bid_order<ASSET_A, ASSET_B>(311 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(311 * 1_000_000_000 * 3, ctx(test)), &clock, ctx(test));
//             clock::destroy_for_testing(clock);
//             test::return_shared(orderbook);
//         };

//         next_tx(test, john);
//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
//             assert!(john_wallet_amount == 309_000_000_000, 0);

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);
           
//            assert!(coin::value(&coin) == 3_000_000_000, 1);
//             transfer::public_transfer(coin, john);

//             let coin = test::take_from_sender<Coin<ASSET_A>>(test);
           
//             assert!(coin::value(&coin) == 3_000_000_000, 1);
//             transfer::public_transfer(coin, john);
            
//             test::return_shared(orderbook);
//         };

//         next_tx(test, ivan);
//         {
//             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

//             let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            
//             assert!(ivan_wallet_amount == 2_000_000_000, 0);
         

//             let coin = test::take_from_sender<Coin<ASSET_B>>(test);

//             assert!(coin::value(&coin) == 930_000_000_000, 1);
//             transfer::public_transfer(coin, ivan);
            
//             test::return_shared(orderbook);
//         };
//     }


//     fun scenario(): Scenario { test::begin(@0x1) }
//     fun people(): (address, address, address, address, address) { (@0xBEEF, @0x1337, @0xcafe, @0xA11CE, @0x2222) }
// }