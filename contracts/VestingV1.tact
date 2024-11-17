import "@stdlib/deploy";
import "@stdlib/ownable";
import "./utils/Arrays.tact";
import "./SampleJetton.tact";

message SetDistribution {
    category: Int;
    amount: Int;
}

message SetGlobals {
    time: Int;
    limit: Array;
    emission: Int;
    decimals: Int;
    nextWithdrawtime: Int;
}

message SetReleaseAmount {
    category: Int;
    releaseAmounts: Array;
}

message RemoveCategory {
    category: Int;
}

message SetCategoryDetails {
    valid: Bool;
    category: Int;
    maxSupply: Int;
    totalReleased: Int;
    releaseAmounts: Array;
    lastWithdrawTime: Int;
    targetAddress: Address;
    lastWithdrawAmount: Int;
}

message SetFirstRelease {
    firstRelease: Int;
}

message AddArrItem {
    queryId: Int as uint64;
    item: Int;
}

message EmergencyWithdraw {
    to: Address;
    amount: Int;
}

message SetTotalV1Emissions {
    emissions: Int;
}

message TestV2EmissionSet {
    emissions: Int;
    address: Address;
}

struct ReleaseInfo {
    releaseTime: Int;
    releaseAmount: Int;
}

struct Category {
    valid: Bool;
    category: Int;
    maxSupply: Int;
    totalReleased: Int;
    releaseAmounts: Array;
    lastWithdrawTime: Int;
    targetAddress: Address;
    lastWithdrawAmount: Int;
}   

struct User {
    id: Int;
}

// Category Numbering
// 1 - Advisors
// 2 - Ecosystem
// 3 - Marketing
// 4 - Liquidity
// 5 - Staking
// 6 - Development

