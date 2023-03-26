module payment::fake_usdc {
    use std::option;
    use sui::transfer;
    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::tx_context::{Self, TxContext};

    struct FakeUSDC has drop {}

    fun init(ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            FakeUSDC {},
            6,
            b"fUSDC",
            b"Fake USDC on SUI",
            b"",
            option::none(),
            ctx,
        );
        transfer::freeze_object(metadata);
        transfer::transfer(treasury_cap, tx_context::sender(ctx));
    }

    public entry fun admin_transfer(treasury_cap: TreasuryCap<FakeUSDC>, new_admin: address) {
        transfer::transfer(treasury_cap, new_admin);
    }

    public entry fun transfer(coin: &mut Coin<FakeUSDC>, recipient: address, amount: u64, ctx: &mut TxContext) {
        let giveout = coin::split(coin, amount, ctx);
        transfer::transfer(giveout, recipient);
    }
}