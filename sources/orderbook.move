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
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::clock::{Self, Clock};
    use sui::event;

    struct OrderbookManagerCap has key, store { id: UID }

    struct Entry has key, store {
        id: UID,
        current: Order,
        is_by_side: bool,
        parent_limit: ID,
        timestamp_ms: u64,
        next: Option<ID>, // Entry
        prev: Option<ID> // Entry
    }

    struct Limit has key, store {
        id: UID,
        price: u64,
        head: Option<ID>, // Entry
        tail: Option<ID>, // Entry
    }

    struct Order has key, store{
        id: UID,
        price: u64,
        is_by_side: bool,
        init_quantity: u64,
        cur_quantity: u64,
        user: address,
    }

    struct Orderbook<phantom AssetA, phantom AssetB> has key, store {
        id: UID,
        bids: vector<Entry>,
        asks: vector<Entry>,
        bid_limits: Table<u64, Limit>,
        ask_limits: Table<u64, Limit>,
        asset_a: Table<address, Balance<AssetA>>,
        asset_b: Table<address, Balance<AssetB>>,
        asset_a_tmp: VecMap<address, Balance<AssetA>>,
        asset_b_tmp: VecMap<address, Balance<AssetB>>, // for satisfy compiler and error still may contain value
    }

    struct OrderMatchedEvent has copy, drop {
        orderbook: ID,
        is_bid: bool,
        timestamp_ms: u64,
        amount: u64,
        price: u64,
    }

    struct OrderCreatedEvent has copy, drop {
        orderbook: ID,
        id: ID,
        timestamp_ms: u64,
        amount: u64,
        price: u64,
        is_bid: bool,
        account: address,
        is_limit: bool,
    }

     struct OrderRemoveEvent has copy, drop {
        orderbook: ID,
        id: ID,
        timestamp_ms: u64,
        is_bid: bool,
        account: address,
        is_limit: bool,
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
            bids: vector::empty<Entry>(),
            asks: vector::empty<Entry>(),
            bid_limits: table::new<u64, Limit>(ctx),
            ask_limits: table::new<u64, Limit>(ctx),
            asset_a: table::new<address, Balance<AssetA>>(ctx),
            asset_b: table::new<address, Balance<AssetB>>(ctx),
            asset_a_tmp: vec_map::empty<address, Balance<AssetA>>(),
            asset_b_tmp: vec_map::empty<address, Balance<AssetB>>(),
        })
    }

    // need to handle initial quantity blya o chem eto ya
    public entry fun add_bid_order<AssetA, AssetB>(price: u64, orderbook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetB>, clock: &Clock, ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);
        
        let coin_balance = coin::into_balance(coin);
        let coin_value = balance::value(&coin_balance);
       
        let order = create_order(price, true, coin_value, coin_value, tx_context::sender(ctx), ctx);
        
        event::emit(OrderCreatedEvent {
            orderbook: object::uid_to_inner(&orderbook.id),
            id: object::uid_to_inner(&order.id),
            timestamp_ms: clock::timestamp_ms(clock),
            amount: coin_value,
            price,
            is_bid: true,
            account: tx_context::sender(ctx),
            is_limit: true,
        });
        
        let balance = borrow_mut_account_balance<AssetB>(&mut orderbook.asset_b, tx_context::sender(ctx));
        balance::join(balance, coin_balance);
        
        add_bid_order_to_orderbook(order, base_limit, orderbook, true, clock, price, ctx);
    }

    public entry fun add_ask_order<AssetA, AssetB>(price: u64, orderbook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetA>, clock: &Clock, ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);

        let coin_balance = coin::into_balance(coin);
        let coin_value = balance::value(&coin_balance);

        let order = create_order(price, false, coin_value, coin_value, tx_context::sender(ctx), ctx);

        event::emit(OrderCreatedEvent {
            orderbook: object::uid_to_inner(&orderbook.id),
            id: object::uid_to_inner(&order.id),
            timestamp_ms: clock::timestamp_ms(clock),
            amount: coin_value,
            price,
            is_bid: false,
            account: tx_context::sender(ctx),
            is_limit: true,
        });

        let balance = borrow_mut_account_balance<AssetA>(&mut orderbook.asset_a, tx_context::sender(ctx));
        balance::join(balance, coin_balance);
        
        add_ask_order_to_orderbook(order, base_limit, orderbook, false, clock, price, ctx);
    }


    public entry fun remove_bid_order<AssetA, AssetB>(entryID: ID, orderbook: &mut Orderbook<AssetA, AssetB>, clock: &Clock, ctx: &mut TxContext) {
        remove_order<AssetB>(&mut orderbook.bids, entryID,&mut orderbook.asset_b,ctx, &mut orderbook.bid_limits);

        event::emit(OrderRemoveEvent {
            orderbook: object::uid_to_inner(&orderbook.id),
            id: entryID,
            timestamp_ms: clock::timestamp_ms(clock),
            is_bid: true,
            account: tx_context::sender(ctx),
            is_limit: true,
        });
    }

     public entry fun remove_ask_order<AssetA, AssetB>(entryID: ID, orderbook: &mut Orderbook<AssetA, AssetB>, clock: &Clock, ctx: &mut TxContext) {
        remove_order<AssetA>(&mut orderbook.asks, entryID,&mut orderbook.asset_a,ctx, &mut orderbook.ask_limits);

        event::emit(OrderRemoveEvent {
            orderbook: object::uid_to_inner(&orderbook.id),
            id: entryID,
            timestamp_ms: clock::timestamp_ms(clock),
            is_bid: false,
            account: tx_context::sender(ctx),
            is_limit: true,
        });
    }

  fun remove_order<T>(entries: &mut vector<Entry>, entryID: ID, asset: &mut Table<address, Balance<T>>, ctx: &mut TxContext, limits: &mut Table<u64, Limit>) {
         let ob_entry_idx = get_idx_opt<Entry>(entries, &entryID);

        if(option::is_none(&ob_entry_idx)) {
            assert!(&1 == &2, 999);
        };
    
        deal_with_location_of_removable_orderboor_entry(entries, ob_entry_idx);

        let entry = vector::borrow(entries, *option::borrow(&ob_entry_idx));

        if(&entry.current.user != &tx_context::sender(ctx)) {
             assert!(&1 == &2, 999);
        };

        deal_with_limit(limits, entry);
        refund_after_remove<T>(entries, ob_entry_idx, asset, ctx);
    }

   

    public fun refund_after_remove<T>(entries: &mut vector<Entry>, ob_entry_idx: Option<u64>, asset: &mut Table<address, Balance<T>>, ctx: &mut TxContext) {
        let entry = vector::remove(entries, *option::borrow(&ob_entry_idx));
        let order_curent_quantity = entry.current.cur_quantity;
        delete_orderbook_entry(entry);
        let bidder_b_wallet = table::borrow_mut(asset, tx_context::sender(ctx));

        if(balance::value(bidder_b_wallet) >= order_curent_quantity) {
            let asset_b_to_refund = balance::split(bidder_b_wallet, order_curent_quantity);
            public_transfer(coin::from_balance<T>(asset_b_to_refund, ctx), tx_context::sender(ctx));
        }
    }

    public fun deal_with_location_of_removable_orderboor_entry(entries: &mut vector<Entry>, ob_entry_idx: Option<u64>) {
        let prev = vector::borrow(entries, *option::borrow(&ob_entry_idx)).prev;
        let next = vector::borrow(entries, *option::borrow(&ob_entry_idx)).next;
      
        if(option::is_some(&prev) && option::is_some(&next)) {
            let next_vec_idx = get_idx_opt<Entry>(entries, option::borrow<ID>(&next));
            let prev_vec_idx = get_idx_opt<Entry>(entries, option::borrow<ID>(&prev));

            if(option::is_some(&next_vec_idx)) {
                let next = vector::borrow_mut<Entry>(entries, *option::borrow(&next_vec_idx));
                next.prev = prev;    
            };

            if(option::is_some(&prev_vec_idx)) {
                let prev = vector::borrow_mut(entries, *option::borrow(&prev_vec_idx));
                prev.next = next; 
            };
        } else if(option::is_some(&prev)) {
            let prev_vec_idx = get_idx_opt<Entry>(entries, option::borrow(&prev));

            if(option::is_some(&prev_vec_idx)) {
                let prev = vector::borrow_mut(entries, *option::borrow(&prev_vec_idx));
                prev.next = option::none(); 
            };
        } else if(option::is_some(&next)) {
            let next_vec_idx = get_idx_opt<Entry>(entries, option::borrow(&next));

            if(option::is_some(&next_vec_idx)) {
                let next = vector::borrow_mut(entries, *option::borrow(&next_vec_idx));
                next.prev = option::none();    
            };
        };
    }

    fun deal_with_limit(limits: &mut Table<u64, Limit>, entry: &Entry) {
        let parent_limit = table::borrow_mut(limits, entry.current.price);

            if(option::is_some(&parent_limit.head) && option::is_some(&parent_limit.tail)) {
                let parent_limit_head_id = option::borrow(&parent_limit.head);
                let parent_limit_tail_id = option::borrow(&parent_limit.tail);

                if(*parent_limit_head_id == object::id(entry) && *parent_limit_tail_id == object::id(entry)) {
                    parent_limit.head = option::none();
                    parent_limit.tail = option::none();

                    let parent_limit_to_delete = table::remove(limits, entry.current.price);
                    delete_limit(parent_limit_to_delete);
                } else if(*parent_limit_head_id == object::id(entry)) {
                    parent_limit.head = entry.next;
                } else if(*parent_limit_tail_id == object::id(entry)) {
                    parent_limit.tail = entry.prev;
                };
            };
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

    fun create_order(price: u64, is_by_side: bool, init_quantity: u64, cur_quantity: u64, user: address, ctx: &mut TxContext): Order {
        Order {
            id: object::new(ctx),
            price,
            is_by_side,
            init_quantity,
            cur_quantity,
            user,
        }
    }

    fun create_new_entry(order: Order, limit_id: ID, is_by_side: bool, clock: &Clock, ctx: &mut TxContext): Entry {
        Entry {
            id: object::new(ctx),
            is_by_side,
            current: order,
            parent_limit: limit_id,
            timestamp_ms: clock::timestamp_ms(clock),
            next: option::none(),
            prev: option::none()
        }
    }

   
    fun add_bid_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderbook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, clock: &Clock, price: u64, ctx: &mut TxContext) {
        add_order(&mut orderbook.bids, &mut orderbook.bid_limits, limit, is_by_side, order, clock, ctx);
        match(orderbook, clock, price, ctx);
    }

    fun add_ask_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderbook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, clock: &Clock, price: u64, ctx: &mut TxContext) {
        add_order(&mut orderbook.asks, &mut orderbook.ask_limits, limit, is_by_side, order, clock, ctx);
        match(orderbook, clock, price, ctx);
    }

    fun add_order(entries: &mut vector<Entry>, limits: &mut Table<u64, Limit>, limit: Limit, is_by_side: bool, order: Order, clock: &Clock,ctx: &mut TxContext) {
        let new_entry = create_new_entry(order, object::id(&limit), is_by_side, clock, ctx);
        if(table::contains(limits, limit.price)) {
            let existing_limit = table::borrow_mut(limits, limit.price);
           
            let tail_proxy_vec_idx = get_idx<Entry>(entries, option::borrow(&existing_limit.tail));
            let tail_proxy = vector::borrow_mut(entries, tail_proxy_vec_idx);
            new_entry.prev = option::some(object::id(tail_proxy));
            tail_proxy.next = option::some(object::id(&new_entry));
            existing_limit.tail = option::some(object::id(&new_entry));

         
            delete_limit(limit);
        } else {
            limit.head = option::some(object::id(&new_entry));
            limit.tail = option::some(object::id(&new_entry));
            table::add(limits, limit.price, limit);
        };

        vector::push_back(entries, new_entry);
    }

    fun join_balance_or_insert<T>(asset_to_transfer: &mut VecMap<address, Balance<T>>, user: address, asset_to_change: Balance<T>) {
        if(vec_map::contains(asset_to_transfer, &user)) {
            let user_balance = vec_map::get_mut(asset_to_transfer, &user);
            balance::join(user_balance, asset_to_change);
        } else {
            vec_map::insert(asset_to_transfer, user, asset_to_change);
        };
    }

    fun fill_with_zero_quantity_orders(entries: &mut vector<Entry>, limits: &mut VecSet<u64>) {
        let count = 0;
        while(count < vector::length(entries)) {
            if(vector::borrow(entries, count).current.cur_quantity == 0) {
                if(!vec_set::contains(limits, &vector::borrow(entries, count).current.price)) {
                    vec_set::insert(limits, vector::borrow(entries, count).current.price); 
                }
            };
            
            count = count + 1;
        };
    }

    fun transfer_all<T>(asset_transfer: &mut VecMap<address, Balance<T>>, is_bid: bool, clock: &Clock, price: u64, orderbook_id: &UID, ctx: &mut TxContext) {
        let x = 0;
        let asset_len = vec_map::size(asset_transfer);
        while(x < asset_len) {
            let (recepient, asset_to_transfer) = vec_map::pop(asset_transfer);
            let amount = balance::value(&asset_to_transfer);
            event::emit(OrderMatchedEvent {
                orderbook: object::uid_to_inner(orderbook_id),
                is_bid,
                timestamp_ms: clock::timestamp_ms(clock),
                price,
                amount,
            });
            public_transfer(coin::from_balance<T>(asset_to_transfer, ctx), recepient);
            x = x + 1;
        }; 
    }

    fun delete_order_butch(ask_orders_to_delete: vector<ID>, entries: &mut vector<Entry>) {
        let h = 0;
        while(h < vector::length(&ask_orders_to_delete)) {
            let order_id = vector::borrow(&ask_orders_to_delete, h);
            let ask_order_to_delete_idx = get_idx_opt<Entry>(entries, order_id);
            let entry = vector::remove(entries, *option::borrow(&ask_order_to_delete_idx));

            delete_orderbook_entry(entry);
            h = h + 1;
        }
    }

    fun delete_limit_butch(limits_to_delete: vector<u64>, limits: &mut Table<u64, Limit>) {
        let y = 0;
        while(y < vector::length(&limits_to_delete)) {
            let limit = table::remove(limits, *vector::borrow(&limits_to_delete, y));
            delete_limit(limit);
            y = y + 1;
        };
    }

    fun delete_limit(limit: Limit) {
        let Limit {
            id,
            price: _,
            head: _,
            tail: _,
        } = limit;
        object::delete(id);
    }

    fun delete_order(order: Order) {
        let Order {
            id,
            price: _,
            is_by_side: _,
            init_quantity: _,
            cur_quantity: _,
            user: _,
        } = order;
        object::delete(id);  
    }

    fun delete_orderbook_entry(entry: Entry) {
        let Entry {
            id,
            current,
            is_by_side: _,
            parent_limit: _,
            timestamp_ms: _,
            next: _,
            prev: _,
        } = entry;
        object::delete(id);
        delete_order(current);
    }
    
    fun get_idx_from_entries(id: Option<ID>, entries: &mut vector<Entry>): Option<u64> {
        if(option::is_none(&id)) {
            option::none()
        } else {
            get_idx_opt<Entry>(entries, option::borrow(&id))
        }
    }

    fun get_current_entry_idx(entries: &mut vector<Entry>, count: u64, limits: &mut Table<u64, Limit>): Option<u64> {
        let parent_bid_limit_price = vector::borrow(entries, count).current.price;
        let parent_bid_limit = table::borrow_mut(limits, parent_bid_limit_price);

        get_idx_opt<Entry>(entries, option::borrow(&parent_bid_limit.head))
    }

    fun match<AssetA, AssetB>(orderbook: &mut Orderbook<AssetA, AssetB>, clock: &Clock, price: u64, ctx: &mut TxContext) {
        sort_vec(&mut orderbook.asks);
        sort_vec(&mut orderbook.bids);
        vector::reverse(&mut orderbook.bids);
        
        let bids_count = 0;
        let asks_count = 0;

        if(vector::length(&orderbook.bids) == 0 || vector::length(&orderbook.asks) == 0) {
            return
        };
        
        while (bids_count < vector::length(&orderbook.bids) && asks_count < vector::length(&orderbook.asks)) {
            let bid = vector::borrow(&orderbook.bids, bids_count);
            let ask = vector::borrow(&orderbook.asks, asks_count);
           
            if(bid.current.price < ask.current.price) {
                break
            };
            
            let curr_bid_idx = get_current_entry_idx(&mut orderbook.bids, bids_count, &mut orderbook.bid_limits);
            let curr_ask_idx = get_current_entry_idx(&mut orderbook.asks, asks_count, &mut orderbook.ask_limits);
           
            while(option::is_some(&curr_bid_idx) && option::is_some(&curr_ask_idx)) {
                let curr_bid = vector::borrow_mut(&mut orderbook.bids, *option::borrow(&curr_bid_idx));
                let curr_ask = vector::borrow_mut(&mut orderbook.asks, *option::borrow(&curr_ask_idx));
                debug::print(table::borrow(&mut orderbook.asset_a, curr_ask.current.user));
                if(curr_ask.current.cur_quantity == 0 || curr_bid.current.cur_quantity == 0) {
                    continue
                };

                let ask_quintity_in_bid_value = 0;

                if(curr_ask.current.price >= 1_000_000_000) {
                    ask_quintity_in_bid_value = curr_ask.current.cur_quantity * (curr_ask.current.price / 1_000_000_000);
                } else {
                     ask_quintity_in_bid_value = curr_ask.current.cur_quantity * curr_ask.current.price / 1_000_000_000;
                };
                debug::print(&ask_quintity_in_bid_value);
                assert!(&ask_quintity_in_bid_value != &0, 999);

                // debug::print(&11111);
                // debug::print(&curr_bid.current.cur_quantity);
                // debug::print(&curr_ask.current.cur_quantity);
                // debug::print(&curr_ask.current.price);
                // debug::print(&ask_quintity_in_bid_value);
                // debug::print(&11112);

                if(curr_bid.current.cur_quantity == ask_quintity_in_bid_value) {
                    debug::print(&11);
                    
                    let bidder_b_wallet = table::borrow_mut(&mut orderbook.asset_b, curr_bid.current.user);
                      
                    let bidder_b_asset = ask_quintity_in_bid_value; 
                    let asker_a_wallet = table::borrow_mut(&mut orderbook.asset_a, curr_ask.current.user);
                  
                    assert!(balance::value(bidder_b_wallet) >= bidder_b_asset && balance::value(asker_a_wallet) >= curr_ask.current.cur_quantity, 123);
                    join_balance_or_insert<AssetB>(&mut orderbook.asset_b_tmp, curr_ask.current.user, balance::split(bidder_b_wallet, bidder_b_asset));
                    join_balance_or_insert<AssetA>(&mut orderbook.asset_a_tmp, curr_bid.current.user, balance::split(asker_a_wallet, curr_ask.current.cur_quantity));
                    
                    curr_bid.current.cur_quantity = 0;
                    curr_ask.current.cur_quantity = 0;
                    curr_bid_idx = get_idx_from_entries(curr_bid.next, &mut orderbook.bids);
                    curr_ask_idx = get_idx_from_entries(curr_ask.next, &mut orderbook.asks);
                    
                    bids_count = bids_count + 1; 
                    asks_count = asks_count + 1; 
                } else if(
                    curr_bid.current.cur_quantity > ask_quintity_in_bid_value
                ) {  
                    debug::print(&22);
                    let bidder_b_wallet = table::borrow_mut(&mut orderbook.asset_b, curr_bid.current.user);
                    let bidder_b_asset = ask_quintity_in_bid_value;
                    let asker_a_wallet = table::borrow_mut(&mut orderbook.asset_a, curr_ask.current.user);
                  
                    assert!(balance::value(bidder_b_wallet) >= bidder_b_asset && balance::value(asker_a_wallet) >= curr_ask.current.cur_quantity, 124);
                    join_balance_or_insert<AssetB>(&mut orderbook.asset_b_tmp, curr_ask.current.user, balance::split(bidder_b_wallet, bidder_b_asset));
                    join_balance_or_insert<AssetA>(&mut orderbook.asset_a_tmp, curr_bid.current.user, balance::split(asker_a_wallet, curr_ask.current.cur_quantity));
                    
                    curr_bid.current.cur_quantity = curr_bid.current.cur_quantity - ask_quintity_in_bid_value;
                    curr_ask.current.cur_quantity = 0;
                    curr_ask_idx = get_idx_from_entries(curr_ask.next, &mut orderbook.asks);

                    asks_count = asks_count + 1;
                } else {
                    debug::print(&33);
                    let bidder_b_wallet = table::borrow_mut(&mut orderbook.asset_b, curr_bid.current.user);
                    
                    let bidder_b_asset = curr_bid.current.cur_quantity / 1_000_00 * curr_ask.current.price / curr_bid.current.price * 1_000_00; // todo make sure that 5 zeroes always exist and need to check that result of dividing not equal zero
                    assert!(&bidder_b_asset != &0, 999);
                    
                    let asker_a_wallet = table::borrow_mut(&mut orderbook.asset_a, curr_ask.current.user);
                    
                    let ask_value_in_bid_quantity = 0;

                    if(curr_bid.current.price >= 1_000_000_000) {
                        ask_value_in_bid_quantity = curr_bid.current.cur_quantity / (curr_bid.current.price / 1_000_000_000);
                    } else {
                        ask_value_in_bid_quantity = curr_bid.current.cur_quantity * 1_000_000_000 / curr_bid.current.price;
                    };

                    assert!(&ask_value_in_bid_quantity != &0, 999);
                    assert!(balance::value(bidder_b_wallet) >= curr_bid.current.cur_quantity &&  balance::value(asker_a_wallet) >= ask_value_in_bid_quantity, 125);
                    
                    let asset_b_to_change = balance::split(bidder_b_wallet, bidder_b_asset);
                    let asset_a_to_change = balance::split(asker_a_wallet, ask_value_in_bid_quantity);

                    join_balance_or_insert<AssetB>(&mut orderbook.asset_b_tmp, curr_ask.current.user, asset_b_to_change);
                    join_balance_or_insert<AssetA>(&mut orderbook.asset_a_tmp, curr_bid.current.user, asset_a_to_change);

                    if((curr_bid.current.cur_quantity - bidder_b_asset) > 0) {
                        let asset_b_to_return = balance::split(bidder_b_wallet, curr_bid.current.cur_quantity - bidder_b_asset);
                        join_balance_or_insert<AssetB>(&mut orderbook.asset_b_tmp, curr_bid.current.user, asset_b_to_return);
                    };
                   
                    curr_ask.current.cur_quantity = curr_ask.current.cur_quantity - ask_value_in_bid_quantity;
                    curr_bid.current.cur_quantity = 0;
                    curr_bid_idx = get_idx_from_entries(curr_bid.next, &mut orderbook.bids);
                    bids_count = bids_count + 1; // new add
                }
            };    

            transfer_all<AssetA>(&mut orderbook.asset_a_tmp, false, clock, price, &orderbook.id, ctx);
            transfer_all<AssetB>(&mut orderbook.asset_b_tmp, true, clock, price, &orderbook.id, ctx);
        };
        
        let bid_limits_vec = vec_set::empty<u64>();
        let ask_limits_vec = vec_set::empty<u64>();

        let bid_limits_to_delete = vector::empty<u64>();
        let bid_orders_to_delete = vector::empty<ID>();

        let ask_limits_to_delete = vector::empty<u64>();
        let ask_orders_to_delete = vector::empty<ID>();
      
        fill_with_zero_quantity_orders(&mut orderbook.bids, &mut bid_limits_vec);
        fill_with_zero_quantity_orders(&mut orderbook.asks, &mut ask_limits_vec);
        collect_limits_and_to_delete(&mut orderbook.bids,&mut orderbook.bid_limits, &mut bid_limits_to_delete, &mut bid_orders_to_delete, bid_limits_vec);
        collect_limits_and_to_delete(&mut orderbook.asks,&mut orderbook.ask_limits, &mut ask_limits_to_delete, &mut ask_orders_to_delete, ask_limits_vec);
        delete_limit_butch(bid_limits_to_delete, &mut orderbook.bid_limits);
        delete_limit_butch(ask_limits_to_delete, &mut orderbook.ask_limits);
        delete_order_butch(bid_orders_to_delete, &mut orderbook.bids);
        delete_order_butch(ask_orders_to_delete, &mut orderbook.asks);
    }

    fun collect_limits_and_to_delete(entries: &mut vector<Entry>, limits: &mut Table<u64, Limit>, limits_to_delete: &mut vector<u64>, entires_to_delete: &mut vector<ID>, limits_vec: VecSet<u64>) {
         let p = 0; 
        while (p < vec_set::size(&limits_vec)) {
            let limit_price = vector::borrow(&vec_set::into_keys(limits_vec), p);
            let limit = table::borrow_mut(limits, *limit_price);
        let run_bid_limit = true;
            while(run_bid_limit) {
                if(option::is_some<ID>(&limit.head)) {
                    let order_idx = get_idx_opt<Entry>(entries, option::borrow(&limit.head));
                    
                    let order = vector::borrow_mut(entries, *option::borrow(&order_idx));
                    let order_id = object::id(order);
                    if(order.current.cur_quantity == 0) {
                        if(option::is_some(&order.prev)) {
                            // "Error, order can not have prev"
                        };
                       
                        if(option::is_some(&order.next)) {
                            limit.head = order.next;
                            let next_order_idx = get_idx_opt<Entry>(entries, option::borrow(&order.next));
                            let next_order = vector::borrow_mut(entries, *option::borrow(&next_order_idx));
                            next_order.prev = option::none();
                        } else if (option::is_some(&limit.tail) && option::borrow(&limit.head) == option::borrow(&limit.tail)) {
                            vector::push_back(limits_to_delete, *limit_price);
                            
                            run_bid_limit = false;
                        };
                        
                        let get_index_to_check_should_not_exist = get_idx_opt_plain<ID>(entires_to_delete, &order_id);
                        
                        if(option::is_none(&get_index_to_check_should_not_exist)) {
                            vector::push_back(entires_to_delete, order_id);
                        }
                        
                    } else {
                        run_bid_limit = false;
                    }
                }
                
            };
               p = p + 1;
        };
    }

    public fun sort_vec(elems: &mut vector<Entry>) {
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

    fun get_idx<K: key + store>(self: &vector<K>, key: &ID): u64 {
        let i = 0;
        let n = vector::length(self);
        while (i < n) {
            let elem = vector::borrow(self, i);
            if (&object::id(elem) == key) {
               break
            };
            i = i + 1;
        };
        assert!(i < n, 0);
        i
    }

    fun get_idx_opt_plain<K>(self: &vector<ID>, key: &ID): Option<u64> {
        let i = 0;
        let n = vector::length(self);
        while (i < n) {
            let elem = vector::borrow(self, i);
            if (elem == key) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    public fun get_length_fields<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>):(u64,u64,u64,u64, u64,u64, u64, u64) {
        return (
            vector::length<Entry>(&orderbook.bids),
            vector::length<Entry>(&orderbook.asks),
            table::length<u64, Limit>(&orderbook.bid_limits),
            table::length<u64, Limit>(&orderbook.ask_limits),
            table::length<address, Balance<AssetA>>(&orderbook.asset_a),
            table::length<address, Balance<AssetB>>(&orderbook.asset_b),
            vec_map::size<address, Balance<AssetA>>(&orderbook.asset_a_tmp),
            vec_map::size<address, Balance<AssetB>>(&orderbook.asset_b_tmp),
        )
    }

    public fun get_bid_wallet_amount<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, ctx: &mut TxContext): u64 {
        if(table::contains(&orderbook.asset_b, tx_context::sender(ctx))) {
            return balance::value(table::borrow(&orderbook.asset_b, tx_context::sender(ctx)))
        } else {
            return 0_u64
        }
    }

    public fun get_ask_wallet_amount<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, ctx: &mut TxContext): u64 {
        if(table::contains(&orderbook.asset_a, tx_context::sender(ctx))) {
            return balance::value(table::borrow(&orderbook.asset_a, tx_context::sender(ctx)))
        } else {
            return 0_u64
        }
    }

    public fun get_bid_order_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, index: u64): (ID, u64, Option<ID>, Option<ID>, u64, u64,u64, address) {
        let obEntry = vector::borrow(&orderbook.bids, index);

        return (
            object::uid_to_inner(&obEntry.id),
            obEntry.current.price,
            obEntry.next,
            obEntry.prev,
            obEntry.current.price,
            obEntry.current.init_quantity,
            obEntry.current.cur_quantity,
            obEntry.current.user,
        )
    }

    public fun get_ask_order_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, index: u64): (ID, u64, Option<ID>, Option<ID>, u64, u64,u64, address) {
        let obEntry = vector::borrow(&orderbook.asks, index);

        return (
            object::uid_to_inner(&obEntry.id),
            obEntry.current.price,
            obEntry.next,
            obEntry.prev,
            obEntry.current.price,
            obEntry.current.init_quantity,
            obEntry.current.cur_quantity,
            obEntry.current.user,
        )
    }

    public fun get_bid_limit_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, id: u64): (u64, Option<ID>, Option<ID>) {
        let limit = table::borrow(&orderbook.bid_limits, id);
        return (
            limit.price,
            limit.head,
            limit.tail,
        )
    }

    public fun get_ask_limit_info<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, id: u64): (u64, Option<ID>, Option<ID>) {
        let limit = table::borrow(&orderbook.ask_limits, id);
        return (
            limit.price,
            limit.head,
            limit.tail,
        )
    }

    #[test_only]
    public fun get_user_balance<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, theguy: address): u64 {
        let user_balance = table::borrow(&orderbook.asset_b, theguy);
        
        return balance::value(user_balance)
    }

    #[test_only]
    public fun get_user_asset_a_balance<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>, theguy: address): u64 {
        let user_balance = table::borrow(&orderbook.asset_a, theguy);
        
        return balance::value(user_balance)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun test<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>) {
        // debug::print(vector::borrow(&orderbook.bids, 0));
        debug::print(orderbook);
        // debug::print(table::borrow(&orderbook.bid_limits, 309));
    }

    #[test_only]
    public fun print_bid_limits<AssetA, AssetB>(orderbook: &Orderbook<AssetA, AssetB>) {
        debug::print(&orderbook.bid_limits);
    }
}