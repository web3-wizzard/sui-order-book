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
        current: Order,
        parent_limit: Option<T>, // Limit
        next: Option<K>, // OrderbookEntry
        previous: Option<K> // OrderbookEntry
    }

    struct Limit<T: key + store> has key, store, drop {
        id: UID,
        price: u64,
        head: Option<T>, // OrderbookEntry
        tail: Option<T>, // OrderbookEntry
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

    public entry fun create_orderbook<K: key + store, T: key + store + drop> (
        _: &OrderbookManagerCap, ctx: &mut TxContext
    ) {
        publish<K,T>(ctx)
    }

    fun publish<K: key + store, T: key + store + drop> (ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Orderbook{
            id, 
            orders: table::new<u64, OrderbookEntry<K, T>>(ctx), 
            bid_limits: vec_set::empty(), 
            ask_limits: vec_set::empty(), 
        })
    }

    public entry fun add_order<K: key + store, T: key + store + drop>(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, orderBook: Orderbook<K, T>, ctx: &mut TxContext) {
        let base_limit = create_limit<T>(price, ctx);
        let order = create_order(price, is_by_side, initial_quantity, current_quantity, user, ctx);
        if(order.is_by_side) {
            add_order_to_orderbook<K, T>(order, base_limit, orderBook.bid_limits, &orderBook.orders, ctx);
        } else {
            add_order_to_orderbook<K, T>(order, base_limit, orderBook.ask_limits, &orderBook.orders, ctx);
        }
    }

    fun create_limit<T: key + store> (price: u64, ctx: &mut TxContext): Limit<T> {
        Limit {
            id: object::new(ctx),
            price,
            head: option::none<T>(),
            tail: option::none<T>(),
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

    // fun create_orderbook_entry<K: key + store, T: key + store>(order: Order, base_limit: Limit<T>, ctx: &mut TxContext): OrderbookEntry<K,T> {
    //     OrderbookEntry {
    //         id: object::new(ctx),
    //         current: order,
    //         parent_limit: option::some(base_limit),
    //         next: option::none(),
    //         previous: option::none()
    //     }
    // }

    fun add_order_to_orderbook<K: key + store, T: key + store + drop>(order: Order, base_limit: Limit<T>, limit_levels: VecSet<ID>, orders: &Table<u64, OrderbookEntry<K, T>>, ctx: &mut TxContext) {
        let new_entry = OrderbookEntry<K, Limit<T>> {
            id: object::new(ctx),
            current: order,
            parent_limit: option::some(base_limit),
            next: option::none(),
            previous: option::none()
        };

        let limit: &mut Limit<T> = &mut base_limit;
        limit.head = option::some(new_entry);
        limit.tail = option::some(new_entry);
    }
}