module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use std::vector::{Self};
    use sui::table::{Self, Table};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::transfer::{public_transfer};
    use std::debug;

    struct OrderbookManagerCap has key, store { id: UID }

    struct OrderbookEntry has key, store {
        id: UID,
        current: Order,
        is_by_side: bool,
        parent_limit: ID,
        next: Option<ID>, // OrderbookEntry
        previous: Option<ID> // OrderbookEntry
    }

    struct Limit has key, store {
        id: UID,
        price: u64,
        head: Option<ID>, // OrderbookEntry
        tail: Option<ID>, // OrderbookEntry
    }

    struct Order has key, store{
        id: UID,
        price: u64,
        is_by_side: bool,
        initial_quantity: u64,
        current_quantity: u64,
        user: address,
    }

    struct Orderbook<phantom AssetA, phantom AssetB> has key, store {
        id: UID,
        bids: vector<OrderbookEntry>,
        asks: vector<OrderbookEntry>,
        bid_limits: Table<ID, Limit>,
        ask_limits: Table<ID, Limit>,
        asset_a: Table<address, Balance<AssetA>>,
        asset_b: Table<address, Balance<AssetB>>
    }

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(OrderbookManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    public entry fun create_orderbook<AssetA, AssetB> (
        _: &OrderbookManagerCap, ctx: &mut TxContext
    ) {
        publish<AssetA, AssetB>(ctx)
    }

    fun publish<AssetA, AssetB>(ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Orderbook{
            id, 
            bids: vector::empty<OrderbookEntry>(),
            asks: vector::empty<OrderbookEntry>(),
            bid_limits: table::new<ID, Limit>(ctx),
            ask_limits: table::new<ID, Limit>(ctx),
            asset_a: table::new<address, Balance<AssetA>>(ctx),
            asset_b: table::new<address, Balance<AssetB>>(ctx),
        })
    }

    // need to handle initial quantity
    public entry fun add_bid_order<AssetA, AssetB>(price: u64, orderBook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetA>,ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);
        
        let asset_a_balance = coin::into_balance(coin);
        let asset_a_value = balance::value(&asset_a_balance);
        // get user from ctx
        let order = create_order(price, true, asset_a_value, asset_a_value, tx_context::sender(ctx), ctx);
        
        let balance = borrow_mut_account_balance<AssetA>(&mut orderBook.asset_a, tx_context::sender(ctx));
        balance::join(balance, asset_a_balance);
        
        add_bid_order_to_orderbook(order, base_limit, orderBook, true, ctx);
    }

    public entry fun remove_order_from_order_book<AssetA, AssetB>(orderbookEntry: OrderbookEntry,  orderBook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        if(vector::contains(&orderBook.bids, &orderbookEntry) || vector::contains(&orderBook.asks, &orderbookEntry)) {
            let refund_quantity = orderbookEntry.current.current_quantity;
            let is_by_side = orderbookEntry.is_by_side;

            let sender = tx_context::sender(ctx);
            if(is_by_side) { 
                remove_bid_order(orderbookEntry, orderBook);
                let user_balance = table::borrow_mut(&mut orderBook.asset_a, sender);
                let refund = coin::take(user_balance, refund_quantity, ctx);
                transfer::public_transfer(refund, sender);
            } else {
                remove_ask_order(orderbookEntry, orderBook);
                let user_balance = table::borrow_mut(&mut orderBook.asset_b, sender);
                let refund = coin::take(user_balance, refund_quantity, ctx);
                transfer::public_transfer(refund, sender);
            }; 
        } else {
           remove_order_from_store(orderbookEntry);
        }
    }

    fun remove_order_from_store(orderbookEntry: OrderbookEntry){
        let OrderbookEntry {
                    id,
                    current,
                    is_by_side: _,
                    parent_limit: _,
                    next: _,
                    previous: _,
                } = orderbookEntry;
                object::delete(id);
                
                let Order {
                    id,
                    price: _,
                    is_by_side: _,
                    initial_quantity: _,
                    current_quantity: _,
                    user: _,
                } = current;
                object::delete(id);
    }

    fun remove_parent_limit_from_store(limit: Limit) {
        let Limit {
                        id,
                        price: _,
                        head: _,
                        tail: _,
                    } = limit;
         object::delete(id)            
    }

    fun remove_bid_order<AssetA, AssetB>(orderbookEntry: OrderbookEntry, orderBook: &mut Orderbook<AssetA, AssetB>) {
        // 1. Deal with location of OrderbookEntry within the linked list.
        if(option::is_some(&orderbookEntry.previous) && option::is_some(&orderbookEntry.next)) {
            let next_id = option::borrow(&orderbookEntry.next);
            let previous_id = option::borrow(&orderbookEntry.previous);

            let next_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, next_id);
            let prev_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, previous_id);

            if(option::is_some(&next_vec_idx)) {
                let next_idx = option::borrow(&next_vec_idx);
                let next = vector::borrow_mut(&mut orderBook.bids, *next_idx);
                next.previous = orderbookEntry.previous;    
            };

            if(option::is_some(&prev_vec_idx)) {
                let prev_idx = option::borrow(&prev_vec_idx);
                let prev = vector::borrow_mut(&mut orderBook.bids, *prev_idx);
                prev.next = orderbookEntry.next; 
            };
        } else if(option::is_some(&orderbookEntry.previous)) {
            let previous_id = option::borrow(&orderbookEntry.previous);
            let prev_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, previous_id);

            if(option::is_some(&prev_vec_idx)) {
                let prev_idx = option::borrow(&prev_vec_idx);
                let prev = vector::borrow_mut(&mut orderBook.bids, *prev_idx);
                prev.next = option::none(); 
            };
        } else if(option::is_some(&orderbookEntry.next)) {
            let next_id = option::borrow(&orderbookEntry.next);
            let next_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, next_id);

            if(option::is_some(&next_vec_idx)) {
                let next_idx = option::borrow(&next_vec_idx);
                let next = vector::borrow_mut(&mut orderBook.bids, *next_idx);
                next.previous = option::none();    
            };
        };

        deal_with_limit(&mut orderBook.bid_limits, orderbookEntry);
    }

    fun remove_ask_order<AssetA, AssetB>(orderbookEntry: OrderbookEntry, orderBook: &mut Orderbook<AssetA, AssetB>) {
        // 1. Deal with location of OrderbookEntry within the linked list.
        if(option::is_some(&orderbookEntry.previous) && option::is_some(&orderbookEntry.next)) {
            let next_id = option::borrow(&orderbookEntry.next);
            let previous_id = option::borrow(&orderbookEntry.previous);

            let next_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, next_id);
            let prev_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, previous_id);

            if(option::is_some(&next_vec_idx)) {
                let next_idx = option::borrow(&next_vec_idx);
                let next = vector::borrow_mut(&mut orderBook.asks, *next_idx);
                next.previous = orderbookEntry.previous;    
            };

            if(option::is_some(&prev_vec_idx)) {
                let prev_idx = option::borrow(&prev_vec_idx);
                let prev = vector::borrow_mut(&mut orderBook.asks, *prev_idx);
                prev.next = orderbookEntry.next; 
            };
        } else if(option::is_some(&orderbookEntry.previous)) {
            let previous_id = option::borrow(&orderbookEntry.previous);
            let prev_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, previous_id);

            if(option::is_some(&prev_vec_idx)) {
                let prev_idx = option::borrow(&prev_vec_idx);
                let prev = vector::borrow_mut(&mut orderBook.asks, *prev_idx);
                prev.next = option::none(); 
            };
        } else if(option::is_some(&orderbookEntry.next)) {
            let next_id = option::borrow(&orderbookEntry.next);
            let next_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, next_id);

            if(option::is_some(&next_vec_idx)) {
                let next_idx = option::borrow(&next_vec_idx);
                let next = vector::borrow_mut(&mut orderBook.asks, *next_idx);
                next.previous = option::none();    
            };
        };

        deal_with_limit(&mut orderBook.ask_limits, orderbookEntry);
    }

    fun deal_with_limit(limits: &mut Table<ID, Limit>, orderbookEntry: OrderbookEntry) {
        let parent_limit = table::borrow_mut(limits, orderbookEntry.parent_limit);

            if(option::is_some(&parent_limit.head) && option::is_some(&parent_limit.tail)) {
                let parent_limit_head_id = option::borrow(&parent_limit.head);
                let parent_limit_tail_id = option::borrow(&parent_limit.tail);

                if(*parent_limit_head_id == object::id(&orderbookEntry) && *parent_limit_tail_id == object::id(&orderbookEntry)) {
                    parent_limit.head = option::none();
                    parent_limit.tail = option::none();

                    let parent_limit_to_delete = table::remove(limits, orderbookEntry.parent_limit);
                    remove_parent_limit_from_store(parent_limit_to_delete);
                } else if(*parent_limit_head_id == object::id(&orderbookEntry)) {
                    parent_limit.head = orderbookEntry.next;
                } else if(*parent_limit_tail_id == object::id(&orderbookEntry)) {
                    parent_limit.tail = orderbookEntry.previous;
                };

                remove_order_from_store(orderbookEntry);
            } else {
                 remove_order_from_store(orderbookEntry);
            };
    }

    public entry fun add_ask_order<AssetA, AssetB>(price: u64, orderBook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetB>,ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);

        let asset_b_balance = coin::into_balance(coin);
        let asset_b_value = balance::value(&asset_b_balance);

        let order = create_order(price, false, asset_b_value, asset_b_value, tx_context::sender(ctx), ctx);

        let balance = borrow_mut_account_balance<AssetB>(&mut orderBook.asset_b, tx_context::sender(ctx));
        balance::join(balance, asset_b_balance);
        
        add_ask_order_to_orderbook(order, base_limit, orderBook, false, ctx);
    }


    fun borrow_mut_account_balance<T>(
        asset: &mut Table<address, Balance<T>>,
        user: address,
    ): &mut Balance<T> {
        if (!table::contains(asset, user)) {
            table::add(
                asset,
                user,
                balance::zero()
            );
        };

        table::borrow_mut(asset, user)
    }

    fun create_limit(price: u64, ctx: &mut TxContext): Limit {
        Limit {
            id: object::new(ctx),
            price,
            head: option::none(),
            tail: option::none(),
        }
    }

    fun create_order(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, ctx: &mut TxContext): Order {
        Order {
            id: object::new(ctx),
            price,
            is_by_side,
            initial_quantity,
            current_quantity,
            user,
        }
    }

    fun create_new_entry(order: Order, limit_id: ID, is_by_side: bool, ctx: &mut TxContext): OrderbookEntry {
        OrderbookEntry {
            id: object::new(ctx),
            is_by_side,
            current: order,
            parent_limit: limit_id,
            next: option::none(),
            previous: option::none()
        }
    }

    fun add_bid_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderBook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, ctx: &mut TxContext) {
        if(table::contains(&orderBook.bid_limits, object::id(&limit))) {
            let new_entry = create_new_entry(order, object::id(&limit), is_by_side, ctx);
            if(option::is_none(&limit.tail)) {
                limit.head = option::some(object::id(&new_entry));
                limit.tail = option::some(object::id(&new_entry));
            } else {
                let tail_proxy_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, option::borrow(&limit.tail));

                if(option::is_some(&tail_proxy_vec_idx)) {
                    let tail_proxy_idx = option::borrow(&tail_proxy_vec_idx);
                    let tail_proxy = vector::borrow_mut(&mut orderBook.bids, *tail_proxy_idx);
                    new_entry.previous = option::some(object::id(tail_proxy));
                    tail_proxy.next = option::some(object::id(&new_entry));
                    limit.tail = option::some(object::id(&new_entry));
                }                
            };
            vector::push_back(&mut orderBook.bids, new_entry);
             let Limit {
                id,
                price: _,
                head: _,
                tail: _,
            } = limit;
            object::delete(id)
        } else {
            let new_entry = create_new_entry(order, object::id(&limit),is_by_side, ctx);
            limit.head = option::some(object::id(&new_entry));
            limit.tail = option::some(object::id(&new_entry));
            table::add(&mut orderBook.bid_limits, object::id(&limit), limit);
            vector::push_back(&mut orderBook.bids, new_entry);
        };
    }

    fun get_idx_opt<K: key + store>(self: &vector<K>, key: &ID): Option<u64> {
        let i = 0;
        let n = vector::length(self);
        while (i < n) {
            let elem = vector::borrow(self, i);
            if (&object::id(elem) == key) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    fun add_ask_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderBook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, ctx: &mut TxContext) {
        if(table::contains(&orderBook.ask_limits, object::id(&limit))) {
            let new_entry = create_new_entry(order, object::id(&limit),is_by_side, ctx);
            if(option::is_none(&limit.tail)) {
                limit.head = option::some(object::id(&new_entry));
                limit.tail = option::some(object::id(&new_entry));
            } else {
                let tail_proxy_vec_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, option::borrow(&limit.tail));

                if(option::is_some(&tail_proxy_vec_idx)) {
                    let tail_proxy_idx = option::borrow(&tail_proxy_vec_idx);
                    let tail_proxy = vector::borrow_mut(&mut orderBook.asks, *tail_proxy_idx);
                    new_entry.previous = option::some(object::id(tail_proxy));
                    tail_proxy.next = option::some(object::id(&new_entry));
                    limit.tail = option::some(object::id(&new_entry));
                }    
            };
            vector::push_back(&mut orderBook.asks, new_entry);
             let Limit {
                id,
                price: _,
                head: _,
                tail: _,
            } = limit;
            object::delete(id);
        } else {
            let new_entry = create_new_entry(order, object::id(&limit),is_by_side, ctx);
            limit.head = option::some(object::id(&new_entry));
            limit.tail = option::some(object::id(&new_entry));
            table::add(&mut orderBook.ask_limits, object::id(&limit), limit);
            vector::push_back(&mut orderBook.asks, new_entry);
        };
    }

    fun match<AssetA, AssetB>(orderBook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        sort_vec(&mut orderBook.asks);
        sort_vec(&mut orderBook.bids);
        vector::reverse(&mut orderBook.bids);

        let bids_count = 0;
        let asks_count = 0;

        if(vector::length(&orderBook.bids) == 0 || vector::length(&orderBook.asks) == 0) {
            return
        };

        while (bids_count < vector::length(&orderBook.bids) && asks_count < vector::length(&orderBook.asks)) {
            let bid_loop = true;

            while(bid_loop) {
                let bid = vector::borrow(&orderBook.bids, bids_count);
                if(bid.current.price == 0) {
                     bids_count = bids_count + 1;
                } else {
                    bid_loop = false;
                }
            };

            let ask_loop = true;

            while(ask_loop) {
                let ask = vector::borrow(&orderBook.asks, asks_count);
                if(ask.current.price == 0) {
                     asks_count = asks_count + 1;
                } else {
                    ask_loop = false;
                }
            };

            let bid = vector::borrow(&orderBook.bids, bids_count);
            let ask = vector::borrow(&orderBook.asks, asks_count);

            if(bid.current.price < ask.current.price) {
                bids_count = vector::length(&orderBook.bids);
                asks_count = vector::length(&orderBook.asks);

                debug::print(&bids_count);
                debug::print(&asks_count);
                break
            };

            let parent_bid_limit_id = vector::borrow(&orderBook.bids, bids_count).parent_limit;
            let parent_bid_limit = table::borrow_mut(&mut orderBook.bid_limits, parent_bid_limit_id);
            let parent_ask_limit_id = vector::borrow(&orderBook.asks, asks_count).parent_limit;
            let parent_ask_limit = table::borrow_mut(&mut orderBook.ask_limits, parent_ask_limit_id);
            
            let current_bid_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, option::borrow(&parent_bid_limit.head));
            let current_ask_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, option::borrow(&parent_ask_limit.head));

            while(option::is_some(&current_bid_idx) && option::is_some(&current_ask_idx)) {
                let bid_idx = option::borrow(&current_bid_idx);
                let ask_idx = option::borrow(&current_ask_idx);
                let current_bid = vector::borrow_mut(&mut orderBook.bids, *bid_idx);
                let current_ask = vector::borrow_mut(&mut orderBook.asks, *ask_idx);

                if(current_bid.current.current_quantity == current_ask.current.current_quantity) {
                    let bidder_usdt_wallet = table::borrow_mut(&mut orderBook.asset_a, current_bid.current.user);
                    let bidder_usdt = current_bid.current.current_quantity * current_ask.current.price;
                    let asker_sui_wallet = table::borrow_mut(&mut orderBook.asset_b, current_ask.current.user);

                    if(balance::value(bidder_usdt_wallet) >= bidder_usdt && balance::value(asker_sui_wallet) >= current_ask.current.current_quantity) {
                        let asset_a_to_change = balance::split(bidder_usdt_wallet, bidder_usdt);
                        let asset_b_to_change = balance::split(asker_sui_wallet, current_ask.current.current_quantity);
                        public_transfer(coin::from_balance<AssetA>(asset_a_to_change, ctx), current_ask.current.user);
                        public_transfer(coin::from_balance<AssetB>(asset_b_to_change, ctx), current_bid.current.user);
                    } else {
                            // return error because sth wrong with wallets
                    };

                    current_bid.current.current_quantity = 0;
                    current_ask.current.current_quantity = 0;
                    current_bid_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.bids, option::borrow(&current_bid.next));
                    current_ask_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.asks, option::borrow(&current_ask.next));
                } else if(
                    current_bid.current.current_quantity > current_ask.current.current_quantity
                ) {
                    let bidder_usdt_wallet = table::borrow_mut(&mut orderBook.asset_a, current_bid.current.user);
                    let bidder_usdt = current_bid.current.current_quantity * current_ask.current.price;
                    let asker_sui_wallet = table::borrow_mut(&mut orderBook.asset_b, current_ask.current.user);

                    if(balance::value(bidder_usdt_wallet) >= bidder_usdt && balance::value(asker_sui_wallet) >= current_ask.current.current_quantity) {
                        let asset_a_to_change = balance::split(bidder_usdt_wallet, bidder_usdt);
                        let asset_b_to_change = balance::split(asker_sui_wallet, current_ask.current.current_quantity);
                        public_transfer(coin::from_balance<AssetA>(asset_a_to_change, ctx), current_ask.current.user);
                        public_transfer(coin::from_balance<AssetB>(asset_b_to_change, ctx), current_bid.current.user);
                    } else {
                        // return error because sth wrong with wallets
                    };
                    current_bid.current.current_quantity = current_bid.current.current_quantity - current_ask.current.current_quantity;
                    current_ask.current.current_quantity = 0;
                    current_ask_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.asks, option::borrow(&current_ask.next));
                } else {
                    let bidder_usdt_wallet = table::borrow_mut(&mut orderBook.asset_a, current_bid.current.user);
                    let bidder_usdt = current_bid.current.current_quantity * current_ask.current.price;
                    let asker_sui_wallet = table::borrow_mut(&mut orderBook.asset_b, current_ask.current.user);

                    if(balance::value(bidder_usdt_wallet) >= bidder_usdt &&  balance::value(asker_sui_wallet) >= current_bid.current.current_quantity) {
                        let asset_a_to_change = balance::split(bidder_usdt_wallet, bidder_usdt);
                        let asset_b_to_change = balance::split(asker_sui_wallet, current_bid.current.current_quantity);
                        public_transfer(coin::from_balance<AssetA>(asset_a_to_change, ctx), current_ask.current.user);
                        public_transfer(coin::from_balance<AssetB>(asset_b_to_change, ctx), current_bid.current.user);
                    } else {
                        // return error because sth wrong with wallets
                    };

                    current_ask.current.current_quantity = current_ask.current.current_quantity - current_bid.current.current_quantity;
                    current_bid.current.current_quantity = 0;
                    current_bid_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.bids, option::borrow(&current_bid.next));
                }
            };            
        };

        // stopped here
        let bids_count2 = 0;
        let bid_limits_vec = vector::empty<ID>();
        let asks_count2 = 0;
        let ask_limits_vec = vector::empty<ID>();

        let bid_limits_to_delete = vector::empty<ID>();
        let bid_orders_to_delete = vector::empty<ID>();

        let ask_limits_to_delete = vector::empty<ID>();
        let ask_orders_to_delete = vector::empty<ID>();

        while(vector::borrow(&orderBook.bids, bids_count2).current.current_quantity == 0) {
            vector::push_back(&mut bid_limits_vec, vector::borrow(&orderBook.bids, bids_count2).parent_limit);
            bids_count2 = bids_count2 + 1;
        };

        while(vector::borrow(&orderBook.asks, asks_count2).current.current_quantity == 0) {
            vector::push_back(&mut ask_limits_vec, vector::borrow(&orderBook.asks, asks_count2).parent_limit);
            asks_count2 = asks_count2 + 1;
        };

        let i = 0; 
        while (i < vector::length(&bid_limits_vec)) {
            let bid_limit_id = vector::borrow(&bid_limits_vec, i);
            let limit = table::borrow_mut(&mut orderBook.bid_limits, *bid_limit_id);
            let run_bid_limit = true;

            while(run_bid_limit) {
                if(option::is_some<ID>(&limit.head)) {
                    let order_idx = get_idx_opt<OrderbookEntry>(&orderBook.bids, option::borrow(&limit.head));
                    let order = vector::borrow_mut(&mut orderBook.bids, *option::borrow(&order_idx));

                    if(order.current.current_quantity == 0) {
                        if(option::is_some(&order.previous)) {
                            // "Error, order can not have previous"
                        };

                        if(option::is_some(&order.next)) {
                            limit.head = order.next;
                            let next_order_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.bids, option::borrow(&order.next));
                            let next_order = vector::borrow_mut(&mut orderBook.bids, *option::borrow(&next_order_idx));
                            next_order.previous = option::none();
                        } else if (option::is_some(&limit.tail) && option::borrow(&limit.head) == option::borrow(&limit.tail)) {
                            vector::push_back(&mut bid_limits_to_delete, *bid_limit_id);

                            run_bid_limit = false;
                        };
                        
                        vector::push_back(&mut bid_orders_to_delete, *option::borrow(&limit.head));
                    }
                }
                
            };
            
            i = i + 1;
        };


        let p = 0; 
        while (p < vector::length(&ask_limits_vec)) {
            let ask_limit_id = vector::borrow(&ask_limits_vec, p);
            let limit = table::borrow_mut(&mut orderBook.ask_limits, *ask_limit_id);
            let run_ask_limit = true;

            while(run_ask_limit) {
                if(option::is_some<ID>(&limit.head)) {
                    let order_idx = get_idx_opt<OrderbookEntry>(&orderBook.asks, option::borrow(&limit.head));
                    let order = vector::borrow_mut(&mut orderBook.asks, *option::borrow(&order_idx));

                    if(order.current.current_quantity == 0) {
                        if(option::is_some(&order.previous)) {
                            // "Error, order can not have previous"
                        };

                        if(option::is_some(&order.next)) {
                            limit.head = order.next;
                            let next_order_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.asks, option::borrow(&order.next));
                            let next_order = vector::borrow_mut(&mut orderBook.asks, *option::borrow(&next_order_idx));
                            next_order.previous = option::none();
                        } else if (option::is_some(&limit.tail) && option::borrow(&limit.head) == option::borrow(&limit.tail)) {
                            vector::push_back(&mut ask_limits_to_delete, *ask_limit_id);

                            run_ask_limit = false;
                        };
                        
                        vector::push_back(&mut ask_orders_to_delete, *option::borrow(&limit.head));
                    }
                }
                
            };
            
            p = p + 1;
        };

        let y = 0;
        while(y < vector::length(&bid_limits_to_delete)) {
            let limit = table::remove(&mut orderBook.bid_limits, *vector::borrow(&bid_limits_to_delete, y));
            let Limit {
                            id,
                            price: _,
                            head: _,
                            tail: _,
                        } = limit;
            object::delete(id);
            y = y + 1;
        };

        let z = 0;
        while(z < vector::length(&bid_orders_to_delete)) {
            let order_id = vector::borrow(&bid_orders_to_delete, z);
            let bid_order_to_delete_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.bids, order_id);
            let orderBookEntry = vector::remove(&mut orderBook.bids, *option::borrow(&bid_order_to_delete_idx));
            let OrderbookEntry {
                            id,
                            current,
                            is_by_side: _,
                            parent_limit: _,
                            next: _,
                            previous: _,
                        } = orderBookEntry;
            object::delete(id);

            let Order {
                id,
                price: _,
                is_by_side: _,
                initial_quantity: _,
                current_quantity: _,
                user: _,
            } = current;
            object::delete(id);
            z = z + 1;
        };


        let d = 0;
        while(d < vector::length(&bid_limits_to_delete)) {
            let limit = table::remove(&mut orderBook.ask_limits, *vector::borrow(&ask_limits_to_delete, d));
            let Limit {
                            id,
                            price: _,
                            head: _,
                            tail: _,
                        } = limit;
            object::delete(id);
            d = d + 1;
        };

        let h = 0;
        while(h < vector::length(&ask_orders_to_delete)) {
            let order_id = vector::borrow(&ask_orders_to_delete, h);
            let ask_order_to_delete_idx = get_idx_opt<OrderbookEntry>(&mut orderBook.asks, order_id);
            let orderBookEntry = vector::remove(&mut orderBook.asks, *option::borrow(&ask_order_to_delete_idx));
            let OrderbookEntry {
                            id,
                            current,
                            is_by_side: _,
                            parent_limit: _,
                            next: _,
                            previous: _,
                        } = orderBookEntry;
            object::delete(id);

            let Order {
                id,
                price: _,
                is_by_side: _,
                initial_quantity: _,
                current_quantity: _,
                user: _,
            } = current;
            object::delete(id);
            h = h + 1;
        }
    }

    public fun sort_vec(elems: &mut vector<OrderbookEntry>) {
            if (vector::length(elems) < 2) return;

            let i = 0;
            let swapped = false;
            while ({
                // Loop invariants are defined within the loop head.
                spec {
                    invariant !swapped ==> (forall j in 0..i: elems[j].current.price <= elems[j + 1].current.price);
                    invariant len(elems) == len(old(elems));
                    invariant forall a in old(elems): contains(elems, a);
                    invariant forall a in elems: contains(old(elems), a);
                };
                i < vector::length(elems) - 1
            })
            {
                if (vector::borrow(elems, i).current.price > vector::borrow(elems, i + 1).current.price) {
                    vector::swap(elems, i, i + 1);
                    swapped = true;
                };
                i = i + 1;
            };
            if (swapped) sort_vec(elems);
    }

    public fun get_length_fields<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>):(u64,u64,u64,u64, u64,u64) {
        return (
            vector::length<OrderbookEntry>(&orderbook.bids),
            vector::length<OrderbookEntry>(&orderbook.asks),
            table::length<ID, Limit>(&orderbook.bid_limits),
            table::length<ID, Limit>(&orderbook.ask_limits),
            table::length<address, Balance<AssetA>>(&orderbook.asset_a),
            table::length<address, Balance<AssetB>>(&orderbook.asset_b),
        )
    }

    public fun get_bid_wallet_amount<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, ctx: &mut TxContext): u64 {
        if(table::contains(&orderbook.asset_a, tx_context::sender(ctx))) {
            return balance::value(table::borrow(&orderbook.asset_a, tx_context::sender(ctx)))
        } else {
            return 0_u64
        }
    }

    public fun get_bid_order_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, index: u64): (ID, ID, Option<ID>, Option<ID>, u64, u64,u64, address) {
        let obEntry = vector::borrow(&orderbook.bids, index);

        return (
            object::uid_to_inner(&obEntry.id),
            obEntry.parent_limit,
            obEntry.next,
            obEntry.previous,
            obEntry.current.price,
            obEntry.current.initial_quantity,
            obEntry.current.current_quantity,
            obEntry.current.user,
        )
    }

    public fun get_bid_limit_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, id: ID): (u64, Option<ID>, Option<ID>) {
        let limit = table::borrow(&orderbook.bid_limits, id);
        return (
            limit.price,
            limit.head,
            limit.tail,
        )
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}

