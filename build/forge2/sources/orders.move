module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use std::vector::{Self};
    use sui::table::{Self, Table};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, split};
    use sui::coin::{Self, Coin, join};

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
    public entry fun add_bid_order<AssetA, AssetB>(price: u64, user: address, orderBook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetA>,ctx: &mut TxContext) {
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
            object::delete(id)
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
                bids_count= vector::length(&orderBook.bids);
                asks_count= vector::length(&orderBook.asks);
                break
            };
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
}