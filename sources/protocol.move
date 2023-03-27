module payment::protocol {
    use std::vector;
    use std::option::{Self, Option};
    use sui::transfer;
    use sui::coin::Coin;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use payment::fake_usdc;

    const EAlreadyLocked: u64 = 0;
    const ENotCorrectItem: u64 = 1;
    const EBillExpired: u64 = 2;

    const ISellerReject: vector<u8> = b"Seller rejects this bill!";

    struct Bill<T: key+store> has key, store {
        id: UID,
        buyer: address,
        seller: address,
        expire: u64,
        price: u64,
        itemID: ID,
        item: Option<T>,        // `T` is the type of the item
    }

    struct Reciept has key, store {
        id: UID,
        buyer: address,
        seller: address,
        itemID: ID,
        dealing_time: u64,
        dealing_price: u64,     // Pay in USDC
    }

    struct CanceledReciept has key, store {
        id: UID,
        buyer: address,
        seller: address,
        itemID: ID,
        failed_reason: vector<u8>,
    }

    struct LockedItems has key, store {
        id: UID,
        locked_objects: vector<ID>,        
    }

    fun get_current_timestamp(): u64 {      // This should be implement in Sui
        0
    }

    // Initialize the locked item vector
    fun init(ctx: &mut TxContext) {
        let lockedItems = LockedItems {
            id: object::new(ctx),
            locked_objects: vector::empty<ID>(),
        };
        transfer::share_object(lockedItems);
    }

    // 1. Buyer create the bill
    public entry fun create_bill<T: key+store>(itemID: ID, price: u64, seller: address, lockedItems: &mut LockedItems, ctx: &mut TxContext) {
        let bill = Bill<T> {
            id: object::new(ctx),
            buyer: tx_context::sender(ctx),
            seller: seller,
            expire: get_current_timestamp() + 5 * 60,         // 5 minutes to pay
            price: price,
            itemID: itemID,
            item: option::none(),
        };
        transfer::transfer(bill, seller);              // Wait for seller to accept

        assert!(vector::contains(&lockedItems.locked_objects, &itemID)==false, EAlreadyLocked);
        vector::push_back(&mut lockedItems.locked_objects, itemID);
    }

    // 2. Seller accept the bill
    public entry fun accept_bill<T: key+store>(item: T, bill: Bill<T>) {
        let buyer = bill.buyer;
        assert!(object::id(&item) == bill.itemID, ENotCorrectItem);
        option::fill(&mut bill.item, item);
        transfer::transfer(bill, buyer);
    }

    // 2.1 Seller reject the bill
    public entry fun reject_bill<T: key+store>(bill: Bill<T>, lockedItems: &mut LockedItems, ctx: &mut TxContext) {
        let Bill {
            id: uid,
            buyer: buyer,
            seller: _,
            expire: _,
            price: _,
            itemID: itemID,
            item: option_none_item,        // `T` is the type of the item
        } = bill;
        object::delete(uid);
        option::destroy_none(option_none_item);

        let (_, itemID_index_in_locked) = vector::index_of(&lockedItems.locked_objects, &itemID);
        vector::remove(&mut lockedItems.locked_objects, itemID_index_in_locked);

        let canceledReciept = CanceledReciept {
            id: object::new(ctx),
            buyer: buyer,
            seller: tx_context::sender(ctx),
            itemID: itemID,
            failed_reason: ISellerReject,
        };
        transfer::transfer(canceledReciept, buyer);
    }

    // 3. Buyer pay the bill. Deal!
    public entry fun pay_bill<T: key+store>(bill: Bill<T>, coin: &mut Coin<fake_usdc::FakeUSDC>, lockedItems: &mut LockedItems, ctx: &mut TxContext) {
        let Bill {
            id: uid,
            buyer: buyer,
            seller: seller,
            expire: expire,
            price: price,
            itemID: itemID,
            item: option_some_item,        // `T` is the type of the item
        } = bill;
        object::delete(uid);
        let item = option::extract(&mut option_some_item);
        option::destroy_none(option_some_item);
        let (_, itemID_index_in_locked) = vector::index_of(&lockedItems.locked_objects, &itemID);
        vector::remove(&mut lockedItems.locked_objects, itemID_index_in_locked);
        let time_now = get_current_timestamp();

        assert!(object::id(&item) == itemID, ENotCorrectItem);
        assert!(time_now < expire, EBillExpired);

        transfer::transfer(item, buyer);
        fake_usdc::transfer(coin, seller, price, ctx);

        let receipt = Reciept {
            id: object::new(ctx),
            buyer: buyer,
            seller: seller,
            itemID: itemID,
            dealing_time: time_now,
            dealing_price: price,
        };
        transfer::transfer(receipt, buyer);
    }

}