contract VestingV1 with Deployable, OwnableTransferable {
    testArr: Array;

    owner: Address;
    time: Int;
    emission: Int;
    decimals: Int;
    lastReleaseTime: Int = 0;
    nextWithdrawtime: Int;
    userName: Array;
    limit: Array;
    firstRelease: Int;

    totalCategories: Int = 0;

    // Mapping for storing distribution information
    distribution: map<Int, Int>;
    
    // Mapping for storing category information
    categories: map<Int, Category>;

    // Mapping for storing user information
    users: map<Int, User>;

    // Mapping for storing release information
    releaseInfo: map<Int, ReleaseInfo>;

    xanaToken: Address;

    init(xanaTokenAddress: Address) {
        self.owner = sender();
        self.testArr = emptyArray();
        self.userName = emptyArray();
        self.limit = emptyArray();

        self.time = 86400;
        self.emission = 6;
        self.decimals = 20;
        self.firstRelease = 1658308200;
        self.nextWithdrawtime = 1666257000;

        self.xanaToken = xanaTokenAddress;
    }

    receive(msg: SetFirstRelease) {
        self.requireOwner();
        self.firstRelease = msg.firstRelease;
    }

    receive(msg: RemoveCategory) {
        self.requireOwner();
        self.categories.set(msg.category, null);
    }

    receive(msg: SetCategoryDetails) {
        self.requireOwner();
        if (self.categories.get(msg.category) == null) {
            self.totalCategories += 1;
        }
        self.categories.set(msg.category, Category{
            valid: msg.valid,
            category: msg.category,
            maxSupply: msg.maxSupply,
            totalReleased: msg.totalReleased,
            releaseAmounts: msg.releaseAmounts,
            lastWithdrawTime: msg.lastWithdrawTime,
            targetAddress: msg.targetAddress,
            lastWithdrawAmount: msg.lastWithdrawAmount
        });
    }

    receive(msg: SetReleaseAmount) {
        self.requireOwner();
        let c: Category = self.categories.get(msg.category)!!;
        c.releaseAmounts = msg.releaseAmounts;
        self.categories.set(msg.category, c);
    }

    receive(msg: SetGlobals) {
        self.requireOwner();
        self.time = msg.time;
        self.limit = msg.limit;
        self.emission = msg.emission;
        self.decimals = msg.decimals;
        self.nextWithdrawtime = msg.nextWithdrawtime;
    }

    receive(msg: SetDistribution) {
        self.requireOwner();
        self.distribution.set(msg.category, msg.amount);
    }

    fun transferJettons(destination: Address, amount: Int, responseDestination: Address) {
        let ctx: Context = context();

        // Gas checks
        let fwdFee: Int = ctx.readForwardFee();
        let final: Int = 2 * ton("0.01") + fwdFee;
        require(ctx.value > final, "Invalid value!!"); 

        // Initialize the wallet
        let walletInit: StateInit = initOf JettonDefaultWallet(self.xanaToken, myAddress());

        // Send the token transfer
        send(SendParameters{
            to: contractAddress(walletInit),
            value: ton("0.05"),
            bounce: false,
            body: TokenTransfer{
                queryId: now(), // Use a proper query ID
                amount: amount,
                destination: destination,
                response_destination: myAddress(),
                custom_payload: null,
                forward_ton_amount: ton("0.01"),
                forward_payload: emptySlice()
            }.toCell()
        });
    }
    
    receive("releaseFunds") {
        require(self.nextWithdrawtime <= now(), "Time is remaining");
        require(self.emission < self.limit.length, "Distribution ended");
        let i: Int = 0;
        while (i < self.totalCategories) {
            let c: Category = self.categories.get(i)!!;
            if (c.releaseAmounts.m.get(self.emission)!! > 0) {
                let calculated: Int = (c.releaseAmounts.m.get(self.emission)!! * c.maxSupply) / 10^9;
                self.distribution.set(self.emission, calculated);
                self.categories.set(i, Category{
                    valid: c.valid,
                    category: c.category,
                    maxSupply: c.maxSupply,
                    totalReleased: c.totalReleased + calculated,
                    releaseAmounts: c.releaseAmounts,
                    lastWithdrawTime: now(),
                    targetAddress: c.targetAddress,
                    lastWithdrawAmount: calculated
                });
                self.transferJettons(c.targetAddress, calculated, c.targetAddress);
            } else {
                self.distribution.set(self.emission, 0);
            }
            self.emission += 1;
            if (self.emission < self.limit.length) {
                self.nextWithdrawtime = self.nextWithdrawtime + (self.limit.m.get(self.emission)!! * self.time);
            }

            // Set the total V1 emissions on target V2 contract
            send(SendParameters{
                to: c.targetAddress,
                value: 0,
                bounce: false,
                body: SetTotalV1Emissions{
                    emissions: self.emission
                }.toCell()
            });
        }
    }

    receive(msg: EmergencyWithdraw) {
        self.requireOwner();
        self.transferJettons(msg.to, msg.amount, msg.to);
    }

    receive(msg: TestV2EmissionSet) {
        send(SendParameters{
            to: msg.address,
            value: 0,
            mode: SendRemainingValue + SendIgnoreErrors,
            body: SetTotalV1Emissions{
                emissions: msg.emissions
            }.toCell()
        });
    }

    get fun MaxSupply(category: Int): Int {
        let c: Category = self.categories.get(category)!!;  // !! tells the compiler this can't be null
        return c.maxSupply;
    }

    get fun ReleaseAmounts(category: Int): Array {
        let c: Category = self.categories.get(category)!!;
        return c.releaseAmounts;
    }

    get fun Percentage(category: Int, step: Int): Int {
        let c: Category = self.categories.get(category)!!;
        return c.releaseAmounts.m.get(step)!!;
    }

    get fun FirstRelease(): Int {
        return self.firstRelease;
    }

    get fun NextWithdrawTime(): Int {
        return self.nextWithdrawtime;
    }

    get fun Distribution(category: Int): Int {
        return self.distribution.get(category)!!;
    }

    get fun CategoryDetails(category: Int): Category {
        return self.categories.get(category)!!;
    }

    get fun Globals(): SetGlobals {
        return SetGlobals{
            time: self.time,
            limit: self.limit,
            emission: self.emission,
            decimals: self.decimals,
            nextWithdrawtime: self.nextWithdrawtime
        };
    }

    get fun TotalCategories(): Int {
        return self.totalCategories;
    }

    get fun UserName(): Array {
        return self.userName;
    }

    get fun Limit(): Array {
        return self.limit;
    }

    // receive(msg: ChangeOwner) is added automatically to transfer ownership
    // get fun owner(): Address is added automatically to query who the owner is
}