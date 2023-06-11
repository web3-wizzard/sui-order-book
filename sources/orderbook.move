module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};

    struct OrderbookManagerCap has key, store { id: UID }

    struct OrderbookEntry<K: drop + store, T: drop + store> has drop, store {
        current: Order,
        parent_limit: Option<T>, // Limit
        next: Option<K>, // OrderbookEntry
        previous: Option<K> // OrderbookEntry
    }

    struct Limit<K: drop + store> has store, drop {
        price: u64,
        head: Option<K>, // OrderbookEntry
        tail: Option<K>, // OrderbookEntry
    }

    struct Order has drop, store{
        price: u64,
        is_by_side: bool,
        initial_quantity: u64,
        current_quantity: u64,
        user: address,
    }

    struct Orderbook has key, store {
        id: UID,
        // orders: Table<u64, OrderbookEntry<K, T>>, // K OrderbookEntry //T Limit
        bid_limits: VecSet<ID>,
        ask_limits: VecSet<ID>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(OrderbookManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    public entry fun create_orderbook<K: drop + store, T: drop + store> (
        _: &OrderbookManagerCap, ctx: &mut TxContext
    ) {
        publish<K,T>(ctx)
    }

    fun publish<K: drop + store, T: drop + store> (ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Orderbook{
            id, 
            // orders: table::new<u64, OrderbookEntry<K, T>>(ctx), 
            bid_limits: vec_set::empty(), 
            ask_limits: vec_set::empty(), 
        })
    }

    public entry fun add_order<K: drop + store, T: drop + store>(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, orderBook: Orderbook<K, T>, ctx: &mut TxContext) {
        let base_limit = create_limit<K>(price);
        let order = create_order(price, is_by_side, initial_quantity, current_quantity, user);
        if(order.is_by_side) {
            add_order_to_orderbook<K, T>(order, base_limit, orderBook.bid_limits);
        } else {
            add_order_to_orderbook<K, T>(order, base_limit, orderBook.ask_limits);
        }
    }

    fun create_limit<K: drop + store> (price: u64): Limit<K> {
        Limit {
            price,
            head: option::none<K>(),
            tail: option::none<K>(),
        }
    }

    fun create_order(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address): Order {
        Order {
            price,
            is_by_side,
            initial_quantity,
            current_quantity,
            user,
        }
    }

    fun add_order_to_orderbook<K: drop + store, T: drop + store>(order: Order, base_limit: Limit<K>, limit_levels: VecSet<ID>) {
        let new_entry = OrderbookEntry<K, Limit<K>> {
            current: order,
            parent_limit: option::some(base_limit),
            next: option::none(),
            previous: option::none()
        };

        base_limit.head = option::some(new_entry);
        base_limit.tail = option::some(new_entry);
    }
}