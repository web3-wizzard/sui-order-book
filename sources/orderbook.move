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

    struct OrderbookManagerCap has key, store { id: UID }

    struct Entry has key, store {
        id: UID,
        current: Order,
        is_by_side: bool,
        parent_limit: ID,
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
    public entry fun add_bid_order<AssetA, AssetB>(price: u64, orderbook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetB>,ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);
        
        let coin_balance = coin::into_balance(coin);
        let coin_value = balance::value(&coin_balance);
       
        let order = create_order(price, true, coin_value, coin_value, tx_context::sender(ctx), ctx);
        
        let balance = borrow_mut_account_balance<AssetB>(&mut orderbook.asset_b, tx_context::sender(ctx));
        balance::join(balance, coin_balance);
        
        add_bid_order_to_orderbook(order, base_limit, orderbook, true, ctx);
    }

    public entry fun add_ask_order<AssetA, AssetB>(price: u64, orderbook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetA>,ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);

        let coin_balance = coin::into_balance(coin);
        let coin_value = balance::value(&coin_balance);

        let order = create_order(price, false, coin_value, coin_value, tx_context::sender(ctx), ctx);

        let balance = borrow_mut_account_balance<AssetA>(&mut orderbook.asset_a, tx_context::sender(ctx));
        balance::join(balance, coin_balance);
        
        add_ask_order_to_orderbook(order, base_limit, orderbook, false, ctx);
    }


    public entry fun remove_bid_order<AssetA, AssetB>(entryID: ID, orderbook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        remove_order<AssetB>(&mut orderbook.bids, entryID,&mut orderbook.asset_b,ctx, &mut orderbook.bid_limits);
    }

     public entry fun remove_ask_order<AssetA, AssetB>(entryID: ID, orderbook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        remove_order<AssetA>(&mut orderbook.asks, entryID,&mut orderbook.asset_a,ctx, &mut orderbook.ask_limits);
    }

  fun remove_order<T>(entries: &mut vector<Entry>, entryID: ID, asset: &mut Table<address, Balance<T>>, ctx: &mut TxContext, limits: &mut Table<u64, Limit>) {
         let ob_entry_idx = get_idx_opt<Entry>(entries, &entryID);

        if(option::is_none(&ob_entry_idx)) {
            // throw error
        };
    
        deal_with_location_of_removable_orderboor_entry(entries, ob_entry_idx);

        let entry = vector::borrow(entries, *option::borrow(&ob_entry_idx));

        if(&entry.current.user != &tx_context::sender(ctx)) {
            // return error
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

    fun create_new_entry(order: Order, limit_id: ID, is_by_side: bool, ctx: &mut TxContext): Entry {
        Entry {
            id: object::new(ctx),
            is_by_side,
            current: order,
            parent_limit: limit_id,
            next: option::none(),
            prev: option::none()
        }
    }

   
    fun add_bid_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderbook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, ctx: &mut TxContext) {
        add_order(&mut orderbook.bids, &mut orderbook.bid_limits, limit, is_by_side, order, ctx);
        match(orderbook, ctx);
    }

    fun add_ask_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderbook: &mut Orderbook<AssetA, AssetB>,is_by_side: bool, ctx: &mut TxContext) {
        add_order(&mut orderbook.asks, &mut orderbook.ask_limits, limit, is_by_side, order, ctx);
        match(orderbook, ctx);
    }

    fun add_order(entries: &mut vector<Entry>, limits: &mut Table<u64, Limit>, limit: Limit, is_by_side: bool, order: Order,ctx: &mut TxContext) {
        let new_entry = create_new_entry(order, object::id(&limit), is_by_side, ctx);
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

    fun transfer_all<T>(asset_transfer: &mut VecMap<address, Balance<T>>, ctx: &mut TxContext) {
        let x = 0;
        let asset_a_len = vec_map::size(asset_transfer);
        while(x < asset_a_len) {
            let (recepient, asset_to_transfer) = vec_map::pop(asset_transfer);
                
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

    fun match<AssetA, AssetB>(orderbook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
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

                let ask_quintity_in_bid_value = 0;

                if(curr_ask.current.price >= 1_000_000_000) {
                    ask_quintity_in_bid_value = curr_ask.current.cur_quantity * (curr_ask.current.price / 1_000_000_000);
                } else {
                     ask_quintity_in_bid_value = curr_ask.current.cur_quantity * (1_000_000_000 / curr_ask.current.price);
                };

                if(curr_bid.current.cur_quantity == ask_quintity_in_bid_value) {
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
                    let bidder_b_wallet = table::borrow_mut(&mut orderbook.asset_b, curr_bid.current.user);
                    
                    let bidder_b_asset = curr_bid.current.cur_quantity - (curr_bid.current.cur_quantity - (curr_bid.current.cur_quantity / curr_bid.current.price * curr_ask.current.price));
                    let asker_a_wallet = table::borrow_mut(&mut orderbook.asset_a, curr_ask.current.user);
                    
                    
                    let ask_value_in_bid_quantity = 0;

                    if(curr_bid.current.price >= 1_000_000_000) {
                        ask_value_in_bid_quantity = curr_bid.current.cur_quantity / (curr_bid.current.price / 1_000_000_000);
                    } else {
                        ask_value_in_bid_quantity = curr_bid.current.cur_quantity * (1_000_000_000 / curr_bid.current.price);
                    };
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

            transfer_all<AssetA>(&mut orderbook.asset_a_tmp, ctx);
            transfer_all<AssetB>(&mut orderbook.asset_b_tmp, ctx);
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

#[test_only]
module orderbookmodule::orders_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{mint_for_testing as mint};
    use orderbookmodule::orders::{Self, OrderbookManagerCap, Orderbook};
    use std::option::{Self};
    use std::debug;
    use sui::coin::{Self, Coin};
    use sui::transfer;

    struct ASSET_A {}
    struct ASSET_B {}

    #[test] fun test_init_orderbook() {
        let scenario = scenario();
        test_init_orderbook_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_add_order() {
        let scenario = scenario();
        test_add_bid_order_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_remove_order() {
        let scenario = scenario();
        test_remove_order_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_add_ask() {
        let scenario = scenario();
        test_add_ask_order_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_remove_ask() {
        let scenario = scenario();
        test_remove_ask_order_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_one_bid_ask_match() {
        let scenario = scenario();
        test_one_bid_ask_match_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_one_exact_bid_ask_match() {
        let scenario = scenario();
        test_one_exact_bid_ask_match_(&mut scenario);
        test::end(scenario);
    }

     #[test] fun test_one_exact_bid_ask_match_with_low_value() {
        let scenario = scenario();
        test_one_exact_bid_ask_match_with_low_value_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_one_exact_ask_bid_match() {
        let scenario = scenario();
        test_one_exact_ask_bid_match_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_another_bid_ask_match() {
        let scenario = scenario();
        test_another_bid_ask_match_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_ask_bids_match() {
        let scenario = scenario();
        test_ask_bids_match_(&mut scenario);
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
            orders::create_orderbook<ASSET_A, ASSET_B>(&witness, ctx(test));
            test::return_to_sender(test, witness);
        };

        next_tx(test, owner);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
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

    fun test_add_bid_order_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, theguy, _, _, _) = people();

        next_tx(test, theguy);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
           
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 10, ctx(test)), ctx(test));
            
            let theguy_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(theguy_wallet_amount == 309_000_000_000_0, 0);

            let (orderbook_entry_id, parent_limit_price,next,prev,price,init_quantity,cur_quantity,user) = orders::get_bid_order_info(&orderbook, 0);
           
            assert!(option::is_none(&next), 0);
            assert!(option::is_none(&prev), 0);
            assert!(price == 309 * 1_000_000_000, 0);
            assert!(init_quantity == 309_000_000_000_0,0);
            assert!(cur_quantity == 309_000_000_000_0,0);
            assert!(user == theguy, 0);

            // todo parent_limit_price is the same as price
            let (price, head, tail) = orders::get_bid_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit_price);
            assert!(price == 309 * 1_000_000_000, 0);
            assert!(head == option::some(orderbook_entry_id), 0);
            assert!(tail == option::some(orderbook_entry_id), 0);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

            assert!(bids_len == 1, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 1, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_b_len == 1, 0);
            assert!(asset_a_len == 0, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_remove_order_(test: &mut Scenario) {
        test_add_bid_order_(test);

         let (_, theguy,_, _, _) = people();

        next_tx(test, theguy);

        {
        let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
        
        let (orderbook_entry_id, _parent_limit,_next,_prev,_price,_init_quantity,_cur_quantity,_user) = orders::get_bid_order_info(&orderbook, 0);
        orders::remove_bid_order(orderbook_entry_id, &mut orderbook, ctx(test));
       
        test::return_shared(orderbook);
        };

         next_tx(test, theguy);

        {
             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            let the_guy_balance = orders::get_user_balance(&orderbook, theguy);
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_b_len == 1, 0);
            assert!(the_guy_balance == 0, 0);
            assert!(asset_a_len == 0, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_add_ask_order_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, _, thegirl, _, _) = people();

        next_tx(test, thegirl);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
           
            orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 10, ctx(test)), ctx(test));
            
            let thegirl_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            
            assert!(thegirl_wallet_amount == 10_000_000_000, 0);

            // todo parent_limit_price is the same as price
            let (orderbook_entry_id, parent_limit_price,next,prev,price,init_quantity,cur_quantity,user) = orders::get_ask_order_info(&orderbook, 0);
           
            assert!(option::is_none(&next), 0);
            assert!(option::is_none(&prev), 0);
            assert!(price == 309 * 1_000_000_000, 0);
            assert!(init_quantity == 10_000_000_000,0);
            assert!(cur_quantity == 10_000_000_000,0);
            assert!(user == thegirl, 0);

            let (price, head, tail) = orders::get_ask_limit_info<ASSET_A, ASSET_B>(&orderbook, parent_limit_price);
            assert!(price == 309 * 1_000_000_000, 0);
            assert!(head == option::some(orderbook_entry_id), 0);
            assert!(tail == option::some(orderbook_entry_id), 0);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);

            assert!(bids_len == 0, 0);
            assert!(asks_len == 1, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 1, 0);
            assert!(asset_b_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_remove_ask_order_(test: &mut Scenario) {
        test_add_ask_order_(test);

         let (_, _,thegirl, _, _) = people();

        next_tx(test, thegirl);

        {
        let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
        
        let (orderbook_entry_id, _parent_limit,_next,_prev,_price,_init_quantity,_cur_quantity,_user) = orders::get_ask_order_info(&orderbook, 0);
        orders::remove_ask_order(orderbook_entry_id, &mut orderbook, ctx(test));
       
        test::return_shared(orderbook);
        };

         next_tx(test, thegirl);

        {
             let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            let the_girl_balance = orders::get_user_asset_a_balance(&orderbook, thegirl);
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_b_len == 0, 0);
            assert!(the_girl_balance == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            test::return_shared(orderbook);
        }
    }

    fun test_ask_bids_match_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, julia, alex) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 10, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };
        

        next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(308 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(308 * 1_000_000_000 * 5, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(307 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(307 * 1_000_000_000 * 1, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, julia);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(311 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 8, ctx(test)), ctx(test));
            test::return_shared(orderbook);    
        };

         next_tx(test, alex);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 12, ctx(test)), ctx(test));
           
            // orders::test(&orderbook);
            test::return_shared(orderbook);
      
        };

        // intermediate check 
        next_tx(test, alex);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            assert!(bids_len == 3, 0);
            assert!(asks_len == 1, 0);
            assert!(bid_limits_len == 3, 0);
            assert!(ask_limits_len == 1, 0);
            assert!(asset_a_len == 2, 0);
            assert!(asset_b_len == 2, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            let alex_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(alex_ask_wallet_amount == 0, 0);

            let alex_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(alex_bid_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            assert!(coin::value(&coin) == 3_708_000_000_000, 1);
            transfer::public_transfer(coin, alex);
           
            test::return_shared(orderbook);
        };

        // intermediate check 
        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let john_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(john_ask_wallet_amount == 0, 0);

            let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            // todo here wrong assertion
            assert!(john_ask_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 10_000_000_000, 1);
            transfer::public_transfer(coin, john);
           
            test::return_shared(orderbook);
        };

        // intermediate check 
        next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let ivan_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_ask_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 2_000_000_000, 1);
            transfer::public_transfer(coin, ivan);
           
            test::return_shared(orderbook);
        };

        next_tx(test, julia);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            orders::add_ask_order<ASSET_A, ASSET_B>(313 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, julia);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(315 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 2, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };


        next_tx(test, julia);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            orders::add_ask_order<ASSET_A, ASSET_B>(308 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 3, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        // intermediate check 
        next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            let ivan_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_bid_wallet_amount == 307_000_000_000, 0);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            
            assert!(coin::value(&coin) == 2_000_000_000, 1);
            transfer::public_transfer(coin, ivan);
        //    orders::test(&orderbook);
            test::return_shared(orderbook);
        };

        // // intermediate check 
        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
           
            assert!(john_bid_wallet_amount == 1_232_000_000_000, 0);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
         
            assert!(coin::value(&coin) == 1_000_000_000, 1);
            transfer::public_transfer(coin, ivan);
        
            test::return_shared(orderbook);
        };
        next_tx(test, alex);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(306 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        // // intermediate check 
        next_tx(test, alex);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let alex_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));

            assert!(alex_ask_wallet_amount == 0, 0);
            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            
            assert!(coin::value(&coin) == 1_224_000_000_000, 1); // todo aler alert probably in each next_tx asset a reset when public transfer if so than right but in real case it should be 3_708_000_000_000 + 1_224_000_000_000 
            transfer::public_transfer(coin, ivan);
        
            test::return_shared(orderbook);
        };

        // intermediate check 
        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            let john_bid_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
          
            assert!(john_bid_wallet_amount == 8_000_000_000, 0);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
         
            assert!(coin::value(&coin) == 4_000_000_000, 1); 
            transfer::public_transfer(coin, ivan);
        
            test::return_shared(orderbook);
        };

        // intermediate check 
        next_tx(test, julia);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            
            let julia_ask_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
          
            assert!(julia_ask_wallet_amount == 14_000_000_000, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            
            transfer::public_transfer(coin, ivan);
        
            test::return_shared(orderbook);
        };
    }

    fun test_one_bid_ask_match_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(306 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
            assert!(bids_len == 1, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 1, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_b_len == 1, 0);
             assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);
            
            let (_orderbook_entry_id, _parent_limit,next,prev,price,_init_quantity,cur_quantity,user) = orders::get_bid_order_info(&orderbook, 0);
           
            assert!(option::is_none(&next), 0);
            assert!(option::is_none(&prev), 0);
            assert!(price == 309 * 1_000_000_000, 0);
            assert!(cur_quantity == 12_000_000_000,0);
            assert!(user == john, 0);

            let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            assert!(coin::value(&coin) == 1_224_000_000_000, 1);
            transfer::public_transfer(coin, ivan);
            
            test::return_shared(orderbook);
        };

         next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 4_000_000_000, 1);
            transfer::public_transfer(coin, john);
            
      
            test::return_shared(orderbook);
        };
    }

    fun test_one_exact_bid_ask_match_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_b_len == 1, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            assert!(coin::value(&coin) == 1_236_000_000_000, 1);
            transfer::public_transfer(coin, ivan);

            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 0, 0);

            test::return_shared(orderbook);
        };

         next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 4_000_000_000, 1);
            transfer::public_transfer(coin, john);
            
            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 0, 0);
        
            test::return_shared(orderbook);
        };
    }

    fun test_one_exact_bid_ask_match_with_low_value_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(1_00_000_000, &mut orderbook, mint<ASSET_B>(1_00_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(1_00_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_b_len == 1, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            assert!(coin::value(&coin) == 1_00_000_000 * 4, 1);
            transfer::public_transfer(coin, ivan);

            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 0, 0);

            test::return_shared(orderbook);
        };

         next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 4_000_000_000, 1);
            transfer::public_transfer(coin, john);
            
            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 0, 0);
        
            test::return_shared(orderbook);
        };
    }

    fun test_one_exact_ask_bid_match_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 4, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

         next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let (bids_len, asks_len, bid_limits_len, ask_limits_len, asset_a_len, asset_b_len, asset_a_tmp_len, asset_b_tmp_len) = orders::get_length_fields<ASSET_A, ASSET_B>(&orderbook);
            
            assert!(bids_len == 0, 0);
            assert!(asks_len == 0, 0);
            assert!(bid_limits_len == 0, 0);
            assert!(ask_limits_len == 0, 0);
            assert!(asset_a_len == 1, 0);
            assert!(asset_b_len == 1, 0);
            assert!(asset_a_tmp_len == 0, 0);
            assert!(asset_b_tmp_len == 0, 0);

            let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            assert!(ivan_wallet_amount == 0, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
            assert!(coin::value(&coin) == 1_236_000_000_000, 1);
            transfer::public_transfer(coin, ivan);

            test::return_shared(orderbook);
        };

         next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
            assert!(coin::value(&coin) == 4_000_000_000, 1);
            transfer::public_transfer(coin, john);
            
            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 0, 0);
          
            test::return_shared(orderbook);
        };
    }

    fun test_another_bid_ask_match_(test: &mut Scenario) {
        test_init_orderbook_(test);

        let (_, john, ivan, _, _) = people();

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(309 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(309 * 1_000_000_000 * 1, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, ivan);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_ask_order<ASSET_A, ASSET_B>(310 * 1_000_000_000, &mut orderbook, mint<ASSET_A>(1_000_000_000 * 5, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, john);

        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);
            orders::add_bid_order<ASSET_A, ASSET_B>(311 * 1_000_000_000, &mut orderbook, mint<ASSET_B>(311 * 1_000_000_000 * 3, ctx(test)), ctx(test));
            test::return_shared(orderbook);
        };

        next_tx(test, john);
        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let john_wallet_amount = orders::get_bid_wallet_amount(&orderbook, ctx(test));
            assert!(john_wallet_amount == 309_000_000_000, 0);

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);
           
           assert!(coin::value(&coin) == 3_000_000_000, 1);
            transfer::public_transfer(coin, john);

            let coin = test::take_from_sender<Coin<ASSET_A>>(test);
           
            assert!(coin::value(&coin) == 3_000_000_000, 1);
            transfer::public_transfer(coin, john);
            
            test::return_shared(orderbook);
        };

        next_tx(test, ivan);
        {
            let orderbook = test::take_shared<Orderbook<ASSET_A, ASSET_B>>(test);

            let ivan_wallet_amount = orders::get_ask_wallet_amount(&orderbook, ctx(test));
            
            assert!(ivan_wallet_amount == 2_000_000_000, 0);
         

            let coin = test::take_from_sender<Coin<ASSET_B>>(test);

            assert!(coin::value(&coin) == 930_000_000_000, 1);
            transfer::public_transfer(coin, ivan);
            
            test::return_shared(orderbook);
        };
    }


    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address, address, address, address) { (@0xBEEF, @0x1337, @0xcafe, @0xA11CE, @0x2222) }
}