module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};

    struct OrderbookManagerCap has key, store { id: UID }

    struct OrderbookEntry<K: key + store, T: key + store> has key, store {
        id: UID,
        date_time: u64,
        parent_limit: Option<T>, // Limit
        next: Option<K>, // OrderbookEntry
        previous: Option<K> // OrderbookEntry
    }

    struct Limit<K: key + store> has key, store {
        id: UID,
        price: u64,
        head: Option<K>, // OrderbookEntry
        tail: Option<K>, // OrderbookEntry
    }

    struct Order has key, store{
        id: UID,
        price: u64,
        is_by_side: bool,
        initial_quantity: u64,
        current_quantity: u64,
        user: address,
    }

    struct Orderbook<K: key + store, T: key + store> has key, store {
        id: UID,
        orders: Table<u64, OrderbookEntry<K, T>>, // K OrderbookEntry //T Limit
        bid_limits: VecSet<ID>,
        ask_limits: VecSet<ID>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(OrderbookManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    public entry fun create_orderbook<K: key + store, T: key + store> (
        _: &OrderbookManagerCap, ctx: &mut TxContext
    ) {
        publish<K,T>(ctx)
    }

    fun publish<K: key + store, T: key + store> (ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Orderbook{
            id, 
            orders: table::new<u64, OrderbookEntry<K, T>>(ctx), 
            bid_limits: vec_set::empty(), 
            ask_limits: vec_set::empty(), 
        })
    }

    // public entry fun add_order<K: key + store>(price: u64, ctx: &mut TxContext) {
    //     let base_limit = create_limit<K>(price, ctx);
    //     add_order()
    // }

    fun create_limit<K: key + store> (price: u64, ctx: &mut TxContext): Limit<K> {
        Limit {
            id: object::new(ctx),
            price,
            head: option::none<K>(),
            tail: option::none<K>(),
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
}