#[test_only]
module orderbookmodule::orders_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{mint_for_testing as mint};
    use orderbookmodule::orders::{Self, OrderbookManagerCap, Orderbook};
    use std::option::{Self};

    struct ASSET_A {}
    struct ASSET_B {}
    use std::debug;
    // use std::vector::{Self};

    #[test] fun test_init_orderbook() {
        let scenario = scenario();
        test_init_orderbook_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_add_order() {
        let scenario = scenario();
        test_add_order_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_remove_order() {
        let scenario = scenario();
        test_remove_order_(&mut scenario);
        test::end(scenario);
    }

    fun test_init_orderbook_(test: &mut Scenario) {
        let (owner, _) = people();

        next_tx(test, owner);

        {
            orders::init_for_testing(ctx(test))
        };

        next_tx(test, owner);

        {
            let witness = test::take_from_sender<OrderbookManagerCap>(test);
            orders::create_orderbook<ASSET_A, ASSET_B>(&witness, ctx(test));
            test::return_to_sender(test, witness);
        };

        next_tx(test, owner);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 0, 0);
            assert!(asset_b_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_add_order_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, theguy) = people();

        next_tx(test, theguy);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
           
            orders::add_bid_order<ASSET_A, ASSET_B>(309_000_000_000, &mut orderbook, mint<ASSET_A>(309_000_000_000 * 10, ctx(test)), ctx(test));
            
            let theguy_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(theguy_wallet_amount == 309_000_000_000_0, 0);

            let (orderbook_entry_id, parent_limit,next,previous,price,initial_quantity,current_quantity,user) = orders::get_bid_order_info(&orderbook, 0);
           
            assert!(option::is_none(&next), 0);
            assert!(option::is_none(&previous), 0);
            assert!(price == 309_000_000_000, 0);
            assert!(initial_quantity == 309_000_000_000_0,0);
            assert!(current_quantity == 309_000_000_000_0,0);
            assert!(user == theguy, 0);

            let (price, head, tail) = orders::get_bid_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit);
            assert!(price == 309_000_000_000, 0);
            assert!(head == option::some(orderbook_entry_id), 0);
            assert!(tail == option::some(orderbook_entry_id), 0);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

            assert!(bids_len == 1, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 1, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_b_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_remove_order_(test: &mut Scenario) {
        test_add_order_(test);

         let (_, theguy) = people();

        next_tx(test, theguy);
        let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
        // debug::
        let (_orderbook_entry_id, _parent_limit,_next,_previous,_price,_initial_quantity,_current_quantity,_user) = orders::get_bid_order_info(&orderbook, 0);
           
        // let obEntry = test::take_shared_by_id<OrderbookEntry>(test, orderbook_entry_id);
        debug::print(&orderbook);
        test::return_shared(orderbook);
        // test::return_shared(obEntry);
    }

    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address) { (@0xBEEF, @0x1337) }
}