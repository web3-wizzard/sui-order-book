module orderbookmodule::orders {
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::table::{Self, Table};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance, split};
    use sui::coin::{Self, Coin, join};

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

    struct Orderbook<phantom AssetA, phantom AssetB> has key, store {
        id: UID,
        orders: Table<ID, OrderbookEntry>,
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
            orders: table::new<ID, OrderbookEntry>(ctx),
            bid_limits: table::new<ID, Limit>(ctx),
            ask_limits: table::new<ID, Limit>(ctx),
            asset_a: table::new<address, Balance<AssetA>>(ctx),
            asset_b: table::new<address, Balance<AssetB>>(ctx),
        })
    }

    public entry fun add_bid_order<AssetA, AssetB>(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, orderBook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetA>,ctx: &mut TxContext) {
        let base_limit = create_limit(price, ctx);
        let order = create_order(price, is_by_side, initial_quantity, current_quantity, user, ctx);
        
        let balance = borrow_mut_account_balance<AssetA>(&mut orderBook.asset_a, tx_context::sender(ctx));
        balance::join(balance, coin::into_balance(coin));
        add_bid_order_to_orderbook(order, base_limit, orderBook, ctx);
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

    // public entry fun add_ask_order<AssetA, AssetB>(price: u64, is_by_side: bool, initial_quantity: u64, current_quantity: u64, user: address, orderBook: &mut Orderbook<AssetA, AssetB>, coin: Coin<AssetB>,ctx: &mut TxContext) {
    //     let base_limit = create_limit(price, ctx);
    //     let order = create_order(price, is_by_side, initial_quantity, current_quantity, user, ctx);
        
    //     add_ask_order_to_orderbook(order, base_limit, orderBook, ctx);
    // }

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

    fun add_bid_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderBook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        if(table::contains(&orderBook.bid_limits, object::id(&limit))) {
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
            table::add(&mut orderBook.bid_limits, object::id(&limit), limit);
            table::add(&mut orderBook.orders, object::id(&new_entry), new_entry);
        };
    }

    fun add_ask_order_to_orderbook<AssetA, AssetB>(order: Order, limit: Limit, orderBook: &mut Orderbook<AssetA, AssetB>, ctx: &mut TxContext) {
        if(table::contains(&orderBook.ask_limits, object::id(&limit))) {
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
            table::add(&mut orderBook.ask_limits, object::id(&limit), limit);
            table::add(&mut orderBook.orders, object::id(&new_entry), new_entry);
        };
    }
}