module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::tx_context::{Self, TxContext};

    struct OrderbookManagerCap has key, store { id: UID }

    struct OrderbookEntry has key, store {
        id: UID,
        current: Order,
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

    struct Orderbook has key, store {
        id: UID,
        orders: Table<ID, OrderbookEntry>,
        limits: Table<ID, Limit>,
        bid_limits: VecSet<ID>,
        ask_limits: VecSet<ID>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(OrderbookManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    public entry fun create_orderbook (
        _: &OrderbookManagerCap, ctx: &mut TxContext
    ) {
        publish(ctx)
    }

    fun publish(ctx: &mut TxContext) {
        let id = object::new(ctx);

        transfer::share_object(Orderbook{
            id, 
            orders: table::new<ID, OrderbookEntry>(ctx),
            limits: table::new<ID, Limit>(ctx),
            bid_limits: vec_set::empty(), 
            ask_limits: vec_set::empty(), 
        })
    }

    public entry fun add_order<K: drop + store>(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, orderBook: &mut Orderbook, ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);
        let order = create_order(price, is_by_side, initial_quantity, current_quantity, user, ctx);
        if(order.is_by_side) {
            add_order_to_orderbook(order, base_limit, orderBook.bid_limits,orderBook, ctx);
        } else {
            add_order_to_orderbook(order, base_limit, orderBook.ask_limits,orderBook, ctx);
        }
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

    fun create_new_entry(order: Order, limit_id: ID, ctx: &mut TxContext): OrderbookEntry {
        OrderbookEntry {
            id: object::new(ctx),
            current: order,
            parent_limit: limit_id,
            next: option::none(),
            previous: option::none()
        }
    }

    fun add_order_to_orderbook(order: Order, limit: Limit, limit_levels: VecSet<ID>, orderBook: &mut Orderbook, ctx: &mut TxContext) {
        if(vec_set::contains(&limit_levels, &object::id(&limit))) {
            let new_entry = create_new_entry(order, object::id(&limit), ctx);
            if(option::is_none(&limit.tail)) {
                limit.head = option::some(object::id(&new_entry));
                limit.tail = option::some(object::id(&new_entry));
            } else {
                let tail_proxy = table::borrow_mut(&mut orderBook.orders, *option::borrow(&limit.tail));
                new_entry.previous = option::some(object::id(tail_proxy));
                tail_proxy.next = option::some(object::id(&new_entry));
                limit.tail = option::some(object::id(&new_entry));
            };
            table::add(&mut orderBook.orders, object::id(&new_entry), new_entry);
             let Limit {
                id,
                price: _,
                head: _,
                tail: _,
            } = limit;
            object::delete(id)
        } else {
            let new_entry = create_new_entry(order, object::id(&limit), ctx);
            limit.head = option::some(object::id(&new_entry));
            limit.tail = option::some(object::id(&new_entry));
            table::add(&mut orderBook.limits, object::id(&limit), limit);
            table::add(&mut orderBook.orders, object::id(&new_entry), new_entry);
        };
    }
}